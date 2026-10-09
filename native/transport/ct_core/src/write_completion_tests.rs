use super::*;
use std::task::Waker;

#[derive(Default)]
struct GateState {
    wire: Vec<u8>,
    write_budget: usize,
    flush_budget: usize,
    flushing: bool,
    fail_write: bool,
    fail_flush: bool,
    waiter: Option<Waker>,
}

#[derive(Clone, Default)]
struct Gate(Arc<Mutex<GateState>>);

impl Gate {
    fn change(&self, change: impl FnOnce(&mut GateState)) {
        let waiter = {
            let mut state = self.0.lock().unwrap();
            change(&mut state);
            state.waiter.take()
        };
        if let Some(waiter) = waiter {
            waiter.wake();
        }
    }

    async fn until(&self, predicate: impl Fn(&GateState) -> bool) {
        time::timeout(Duration::from_secs(3), async {
            loop {
                if predicate(&self.0.lock().unwrap()) {
                    return;
                }
                time::sleep(Duration::from_millis(1)).await;
            }
        })
        .await
        .expect("writer did not reach controlled boundary");
    }
}

impl AsyncWrite for Gate {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        let mut state = self.0.lock().unwrap();
        if state.fail_write {
            return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
        }
        if state.write_budget == 0 {
            state.waiter = Some(cx.waker().clone());
            return Poll::Pending;
        }
        let length = bytes.len().min(state.write_budget).min(2);
        state.wire.extend_from_slice(&bytes[..length]);
        state.write_budget -= length;
        Poll::Ready(Ok(length))
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let mut state = self.0.lock().unwrap();
        state.flushing = true;
        if state.fail_flush {
            return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
        }
        if state.flush_budget == 0 {
            state.waiter = Some(cx.waker().clone());
            return Poll::Pending;
        }
        state.flush_budget -= 1;
        state.flushing = false;
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

fn writer(websocket: bool, gate: Gate, receiver: mpsc::Receiver<OutboundFrame>) -> AbortHandle {
    let (close, _) = mpsc::unbounded_channel();
    if websocket {
        spawn_websocket_writer(
            tokio::runtime::Handle::current(),
            ConnectionId(94),
            rawsocket::Serializer::Cbor,
            gate,
            receiver,
            close,
            false,
        )
    } else {
        spawn_connection_writer(
            tokio::runtime::Handle::current(),
            ConnectionId(94),
            gate,
            None,
            24,
            receiver,
            close,
        )
    }
}

async fn outcome(receipt: WriteReceipt) -> WriteOutcome {
    time::timeout(Duration::from_secs(3), receipt.wait())
        .await
        .unwrap()
}

#[tokio::test]
async fn receipt_requires_complete_partial_write_and_flush() {
    for websocket in [false, true] {
        let gate = Gate::default();
        gate.change(|state| state.write_budget = 1);
        let (sender, receiver) = mpsc::channel(8);
        let task = writer(websocket, gate.clone(), receiver);
        let (frame, receipt) = OutboundFrame::message(Bytes::from_static(b"ABCDE")).tracked();
        assert!(sender.try_send(frame).is_ok());
        gate.until(|state| state.wire.len() == 1).await;
        assert_eq!(receipt.outcome(), WriteOutcome::Pending);
        gate.change(|state| state.write_budget = usize::MAX);
        gate.until(|state| state.flushing).await;
        assert_eq!(receipt.outcome(), WriteOutcome::Pending);
        let expected = if websocket {
            b"\x82\x05ABCDE".as_slice()
        } else {
            b"\x00\x00\x00\x05ABCDE".as_slice()
        };
        assert_eq!(gate.0.lock().unwrap().wire, expected);
        gate.change(|state| state.flush_budget = 1);
        assert_eq!(outcome(receipt).await, WriteOutcome::Written);
        task.abort();
    }
}

#[tokio::test]
async fn barrier_is_fifo_flush_without_an_extra_wire_frame() {
    for websocket in [false, true] {
        let gate = Gate::default();
        gate.change(|state| state.write_budget = usize::MAX);
        let (sender, receiver) = mpsc::channel(8);
        let task = writer(websocket, gate.clone(), receiver);
        let (first, first_receipt) = OutboundFrame::message(Bytes::from_static(b"A")).tracked();
        let (barrier, barrier_receipt) = OutboundFrame::barrier().tracked();
        let (last, last_receipt) = OutboundFrame::message(Bytes::from_static(b"B")).tracked();
        assert!(sender.try_send(first).is_ok());
        assert!(sender.try_send(barrier).is_ok());
        assert!(sender.try_send(last).is_ok());
        gate.until(|state| state.flushing).await;
        let first_length = if websocket { 3 } else { 5 };
        assert_eq!(gate.0.lock().unwrap().wire.len(), first_length);
        assert_eq!(barrier_receipt.outcome(), WriteOutcome::Pending);
        gate.change(|state| state.flush_budget = 1);
        assert_eq!(outcome(first_receipt).await, WriteOutcome::Written);
        assert_eq!(barrier_receipt.outcome(), WriteOutcome::Pending);
        assert_eq!(gate.0.lock().unwrap().wire.len(), first_length);
        gate.change(|state| state.flush_budget = 1);
        assert_eq!(outcome(barrier_receipt).await, WriteOutcome::Written);
        gate.until(|state| state.wire.len() == first_length * 2 && state.flushing)
            .await;
        assert_eq!(last_receipt.outcome(), WriteOutcome::Pending);
        gate.change(|state| state.flush_budget = 1);
        assert_eq!(outcome(last_receipt).await, WriteOutcome::Written);
        task.abort();
    }
}

#[tokio::test]
async fn cancellation_and_write_or_flush_failure_abandon_active_and_queued_receipts() {
    for websocket in [false, true] {
        for failure in 0..3 {
            let gate = Gate::default();
            gate.change(|state| state.write_budget = if failure == 2 { usize::MAX } else { 1 });
            let (sender, receiver) = mpsc::channel(8);
            let task = writer(websocket, gate.clone(), receiver);
            let (first, receipt) = OutboundFrame::message(Bytes::from_static(b"ABCDE")).tracked();
            let (queued, queued_receipt) = OutboundFrame::barrier().tracked();
            assert!(sender.try_send(first).is_ok());
            assert!(sender.try_send(queued).is_ok());
            gate.until(|state| {
                if failure == 2 {
                    state.flushing
                } else {
                    state.wire.len() == 1
                }
            })
            .await;
            assert_eq!(receipt.outcome(), WriteOutcome::Pending);
            match failure {
                0 => task.abort(),
                1 => gate.change(|state| state.fail_write = true),
                _ => gate.change(|state| state.fail_flush = true),
            }
            assert_eq!(outcome(receipt).await, WriteOutcome::Abandoned);
            assert_eq!(outcome(queued_receipt).await, WriteOutcome::Abandoned);
            task.abort();
        }
    }
}

#[tokio::test]
async fn rejected_queue_and_bad_deferred_segment_abandon_receipts() {
    let (sender, receiver) = mpsc::channel(1);
    assert!(sender
        .try_send(OutboundFrame::message(Bytes::new()))
        .is_ok());
    let (frame, receipt) = OutboundFrame::message(Bytes::new()).tracked();
    assert!(matches!(sender.try_send(frame), Err(TrySendError::Full(_))));
    assert_eq!(outcome(receipt).await, WriteOutcome::Abandoned);
    drop(receiver);
    let (frame, receipt) = OutboundFrame::message(Bytes::new()).tracked();
    assert!(matches!(
        sender.try_send(frame),
        Err(TrySendError::Closed(_))
    ));
    assert_eq!(outcome(receipt).await, WriteOutcome::Abandoned);
    for websocket in [false, true] {
        let (sender, receiver) = mpsc::channel(8);
        let task = writer(websocket, Gate::default(), receiver);
        let frame = OutboundFrame::message_deferred_segment(Bytes::new(), 3, || {
            Ok(Bytes::from_static(b"wrong length"))
        })
        .unwrap();
        let (frame, receipt) = frame.tracked();
        let (barrier, after) = OutboundFrame::barrier().tracked();
        assert!(sender.try_send(frame).is_ok());
        assert!(sender.try_send(barrier).is_ok());
        assert_eq!(outcome(receipt).await, WriteOutcome::Abandoned);
        assert_eq!(outcome(after).await, WriteOutcome::Abandoned);
        task.abort();
    }
}

struct Loan {
    bytes: Vec<u8>,
    releases: Arc<std::sync::atomic::AtomicUsize>,
}

#[tokio::test]
async fn cancelling_deferred_preparation_abandons_write_before_worker_releases_loan() {
    for websocket in [false, true] {
        let releases = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let started = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let resume = Arc::new((Mutex::new(false), std::sync::Condvar::new()));
        let payload = Bytes::from_owner(Loan {
            bytes: b"ABCDE".to_vec(),
            releases: releases.clone(),
        });
        let worker_started = started.clone();
        let worker_resume = resume.clone();
        let frame = OutboundFrame::message_deferred_segment(Bytes::new(), 5, move || {
            worker_started.store(true, Ordering::Release);
            let (mutex, ready) = &*worker_resume;
            let mut resumed = mutex.lock().unwrap();
            while !*resumed {
                resumed = ready.wait(resumed).unwrap();
            }
            Ok(payload)
        })
        .unwrap();
        let (frame, receipt) = frame.tracked();
        let (sender, receiver) = mpsc::channel(8);
        let task = writer(websocket, Gate::default(), receiver);
        assert!(sender.try_send(frame).is_ok());
        let began = time::timeout(Duration::from_secs(3), async {
            while !started.load(Ordering::Acquire) {
                time::sleep(Duration::from_millis(1)).await;
            }
        })
        .await;
        // Always unblock the native worker, even if a receipt assertion fails.
        struct ResumeOnDrop(Arc<(Mutex<bool>, std::sync::Condvar)>);
        impl Drop for ResumeOnDrop {
            fn drop(&mut self) {
                *self.0 .0.lock().unwrap() = true;
                self.0 .1.notify_all();
            }
        }
        let unblock = ResumeOnDrop(resume);
        assert!(began.is_ok());
        assert_eq!(receipt.outcome(), WriteOutcome::Pending);
        task.abort();
        assert_eq!(outcome(receipt).await, WriteOutcome::Abandoned);
        assert_eq!(releases.load(Ordering::SeqCst), 0);
        drop(unblock);
        time::timeout(Duration::from_secs(3), async {
            while releases.load(Ordering::SeqCst) == 0 {
                time::sleep(Duration::from_millis(1)).await;
            }
        })
        .await
        .unwrap();
        assert_eq!(releases.load(Ordering::SeqCst), 1);
    }
}
impl AsRef<[u8]> for Loan {
    fn as_ref(&self) -> &[u8] {
        &self.bytes
    }
}
impl Drop for Loan {
    fn drop(&mut self) {
        self.releases.fetch_add(1, Ordering::SeqCst);
    }
}

#[tokio::test]
async fn one_slow_fanout_destination_keeps_loan_after_other_write_completes() {
    for websocket in [false, true] {
        let releases = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let bytes = Bytes::from_owner(Loan {
            bytes: b"ABCDE".to_vec(),
            releases: releases.clone(),
        });
        let fast = Gate::default();
        fast.change(|state| {
            state.write_budget = usize::MAX;
            state.flush_budget = 1;
        });
        let slow = Gate::default();
        let (a, ar) = mpsc::channel(8);
        let (b, br) = mpsc::channel(8);
        let fast_task = writer(websocket, fast, ar);
        let slow_task = writer(websocket, slow, br);
        let (first, first_receipt) = OutboundFrame::message(bytes.clone()).tracked();
        let (second, second_receipt) = OutboundFrame::message(bytes).tracked();
        assert!(a.try_send(first).is_ok());
        assert!(b.try_send(second).is_ok());
        assert_eq!(outcome(first_receipt).await, WriteOutcome::Written);
        assert_eq!(second_receipt.outcome(), WriteOutcome::Pending);
        assert_eq!(releases.load(Ordering::SeqCst), 0);
        slow_task.abort();
        assert_eq!(outcome(second_receipt).await, WriteOutcome::Abandoned);
        time::timeout(Duration::from_secs(3), async {
            while releases.load(Ordering::SeqCst) == 0 {
                time::sleep(Duration::from_millis(1)).await;
            }
        })
        .await
        .unwrap();
        assert_eq!(releases.load(Ordering::SeqCst), 1);
        fast_task.abort();
    }
}
