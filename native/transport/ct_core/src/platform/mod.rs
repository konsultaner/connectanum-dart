//! Platform specific runtime implementations.

use std::fmt;

/// Error returned when the runtime is requested on an unsupported platform.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UnsupportedPlatform;

impl fmt::Display for UnsupportedPlatform {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "native transport runtime not implemented for this platform"
        )
    }
}

impl std::error::Error for UnsupportedPlatform {}

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod supported;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub use supported::*;

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
mod unsupported;
#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
pub use unsupported::*;
