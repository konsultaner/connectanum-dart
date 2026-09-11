use dashmap::{mapref::entry::Entry, DashMap};
use std::sync::atomic::{AtomicU32, Ordering};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ResourceHandleError {
    Exhausted,
}

pub fn insert_resource<T>(
    next_id: &AtomicU32,
    entries: &DashMap<u32, T>,
    resource: T,
) -> Result<u32, ResourceHandleError> {
    // Zero and negative signed-C values are not handles. Never wrap or recycle:
    // queued work and finalizers can outlive a removed entry or runtime restart.
    let id = next_id
        .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |next| {
            if next == 0 || next > i32::MAX as u32 {
                None
            } else {
                Some(next + 1)
            }
        })
        .map_err(|_| ResourceHandleError::Exhausted)?;
    match entries.entry(id) {
        Entry::Vacant(entry) => {
            entry.insert(resource);
            Ok(id)
        }
        Entry::Occupied(_) => Err(ResourceHandleError::Exhausted),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier};
    use std::thread;

    #[test]
    fn resource_handle_fresh_ids_remain_positive_and_distinct() {
        let next = AtomicU32::new(1);
        let entries = DashMap::new();
        assert_eq!(insert_resource(&next, &entries, "first"), Ok(1));
        assert_eq!(insert_resource(&next, &entries, "second"), Ok(2));
        assert_eq!(*entries.get(&1).unwrap(), "first");
        assert_eq!(*entries.get(&2).unwrap(), "second");
    }

    #[test]
    fn resource_handle_zero_is_never_allocated() {
        let next = AtomicU32::new(0);
        let entries = DashMap::new();
        assert_eq!(
            insert_resource(&next, &entries, 1),
            Err(ResourceHandleError::Exhausted)
        );
        assert!(entries.is_empty());
        assert_eq!(next.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn resource_handle_last_positive_id_is_available_only_once() {
        let next = AtomicU32::new(i32::MAX as u32);
        let entries = DashMap::new();
        assert_eq!(
            insert_resource(&next, &entries, "last"),
            Ok(i32::MAX as u32)
        );
        for _ in 0..4 {
            assert_eq!(
                insert_resource(&next, &entries, "rejected"),
                Err(ResourceHandleError::Exhausted)
            );
        }
        assert_eq!(entries.len(), 1);
        assert_eq!(*entries.get(&(i32::MAX as u32)).unwrap(), "last");
        assert_eq!(next.load(Ordering::SeqCst), i32::MAX as u32 + 1);
    }

    #[test]
    fn resource_handle_unsigned_max_does_not_wrap_into_live_entries() {
        let next = AtomicU32::new(u32::MAX);
        let entries = DashMap::new();
        entries.insert(1, "existing");
        let results: Vec<_> = (0..3)
            .map(|_| insert_resource(&next, &entries, "replacement"))
            .collect();
        assert_eq!(*entries.get(&1).unwrap(), "existing");
        assert!(results
            .iter()
            .all(|result| *result == Err(ResourceHandleError::Exhausted)));
        assert_eq!(entries.len(), 1);
        assert_eq!(next.load(Ordering::SeqCst), u32::MAX);
    }

    #[test]
    fn resource_handle_collision_preserves_the_live_owner() {
        let next = AtomicU32::new(17);
        let entries = DashMap::new();
        let original = Arc::new(());
        let observer = Arc::downgrade(&original);
        entries.insert(17, original);
        let result = insert_resource(&next, &entries, Arc::new(()));
        assert!(observer.upgrade().is_some(), "live owner was replaced");
        assert_eq!(result, Err(ResourceHandleError::Exhausted));
        assert_eq!(entries.len(), 1);
    }

    #[test]
    fn resource_handle_exhaustion_drops_the_rejected_owner() {
        let next = AtomicU32::new(i32::MAX as u32 + 1);
        let entries = DashMap::new();
        let resource = Arc::new(());
        let observer = Arc::downgrade(&resource);
        let result = insert_resource(&next, &entries, resource);
        assert!(observer.upgrade().is_none(), "rejected owner was retained");
        assert_eq!(result, Err(ResourceHandleError::Exhausted));
        assert!(entries.is_empty());
    }

    #[test]
    fn resource_handle_collision_drops_only_the_rejected_owner() {
        let next = AtomicU32::new(17);
        let entries = DashMap::new();
        let original = Arc::new(());
        let original_observer = Arc::downgrade(&original);
        entries.insert(17, original);
        let rejected = Arc::new(());
        let rejected_observer = Arc::downgrade(&rejected);
        let result = insert_resource(&next, &entries, rejected);
        assert!(rejected_observer.upgrade().is_none());
        assert!(original_observer.upgrade().is_some());
        assert_eq!(result, Err(ResourceHandleError::Exhausted));
    }

    #[test]
    fn resource_handle_concurrent_final_slot_has_one_winner() {
        let next = AtomicU32::new(i32::MAX as u32);
        let entries = DashMap::new();
        let start = Barrier::new(8);
        let results = thread::scope(|scope| {
            let threads: Vec<_> = (0..8)
                .map(|value| {
                    let (next, entries, start) = (&next, &entries, &start);
                    scope.spawn(move || {
                        start.wait();
                        insert_resource(next, entries, value)
                    })
                })
                .collect();
            threads
                .into_iter()
                .map(|t| t.join().unwrap())
                .collect::<Vec<_>>()
        });
        assert_eq!(results.iter().filter(|result| result.is_ok()).count(), 1);
        assert_eq!(results.iter().filter(|result| result.is_err()).count(), 7);
        assert_eq!(entries.len(), 1);
        assert_eq!(next.load(Ordering::SeqCst), i32::MAX as u32 + 1);
    }

    #[test]
    fn resource_handle_clear_does_not_revive_stale_ids() {
        let next = AtomicU32::new(1);
        let entries = DashMap::new();
        let stale = insert_resource(&next, &entries, "old").unwrap();
        entries.clear();
        let fresh = insert_resource(&next, &entries, "new").unwrap();
        assert_ne!(stale, fresh);
        assert!(!entries.contains_key(&stale));
        assert_eq!(*entries.get(&fresh).unwrap(), "new");
    }
}
