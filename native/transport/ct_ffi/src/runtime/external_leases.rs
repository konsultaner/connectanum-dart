//! Storage-agnostic native producer loans. Last-reference cleanup queues a
//! native callback; only the registering OS thread may dispatch it.
//!
//! Its caller must keep the owner registered until close succeeds. The FFI
//! registry rejects deletion while any live/queued lease remains; merely
//! dropping an Arc is not a producer-thread cleanup operation.

use std::collections::VecDeque;
use std::ffi::c_void;
use std::ptr::NonNull;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::{self, ThreadId};
use std::time::Duration;

pub(super) type ReleaseCallback = unsafe extern "C" fn(*mut c_void);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum LeaseError {
    InvalidArgument,
    WrongThread,
    Closing,
    QuotaExceeded,
    Busy,
    Reentrant,
    AllocationFailed,
}

#[derive(Debug, Clone, Copy)]
pub(super) struct LeaseLimits {
    pub bytes: usize,
    pub leases: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct LeaseMetrics {
    pub bytes: usize,
    pub leases: usize,
    pub pending_releases: usize,
    pub closing: bool,
}

struct Release {
    callback: ReleaseCallback,
    token: usize,
    bytes: usize,
}

struct State {
    bytes: usize,
    leases: usize,
    releases: VecDeque<Release>,
    closing: bool,
    dispatching: bool,
}

pub(super) struct LeaseOwner {
    thread: ThreadId,
    limits: LeaseLimits,
    state: Mutex<State>,
    ready: Condvar,
}

impl LeaseOwner {
    pub fn new(limits: LeaseLimits) -> Result<Arc<Self>, LeaseError> {
        if limits.leases == 0 || limits.leases > i32::MAX as usize {
            return Err(LeaseError::InvalidArgument);
        }
        let mut releases = VecDeque::new();
        // Pending cleanup remains part of the outstanding lease quota, so this
        // capacity suffices for every last-reference Drop without reallocation.
        releases
            .try_reserve_exact(limits.leases)
            .map_err(|_| LeaseError::AllocationFailed)?;
        Ok(Arc::new(Self {
            thread: thread::current().id(),
            limits,
            state: Mutex::new(State {
                bytes: 0,
                leases: 0,
                releases,
                closing: false,
                dispatching: false,
            }),
            ready: Condvar::new(),
        }))
    }

    fn state(&self) -> MutexGuard<'_, State> {
        // No producer/user callback executes while this mutex is held. State
        // transitions consist only of checked arithmetic and reserved queues.
        self.state.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn on_owner_thread(&self) -> Result<(), LeaseError> {
        if thread::current().id() != self.thread {
            return Err(LeaseError::WrongThread);
        }
        Ok(())
    }

    /// Admit one producer resource reference, without adopting its allocation.
    /// All normal errors leave the producer's token/reference unconsumed.
    ///
    /// # Safety
    /// `base..base+length` must be readable and immutable until `callback(token)`
    /// runs. The native callback and token must remain valid through that call,
    /// must not unwind, and must never be a Dart callback. Each successful
    /// admission transfers one resource reference for exactly one callback.
    pub unsafe fn admit(
        self: &Arc<Self>,
        base: *const u8,
        length: usize,
        callback: ReleaseCallback,
        token: *mut c_void,
    ) -> Result<ExternalLoan, LeaseError> {
        self.on_owner_thread()?;
        if length > isize::MAX as usize
            || (length != 0 && base.is_null())
            || (base as usize).checked_add(length).is_none()
        {
            return Err(LeaseError::InvalidArgument);
        }
        let mut state = self.state();
        if state.closing {
            return Err(LeaseError::Closing);
        }
        let bytes = state
            .bytes
            .checked_add(length)
            .filter(|&bytes| bytes <= self.limits.bytes)
            .ok_or(LeaseError::QuotaExceeded)?;
        if state.leases == self.limits.leases {
            return Err(LeaseError::QuotaExceeded);
        }
        state.bytes = bytes;
        state.leases += 1;
        Ok(ExternalLoan {
            // Rust slices require a nonnull pointer even at length zero.
            base: NonNull::new(base as *mut u8).unwrap_or_else(NonNull::dangling),
            length,
            owner: Arc::clone(self),
            release: Release {
                callback,
                token: token as usize,
                bytes: length,
            },
        })
    }

    pub fn metrics(&self) -> LeaseMetrics {
        let state = self.state();
        LeaseMetrics {
            bytes: state.bytes,
            leases: state.leases,
            pending_releases: state.releases.len(),
            closing: state.closing,
        }
    }

    /// Stops admission immediately. Busy means existing references or cleanup
    /// still need to drain; it never authorizes closing the producer resource.
    pub fn close(&self) -> Result<(), LeaseError> {
        self.on_owner_thread()?;
        let mut state = self.state();
        state.closing = true;
        if state.leases != 0 {
            return Err(LeaseError::Busy);
        }
        Ok(())
    }

    pub fn wait_for_release(&self, timeout: Duration) -> Result<bool, LeaseError> {
        self.on_owner_thread()?;
        let state = self.state();
        if state.dispatching {
            return Err(LeaseError::Reentrant);
        }
        let (state, _) = self
            .ready
            .wait_timeout_while(state, timeout, |s| s.releases.is_empty() && s.leases != 0)
            .unwrap_or_else(|p| p.into_inner());
        Ok(!state.releases.is_empty())
    }

    pub fn dispatch(&self, maximum: usize) -> Result<usize, LeaseError> {
        self.on_owner_thread()?;
        {
            let mut state = self.state();
            if state.dispatching {
                return Err(LeaseError::Reentrant);
            }
            state.dispatching = true;
        }
        let _dispatch = DispatchGuard(self);
        let mut count = 0;
        while count < maximum {
            let release = self.state().releases.pop_front();
            let Some(release) = release else { break };
            // Keep quota charged while native cleanup runs outside the mutex.
            unsafe { (release.callback)(release.token as *mut c_void) };
            let mut state = self.state();
            state.bytes -= release.bytes;
            state.leases -= 1;
            count += 1;
        }
        Ok(count)
    }
}

struct DispatchGuard<'a>(&'a LeaseOwner);

impl Drop for DispatchGuard<'_> {
    fn drop(&mut self) {
        self.0.state().dispatching = false;
    }
}

pub(super) struct ExternalLoan {
    base: NonNull<u8>,
    length: usize,
    owner: Arc<LeaseOwner>,
    release: Release,
}

// Admission's native producer contract guarantees immutable, readable memory
// until the owner-thread release. Dropping/reading on transport workers is safe;
// Drop only queues a callback and never touches or frees the producer's bytes.
unsafe impl Send for ExternalLoan {}
unsafe impl Sync for ExternalLoan {}

impl AsRef<[u8]> for ExternalLoan {
    fn as_ref(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.base.as_ptr(), self.length) }
    }
}

impl Drop for ExternalLoan {
    fn drop(&mut self) {
        let mut state = self.owner.state();
        state.releases.push_back(Release {
            callback: self.release.callback,
            token: self.release.token,
            bytes: self.release.bytes,
        });
        self.owner.ready.notify_one();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    type Releases = Arc<Mutex<Vec<(usize, ThreadId)>>>;

    struct Resource {
        bytes: Box<[u8]>,
        id: usize,
        released: Releases,
    }

    fn resource(bytes: &[u8], id: usize, released: &Releases) -> (*const u8, *mut c_void) {
        let resource = Box::new(Resource {
            bytes: bytes.into(),
            id,
            released: Arc::clone(released),
        });
        let base = resource.bytes.as_ptr();
        (base, Box::into_raw(resource).cast())
    }

    unsafe extern "C" fn release_resource(token: *mut c_void) {
        let resource = unsafe { Box::from_raw(token.cast::<Resource>()) };
        resource
            .released
            .lock()
            .unwrap()
            .push((resource.id, thread::current().id()));
        // Only this native callback owns/frees the allocation.
    }

    fn owner(bytes: usize, leases: usize) -> Arc<LeaseOwner> {
        LeaseOwner::new(LeaseLimits { bytes, leases }).unwrap()
    }

    fn releases() -> Releases {
        Arc::new(Mutex::new(Vec::new()))
    }

    #[test]
    fn foreign_pointer_survives_delayed_fanout_until_owner_dispatch() {
        let owner = owner(4, 1);
        let released = releases();
        let (base, token) = resource(&[1, 2, 0, 255], 7, &released);
        let loan = unsafe { owner.admit(base, 4, release_resource, token) }.unwrap();
        assert_eq!(loan.as_ref().as_ptr(), base);
        let loan = Arc::new(loan);
        let fast = Arc::clone(&loan);
        let slow = Arc::clone(&loan);
        drop(loan);
        let fast = thread::spawn(move || {
            assert_eq!(fast.as_ref().as_ref(), &[1, 2, 0, 255]);
        });
        let (ready_tx, ready_rx) = mpsc::channel();
        let (drop_tx, drop_rx) = mpsc::channel();
        let slow = thread::spawn(move || {
            ready_tx.send(()).unwrap();
            drop_rx.recv().unwrap();
            assert_eq!(slow.as_ref().as_ref(), &[1, 2, 0, 255]);
        });
        fast.join().unwrap();
        ready_rx.recv().unwrap();
        assert!(released.lock().unwrap().is_empty());
        assert_eq!(owner.metrics().pending_releases, 0);
        drop_tx.send(()).unwrap();
        assert!(owner.wait_for_release(Duration::from_secs(1)).unwrap());
        slow.join().unwrap();
        assert_eq!(owner.metrics().bytes, 4);
        assert_eq!(owner.metrics().leases, 1);
        assert_eq!(owner.metrics().pending_releases, 1);
        assert!(released.lock().unwrap().is_empty());
        assert_eq!(owner.dispatch(8), Ok(1));
        assert_eq!(*released.lock().unwrap(), [(7, thread::current().id())]);
        assert_eq!(owner.metrics().bytes, 0);
        assert_eq!(owner.metrics().leases, 0);
        assert_eq!(owner.dispatch(8), Ok(0));
        assert_eq!(owner.close(), Ok(()));
    }

    #[test]
    fn wrong_thread_cannot_admit_dispatch_wait_or_close() {
        let owner = owner(8, 2);
        let released = releases();
        let (base, token) = resource(&[1], 1, &released);
        let loan = unsafe { owner.admit(base, 1, release_resource, token) }.unwrap();
        drop(loan);
        let (other_base, other_token) = resource(&[2], 2, &released);
        let moved_owner = Arc::clone(&owner);
        let (other_base, other_address) = (other_base as usize, other_token as usize);
        thread::spawn(move || {
            let error = unsafe {
                moved_owner.admit(
                    other_base as *const u8,
                    1,
                    release_resource,
                    other_address as *mut c_void,
                )
            }
            .err();
            assert_eq!(error, Some(LeaseError::WrongThread));
            assert_eq!(moved_owner.dispatch(1), Err(LeaseError::WrongThread));
            assert_eq!(moved_owner.close(), Err(LeaseError::WrongThread));
            assert_eq!(
                moved_owner.wait_for_release(Duration::ZERO),
                Err(LeaseError::WrongThread)
            );
        })
        .join()
        .unwrap();
        assert!(!owner.metrics().closing);
        assert_eq!(owner.metrics().pending_releases, 1);
        assert!(released.lock().unwrap().is_empty());
        // Failed admission left this producer reference unconsumed.
        unsafe { release_resource(other_token) };
        assert_eq!(owner.dispatch(1), Ok(1));
        let producer = thread::current().id();
        assert_eq!(*released.lock().unwrap(), [(2, producer), (1, producer)]);
    }

    #[test]
    fn pending_release_holds_byte_quota_and_failed_admission_preserves_token() {
        let owner = owner(4, 2);
        let released = releases();
        let (base, token) = resource(&[0, 1, 2, 3], 1, &released);
        let first = unsafe { owner.admit(base, 4, release_resource, token) }.unwrap();
        let (other_base, other_token) = resource(&[255], 2, &released);
        assert_eq!(owner.metrics().pending_releases, 0);
        assert_eq!(
            unsafe { owner.admit(other_base, 1, release_resource, other_token) }.err(),
            Some(LeaseError::QuotaExceeded)
        );
        drop(first);
        assert_eq!(owner.metrics().pending_releases, 1);
        assert_eq!(
            unsafe { owner.admit(other_base, 1, release_resource, other_token) }.err(),
            Some(LeaseError::QuotaExceeded)
        );
        assert!(released.lock().unwrap().is_empty());
        assert_eq!(owner.dispatch(1), Ok(1));
        let second = unsafe { owner.admit(other_base, 1, release_resource, other_token) }.unwrap();
        assert_eq!(second.as_ref(), &[255]);
        drop(second);
        assert_eq!(owner.dispatch(1), Ok(1));
        assert_eq!(released.lock().unwrap().len(), 2);
        assert_eq!(owner.metrics().bytes, 0);
    }

    #[test]
    fn close_rejects_new_loans_and_requires_actual_cleanup() {
        let owner = owner(8, 2);
        let released = releases();
        let (base, token) = resource(&[1], 1, &released);
        let loan = unsafe { owner.admit(base, 1, release_resource, token) }.unwrap();
        assert_eq!(owner.close(), Err(LeaseError::Busy));
        let (other_base, other_token) = resource(&[2], 2, &released);
        assert_eq!(
            unsafe { owner.admit(other_base, 1, release_resource, other_token) }.err(),
            Some(LeaseError::Closing)
        );
        unsafe { release_resource(other_token) };
        assert!(!owner.wait_for_release(Duration::ZERO).unwrap());
        drop(loan);
        assert_eq!(owner.close(), Err(LeaseError::Busy));
        assert_eq!(owner.dispatch(1), Ok(1));
        assert_eq!(owner.close(), Ok(()));
        assert!(!owner.wait_for_release(Duration::from_secs(1)).unwrap());
    }

    struct CallbackProbe {
        bytes: Box<[u8]>,
        owner: Arc<LeaseOwner>,
        observed: Arc<Mutex<Option<CallbackObservation>>>,
    }

    #[derive(Debug)]
    struct CallbackObservation {
        metrics: LeaseMetrics,
        dispatch: Result<usize, LeaseError>,
        wait: Result<bool, LeaseError>,
        admission: Option<LeaseError>,
        close: Result<(), LeaseError>,
    }

    unsafe extern "C" fn release_probe(token: *mut c_void) {
        let probe = unsafe { Box::from_raw(token.cast::<CallbackProbe>()) };
        let released = releases();
        let (base, token) = resource(&[9], 9, &released);
        let admission = unsafe { probe.owner.admit(base, 1, release_resource, token) }.err();
        if admission.is_some() {
            unsafe { release_resource(token) };
        }
        *probe.observed.lock().unwrap() = Some(CallbackObservation {
            metrics: probe.owner.metrics(),
            dispatch: probe.owner.dispatch(1),
            wait: probe.owner.wait_for_release(Duration::ZERO),
            admission,
            close: probe.owner.close(),
        });
    }

    #[test]
    fn callback_runs_unlocked_with_quota_charged_and_recursive_dispatch_rejected() {
        let owner = owner(1, 1);
        let observed = Arc::new(Mutex::new(None));
        let probe = Box::new(CallbackProbe {
            bytes: vec![7].into_boxed_slice(),
            owner: Arc::clone(&owner),
            observed: Arc::clone(&observed),
        });
        let base = probe.bytes.as_ptr();
        let token = Box::into_raw(probe).cast();
        let loan = unsafe { owner.admit(base, 1, release_probe, token) }.unwrap();
        drop(loan);
        assert_eq!(owner.dispatch(1), Ok(1));
        let observation = observed.lock().unwrap().take().unwrap();
        assert_eq!(observation.metrics.bytes, 1);
        assert_eq!(observation.metrics.leases, 1);
        assert_eq!(observation.metrics.pending_releases, 0);
        assert_eq!(observation.dispatch, Err(LeaseError::Reentrant));
        assert_eq!(observation.wait, Err(LeaseError::Reentrant));
        assert_eq!(observation.admission, Some(LeaseError::QuotaExceeded));
        assert_eq!(observation.close, Err(LeaseError::Busy));
        assert_eq!(owner.metrics().leases, 0);
        assert_eq!(owner.close(), Ok(()));
    }

    #[test]
    fn empty_loans_consume_count_quota_and_invalid_spans_consume_nothing() {
        let owner = owner(0, 1);
        let released = releases();
        let (_, token) = resource(&[], 1, &released);
        for (base, length) in [
            (std::ptr::null(), 1),
            (std::ptr::dangling::<u8>(), usize::MAX),
            (usize::MAX as *const u8, 1),
        ] {
            assert_eq!(
                unsafe { owner.admit(base, length, release_resource, token) }.err(),
                Some(LeaseError::InvalidArgument)
            );
            assert_eq!(owner.metrics().leases, 0);
        }
        let loan = unsafe { owner.admit(std::ptr::null(), 0, release_resource, token) }.unwrap();
        assert!(loan.as_ref().is_empty());
        assert_eq!(owner.metrics().bytes, 0);
        assert_eq!(owner.metrics().leases, 1);
        assert_eq!(
            unsafe { owner.admit(std::ptr::null(), 0, release_resource, token) }.err(),
            Some(LeaseError::QuotaExceeded)
        );
        drop(loan);
        assert!(released.lock().unwrap().is_empty());
        assert_eq!(owner.dispatch(1), Ok(1));
        assert_eq!(released.lock().unwrap().len(), 1);
    }

    #[test]
    fn bounded_queue_reuses_reserved_capacity_across_partial_drains() {
        let owner = owner(6, 3);
        let released = releases();
        let capacity = owner.state().releases.capacity();
        for cycle in 0..20 {
            for slot in 0..3 {
                let (base, token) = resource(&[1, 2], cycle * 3 + slot, &released);
                let loan = unsafe { owner.admit(base, 2, release_resource, token) }.unwrap();
                thread::spawn(move || drop(loan)).join().unwrap();
            }
            assert_eq!(owner.metrics().leases, 3);
            assert_eq!(owner.metrics().pending_releases, 3);
            assert_eq!(owner.state().releases.capacity(), capacity);
            assert_eq!(owner.dispatch(2), Ok(2));
            assert_eq!(owner.metrics().bytes, 2);
            assert_eq!(owner.metrics().leases, 1);
            assert_eq!(owner.dispatch(2), Ok(1));
            assert_eq!(owner.state().releases.capacity(), capacity);
        }
        assert_eq!(released.lock().unwrap().len(), 60);
        assert_eq!(owner.close(), Ok(()));
        assert!(matches!(
            LeaseOwner::new(LeaseLimits {
                bytes: 0,
                leases: 0
            }),
            Err(LeaseError::InvalidArgument)
        ));
    }
}
