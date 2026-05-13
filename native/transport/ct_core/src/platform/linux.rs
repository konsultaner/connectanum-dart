//! Runtime primitives shared by the currently supported Unix hosts.

use super::UnsupportedPlatform;

/// Runtime handle for the native transport stack.
#[derive(Debug, Default)]
pub struct Runtime;

impl Runtime {
    /// Create a new runtime instance. Supported Unix hosts succeed here, while
    /// unsupported platforms yield an [`UnsupportedPlatform`] error.
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
