use std::sync::{Mutex, OnceLock};

fn guard() -> &'static Mutex<()> {
    static GUARD: OnceLock<Mutex<()>> = OnceLock::new();
    GUARD.get_or_init(|| Mutex::new(()))
}

pub(crate) fn test_guard() -> std::sync::MutexGuard<'static, ()> {
    guard().lock().unwrap_or_else(|poison| poison.into_inner())
}

#[cfg(target_os = "linux")]
mod error_cases;
#[cfg(target_os = "linux")]
mod listen_flow;
mod router_config;
#[cfg(target_os = "linux")]
mod runtime_lifecycle;

#[cfg(not(target_os = "linux"))]
mod unsupported;
