//! Native-only producer registration. Callbacks are dispatched explicitly by
//! their registering OS thread, independently of runtime/socket shutdown.

use super::constants::*;
use super::external_leases::{LeaseError, LeaseLimits, LeaseOwner, ReleaseCallback};
use super::owned_buffers::{reserve_frozen, store_identity, FrozenReservation};
use super::resource_handles::insert_resource;
use bytes::Bytes;
use dashmap::DashMap;
use std::ffi::c_void;
use std::ptr;
use std::sync::atomic::{AtomicU32, AtomicUsize, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

const MAX_REGISTERED_OWNERS: usize = 1024;

fn status(error: LeaseError) -> i32 {
    match error {
        LeaseError::InvalidArgument => ERR_INVALID_ARGUMENT,
        LeaseError::WrongThread => ERR_LEASE_WRONG_THREAD,
        LeaseError::Closing => ERR_LEASE_CLOSING,
        LeaseError::QuotaExceeded => ERR_LEASE_QUOTA_EXCEEDED,
        LeaseError::Busy => ERR_LEASE_BUSY,
        LeaseError::Reentrant => ERR_LEASE_REENTRANT,
        LeaseError::AllocationFailed => ERR_IO,
    }
}

struct OwnerRegistry {
    next: AtomicU32,
    count: AtomicUsize,
    maximum: usize,
    owners: DashMap<u32, Arc<LeaseOwner>>,
}

struct OwnerSlot<'a> {
    registry: &'a OwnerRegistry,
    committed: bool,
}

impl Drop for OwnerSlot<'_> {
    fn drop(&mut self) {
        if !self.committed {
            self.registry.count.fetch_sub(1, Ordering::AcqRel);
        }
    }
}

impl OwnerRegistry {
    fn new(maximum: usize) -> Self {
        Self {
            next: AtomicU32::new(1),
            count: AtomicUsize::new(0),
            maximum,
            owners: DashMap::new(),
        }
    }

    fn create(&self, limits: LeaseLimits) -> Result<u32, i32> {
        self.count
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |count| {
                (count < self.maximum).then(|| count + 1)
            })
            .map_err(|_| ERR_LEASE_QUOTA_EXCEEDED)?;
        let mut slot = OwnerSlot {
            registry: self,
            committed: false,
        };
        let owner = LeaseOwner::new(limits).map_err(status)?;
        let handle =
            insert_resource(&self.next, &self.owners, owner).map_err(|_| ERR_HANDLE_UNAVAILABLE)?;
        slot.committed = true;
        Ok(handle)
    }

    fn get(&self, handle: i32) -> Result<Arc<LeaseOwner>, i32> {
        if handle <= 0 {
            return Err(ERR_INVALID_ARGUMENT);
        }
        self.owners
            .get(&(handle as u32))
            .map(|entry| Arc::clone(entry.value()))
            .ok_or(ERR_INVALID_ARGUMENT)
    }

    fn destroy(&self, handle: i32) -> Result<(), i32> {
        // Admission, close and dispatch are owner-thread-only. An outstanding
        // callback retains its quota, so reentrant destruction cannot win.
        self.get(handle)?.close().map_err(status)?;
        self.owners
            .remove(&(handle as u32))
            .ok_or(ERR_INVALID_ARGUMENT)?;
        self.count.fetch_sub(1, Ordering::AcqRel);
        Ok(())
    }
}

static OWNERS: OnceLock<OwnerRegistry> = OnceLock::new();

fn owners() -> &'static OwnerRegistry {
    // Never clear this on transport shutdown: exported views and fan-out may
    // still own a loan, and cleanup must occur on the producer's own thread.
    OWNERS.get_or_init(|| OwnerRegistry::new(MAX_REGISTERED_OWNERS))
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CtExternalBufferToken {
    pub handle: i32,
    pub identity: *const c_void,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CtExternalOwnerMetrics {
    pub retained_bytes: usize,
    pub outstanding_leases: usize,
    pub pending_releases: usize,
    pub closing: i32,
}

#[no_mangle]
pub extern "C" fn ct_external_lease_abi_version() -> u32 {
    1
}

#[no_mangle]
pub extern "C" fn ct_external_buffer_store_identity() -> *const c_void {
    store_identity()
}

/// Called by the dedicated native producer thread. Returns a positive handle,
/// or a negative error. At most 1024 owners can be registered in this library.
#[no_mangle]
pub extern "C" fn ct_external_owner_create(maximum_bytes: usize, maximum_leases: u32) -> i32 {
    owners()
        .create(LeaseLimits {
            bytes: maximum_bytes,
            leases: maximum_leases as usize,
        })
        .map(|handle| handle as i32)
        .unwrap_or_else(|error| error)
}

/// Closes admission immediately. BUSY means tokens still need native cleanup.
#[no_mangle]
pub extern "C" fn ct_external_owner_close(handle: i32) -> i32 {
    owners()
        .get(handle)
        .and_then(|owner| owner.close().map_err(status))
        .map(|_| SUCCESS)
        .unwrap_or_else(|error| error)
}

/// Deletion requires the producer thread and no live/queued/in-flight loans.
#[no_mangle]
pub extern "C" fn ct_external_owner_destroy(handle: i32) -> i32 {
    owners()
        .destroy(handle)
        .map(|_| SUCCESS)
        .unwrap_or_else(|error| error)
}

/// Returns number of callbacks dispatched, or a negative error. Native callbacks
/// execute without registry/state locks. Recursive dispatch is rejected.
#[no_mangle]
pub extern "C" fn ct_external_owner_dispatch(handle: i32, maximum: u32) -> i32 {
    if maximum > i32::MAX as u32 {
        return ERR_INVALID_ARGUMENT;
    }
    owners()
        .get(handle)
        .and_then(|owner| owner.dispatch(maximum as usize).map_err(status))
        .map(|count| count as i32)
        .unwrap_or_else(|error| error)
}

/// Dedicated producer-thread wait: 1 means cleanup is queued; 0 means timeout
/// or no outstanding loans. This must not run on a Dart isolate/event loop.
#[no_mangle]
pub extern "C" fn ct_external_owner_wait(handle: i32, timeout_millis: u32) -> i32 {
    owners()
        .get(handle)
        .and_then(|owner| {
            owner
                .wait_for_release(Duration::from_millis(timeout_millis as u64))
                .map_err(status)
        })
        .map(i32::from)
        .unwrap_or_else(|error| error)
}

/// # Safety
/// A nonnull `out` must point to writable, aligned metrics storage for this call.
#[no_mangle]
pub unsafe extern "C" fn ct_external_owner_metrics(
    handle: i32,
    out: *mut CtExternalOwnerMetrics,
) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let owner = match owners().get(handle) {
        Ok(owner) => owner,
        Err(error) => return error,
    };
    let metrics = owner.metrics();
    unsafe {
        ptr::write(
            out,
            CtExternalOwnerMetrics {
                retained_bytes: metrics.bytes,
                outstanding_leases: metrics.leases,
                pending_releases: metrics.pending_releases,
                closing: i32::from(metrics.closing),
            },
        )
    };
    SUCCESS
}

unsafe fn register_with(
    owner: &Arc<LeaseOwner>,
    base: *const u8,
    span_length: usize,
    offset: usize,
    length: usize,
    callback: ReleaseCallback,
    token: *mut c_void,
    reserve: impl FnOnce() -> Result<FrozenReservation<'static>, i32>,
) -> Result<CtExternalBufferToken, i32> {
    let end = offset
        .checked_add(length)
        .filter(|&end| end <= span_length)
        .ok_or(ERR_INVALID_ARGUMENT)?;
    if span_length > i32::MAX as usize {
        return Err(ERR_INVALID_ARGUMENT);
    }
    // Reserve before token/quota consumption. All normal admission failures
    // roll this slot back without freeing or invoking the producer's token.
    let reservation = reserve()?;
    let loan = unsafe { owner.admit(base, span_length, callback, token) }.map_err(status)?;
    let allocation = Bytes::from_owner(loan);
    let handle = reservation.commit(allocation, offset..end);
    Ok(CtExternalBufferToken {
        handle: handle as i32,
        identity: store_identity(),
    })
}

/// Registers an initialized immutable span and publishes a frozen native buffer.
/// On SUCCESS one producer resource reference is consumed. On every normal
/// error no reference is consumed and output is zeroed. The callback must be a
/// native function (never Dart), must not unwind, and must remain loaded/valid
/// until producer-thread dispatch. Resource memory remains readable/immutable
/// until that callback. The producer thread must outlive every admitted loan.
///
/// # Safety
/// A nonnull output must be writable/aligned for CtExternalBufferToken. An
/// admitted span must be initialized/readable/immutable until native cleanup;
/// callback code and its resource reference must remain valid through dispatch.
#[no_mangle]
pub unsafe extern "C" fn ct_external_buffer_register(
    owner: i32,
    base: *const u8,
    span_length: usize,
    offset: usize,
    length: usize,
    callback: Option<ReleaseCallback>,
    token: *mut c_void,
    out: *mut CtExternalBufferToken,
) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe {
        ptr::write(
            out,
            CtExternalBufferToken {
                handle: 0,
                identity: ptr::null(),
            },
        )
    };
    let Some(callback) = callback else {
        return ERR_INVALID_ARGUMENT;
    };
    let owner = match owners().get(owner) {
        Ok(owner) => owner,
        Err(error) => return error,
    };
    match unsafe {
        register_with(
            &owner,
            base,
            span_length,
            offset,
            length,
            callback,
            token,
            reserve_frozen,
        )
    } {
        Ok(buffer) => {
            unsafe { ptr::write(out, buffer) };
            SUCCESS
        }
        Err(error) => error,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::ffi::CtMessageByteView;
    use crate::runtime::owned_buffers::*;
    use std::sync::Mutex;
    use std::thread::{self, ThreadId};

    macro_rules! native_register {
        ($($argument:expr),* $(,)?) => {
            unsafe { ct_external_buffer_register($($argument),*) }
        };
    }

    struct Resource {
        bytes: Box<[u8]>,
        releases: Arc<Mutex<Vec<ThreadId>>>,
    }

    type Releases = Arc<Mutex<Vec<ThreadId>>>;

    fn resource(bytes: &[u8]) -> (*const u8, *mut c_void, Releases) {
        let releases = Arc::new(Mutex::new(Vec::new()));
        let resource = Box::new(Resource {
            bytes: bytes.into(),
            releases: Arc::clone(&releases),
        });
        let base = resource.bytes.as_ptr();
        (base, Box::into_raw(resource).cast(), releases)
    }

    unsafe extern "C" fn release_resource(token: *mut c_void) {
        let resource = unsafe { Box::from_raw(token.cast::<Resource>()) };
        resource
            .releases
            .lock()
            .unwrap()
            .push(thread::current().id());
    }

    fn token() -> CtExternalBufferToken {
        CtExternalBufferToken {
            handle: 0,
            identity: ptr::null(),
        }
    }

    fn metrics(owner: i32) -> CtExternalOwnerMetrics {
        let mut out = std::mem::MaybeUninit::uninit();
        assert_eq!(
            unsafe { ct_external_owner_metrics(owner, out.as_mut_ptr()) },
            SUCCESS
        );
        unsafe { out.assume_init() }
    }

    #[test]
    fn owner_registry_bounds_and_creation_failures_return_the_reserved_slot() {
        let registry = OwnerRegistry::new(1);
        assert_eq!(
            registry.create(LeaseLimits {
                bytes: 0,
                leases: 0
            }),
            Err(ERR_INVALID_ARGUMENT)
        );
        assert_eq!(registry.count.load(Ordering::Acquire), 0);
        let first = registry
            .create(LeaseLimits {
                bytes: 8,
                leases: 1,
            })
            .unwrap();
        assert_eq!(
            registry.create(LeaseLimits {
                bytes: 8,
                leases: 1
            }),
            Err(ERR_LEASE_QUOTA_EXCEEDED)
        );
        registry.destroy(first as i32).unwrap();
        let second = registry
            .create(LeaseLimits {
                bytes: 8,
                leases: 1,
            })
            .unwrap();
        assert!(second > first);
        assert!(registry.get(first as i32).is_err());
        registry.destroy(second as i32).unwrap();
        registry.next.store(i32::MAX as u32 + 1, Ordering::Release);
        assert_eq!(
            registry.create(LeaseLimits {
                bytes: 8,
                leases: 1
            }),
            Err(ERR_HANDLE_UNAVAILABLE)
        );
        assert_eq!(registry.count.load(Ordering::Acquire), 0);
    }

    #[test]
    fn dispatch_count_rejects_values_outside_its_signed_return_range() {
        let owner = ct_external_owner_create(0, 1);
        assert_eq!(
            ct_external_owner_dispatch(owner, i32::MAX as u32 + 1),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(ct_external_owner_dispatch(owner, 0), 0);
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    }

    #[test]
    fn handle_reservation_failure_never_consumes_native_producer_reference() {
        let owner = LeaseOwner::new(LeaseLimits {
            bytes: 4,
            leases: 1,
        })
        .unwrap();
        let (base, token, releases) = resource(&[1, 2, 3, 4]);
        let error = unsafe {
            register_with(&owner, base, 4, 0, 4, release_resource, token, || {
                Err(ERR_HANDLE_UNAVAILABLE)
            })
        }
        .err();
        assert_eq!(error, Some(ERR_HANDLE_UNAVAILABLE));
        assert_eq!(owner.metrics().leases, 0);
        assert!(releases.lock().unwrap().is_empty());
        unsafe { release_resource(token) };
        assert_eq!(releases.lock().unwrap().len(), 1);
    }

    #[test]
    fn native_ffi_fanout_and_export_retain_foreign_allocation_until_producer_dispatch() {
        assert_eq!(ct_external_lease_abi_version(), 1);
        let owner = ct_external_owner_create(5, 1);
        assert!(owner > 0);
        let (base, resource, releases) = resource(&[0, 1, 2, 3, 4]);
        let mut registered = token();
        assert_eq!(
            native_register!(
                owner,
                base,
                5,
                1,
                3,
                Some(release_resource),
                resource,
                &mut registered
            ),
            SUCCESS
        );
        assert!(registered.handle > 0);
        assert_eq!(registered.identity, ct_external_buffer_store_identity());
        let mut info = std::mem::MaybeUninit::uninit();
        assert_eq!(
            ct_owned_buffer_info(registered.handle, info.as_mut_ptr()),
            SUCCESS
        );
        let info = unsafe { info.assume_init() };
        assert_eq!(info.base, base);
        assert_eq!(
            (
                info.capacity,
                info.initialized_length,
                info.offset,
                info.length,
                info.writable
            ),
            (5, 5, 1, 3, 0)
        );
        let slice = ct_owned_buffer_slice(registered.handle, 1, 1);
        assert!(slice > 0);
        let payload = take_frozen(slice).unwrap();
        assert_eq!(payload.as_ptr(), unsafe { base.add(2) });
        assert_eq!(payload.as_ref(), &[2]);
        let mut view = std::mem::MaybeUninit::<CtMessageByteView>::uninit();
        assert_eq!(
            ct_owned_buffer_export(registered.handle, view.as_mut_ptr()),
            SUCCESS
        );
        let view = unsafe { view.assume_init() };
        assert_eq!(view.ptr, unsafe { base.add(1) });
        assert_eq!(view.len, 3);
        assert_eq!(ct_owned_buffer_release(registered.handle), SUCCESS);
        assert_eq!(ct_external_owner_destroy(owner), ERR_LEASE_BUSY);
        thread::spawn(move || drop(payload)).join().unwrap();
        assert_eq!(metrics(owner).retained_bytes, 5);
        assert_eq!(metrics(owner).outstanding_leases, 1);
        assert_eq!(metrics(owner).pending_releases, 0);
        assert!(releases.lock().unwrap().is_empty());
        let view_token = view.owner as usize;
        thread::spawn(move || {
            ct_owned_buffer_view_finalizer(view_token as *mut c_void);
        })
        .join()
        .unwrap();
        assert_eq!(ct_external_owner_wait(owner, 1000), 1);
        assert_eq!(metrics(owner).pending_releases, 1);
        assert_eq!(metrics(owner).retained_bytes, 5);
        assert!(releases.lock().unwrap().is_empty());
        assert_eq!(ct_external_owner_dispatch(owner, 1), 1);
        assert_eq!(*releases.lock().unwrap(), [thread::current().id()]);
        assert_eq!(metrics(owner).outstanding_leases, 0);
        assert_eq!(ct_external_owner_close(owner), SUCCESS);
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
        assert_eq!(ct_external_owner_destroy(owner), ERR_INVALID_ARGUMENT);
    }

    #[test]
    fn ffi_invalid_admission_zeroes_output_and_preserves_the_producer_token() {
        let owner = ct_external_owner_create(4, 1);
        let (base, resource, releases) = resource(&[1, 2, 3, 4]);
        for (owner_arg, base_arg, span, offset, length, callback) in [
            (
                owner,
                base,
                4,
                usize::MAX,
                1,
                Some(release_resource as ReleaseCallback),
            ),
            (
                owner,
                base,
                4,
                4,
                1,
                Some(release_resource as ReleaseCallback),
            ),
            (
                owner,
                ptr::null(),
                4,
                0,
                4,
                Some(release_resource as ReleaseCallback),
            ),
            (
                owner,
                base,
                i32::MAX as usize + 1,
                0,
                4,
                Some(release_resource as ReleaseCallback),
            ),
            (0, base, 4, 0, 4, Some(release_resource as ReleaseCallback)),
            (owner, base, 4, 0, 4, None),
        ] {
            let mut out = CtExternalBufferToken {
                handle: 1234,
                identity: base.cast(),
            };
            assert_eq!(
                native_register!(
                    owner_arg, base_arg, span, offset, length, callback, resource, &mut out
                ),
                ERR_INVALID_ARGUMENT
            );
            assert_eq!(out.handle, 0);
            assert!(out.identity.is_null());
            assert_eq!(metrics(owner).outstanding_leases, 0);
            assert!(releases.lock().unwrap().is_empty());
        }
        assert_eq!(
            native_register!(
                owner,
                base,
                4,
                0,
                4,
                Some(release_resource),
                resource,
                ptr::null_mut()
            ),
            ERR_INVALID_ARGUMENT
        );
        assert!(releases.lock().unwrap().is_empty());
        unsafe { release_resource(resource) };
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    }

    #[test]
    fn ffi_wrong_thread_admission_and_cleanup_preserve_native_owner_registration() {
        let owner = ct_external_owner_create(1, 1);
        let (base, resource, releases) = resource(&[7]);
        let (base_address, resource_address) = (base as usize, resource as usize);
        thread::spawn(move || {
            let mut out = token();
            assert_eq!(
                native_register!(
                    owner,
                    base_address as *const u8,
                    1,
                    0,
                    1,
                    Some(release_resource),
                    resource_address as *mut c_void,
                    &mut out
                ),
                ERR_LEASE_WRONG_THREAD
            );
            assert_eq!(out.handle, 0);
            assert_eq!(ct_external_owner_dispatch(owner, 1), ERR_LEASE_WRONG_THREAD);
            assert_eq!(ct_external_owner_wait(owner, 0), ERR_LEASE_WRONG_THREAD);
            assert_eq!(ct_external_owner_close(owner), ERR_LEASE_WRONG_THREAD);
            assert_eq!(ct_external_owner_destroy(owner), ERR_LEASE_WRONG_THREAD);
        })
        .join()
        .unwrap();
        assert_eq!(metrics(owner).closing, 0);
        assert_eq!(metrics(owner).outstanding_leases, 0);
        assert!(releases.lock().unwrap().is_empty());
        unsafe { release_resource(resource) };
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    }

    #[test]
    fn ffi_empty_loan_still_queues_exactly_one_native_resource_release() {
        let owner = ct_external_owner_create(0, 1);
        let (_, resource, releases) = resource(&[]);
        let mut registered = token();
        assert_eq!(
            native_register!(
                owner,
                ptr::null(),
                0,
                0,
                0,
                Some(release_resource),
                resource,
                &mut registered
            ),
            SUCCESS
        );
        assert_eq!(metrics(owner).outstanding_leases, 1);
        assert_eq!(ct_owned_buffer_release(registered.handle), SUCCESS);
        assert_eq!(metrics(owner).pending_releases, 1);
        assert_eq!(ct_external_owner_dispatch(owner, 8), 1);
        assert_eq!(ct_external_owner_dispatch(owner, 8), 0);
        assert_eq!(*releases.lock().unwrap(), [thread::current().id()]);
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    }

    #[test]
    fn submission_rejection_consumes_buffer_but_cleanup_stays_queued_and_charged() {
        let owner = ct_external_owner_create(1, 1);
        let (base, first_resource, first_releases) = resource(&[7]);
        let mut first = token();
        assert_eq!(
            native_register!(
                owner,
                base,
                1,
                0,
                1,
                Some(release_resource),
                first_resource,
                &mut first
            ),
            SUCCESS
        );
        let status = submit_frozen(first.handle, |payload| {
            assert_eq!(payload.as_ptr(), base);
            assert_eq!(payload.as_ref(), &[7]);
            assert_eq!(metrics(owner).outstanding_leases, 1);
            assert!(first_releases.lock().unwrap().is_empty());
            ERR_SEND_QUEUE_FULL
        });
        assert_eq!(status, ERR_SEND_QUEUE_FULL);
        assert_eq!(ct_owned_buffer_release(first.handle), ERR_INVALID_ARGUMENT);
        assert_eq!(metrics(owner).pending_releases, 1);
        assert_eq!(metrics(owner).retained_bytes, 1);
        assert!(first_releases.lock().unwrap().is_empty());
        let (second_base, second_resource, second_releases) = resource(&[8]);
        let mut second = token();
        assert_eq!(
            native_register!(
                owner,
                second_base,
                1,
                0,
                1,
                Some(release_resource),
                second_resource,
                &mut second
            ),
            ERR_LEASE_QUOTA_EXCEEDED
        );
        assert_eq!(second.handle, 0);
        assert!(second.identity.is_null());
        assert!(second_releases.lock().unwrap().is_empty());
        assert_eq!(ct_external_owner_dispatch(owner, 1), 1);
        assert_eq!(first_releases.lock().unwrap().len(), 1);
        // The failed attempt left this same producer reference reusable.
        assert_eq!(
            native_register!(
                owner,
                second_base,
                1,
                0,
                1,
                Some(release_resource),
                second_resource,
                &mut second
            ),
            SUCCESS
        );
        assert_eq!(
            submit_frozen(second.handle, |_| ERR_CONNECTION_NOT_FOUND),
            ERR_CONNECTION_NOT_FOUND
        );
        assert!(second_releases.lock().unwrap().is_empty());
        assert_eq!(ct_external_owner_dispatch(owner, 1), 1);
        assert_eq!(second_releases.lock().unwrap().len(), 1);
        assert_eq!(ct_external_owner_destroy(owner), SUCCESS);
    }
}
