use std::thread::JoinHandle;
use std::time::{Duration, Instant};

pub(super) struct ClientConnect {
    task: Option<JoinHandle<i32>>,
    connection: Option<i32>,
}

impl ClientConnect {
    pub(super) fn new(task: JoinHandle<i32>) -> Self {
        Self {
            task: Some(task),
            connection: None,
        }
    }

    fn observe(&mut self) -> Option<i32> {
        if self.task.as_ref().is_some_and(JoinHandle::is_finished) {
            let result = self.task.take().unwrap().join();
            let connection = match result {
                Ok(connection) => connection,
                Err(panic) => std::panic::resume_unwind(panic),
            };
            assert!(connection > 0);
            self.connection = Some(connection);
        }
        self.connection
    }

    pub(super) fn wait_for_server(
        &mut self,
        mut poll: impl FnMut() -> i32,
        deadline: Instant,
    ) -> i32 {
        loop {
            // RawSocket may finish first; WebSocket needs server acceptance.
            self.observe();
            let connection = poll();
            assert!(connection >= 0);
            if connection > 0 {
                return connection;
            }
            if Instant::now() >= deadline {
                panic!("timed out waiting for server connection");
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }

    pub(super) fn finish(&mut self, deadline: Instant) -> i32 {
        loop {
            if let Some(connection) = self.observe() {
                return connection;
            }
            if Instant::now() >= deadline {
                panic!("timed out waiting for client connection");
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::panic::{catch_unwind, AssertUnwindSafe};
    use std::sync::mpsc;

    fn deadline() -> Instant {
        Instant::now() + Duration::from_secs(5)
    }

    fn completed(task: JoinHandle<i32>) -> ClientConnect {
        let deadline = deadline();
        while !task.is_finished() {
            if Instant::now() >= deadline {
                panic!("fixture client did not finish");
            }
            std::thread::yield_now();
        }
        ClientConnect::new(task)
    }

    fn panic_text(error: Box<dyn std::any::Any + Send>) -> String {
        if let Some(message) = error.downcast_ref::<String>() {
            message.clone()
        } else {
            error.downcast_ref::<&str>().unwrap().to_string()
        }
    }

    #[test]
    fn rejects_completed_failure_before_polling_the_server() {
        for returned in [0, -1, -7] {
            let mut client = completed(std::thread::spawn(move || returned));
            let mut polls = 0;
            let error = catch_unwind(AssertUnwindSafe(|| {
                client.wait_for_server(
                    || {
                        polls += 1;
                        42
                    },
                    deadline(),
                )
            }))
            .unwrap_err();
            assert_eq!(polls, 0);
            assert_eq!(panic_text(error), "assertion failed: connection > 0");
        }
    }

    #[test]
    fn retains_early_success_until_server_is_ready() {
        let mut client = completed(std::thread::spawn(|| 41));
        let mut polls = 0;
        assert_eq!(
            client.wait_for_server(
                || {
                    polls += 1;
                    if polls < 3 {
                        0
                    } else {
                        42
                    }
                },
                deadline(),
            ),
            42
        );
        assert_eq!(polls, 3);
        assert_eq!(client.finish(deadline()), 41);
        assert_eq!(client.finish(deadline()), 41);
    }

    #[test]
    fn returns_server_while_client_waits_for_acceptance() {
        let (tx, rx) = mpsc::channel();
        let mut client = ClientConnect::new(std::thread::spawn(move || rx.recv().unwrap()));
        assert_eq!(client.wait_for_server(|| 42, deadline()), 42);
        tx.send(41).unwrap();
        assert_eq!(client.finish(deadline()), 41);
    }

    #[test]
    fn preserves_worker_panic_instead_of_asserting_on_it() {
        let mut client = completed(std::thread::spawn(|| panic!("worker failure sentinel")));
        let error = catch_unwind(AssertUnwindSafe(|| client.finish(deadline()))).unwrap_err();
        assert_eq!(panic_text(error), "worker failure sentinel");
    }

    #[test]
    fn pending_server_and_client_have_non_assertion_deadlines() {
        let (tx, rx) = mpsc::channel();
        let mut client = ClientConnect::new(std::thread::spawn(move || rx.recv().unwrap()));
        let expired = Instant::now() - Duration::from_secs(1);
        let server_error =
            catch_unwind(AssertUnwindSafe(|| client.wait_for_server(|| 0, expired))).unwrap_err();
        let client_error = catch_unwind(AssertUnwindSafe(|| client.finish(expired))).unwrap_err();
        tx.send(41).unwrap();
        assert_eq!(client.finish(deadline()), 41);
        assert_eq!(
            panic_text(server_error),
            "timed out waiting for server connection"
        );
        assert_eq!(
            panic_text(client_error),
            "timed out waiting for client connection"
        );
    }
}
