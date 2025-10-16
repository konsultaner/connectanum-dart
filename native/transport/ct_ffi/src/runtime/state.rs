use std::sync::{Mutex, OnceLock};

use ct_core::{ConnectionId, ListenerId};
use dashmap::DashMap;
use tokio::sync::mpsc::Receiver;

struct ReceiverEntry {
    receiver: Mutex<Receiver<ConnectionId>>,
}

static CHANNELS: OnceLock<DashMap<ListenerId, ReceiverEntry>> = OnceLock::new();

fn map() -> &'static DashMap<ListenerId, ReceiverEntry> {
    CHANNELS.get_or_init(DashMap::new)
}

pub fn store_channel(listener_id: ListenerId, receiver: Receiver<ConnectionId>) {
    map().insert(
        listener_id,
        ReceiverEntry {
            receiver: Mutex::new(receiver),
        },
    );
}

pub fn with_channel<F, T>(listener_id: ListenerId, f: F) -> Option<T>
where
    F: FnOnce(&mut Receiver<ConnectionId>) -> T,
{
    map().get(&listener_id).map(|entry| {
        let mut guard = entry.receiver.lock().unwrap();
        f(&mut guard)
    })
}

pub fn clear_channels() {
    map().clear();
}
