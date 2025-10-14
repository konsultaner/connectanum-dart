//! Core transport runtime primitives for the native connectanum runtime.
//!
//! At the moment only Linux is supported. The module structure below keeps the
//! surface area ready for additional operating systems later on.

mod platform;

pub use platform::{Runtime, UnsupportedPlatform};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(target_os = "linux")]
    fn linux_runtime_initializes() {
        assert!(Runtime::new().is_ok(), "Linux runtime should initialize");
    }
}
