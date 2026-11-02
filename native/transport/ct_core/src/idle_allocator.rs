//! Return unused native allocator pages after a quiet connection interval.
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex, OnceLock,
};
use std::time::{Duration, Instant};

pub(super) const IDLE_DELAY: Duration = Duration::from_millis(100);
const MIN_INTERVAL: Duration = Duration::from_secs(2);

#[derive(Default)]
pub(super) struct IdleAllocatorRelease {
    queued: AtomicBool,
    last_release: Mutex<Option<Instant>>,
}

pub(super) fn shared() -> Arc<IdleAllocatorRelease> {
    static STATE: OnceLock<Arc<IdleAllocatorRelease>> = OnceLock::new();
    Arc::clone(STATE.get_or_init(Arc::default))
}

impl IdleAllocatorRelease {
    pub(super) fn reserve(self: &Arc<Self>, idle: bool) -> Option<Reservation> {
        if !idle
            || self
                .queued
                .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
                .is_err()
        {
            return None;
        }
        Some(Reservation(Arc::clone(self)))
    }
}

pub(super) struct Reservation(Arc<IdleAllocatorRelease>);

impl Reservation {
    pub(super) fn release_if_due(self, idle: bool, now: Instant, release: impl FnOnce()) -> bool {
        let due = idle && {
            let mut last = self
                .0
                .last_release
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            let due = last.map_or(true, |at| now.saturating_duration_since(at) >= MIN_INTERVAL);
            if due {
                *last = Some(now);
            }
            due
        };
        // Never hold the connection registry or limiter lock in the allocator.
        let rss = || {
            std::fs::read_to_string("/proc/self/status")
                .unwrap_or_default()
                .lines()
                .find(|line| line.starts_with("VmRSS:"))
                .unwrap_or("missing")
                .to_string()
        };
        eprintln!(
            "IDLE_TRACE before due={due} idle={idle} rss={} at={:?}",
            rss(),
            std::time::SystemTime::now()
        );
        if due {
            release();
            eprintln!(
                "IDLE_TRACE after rss={} at={:?}",
                rss(),
                std::time::SystemTime::now()
            );
        }
        due
    }
}

impl Drop for Reservation {
    fn drop(&mut self) {
        self.0.queued.store(false, Ordering::Release);
    }
}

#[cfg(all(target_os = "linux", target_env = "gnu"))]
pub(super) fn release_unused_pages() {
    // SAFETY: glibc releases only free allocator pages; live buffers stay owned.
    unsafe { libc::malloc_trim(0) };
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    #[test]
    fn limiter_is_shared_across_runtime_restarts() {
        assert!(Arc::ptr_eq(&shared(), &shared()));
    }

    #[test]
    fn active_connections_and_duplicate_requests_do_not_release() {
        let state = Arc::new(IdleAllocatorRelease::default());
        assert!(state.reserve(false).is_none());
        let reserved = state.reserve(true).unwrap();
        assert!(state.reserve(true).is_none());
        assert!(!reserved.release_if_due(false, Instant::now(), || panic!("active")));
        assert!(state.reserve(true).is_some());
    }

    #[test]
    fn releases_are_rate_limited_without_holding_the_limiter_lock() {
        let state = Arc::new(IdleAllocatorRelease::default());
        let now = Instant::now();
        let calls = AtomicUsize::new(0);
        let release = || {
            assert!(state.last_release.try_lock().is_ok());
            calls.fetch_add(1, Ordering::SeqCst);
        };
        assert!(state
            .reserve(true)
            .unwrap()
            .release_if_due(true, now, release));
        for at in [now - Duration::from_millis(1), now + MIN_INTERVAL / 2] {
            assert!(!state
                .reserve(true)
                .unwrap()
                .release_if_due(true, at, || { panic!("rate limit") }));
        }
        assert!(state
            .reserve(true)
            .unwrap()
            .release_if_due(true, now + MIN_INTERVAL, release));
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn cancellation_and_callback_failure_release_the_reservation() {
        let state = Arc::new(IdleAllocatorRelease::default());
        drop(state.reserve(true).unwrap());
        let reserved = state.reserve(true).unwrap();
        let failed = std::panic::catch_unwind(|| {
            reserved.release_if_due(true, Instant::now(), || panic!("allocator"));
        });
        assert!(failed.is_err());
        assert!(state.reserve(true).is_some());
    }

    #[test]
    fn poisoned_limiter_recovers_without_losing_its_bound() {
        let state = Arc::new(IdleAllocatorRelease::default());
        let cloned = Arc::clone(&state);
        let _ = std::thread::spawn(move || {
            let _guard = cloned.last_release.lock().unwrap();
            panic!("poison");
        })
        .join();
        assert!(state
            .reserve(true)
            .unwrap()
            .release_if_due(true, Instant::now(), || {}));
    }

    #[test]
    #[cfg(all(target_os = "linux", target_env = "gnu"))]
    fn trimming_does_not_change_live_native_buffers() {
        let live = vec![0x71u8; 2 * 1024 * 1024];
        release_unused_pages();
        assert!(live.iter().all(|byte| *byte == 0x71));
    }
}
