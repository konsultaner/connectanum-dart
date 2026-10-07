//! Stub runtime exposed when the current platform is unsupported.

use super::UnsupportedPlatform;

/// Runtime handle placeholder for unsupported platforms.
#[derive(Debug, Default)]
pub struct Runtime;

impl Runtime {
    /// Returns an [`UnsupportedPlatform`] error to notify callers that the native
    /// runtime is not available on this operating system yet.
    pub fn new() -> Result<Self, UnsupportedPlatform> {
        Err(UnsupportedPlatform)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_new_rejects_unsupported_hosts() {
        assert!(matches!(Runtime::new(), Err(UnsupportedPlatform)));
    }
}
