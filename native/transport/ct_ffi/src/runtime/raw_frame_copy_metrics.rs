//! Additive observations of owned native raw-frame copies.
use super::constants::{ERR_INVALID_ARGUMENT, SUCCESS};

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CtRawFrameCopyMetricsInfo {
    pub coalescing_copy_bytes_total: u64,
    pub range_copy_bytes_total: u64,
    pub single_segment_contiguous_requests_total: u64,
    pub multi_segment_contiguous_requests_total: u64,
}

#[no_mangle]
pub extern "C" fn ct_raw_frame_copy_metrics_abi_version() -> u32 {
    1
}

/// Cumulative process observations; does not synchronize in-flight parsing.
#[no_mangle]
pub extern "C" fn ct_raw_frame_copy_metrics_snapshot(out: *mut CtRawFrameCopyMetricsInfo) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let value = ct_core::raw_frame_copy_metrics_snapshot();
    unsafe {
        out.write(CtRawFrameCopyMetricsInfo {
            coalescing_copy_bytes_total: value.coalescing_copy_bytes_total,
            range_copy_bytes_total: value.range_copy_bytes_total,
            single_segment_contiguous_requests_total: value
                .single_segment_contiguous_requests_total,
            multi_segment_contiguous_requests_total: value.multi_segment_contiguous_requests_total,
        });
    }
    SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn raw_frame_metrics_v1_preserves_guards_and_rejects_null() {
        assert_eq!(ct_raw_frame_copy_metrics_abi_version(), 1);
        assert_eq!(std::mem::size_of::<CtRawFrameCopyMetricsInfo>(), 32);
        assert_eq!(std::mem::align_of::<CtRawFrameCopyMetricsInfo>(), 8);
        assert_eq!(
            ct_raw_frame_copy_metrics_snapshot(std::ptr::null_mut()),
            ERR_INVALID_ARGUMENT
        );
        #[repr(C)]
        struct Guarded {
            before: u64,
            value: CtRawFrameCopyMetricsInfo,
            after: u64,
        }
        let mut guarded = Guarded {
            before: 0x123456789abcdef,
            value: CtRawFrameCopyMetricsInfo::default(),
            after: 0xabcdef123456789,
        };
        assert_eq!(
            ct_raw_frame_copy_metrics_snapshot(&mut guarded.value),
            SUCCESS
        );
        assert_eq!(guarded.before, 0x123456789abcdef);
        assert_eq!(guarded.after, 0xabcdef123456789);
    }
}
