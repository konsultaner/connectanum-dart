//! Bounded local write receipts. They contain no payload storage and survive
//! runtime shutdown so callers can still observe abandonment.
use super::constants::*;
use super::owned_buffers::submit_frozen;
use super::resource_handles::insert_resource;
use ct_core::{drain_wamp_writes, send_wamp_message_tracked, ConnectionId, WriteReceipt};
use dashmap::{mapref::entry::Entry, DashMap};
use std::ffi::c_void;
use std::sync::atomic::{AtomicU32, AtomicUsize, Ordering};
use std::sync::OnceLock;

const MAX_RECEIPTS: usize = 8192;

struct ReceiptStore {
    next: AtomicU32,
    count: AtomicUsize,
    maximum: usize,
    entries: DashMap<u32, Option<WriteReceipt>>,
}

impl ReceiptStore {
    fn new(maximum: usize) -> Self {
        Self {
            next: AtomicU32::new(1),
            count: AtomicUsize::new(0),
            maximum,
            entries: DashMap::new(),
        }
    }

    fn reserve(&self) -> Result<Reservation<'_>, i32> {
        self.count
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |count| {
                (count < self.maximum).then(|| count + 1)
            })
            .map_err(|_| ERR_WRITE_RECEIPT_QUOTA_EXCEEDED)?;
        match insert_resource(&self.next, &self.entries, None) {
            Ok(handle) => Ok(Reservation {
                store: self,
                handle,
                committed: false,
            }),
            Err(_) => {
                self.count.fetch_sub(1, Ordering::AcqRel);
                Err(ERR_HANDLE_UNAVAILABLE)
            }
        }
    }

    fn outcome(&self, handle: i32) -> Result<i32, i32> {
        if handle <= 0 {
            return Err(ERR_INVALID_ARGUMENT);
        }
        self.entries
            .get(&(handle as u32))
            .and_then(|entry| entry.as_ref().map(|receipt| receipt.outcome() as i32))
            .ok_or(ERR_INVALID_ARGUMENT)
    }

    fn release(&self, handle: i32) -> Result<(), i32> {
        if handle <= 0 {
            return Err(ERR_INVALID_ARGUMENT);
        }
        match self.entries.entry(handle as u32) {
            Entry::Occupied(entry) if entry.get().is_some() => {
                entry.remove();
                self.count.fetch_sub(1, Ordering::AcqRel);
                Ok(())
            }
            _ => Err(ERR_INVALID_ARGUMENT),
        }
    }
}

struct Reservation<'a> {
    store: &'a ReceiptStore,
    handle: u32,
    committed: bool,
}

impl Reservation<'_> {
    fn commit(mut self, receipt: WriteReceipt) -> i32 {
        // Public release/outcome reject reservations; this entry cannot vanish.
        *self
            .store
            .entries
            .get_mut(&self.handle)
            .expect("reserved receipt") = Some(receipt);
        self.committed = true;
        self.handle as i32
    }
}

impl Drop for Reservation<'_> {
    fn drop(&mut self) {
        if !self.committed {
            self.store.entries.remove(&self.handle);
            self.store.count.fetch_sub(1, Ordering::AcqRel);
        }
    }
}

fn receipts() -> &'static ReceiptStore {
    static STORE: OnceLock<ReceiptStore> = OnceLock::new();
    STORE.get_or_init(|| ReceiptStore::new(MAX_RECEIPTS))
}

#[no_mangle]
pub extern "C" fn ct_write_receipt_abi_version() -> u32 {
    1
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_write_receipt_live_handles() -> usize {
    receipts().count.load(Ordering::Acquire)
}

/// Consume a valid frozen handle even on runtime/connection/queue/receipt-quota
/// rejection. Returns a positive receipt handle on queue acceptance, or error.
/// Unknown/mutable buffer handles are not consumed. Receipts must be released.
#[no_mangle]
pub extern "C" fn ct_owned_buffer_send_tracked(connection: i32, buffer: i32) -> i32 {
    submit_frozen(buffer, |payload| {
        let reservation = match receipts().reserve() {
            Ok(value) => value,
            Err(error) => return error,
        };
        match send_wamp_message_tracked(ConnectionId(connection as u32), payload) {
            Ok(receipt) => reservation.commit(receipt),
            Err(error) => super::ffi::map_error(error),
        }
    })
}

/// Positive receipt handle for a FIFO flush barrier; no protocol frame emitted.
#[no_mangle]
pub extern "C" fn ct_connection_drain_writes(connection: i32) -> i32 {
    let reservation = match receipts().reserve() {
        Ok(value) => value,
        Err(error) => return error,
    };
    match drain_wamp_writes(ConnectionId(connection as u32)) {
        Ok(receipt) => reservation.commit(receipt),
        Err(error) => super::ffi::map_error(error),
    }
}

/// 0 pending, 1 full frame written and flushed, 2 abandoned; negative error.
#[no_mangle]
pub extern "C" fn ct_write_receipt_state(handle: i32) -> i32 {
    receipts().outcome(handle).unwrap_or_else(|error| error)
}

#[no_mangle]
pub extern "C" fn ct_write_receipt_release(handle: i32) -> i32 {
    receipts()
        .release(handle)
        .map(|_| SUCCESS)
        .unwrap_or_else(|error| error)
}

#[no_mangle]
pub extern "C" fn ct_write_receipt_finalizer(token: *mut c_void) {
    let handle = token as usize;
    if handle > 0 && handle <= i32::MAX as usize {
        let _ = receipts().release(handle as i32);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reservation_is_bounded_invisible_rollback_safe_and_non_recycled() {
        let store = ReceiptStore::new(1);
        let first = store.reserve().unwrap();
        let id = first.handle as i32;
        assert_eq!(store.outcome(id), Err(ERR_INVALID_ARGUMENT));
        assert_eq!(store.release(id), Err(ERR_INVALID_ARGUMENT));
        assert_eq!(
            store.reserve().err(),
            Some(ERR_WRITE_RECEIPT_QUOTA_EXCEEDED)
        );
        drop(first);
        assert_eq!(store.count.load(Ordering::Acquire), 0);
        let second = store.reserve().unwrap();
        assert_ne!(second.handle as i32, id);
        drop(second);
        store.next.store(i32::MAX as u32 + 1, Ordering::Release);
        assert_eq!(store.reserve().err(), Some(ERR_HANDLE_UNAVAILABLE));
        assert_eq!(store.count.load(Ordering::Acquire), 0);
    }

    #[test]
    fn rejected_submission_consumes_only_frozen_buffers_and_restores_receipt_budget() {
        use super::super::owned_buffers::*;
        let before = receipts().count.load(Ordering::Acquire);
        let mutable = ct_owned_buffer_allocate(8);
        assert!(mutable > 0);
        assert_eq!(
            ct_owned_buffer_send_tracked(0, mutable),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(ct_owned_buffer_freeze(mutable, 0, 8), SUCCESS);
        assert!(ct_owned_buffer_send_tracked(0, mutable) < 0);
        assert_eq!(ct_owned_buffer_release(mutable), ERR_INVALID_ARGUMENT);
        assert!(ct_connection_drain_writes(0) < 0);
        assert_eq!(receipts().count.load(Ordering::Acquire), before);
        assert_eq!(ct_write_receipt_abi_version(), 1);
        assert_eq!(ct_write_receipt_state(0), ERR_INVALID_ARGUMENT);
        assert_eq!(ct_write_receipt_release(-1), ERR_INVALID_ARGUMENT);
        ct_write_receipt_finalizer(std::ptr::null_mut());
    }
}
