use std::sync::{Mutex, OnceLock};

use crate::runtime::ffi::ct_shutdown;

fn guard() -> &'static Mutex<()> {
    static GUARD: OnceLock<Mutex<()>> = OnceLock::new();
    GUARD.get_or_init(|| Mutex::new(()))
}

pub(crate) fn test_guard() -> std::sync::MutexGuard<'static, ()> {
    let guard = guard().lock().unwrap_or_else(|poison| poison.into_inner());
    let _ = ct_shutdown();
    guard
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
mod error_cases;
mod e2ee;
#[cfg(any(target_os = "linux", target_os = "macos"))]
mod listen_flow;
mod router_config;
#[cfg(any(target_os = "linux", target_os = "macos"))]
mod runtime_lifecycle;

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
mod unsupported;
