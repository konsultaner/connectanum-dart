//! C-compatible surface area for the native transport runtime.
//!
//! The functions exposed here will later be consumed via Dart FFI.

use ct_core::Runtime;

/// Returns `true` when the native runtime is available on the current
/// platform. The implementation attempts to initialise the runtime and reports
/// whether the operation succeeded.
#[no_mangle]
pub extern "C" fn ct_runtime_is_supported() -> bool {
    Runtime::new().is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(target_os = "linux")]
    fn linux_supports_runtime() {
        assert!(ct_runtime_is_supported());
    }

    #[test]
    #[cfg(not(target_os = "linux"))]
    fn non_linux_does_not_support_runtime() {
        assert!(!ct_runtime_is_supported());
    }
}
