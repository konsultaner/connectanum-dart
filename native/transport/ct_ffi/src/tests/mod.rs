use std::sync::{Mutex, OnceLock};

fn guard() -> &'static Mutex<()> {
    static GUARD: OnceLock<Mutex<()>> = OnceLock::new();
    GUARD.get_or_init(|| Mutex::new(()))
}

pub(crate) fn test_guard() -> std::sync::MutexGuard<'static, ()> {
    guard().lock().unwrap()
}

#[cfg(target_os = "linux")]
mod error_cases;
#[cfg(target_os = "linux")]
mod listen_flow;
#[cfg(target_os = "linux")]
mod runtime_lifecycle;

#[cfg(not(target_os = "linux"))]
mod unsupported;
