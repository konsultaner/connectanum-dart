//! Copy observations for the pinned Connectanum Rustls build.
//!
//! These counters cover only their named sites. They cannot certify total TLS
//! memory-copy coverage; unobserved record, growth and crypto paths remain.

use core::sync::atomic::{AtomicU64, Ordering};

static OUTBOUND_CHUNK_BYTES: AtomicU64 = AtomicU64::new(0);
static QUEUE_READ_BYTES: AtomicU64 = AtomicU64::new(0);

/// Cumulative bytes actually copied at the named source sites.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Snapshot {
    /// Bytes appended from outbound source chunks, excluding buffer growth.
    pub outbound_chunk_copy_bytes: u64,
    /// Bytes read from a Rustls queue into the caller's destination.
    pub queue_read_copy_bytes: u64,
}

/// Read this process's cumulative observations. This is partial TLS coverage.
pub fn snapshot() -> Snapshot {
    Snapshot {
        outbound_chunk_copy_bytes: OUTBOUND_CHUNK_BYTES.load(Ordering::Relaxed),
        queue_read_copy_bytes: QUEUE_READ_BYTES.load(Ordering::Relaxed),
    }
}

#[cfg(test)]
std::thread_local! {
    static LOCAL: std::cell::Cell<(u64, u64)> = const { std::cell::Cell::new((0, 0)) };
}

pub(crate) fn outbound_chunk_copy(bytes: usize) {
    OUTBOUND_CHUNK_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    LOCAL.with(|value| {
        let (outbound, read) = value.get();
        value.set((outbound + bytes as u64, read));
    });
}

pub(crate) fn queue_read_copy(bytes: usize) {
    QUEUE_READ_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    LOCAL.with(|value| {
        let (outbound, read) = value.get();
        value.set((outbound, read + bytes as u64));
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::msgs::message::OutboundChunks;
    use crate::vecbuf::ChunkVecBuffer;
    use alloc::{vec, vec::Vec};

    #[test]
    fn observer_counts_partial_queue_appends_and_reads() {
        LOCAL.with(|value| value.set((0, 0)));
        let mut queue = ChunkVecBuffer::new(Some(5));
        assert_eq!(queue.append_limited_copy(b"abcdef"[..].into()), 5);
        assert_eq!(queue.append_limited_copy(b"more"[..].into()), 0);
        let mut first = [0; 2];
        assert_eq!(queue.read(&mut first).unwrap(), 2);
        assert_eq!(&first, b"ab");
        assert_eq!(queue.read(&mut []).unwrap(), 0);
        let mut rest = [0; 4];
        assert_eq!(queue.read(&mut rest).unwrap(), 3);
        assert_eq!(&rest[..3], b"cde");
        assert_eq!(LOCAL.with(|value| value.get()), (5, 5));
    }

    #[test]
    fn observer_counts_only_selected_outbound_chunk_ranges() {
        LOCAL.with(|value| value.set((0, 0)));
        let chunks: &[&[u8]] = &[b"ab", b"cdef", b"gh"];
        let selected = OutboundChunks::Multiple {
            chunks,
            start: 1,
            end: 7,
        };
        let mut destination = vec![42];
        selected.copy_to_vec(&mut destination);
        assert_eq!(&destination, b"*bcdefg");
        assert_eq!(LOCAL.with(|value| value.get()), (6, 0));
        assert_eq!(OutboundChunks::new_empty().to_vec(), Vec::<u8>::new());
        assert_eq!(LOCAL.with(|value| value.get()), (6, 0));
    }
}
