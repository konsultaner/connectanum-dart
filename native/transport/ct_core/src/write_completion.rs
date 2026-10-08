//! Local writer progress is independent of payload ownership and peer delivery.
use tokio::sync::watch;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
pub enum WriteOutcome {
    Pending = 0,
    Written = 1,
    Abandoned = 2,
}

#[derive(Clone)]
pub struct WriteReceipt {
    receiver: watch::Receiver<WriteOutcome>,
}

impl WriteReceipt {
    pub fn outcome(&self) -> WriteOutcome {
        *self.receiver.borrow()
    }

    pub async fn wait(mut self) -> WriteOutcome {
        loop {
            let outcome = *self.receiver.borrow_and_update();
            if outcome != WriteOutcome::Pending {
                return outcome;
            }
            if self.receiver.changed().await.is_err() {
                return WriteOutcome::Abandoned;
            }
        }
    }
}

pub(crate) struct WriteGuard {
    sender: Option<watch::Sender<WriteOutcome>>,
}

impl WriteGuard {
    pub(crate) fn new() -> (Self, WriteReceipt) {
        let (sender, receiver) = watch::channel(WriteOutcome::Pending);
        (
            Self {
                sender: Some(sender),
            },
            WriteReceipt { receiver },
        )
    }

    // Only native writers call this after the full frame and flush succeed.
    pub(crate) fn written(mut self) {
        if let Some(sender) = self.sender.take() {
            sender.send_replace(WriteOutcome::Written);
        }
    }
}

impl Drop for WriteGuard {
    fn drop(&mut self) {
        if let Some(sender) = self.sender.take() {
            sender.send_replace(WriteOutcome::Abandoned);
        }
    }
}
