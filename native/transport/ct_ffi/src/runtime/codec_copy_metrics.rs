//! Additive observations of explicit native codec copies.
use super::constants::{ERR_INVALID_ARGUMENT, SUCCESS};

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CtCodecCopyMetricsInfo {
    pub vector_copy_bytes_total: u64,
    pub string_copy_bytes_total: u64,
    pub growth_copy_bytes_total: u64,
    pub parser_read_copy_bytes_total: u64,
    pub framing_copy_bytes_total: u64,
    pub key_material_copy_bytes_total: u64,
}
#[no_mangle]
pub extern "C" fn ct_codec_copy_metrics_abi_version() -> u32 {
    1
}

/// Completeness of the source-level byte-buffer inventory, independent of the
/// unchanged six-u64 v1 layout. Earlier partial v1 producers lack this symbol.
#[no_mangle]
pub extern "C" fn ct_codec_copy_metrics_coverage_version() -> u32 {
    1
}

/// Cumulative process observations; callers must first settle their workload.
#[no_mangle]
pub extern "C" fn ct_codec_copy_metrics_snapshot(out: *mut CtCodecCopyMetricsInfo) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let value = ct_core::codec_copy_metrics_snapshot();
    unsafe {
        out.write(CtCodecCopyMetricsInfo {
            vector_copy_bytes_total: value.vector_copy_bytes_total,
            string_copy_bytes_total: value.string_copy_bytes_total,
            growth_copy_bytes_total: value.growth_copy_bytes_total,
            parser_read_copy_bytes_total: value.parser_read_copy_bytes_total,
            framing_copy_bytes_total: value.framing_copy_bytes_total,
            key_material_copy_bytes_total: value.key_material_copy_bytes_total,
        });
    }
    SUCCESS
}
/// Additive scalar observations: no extension of the six-u64 copy ABI.
#[no_mangle]
pub extern "C" fn ct_wamp_encoded_bytes_accepted_total_v1() -> u64 {
    ct_core::encoded_wamp_accepted_bytes()
}

#[no_mangle]
pub extern "C" fn ct_wamp_encoded_send_rejections_total_v1() -> u64 {
    ct_core::encoded_wamp_rejected_submissions()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn codec_metrics_v1_preserves_guards_and_rejects_null() {
        assert_eq!(ct_codec_copy_metrics_abi_version(), 1);
        assert_eq!(ct_codec_copy_metrics_coverage_version(), 1);
        assert_eq!(std::mem::size_of::<CtCodecCopyMetricsInfo>(), 48);
        assert_eq!(std::mem::align_of::<CtCodecCopyMetricsInfo>(), 8);
        assert_eq!(
            ct_codec_copy_metrics_snapshot(std::ptr::null_mut()),
            ERR_INVALID_ARGUMENT
        );
        #[repr(C)]
        struct Guarded {
            before: u64,
            value: CtCodecCopyMetricsInfo,
            after: u64,
        }
        let mut guarded = Guarded {
            before: 0x123456789abcdef,
            value: CtCodecCopyMetricsInfo::default(),
            after: 0xabcdef123456789,
        };
        assert_eq!(ct_codec_copy_metrics_snapshot(&mut guarded.value), SUCCESS);
        assert_eq!(guarded.before, 0x123456789abcdef);
        assert_eq!(guarded.after, 0xabcdef123456789);
    }
}
