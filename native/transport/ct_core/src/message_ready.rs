use std::sync::{Mutex, OnceLock};

#[derive(Default)]
struct State {
    callback: Option<extern "C" fn()>,
    pending: bool,
}

#[derive(Default)]
struct MessageReadyNotifier {
    state: Mutex<State>,
}

impl MessageReadyNotifier {
    fn set_callback(&self, callback: Option<extern "C" fn()>) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        state.callback = callback;
        state.pending = false;
    }

    fn arm(&self) {
        self.state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
            .pending = false;
    }

    fn notify(&self) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        if state.pending {
            return;
        }
        if let Some(callback) = state.callback {
            state.pending = true;
            // Removal waits for this invocation before its callable can close.
            callback();
        }
    }
}

fn notifier() -> &'static MessageReadyNotifier {
    static NOTIFIER: OnceLock<MessageReadyNotifier> = OnceLock::new();
    NOTIFIER.get_or_init(MessageReadyNotifier::default)
}

/// Registers a process-wide, coalesced WAMP queue readiness notification.
///
/// The callback runs on native reader threads and must return promptly without
/// re-entering registration or arming. Removing it waits for in-flight calls;
/// callers must remove it before releasing the callback's executable storage.
/// A notification does not consume a message or transfer payload ownership.
pub fn set_message_ready_callback(callback: Option<extern "C" fn()>) {
    notifier().set_callback(callback);
}

/// Re-arms notification before inspecting the existing message queues.
pub fn arm_message_ready_callback() {
    notifier().arm();
}

pub(crate) fn notify_message_ready() {
    notifier().notify();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc, Arc, Condvar,
    };
    use std::time::Duration;

    static COUNT: AtomicUsize = AtomicUsize::new(0);
    static PARALLEL_COUNT: AtomicUsize = AtomicUsize::new(0);

    extern "C" fn count() {
        COUNT.fetch_add(1, Ordering::SeqCst);
    }

    extern "C" fn count_parallel() {
        PARALLEL_COUNT.fetch_add(1, Ordering::SeqCst);
    }

    #[test]
    fn coalesces_until_armed_and_resets_when_registration_changes() {
        let notifier = MessageReadyNotifier::default();
        notifier.notify();
        notifier.arm();
        notifier.set_callback(Some(count));
        notifier.notify();
        notifier.notify();
        assert_eq!(COUNT.load(Ordering::SeqCst), 1);
        notifier.arm();
        notifier.notify();
        assert_eq!(COUNT.load(Ordering::SeqCst), 2);
        notifier.set_callback(None);
        notifier.arm();
        notifier.notify();
        assert_eq!(COUNT.load(Ordering::SeqCst), 2);
        notifier.set_callback(Some(count));
        notifier.notify();
        assert_eq!(COUNT.load(Ordering::SeqCst), 3);
    }

    #[test]
    fn concurrent_readers_publish_only_one_notification_per_arm() {
        let notifier = Arc::new(MessageReadyNotifier::default());
        notifier.set_callback(Some(count_parallel));
        for round in 1..=3 {
            let readers: Vec<_> = (0..8)
                .map(|_| {
                    let notifier = Arc::clone(&notifier);
                    std::thread::spawn(move || {
                        for _ in 0..100 {
                            notifier.notify();
                        }
                    })
                })
                .collect();
            for reader in readers {
                reader.join().unwrap();
            }
            assert_eq!(PARALLEL_COUNT.load(Ordering::SeqCst), round);
            notifier.arm();
        }
    }

    fn callback_gate() -> &'static (Mutex<(bool, bool)>, Condvar) {
        static GATE: OnceLock<(Mutex<(bool, bool)>, Condvar)> = OnceLock::new();
        GATE.get_or_init(|| (Mutex::new((false, false)), Condvar::new()))
    }

    extern "C" fn blocking_callback() {
        let (state, ready) = callback_gate();
        let mut state = state.lock().unwrap();
        state.0 = true;
        ready.notify_all();
        while !state.1 {
            state = ready.wait(state).unwrap();
        }
    }

    #[test]
    fn unregister_waits_for_native_invocation_before_callable_release() {
        let notifier = Arc::new(MessageReadyNotifier::default());
        notifier.set_callback(Some(blocking_callback));
        let reader = {
            let notifier = Arc::clone(&notifier);
            std::thread::spawn(move || notifier.notify())
        };
        let (state, ready) = callback_gate();
        let (mut state, timeout) = ready
            .wait_timeout_while(state.lock().unwrap(), Duration::from_secs(5), |state| {
                !state.0
            })
            .unwrap();
        assert!(!timeout.timed_out());
        assert!(notifier.state.try_lock().is_err());
        let (started_tx, started_rx) = mpsc::channel();
        let (finished_tx, finished_rx) = mpsc::channel();
        let unregister = {
            let notifier = Arc::clone(&notifier);
            std::thread::spawn(move || {
                started_tx.send(()).unwrap();
                notifier.set_callback(None);
                finished_tx.send(()).unwrap();
            })
        };
        started_rx.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(finished_rx.try_recv().is_err());
        state.1 = true;
        ready.notify_all();
        drop(state);
        reader.join().unwrap();
        finished_rx.recv_timeout(Duration::from_secs(5)).unwrap();
        unregister.join().unwrap();
        notifier.notify();
        assert!(notifier.state.lock().unwrap().callback.is_none());
    }
}
