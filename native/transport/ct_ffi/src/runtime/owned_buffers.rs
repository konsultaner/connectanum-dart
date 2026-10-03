//! Handle-owned, initialized outbound storage. Foreign/interior pointers are
//! never adopted. A mutable pointer borrow must end before freeze or release.

use super::constants::{ERR_HANDLE_UNAVAILABLE, ERR_INVALID_ARGUMENT, ERR_IO, SUCCESS};
use super::ffi::CtMessageByteView;
use super::resource_handles::insert_resource;
use bytes::Bytes;
use dashmap::{mapref::entry::Entry, DashMap};
use std::ffi::c_void;
use std::ops::Range;
use std::ptr;
use std::sync::atomic::AtomicU32;
use std::sync::OnceLock;

#[cfg(any(test, feature = "ffi-test"))]
static LIVE_ALLOCATIONS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

#[cfg(feature = "ffi-test")]
static LAST_FROZEN_ALIGNMENT: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);

#[cfg(any(test, feature = "ffi-test"))]
impl Drop for Allocation {
    fn drop(&mut self) {
        LIVE_ALLOCATIONS.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
    }
}

struct Allocation {
    storage: Vec<u8>,
    #[cfg(test)]
    lifetime: std::sync::Arc<()>,
}

impl AsRef<[u8]> for Allocation {
    fn as_ref(&self) -> &[u8] {
        &self.storage
    }
}

#[derive(Clone)]
struct Frozen {
    allocation: Bytes,
    capacity: usize,
    range: Range<usize>,
}

impl Frozen {
    fn bytes(&self) -> Bytes {
        self.allocation.slice(self.range.clone())
    }
}

enum Storage {
    Mutable(Allocation),
    Frozen(Frozen),
}

struct BufferStore {
    next: AtomicU32,
    entries: DashMap<u32, Storage>,
}

impl Default for BufferStore {
    fn default() -> Self {
        Self {
            next: AtomicU32::new(1),
            entries: DashMap::new(),
        }
    }
}

impl BufferStore {
    fn allocate(&self, length: usize) -> Result<u32, i32> {
        if length > i32::MAX as usize {
            return Err(ERR_INVALID_ARGUMENT);
        }
        let mut storage = Vec::new();
        storage.try_reserve_exact(length).map_err(|_| ERR_IO)?;
        storage.resize(length, 0);
        #[cfg(any(test, feature = "ffi-test"))]
        LIVE_ALLOCATIONS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let allocation = Allocation {
            storage,
            #[cfg(test)]
            lifetime: std::sync::Arc::new(()),
        };
        self.insert(Storage::Mutable(allocation))
    }

    fn insert(&self, storage: Storage) -> Result<u32, i32> {
        insert_resource(&self.next, &self.entries, storage).map_err(|_| ERR_HANDLE_UNAVAILABLE)
    }

    fn info(&self, handle: u32) -> Result<CtOwnedBufferInfo, i32> {
        let storage = self.entries.get(&handle).ok_or(ERR_INVALID_ARGUMENT)?;
        Ok(match storage.value() {
            Storage::Mutable(allocation) => CtOwnedBufferInfo {
                base: allocation.storage.as_ptr(),
                capacity: allocation.storage.capacity(),
                initialized_length: allocation.storage.len(),
                offset: 0,
                length: allocation.storage.len(),
                writable: 1,
            },
            Storage::Frozen(frozen) => CtOwnedBufferInfo {
                base: frozen.allocation.as_ptr(),
                capacity: frozen.capacity,
                initialized_length: frozen.allocation.len(),
                offset: frozen.range.start,
                length: frozen.range.len(),
                writable: 0,
            },
        })
    }

    fn freeze(&self, handle: u32, offset: usize, length: usize) -> Result<(), i32> {
        let mut storage = self.entries.get_mut(&handle).ok_or(ERR_INVALID_ARGUMENT)?;
        let Storage::Mutable(allocation) = storage.value() else {
            return Err(ERR_INVALID_ARGUMENT);
        };
        let end = offset.checked_add(length).ok_or(ERR_INVALID_ARGUMENT)?;
        if end > allocation.storage.len() {
            return Err(ERR_INVALID_ARGUMENT);
        }
        #[cfg(feature = "ffi-test")]
        LAST_FROZEN_ALIGNMENT.store(
            (allocation.storage.as_ptr() as usize + offset) % 8,
            std::sync::atomic::Ordering::SeqCst,
        );
        let capacity = allocation.storage.capacity();
        // Replace only after complete validation. No external pointer is
        // reconstructed as a Vec; its original initialized allocation moves.
        let previous = std::mem::replace(
            storage.value_mut(),
            Storage::Frozen(Frozen {
                allocation: Bytes::new(),
                capacity: 0,
                range: 0..0,
            }),
        );
        let Storage::Mutable(allocation) = previous else {
            unreachable!()
        };
        *storage = Storage::Frozen(Frozen {
            allocation: Bytes::from_owner(allocation),
            capacity,
            range: offset..end,
        });
        Ok(())
    }

    fn frozen(&self, handle: u32) -> Result<Frozen, i32> {
        let storage = self.entries.get(&handle).ok_or(ERR_INVALID_ARGUMENT)?;
        match storage.value() {
            Storage::Frozen(frozen) => Ok(frozen.clone()),
            Storage::Mutable(_) => Err(ERR_INVALID_ARGUMENT),
        }
    }

    fn slice(&self, handle: u32, offset: usize, length: usize) -> Result<u32, i32> {
        let mut frozen = self.frozen(handle)?;
        let end = offset.checked_add(length).ok_or(ERR_INVALID_ARGUMENT)?;
        if end > frozen.range.len() {
            return Err(ERR_INVALID_ARGUMENT);
        }
        frozen.range = frozen.range.start + offset..frozen.range.start + end;
        self.insert(Storage::Frozen(frozen))
    }

    fn take(&self, handle: u32) -> Result<Bytes, i32> {
        match self.entries.entry(handle) {
            Entry::Occupied(entry) if matches!(entry.get(), Storage::Frozen(_)) => {
                let Storage::Frozen(frozen) = entry.remove() else {
                    unreachable!()
                };
                Ok(frozen.bytes())
            }
            _ => Err(ERR_INVALID_ARGUMENT),
        }
    }

    fn release(&self, handle: u32) -> Result<(), i32> {
        self.entries
            .remove(&handle)
            .map(|_| ())
            .ok_or(ERR_INVALID_ARGUMENT)
    }
}

static STORE: OnceLock<BufferStore> = OnceLock::new();

fn store() -> &'static BufferStore {
    // Not cleared on runtime shutdown: queued writes, builders and exported
    // typed-data views have independent lifetimes. IDs are never recycled.
    STORE.get_or_init(BufferStore::default)
}

pub(super) fn take_frozen(handle: i32) -> Result<Bytes, i32> {
    if handle <= 0 {
        return Err(ERR_INVALID_ARGUMENT);
    }
    store().take(handle as u32)
}

pub(super) fn submit_frozen(handle: i32, submit: impl FnOnce(Bytes) -> i32) -> i32 {
    match take_frozen(handle) {
        Ok(payload) => submit(payload),
        Err(error) => error,
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CtOwnedBufferInfo {
    pub base: *const u8,
    pub capacity: usize,
    pub initialized_length: usize,
    pub offset: usize,
    pub length: usize,
    pub writable: i32,
}

#[no_mangle]
pub extern "C" fn ct_owned_buffer_abi_version() -> u32 {
    1
}

// Test-only observations count actual allocation drops, rather than wrapper
// reachability. They are absent from production libraries.
#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_owned_buffer_live_allocations() -> usize {
    LIVE_ALLOCATIONS.load(std::sync::atomic::Ordering::SeqCst)
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_owned_buffer_live_handles() -> usize {
    store().entries.len()
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_owned_buffer_last_frozen_alignment() -> usize {
    LAST_FROZEN_ALIGNMENT.load(std::sync::atomic::Ordering::SeqCst)
}

#[no_mangle]
pub extern "C" fn ct_owned_buffer_allocate(length: i32) -> i32 {
    if length < 0 {
        return ERR_INVALID_ARGUMENT;
    }
    store()
        .allocate(length as usize)
        .map(|id| id as i32)
        .unwrap_or_else(|error| error)
}

/// The mutable borrow of base is valid only until freeze/release and must not
/// overlap those operations. Frozen base is read-only. Use export for a view
/// that must outlive a handle, including all asynchronous access.
#[no_mangle]
pub extern "C" fn ct_owned_buffer_info(handle: i32, out: *mut CtOwnedBufferInfo) -> i32 {
    if out.is_null() || handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    match store().info(handle as u32) {
        Ok(info) => {
            unsafe {
                out.write(info);
            }
            SUCCESS
        }
        Err(error) => error,
    }
}

#[no_mangle]
pub extern "C" fn ct_owned_buffer_freeze(handle: i32, offset: usize, length: usize) -> i32 {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    store()
        .freeze(handle as u32, offset, length)
        .map(|_| SUCCESS)
        .unwrap_or_else(|error| error)
}

#[no_mangle]
pub extern "C" fn ct_owned_buffer_slice(handle: i32, offset: usize, length: usize) -> i32 {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    store()
        .slice(handle as u32, offset, length)
        .map(|id| id as i32)
        .unwrap_or_else(|error| error)
}

#[no_mangle]
pub extern "C" fn ct_owned_buffer_release(handle: i32) -> i32 {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    store()
        .release(handle as u32)
        .map(|_| SUCCESS)
        .unwrap_or_else(|error| error)
}

/// A token encoding a monotonic handle, not an allocation pointer. It is never
/// dereferenced or freed and an already released handle is harmless.
#[no_mangle]
pub extern "C" fn ct_owned_buffer_handle_finalizer(token: *mut c_void) {
    let handle = token as usize;
    if handle > 0 && handle <= i32::MAX as usize {
        let _ = store().release(handle as u32);
    }
}

#[no_mangle]
pub extern "C" fn ct_owned_buffer_export(handle: i32, out: *mut CtMessageByteView) -> i32 {
    if out.is_null() || handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe {
        out.write(CtMessageByteView {
            ptr: ptr::null(),
            len: 0,
            owner: ptr::null_mut(),
        });
    }
    let frozen = match store().frozen(handle as u32) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let data = unsafe { frozen.allocation.as_ptr().add(frozen.range.start) };
    let len = frozen.range.len();
    let owner = Box::into_raw(Box::new(frozen)).cast();
    unsafe {
        out.write(CtMessageByteView {
            ptr: data,
            len,
            owner,
        });
    }
    SUCCESS
}

/// Takes exactly the token returned by export, once. Typed-data subviews retain
/// the backing allocation; never call this on their data pointer or a handle.
#[no_mangle]
pub extern "C" fn ct_owned_buffer_view_finalizer(owner: *mut c_void) {
    if !owner.is_null() {
        unsafe {
            drop(Box::from_raw(owner.cast::<Frozen>()));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn observer(store: &BufferStore, handle: u32) -> std::sync::Weak<()> {
        let storage = store.entries.get(&handle).unwrap();
        let Storage::Mutable(allocation) = storage.value() else {
            panic!("mutable allocation")
        };
        std::sync::Arc::downgrade(&allocation.lifetime)
    }

    #[test]
    fn freeze_keeps_backward_subrange_pointer_and_capacity_without_copying() {
        let store = BufferStore::default();
        let handle = store.allocate(64).unwrap();
        let initial = store.info(handle).unwrap();
        assert!(unsafe { std::slice::from_raw_parts(initial.base, 64) }
            .iter()
            .all(|b| *b == 0));
        unsafe {
            ptr::copy_nonoverlapping([1u8, 2, 3, 4].as_ptr(), initial.base.cast_mut().add(60), 4);
        }
        store.freeze(handle, 60, 4).unwrap();
        let frozen = store.info(handle).unwrap();
        assert_eq!(frozen.base, initial.base);
        assert_eq!(frozen.capacity, initial.capacity);
        assert_eq!((frozen.offset, frozen.length, frozen.writable), (60, 4, 0));
        let bytes = store.take(handle).unwrap();
        assert_eq!(bytes.as_ptr(), unsafe { initial.base.add(60) });
        assert_eq!(bytes.as_ref(), &[1, 2, 3, 4]);
        assert_eq!(store.take(handle).unwrap_err(), ERR_INVALID_ARGUMENT);
    }

    #[test]
    fn invalid_freeze_and_mutable_take_do_not_consume_or_change_storage() {
        let store = BufferStore::default();
        let handle = store.allocate(8).unwrap();
        for range in [(9, 0), (7, 2), (usize::MAX, 1)] {
            assert_eq!(
                store.freeze(handle, range.0, range.1),
                Err(ERR_INVALID_ARGUMENT)
            );
            assert_eq!(store.info(handle).unwrap().writable, 1);
        }
        assert_eq!(store.take(handle).unwrap_err(), ERR_INVALID_ARGUMENT);
        store.freeze(handle, 8, 0).unwrap();
        assert_eq!(store.freeze(handle, 0, 0), Err(ERR_INVALID_ARGUMENT));
        assert!(store.take(handle).unwrap().is_empty());
    }

    #[test]
    fn retained_and_empty_slices_hold_original_owner_until_last_release() {
        let store = BufferStore::default();
        let handle = store.allocate(8).unwrap();
        let lifetime = observer(&store, handle);
        let base = store.info(handle).unwrap().base;
        store.freeze(handle, 2, 6).unwrap();
        let slice = store.slice(handle, 1, 3).unwrap();
        let empty = store.slice(slice, 3, 0).unwrap();
        assert_eq!(store.info(slice).unwrap().base, base);
        assert_eq!(store.info(slice).unwrap().offset, 3);
        assert_eq!(store.info(empty).unwrap().offset, 6);
        assert_eq!(store.slice(slice, 3, 1), Err(ERR_INVALID_ARGUMENT));
        store.release(handle).unwrap();
        store.release(slice).unwrap();
        assert!(lifetime.upgrade().is_some());
        store.release(empty).unwrap();
        assert!(lifetime.upgrade().is_none());
        assert_eq!(store.release(empty), Err(ERR_INVALID_ARGUMENT));
        assert_ne!(store.allocate(0).unwrap(), empty);
    }

    #[test]
    fn export_finalizer_owner_outlives_handle_and_is_released_exactly_once() {
        let handle = ct_owned_buffer_allocate(16);
        let lifetime = observer(store(), handle as u32);
        let initial = store().info(handle as u32).unwrap();
        assert_eq!(ct_owned_buffer_freeze(handle, 8, 8), SUCCESS);
        let mut view = CtMessageByteView {
            ptr: ptr::null(),
            len: 0,
            owner: ptr::null_mut(),
        };
        assert_eq!(ct_owned_buffer_export(handle, &mut view), SUCCESS);
        assert_eq!(view.ptr, unsafe { initial.base.add(8) });
        assert_eq!(view.len, 8);
        assert_eq!(ct_owned_buffer_release(handle), SUCCESS);
        assert!(lifetime.upgrade().is_some());
        assert_eq!(
            unsafe { std::slice::from_raw_parts(view.ptr, view.len) },
            &[0; 8]
        );
        ct_owned_buffer_view_finalizer(view.owner);
        assert!(lifetime.upgrade().is_none());
        ct_owned_buffer_handle_finalizer(handle as usize as *mut c_void);
        assert_eq!(ct_owned_buffer_release(handle), ERR_INVALID_ARGUMENT);
    }

    #[test]
    fn concurrent_transfers_have_one_owner_and_never_reuse_stale_handles() {
        let store = std::sync::Arc::new(BufferStore::default());
        let handle = store.allocate(8).unwrap();
        let lifetime = observer(&store, handle);
        store.freeze(handle, 0, 8).unwrap();
        let threads: Vec<_> = (0..4)
            .map(|_| {
                let store = store.clone();
                std::thread::spawn(move || store.take(handle))
            })
            .collect();
        let results: Vec<_> = threads.into_iter().map(|t| t.join().unwrap()).collect();
        assert_eq!(results.iter().filter(|r| r.is_ok()).count(), 1);
        assert!(lifetime.upgrade().is_some());
        drop(results);
        assert!(lifetime.upgrade().is_none());
        assert_ne!(store.allocate(8).unwrap(), handle);
    }

    #[test]
    fn rejected_send_consumes_frozen_but_preserves_mutable_handle() {
        let handle = ct_owned_buffer_allocate(8);
        let lifetime = observer(store(), handle as u32);
        assert!(super::super::ffi::ct_owned_buffer_send(0, handle) < 0);
        assert_eq!(store().info(handle as u32).unwrap().writable, 1);
        assert_eq!(ct_owned_buffer_freeze(handle, 4, 4), SUCCESS);
        assert!(super::super::ffi::ct_owned_buffer_send(0, handle) < 0);
        assert_eq!(ct_owned_buffer_release(handle), ERR_INVALID_ARGUMENT);
        assert!(lifetime.upgrade().is_none());
    }

    #[test]
    fn submission_preserves_used_pointer_and_releases_on_queue_rejection() {
        let handle = ct_owned_buffer_allocate(64);
        let lifetime = observer(store(), handle as u32);
        let base = store().info(handle as u32).unwrap().base;
        assert_eq!(ct_owned_buffer_freeze(handle, 56, 8), SUCCESS);
        let mut accepted = None;
        assert_eq!(
            submit_frozen(handle, |payload| {
                assert_eq!(payload.as_ptr(), unsafe { base.add(56) });
                accepted = Some(payload);
                SUCCESS
            }),
            SUCCESS
        );
        assert_eq!(ct_owned_buffer_release(handle), ERR_INVALID_ARGUMENT);
        assert!(lifetime.upgrade().is_some());
        drop(accepted);
        assert!(lifetime.upgrade().is_none());

        let rejected = ct_owned_buffer_allocate(16);
        let lifetime = observer(store(), rejected as u32);
        assert_eq!(ct_owned_buffer_freeze(rejected, 8, 8), SUCCESS);
        assert_eq!(
            submit_frozen(rejected, |_| super::super::constants::ERR_SEND_QUEUE_FULL),
            super::super::constants::ERR_SEND_QUEUE_FULL
        );
        assert!(lifetime.upgrade().is_none());
        assert_eq!(ct_owned_buffer_release(rejected), ERR_INVALID_ARGUMENT);
    }
}
