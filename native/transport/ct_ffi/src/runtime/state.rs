use std::sync::{
    atomic::{AtomicU32, Ordering},
    Arc, Mutex, OnceLock,
};

use bytes::Bytes;
use ct_core::{ConnectionId, ListenerId, RawSocketSerializer, WampMessage};
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
    clear_messages();
}

#[derive(Clone)]
pub struct StoredMessage {
    pub serializer: RawSocketSerializer,
    pub code: u64,
    pub raw: Bytes,
    pub message: WampMessage,
    pub args: Option<Bytes>,
    pub kwargs: Option<Bytes>,
}

struct MessageStore {
    next_id: AtomicU32,
    messages: DashMap<u32, Arc<StoredMessage>>,
}

impl Default for MessageStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU32::new(1),
            messages: DashMap::new(),
        }
    }
}

static MESSAGE_STORE: OnceLock<MessageStore> = OnceLock::new();

fn message_store() -> &'static MessageStore {
    MESSAGE_STORE.get_or_init(MessageStore::default)
}

pub fn store_message(message: StoredMessage) -> u32 {
    let store = message_store();
    let id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store.messages.insert(id, Arc::new(message));
    id
}

pub fn with_message<F, T>(id: u32, f: F) -> Option<T>
where
    F: FnOnce(&StoredMessage) -> T,
{
    message_store().messages.get(&id).map(|entry| {
        let message = Arc::clone(entry.value());
        f(message.as_ref())
    })
}

pub fn remove_message(id: u32) -> Option<Arc<StoredMessage>> {
    message_store().messages.remove(&id).map(|(_, msg)| msg)
}

pub fn clear_messages() {
    if let Some(store) = MESSAGE_STORE.get() {
        store.messages.clear();
    }
}

pub fn clone_message(id: u32) -> Option<u32> {
    let store = message_store();
    let message = store.messages.get(&id)?;
    let cloned = Arc::clone(message.value());
    let new_id = store.next_id.fetch_add(1, Ordering::SeqCst);
    store.messages.insert(new_id, cloned);
    Some(new_id)
}
