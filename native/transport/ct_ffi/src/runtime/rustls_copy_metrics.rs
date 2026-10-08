//! Named partial Rustls source-copy observations; not a total TLS-copy metric.
//! Snapshots are cumulative and process-wide, without synchronizing concurrent
//! TLS operations. The original transport snapshot ABIs remain unchanged.

use super::constants::{ERR_INVALID_ARGUMENT, SUCCESS};

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CtRustlsCopyMetricsInfo {
    pub outbound_chunk_copy_bytes_total: u64,
    pub queue_read_copy_bytes_total: u64,
    pub deframer_append_copy_bytes_total: u64,
    pub deframer_move_copy_bytes_total: u64,
    pub record_buffer_copy_bytes_total: u64,
    pub record_append_copy_bytes_total: u64,
}

#[no_mangle]
pub extern "C" fn ct_rustls_copy_metrics_snapshot(out: *mut CtRustlsCopyMetricsInfo) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let observed = ct_core::rustls_copy_metrics_snapshot();
    unsafe {
        out.write(CtRustlsCopyMetricsInfo {
            outbound_chunk_copy_bytes_total: observed.outbound_chunk_copy_bytes,
            queue_read_copy_bytes_total: observed.queue_read_copy_bytes,
            deframer_append_copy_bytes_total: observed.deframer_append_copy_bytes,
            deframer_move_copy_bytes_total: observed.deframer_move_copy_bytes,
            record_buffer_copy_bytes_total: observed.record_buffer_copy_bytes,
            record_append_copy_bytes_total: observed.record_append_copy_bytes,
        });
    }
    SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_rustls_snapshot_keeps_its_layout_and_does_not_overwrite_tail() {
        #[repr(C)]
        struct Guarded {
            snapshot: CtRustlsCopyMetricsInfo,
            sentinel: u64,
        }
        assert_eq!(std::mem::size_of::<CtRustlsCopyMetricsInfo>(), 48);
        assert_eq!(std::mem::align_of::<CtRustlsCopyMetricsInfo>(), 8);
        let mut guarded = Guarded {
            snapshot: CtRustlsCopyMetricsInfo::default(),
            sentinel: 0xfedc_ba98_7654_3210,
        };
        assert_eq!(
            ct_rustls_copy_metrics_snapshot(&mut guarded.snapshot),
            SUCCESS
        );
        assert_eq!(guarded.sentinel, 0xfedc_ba98_7654_3210);
        let after = ct_core::rustls_copy_metrics_snapshot();
        let ffi = guarded.snapshot;
        assert!(ffi.outbound_chunk_copy_bytes_total <= after.outbound_chunk_copy_bytes);
        assert!(ffi.queue_read_copy_bytes_total <= after.queue_read_copy_bytes);
        assert!(ffi.deframer_append_copy_bytes_total <= after.deframer_append_copy_bytes);
        assert!(ffi.deframer_move_copy_bytes_total <= after.deframer_move_copy_bytes);
        assert!(ffi.record_buffer_copy_bytes_total <= after.record_buffer_copy_bytes);
        assert!(ffi.record_append_copy_bytes_total <= after.record_append_copy_bytes);
        assert_eq!(
            ct_rustls_copy_metrics_snapshot(std::ptr::null_mut()),
            ERR_INVALID_ARGUMENT
        );
    }
}
