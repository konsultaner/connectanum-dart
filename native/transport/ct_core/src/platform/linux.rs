//! Linux specific runtime primitives.

use super::UnsupportedPlatform;

/// Runtime handle for the native transport stack.
#[derive(Debug, Default)]
pub struct Runtime;

impl Runtime {
    /// Create a new runtime instance. On Linux this succeeds today, while other
    /// platforms yield an [`UnsupportedPlatform`] error.
    pub fn new() -> Result<Self, UnsupportedPlatform> {
        Ok(Self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_new_succeeds() {
        assert!(Runtime::new().is_ok());
    }
}
