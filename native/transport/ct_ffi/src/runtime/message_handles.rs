//! Wide routing handles are process-local, not WAMP wire IDs.
//! Keep their namespace disjoint from the retained legacy C ABI.

use super::state::{self, MessageHandleError, StoredMessage};
use dashmap::{mapref::entry::Entry, DashMap};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};

// Accidental narrowing to the legacy signed ABI must yield an invalid handle,
// never the ID of an unrelated live message. Keep bit 31 set on every wide ID.
const NARROW_SIGN_BIT: u64 = 1 << 31;
const FIRST_WIDE_HANDLE: u64 = (1 << 32) | NARROW_SIGN_BIT;

struct WideMessageStore {
    next_id: AtomicU64,
    messages: DashMap<u64, Arc<StoredMessage>>,
}

impl Default for WideMessageStore {
    fn default() -> Self {
        Self {
            next_id: AtomicU64::new(FIRST_WIDE_HANDLE),
            messages: DashMap::new(),
        }
    }
}

impl WideMessageStore {
    fn insert(&self, message: Arc<StoredMessage>) -> Result<u64, MessageHandleError> {
        let id = self
            .next_id
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |next| {
                if !(FIRST_WIDE_HANDLE..=i64::MAX as u64).contains(&next)
                    || next & NARROW_SIGN_BIT == 0
                {
                    return None;
                }
                // At low-word carry, skip the region that would narrow positive.
                // The i64::MAX successor is a sentinel, never an issued handle.
                Some(
                    next + if next as u32 == u32::MAX {
                        NARROW_SIGN_BIT + 1
                    } else {
                        1
                    },
                )
            })
            .map_err(|_| MessageHandleError::Exhausted)?;
        match self.messages.entry(id) {
            Entry::Vacant(entry) => {
                entry.insert(message);
                Ok(id)
            }
            Entry::Occupied(_) => Err(MessageHandleError::Exhausted),
        }
    }

    fn retain(&self, id: u64) -> Option<Arc<StoredMessage>> {
        self.messages
            .get(&id)
            .map(|entry| Arc::clone(entry.value()))
    }

    fn clear(&self) {
        // Delayed worker messages and finalizers can outlive runtime restarts.
        self.messages.clear();
    }
}

static STORE: OnceLock<WideMessageStore> = OnceLock::new();

fn store() -> &'static WideMessageStore {
    STORE.get_or_init(WideMessageStore::default)
}

pub(super) fn insert(message: StoredMessage) -> Result<u64, MessageHandleError> {
    store().insert(Arc::new(message))
}

pub(super) fn retain_allocation(id: u64) -> Option<Arc<StoredMessage>> {
    if id <= i32::MAX as u64 {
        state::retain_message_allocation(id as u32)
    } else {
        store().retain(id)
    }
}

pub(super) fn with_message<T>(id: u64, f: impl FnOnce(&StoredMessage) -> T) -> Option<T> {
    // The independent owner also releases the map shard before calling f.
    retain_allocation(id).map(|message| f(&message))
}

pub(super) fn remove(id: u64) -> Option<Arc<StoredMessage>> {
    if id <= i32::MAX as u64 {
        state::remove_message(id as u32)
    } else {
        store().messages.remove(&id).map(|(_, message)| message)
    }
}

pub(super) fn retain(id: u64) -> Result<u64, MessageHandleError> {
    let message = retain_allocation(id).ok_or(MessageHandleError::Unavailable)?;
    store().insert(message)
}

pub(super) fn clear() {
    if let Some(store) = STORE.get() {
        store.clear();
    }
}

#[cfg(feature = "ffi-test")]
pub(super) fn observe_call(procedure: &str) -> Option<std::sync::Weak<StoredMessage>> {
    store().messages.iter().find_map(|entry| {
        if let ct_core::WampMessage::Call {
            procedure: candidate,
            ..
        } = &entry.value().message
        {
            if candidate == procedure {
                return Some(Arc::downgrade(entry.value()));
            }
        }
        None
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::state::StoredRawFrame;
    use bytes::Bytes;
    use ct_core::{RawSocketSerializer, WampMessage};

    fn message() -> Arc<StoredMessage> {
        Arc::new(StoredMessage {
            serializer: RawSocketSerializer::Json,
            code: 7,
            raw: StoredRawFrame::from_bytes(Bytes::from_static(b"[7,{},\"wamp.close.normal\"]")),
            message: WampMessage::Goodbye {
                details: Default::default(),
                reason: "wamp.close.normal".into(),
                payload: Default::default(),
            },
            details: None,
            args: None,
            kwargs: None,
        })
    }

    #[test]
    fn wide_ids_never_enter_legacy_namespace_or_wrap() {
        for invalid in [
            0,
            1,
            i32::MAX as u64,
            u32::MAX as u64,
            0x2_0000_0000,
            0x2_7fff_ffff,
            i64::MAX as u64 + 1,
            u64::MAX,
        ] {
            let store = WideMessageStore {
                next_id: AtomicU64::new(invalid),
                ..Default::default()
            };
            let value = message();
            let observer = Arc::downgrade(&value);
            assert_eq!(store.insert(value), Err(MessageHandleError::Exhausted));
            assert_eq!(store.next_id.load(Ordering::SeqCst), invalid);
            assert!(store.messages.is_empty());
            assert_eq!(observer.strong_count(), 0);
        }
        let store = WideMessageStore {
            next_id: AtomicU64::new(i64::MAX as u64),
            ..Default::default()
        };
        assert_eq!(store.insert(message()), Ok(i64::MAX as u64));
        store.clear();
        assert_eq!(store.insert(message()), Err(MessageHandleError::Exhausted));
    }

    #[test]
    fn wide_ids_fail_closed_if_accidentally_narrowed() {
        let store = WideMessageStore::default();
        for _ in 0..8 {
            let id = store.insert(message()).unwrap();
            assert!(
                (id as i32) <= 0,
                "wide ID could alias a valid legacy handle"
            );
        }
    }

    #[test]
    fn wide_ids_skip_the_positive_low_word_at_carry() {
        let store = WideMessageStore {
            next_id: AtomicU64::new(0x1_ffff_fffe),
            ..Default::default()
        };
        for expected in [0x1_ffff_fffe, 0x1_ffff_ffff, 0x2_8000_0000, 0x2_8000_0001] {
            let id = store.insert(message()).unwrap();
            assert_eq!(id, expected);
            assert!((id as i32) < 0);
        }
    }

    #[test]
    fn wide_clear_does_not_alias_stale_ids_or_drop_retained_owners() {
        let store = WideMessageStore::default();
        let first = store.insert(message()).unwrap();
        assert_eq!(first, FIRST_WIDE_HANDLE);
        let owner = store.retain(first).unwrap();
        let observer = Arc::downgrade(&owner);
        store.clear();
        let second = store.insert(message()).unwrap();
        assert_eq!(second, first + 1);
        assert!(store.retain(first).is_none());
        assert_eq!(observer.strong_count(), 1);
        drop(owner);
        assert_eq!(observer.strong_count(), 0);
    }

    #[test]
    fn wide_collision_preserves_live_entry_and_releases_rejected_owner() {
        let store = WideMessageStore::default();
        let original = message();
        store
            .messages
            .insert(FIRST_WIDE_HANDLE, Arc::clone(&original));
        let rejected = message();
        let observer = Arc::downgrade(&rejected);
        assert_eq!(store.insert(rejected), Err(MessageHandleError::Exhausted));
        assert_eq!(observer.strong_count(), 0);
        assert!(Arc::ptr_eq(
            &store.retain(FIRST_WIDE_HANDLE).unwrap(),
            &original
        ));
    }

    #[test]
    fn concurrent_wide_allocation_issues_each_final_id_once() {
        let store = Arc::new(WideMessageStore {
            next_id: AtomicU64::new(i64::MAX as u64 - 7),
            ..Default::default()
        });
        let source = message();
        let observer = Arc::downgrade(&source);
        let barrier = Arc::new(std::sync::Barrier::new(16));
        let threads = (0..16)
            .map(|_| {
                let store = Arc::clone(&store);
                let value = Arc::clone(&source);
                let barrier = Arc::clone(&barrier);
                std::thread::spawn(move || {
                    barrier.wait();
                    store.insert(value)
                })
            })
            .collect::<Vec<_>>();
        drop(source);
        let results = threads
            .into_iter()
            .map(|thread| thread.join().unwrap())
            .collect::<Vec<_>>();
        let ids = results
            .iter()
            .filter_map(|result| result.as_ref().ok().copied())
            .collect::<std::collections::HashSet<_>>();
        assert_eq!(ids.len(), 8);
        assert!(ids
            .iter()
            .all(|id| *id >= FIRST_WIDE_HANDLE && *id <= i64::MAX as u64));
        assert_eq!(
            results
                .iter()
                .filter(|result| **result == Err(MessageHandleError::Exhausted))
                .count(),
            8
        );
        assert_eq!(observer.strong_count(), 8);
        store.clear();
        assert_eq!(observer.strong_count(), 0);
    }
}
