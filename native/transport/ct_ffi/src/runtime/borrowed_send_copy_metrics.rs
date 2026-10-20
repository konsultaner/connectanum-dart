//! Actual Rust copies of borrowed outbound WAMP inputs, separate from Dart
//! staging, transport framing and cryptographic transformations. Owned sends
//! adopt their allocations and do not increment this counter. Copies made
//! before a later validation/enqueue error still count.

use super::constants::{ERR_INVALID_ARGUMENT, SUCCESS};
use std::sync::atomic::{AtomicU64, Ordering};

static COPIED_BYTES: AtomicU64 = AtomicU64::new(0);

pub(super) fn copy_borrowed_send_input(input: &[u8]) -> bytes::Bytes {
    let output = bytes::Bytes::copy_from_slice(input);
    COPIED_BYTES.fetch_add(input.len() as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|value| value.set(value.get() + input.len() as u64));
    output
}

#[cfg(test)]
thread_local! {
    static OBSERVED: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

#[cfg(test)]
fn observed() -> u64 {
    OBSERVED.with(std::cell::Cell::get)
}

/// Separate optional scalar ABI; existing 24/40/48-byte snapshots are unchanged.
#[no_mangle]
pub extern "C" fn ct_ffi_borrowed_send_copy_metrics_snapshot(out: *mut u64) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe { out.write(COPIED_BYTES.load(Ordering::Relaxed)) };
    SUCCESS
}

#[cfg(test)]
mod tests {
    use super::super::ffi::*;
    use super::*;
    use std::ptr;

    #[test]
    fn borrowed_send_counts_copies_before_connection_rejection() {
        let input = [1u8, 2, 3];
        let before = observed();
        assert_ne!(ct_send_message(0, input.as_ptr(), 3), SUCCESS);
        assert_eq!(observed() - before, 3);
        assert_ne!(ct_send_message_fragmented(0, input.as_ptr(), 3, 1), SUCCESS);
        assert_eq!(observed() - before, 6);
    }

    #[test]
    fn validation_and_empty_inputs_do_not_copy() {
        let input = [1u8, 2, 3];
        let before = observed();
        assert_eq!(ct_send_message(0, ptr::null(), 3), ERR_INVALID_ARGUMENT);
        assert_eq!(ct_send_message(0, input.as_ptr(), -1), ERR_INVALID_ARGUMENT);
        assert_eq!(
            ct_send_message_fragmented(0, input.as_ptr(), 3, 0),
            ERR_INVALID_ARGUMENT
        );
        assert_ne!(ct_send_message(0, ptr::null(), 0), SUCCESS);
        assert_eq!(observed(), before);
    }

    #[test]
    fn file_wrappers_count_copies_even_when_submission_fails() {
        let prefix = [1u8, 2, 3];
        let suffix = [4u8, 5];
        let before = observed();
        assert_ne!(
            ct_send_message_file_segment(0, prefix.as_ptr(), 3, 1, 0, 1, suffix.as_ptr(), 2),
            SUCCESS
        );
        assert_eq!(observed() - before, 5);
        assert_ne!(
            ct_send_message_base64_file_segment(0, prefix.as_ptr(), 3, 1, 0, 1, suffix.as_ptr(), 2),
            SUCCESS
        );
        assert_eq!(observed() - before, 10);
        // The E2EE wrapper copies the prefix before validating suffix length.
        assert_eq!(
            ct_send_message_native_e2ee_file_segment_v2(
                1,
                prefix.as_ptr(),
                3,
                1,
                0,
                1,
                1,
                ptr::null(),
                0,
                0,
                suffix.as_ptr(),
                -1,
                0
            ),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(observed() - before, 13);
    }

    #[test]
    fn owned_sends_adopt_valid_allocations_on_rejection_without_copying() {
        let before = observed();
        for fragmented in [false, true] {
            let data = ct_outbound_buffer_alloc(3);
            assert!(!data.is_null());
            unsafe { ptr::copy_nonoverlapping([1u8, 2, 3].as_ptr(), data, 3) };
            let result = if fragmented {
                ct_send_message_fragmented_owned(0, data, 3, 1)
            } else {
                ct_send_message_owned(0, data, 3)
            };
            assert_ne!(result, SUCCESS);
            // The valid allocation has been consumed; no caller free follows.
        }
        assert_eq!(observed(), before);
    }

    #[test]
    fn snapshot_rejects_null_and_preserves_adjacent_storage() {
        let before = COPIED_BYTES.load(Ordering::Relaxed);
        let mut storage = [0x12345678u64, u64::MAX, 0x76543210];
        assert_eq!(
            ct_ffi_borrowed_send_copy_metrics_snapshot(&mut storage[1]),
            SUCCESS
        );
        assert!(storage[1] >= before);
        assert!(storage[1] <= COPIED_BYTES.load(Ordering::Relaxed));
        assert_eq!(storage[0], 0x12345678);
        assert_eq!(storage[2], 0x76543210);
        assert_eq!(
            ct_ffi_borrowed_send_copy_metrics_snapshot(ptr::null_mut()),
            ERR_INVALID_ARGUMENT
        );
    }
}
