//! Copy observations for the pinned Connectanum Rustls build.
//!
//! These counters cover only their named sites. They cannot certify total TLS
//! memory-copy coverage; unobserved record, growth and crypto paths remain.

use core::sync::atomic::{AtomicU64, Ordering};

static OUTBOUND_CHUNK_BYTES: AtomicU64 = AtomicU64::new(0);
static QUEUE_READ_BYTES: AtomicU64 = AtomicU64::new(0);
static DEFRAMER_APPEND_BYTES: AtomicU64 = AtomicU64::new(0);
static DEFRAMER_MOVE_BYTES: AtomicU64 = AtomicU64::new(0);
static RECORD_BUFFER_BYTES: AtomicU64 = AtomicU64::new(0);
static RECORD_APPEND_BYTES: AtomicU64 = AtomicU64::new(0);

/// Cumulative bytes actually copied at the named source sites.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Snapshot {
    /// Bytes appended from outbound source chunks, excluding buffer growth.
    pub outbound_chunk_copy_bytes: u64,
    /// Bytes read from a Rustls queue into the caller's destination.
    pub queue_read_copy_bytes: u64,
    /// Bytes appended into deframer storage, excluding capacity growth.
    pub deframer_append_copy_bytes: u64,
    /// Bytes actually moved by deframer compaction or coalescing.
    pub deframer_move_copy_bytes: u64,
    /// Bytes copied from record buffers; prefixed clones include their header.
    pub record_buffer_copy_bytes: u64,
    /// Bytes copied from slices/iterators into record buffers, excluding growth
    /// and initial header initialization. Includes appended type/tag bytes.
    pub record_append_copy_bytes: u64,
}

/// Read this process's cumulative observations. This is partial TLS coverage.
pub fn snapshot() -> Snapshot {
    Snapshot {
        outbound_chunk_copy_bytes: OUTBOUND_CHUNK_BYTES.load(Ordering::Relaxed),
        queue_read_copy_bytes: QUEUE_READ_BYTES.load(Ordering::Relaxed),
        deframer_append_copy_bytes: DEFRAMER_APPEND_BYTES.load(Ordering::Relaxed),
        deframer_move_copy_bytes: DEFRAMER_MOVE_BYTES.load(Ordering::Relaxed),
        record_buffer_copy_bytes: RECORD_BUFFER_BYTES.load(Ordering::Relaxed),
        record_append_copy_bytes: RECORD_APPEND_BYTES.load(Ordering::Relaxed),
    }
}

#[cfg(test)]
std::thread_local! {
    static LOCAL: std::cell::Cell<(u64, u64, u64, u64, u64, u64)> = const { std::cell::Cell::new((0, 0, 0, 0, 0, 0)) };
}

pub(crate) fn outbound_chunk_copy(bytes: usize) {
    OUTBOUND_CHUNK_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    LOCAL.with(|value| {
        let (outbound, read, append, moved, record, record_append) = value.get();
        value.set((
            outbound + bytes as u64,
            read,
            append,
            moved,
            record,
            record_append,
        ));
    });
}

pub(crate) fn queue_read_copy(bytes: usize) {
    QUEUE_READ_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    LOCAL.with(|value| {
        let (outbound, read, append, moved, record, record_append) = value.get();
        value.set((
            outbound,
            read + bytes as u64,
            append,
            moved,
            record,
            record_append,
        ));
    });
}

pub(crate) fn deframer_append_copy(bytes: usize) {
    DEFRAMER_APPEND_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    LOCAL.with(|value| {
        let (outbound, read, append, moved, record, record_append) = value.get();
        value.set((
            outbound,
            read,
            append + bytes as u64,
            moved,
            record,
            record_append,
        ));
    });
}

pub(crate) fn deframer_move_copy(bytes: usize) {
    DEFRAMER_MOVE_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    LOCAL.with(|value| {
        let (outbound, read, append, moved, record, record_append) = value.get();
        value.set((
            outbound,
            read,
            append,
            moved + bytes as u64,
            record,
            record_append,
        ));
    });
}

pub(crate) fn record_buffer_copy(bytes: usize) {
    RECORD_BUFFER_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    LOCAL.with(|value| {
        let (outbound, read, append, moved, record, record_append) = value.get();
        value.set((
            outbound,
            read,
            append,
            moved,
            record + bytes as u64,
            record_append,
        ));
    });
}

pub(crate) fn record_append_copy(bytes: usize) {
    RECORD_APPEND_BYTES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    LOCAL.with(|value| {
        let (outbound, read, append, moved, record, record_append) = value.get();
        value.set((
            outbound,
            read,
            append,
            moved,
            record,
            record_append + bytes as u64,
        ));
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::enums::{ContentType, ProtocolVersion};
    use crate::msgs::deframer::buffers::{Coalescer, DeframerVecBuffer};
    use crate::msgs::message::OutboundChunks;
    use crate::msgs::message::{OutboundOpaqueMessage, PrefixedPayload, HEADER_SIZE};
    use crate::vecbuf::ChunkVecBuffer;
    use alloc::{vec, vec::Vec};

    #[test]
    fn observer_counts_partial_queue_appends_and_reads() {
        LOCAL.with(|value| value.set((0, 0, 0, 0, 0, 0)));
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
        assert_eq!(LOCAL.with(|value| value.get()), (5, 5, 0, 0, 0, 0));
    }

    #[test]
    fn observer_counts_only_selected_outbound_chunk_ranges() {
        LOCAL.with(|value| value.set((0, 0, 0, 0, 0, 0)));
        let chunks: &[&[u8]] = &[b"ab", b"cdef", b"gh"];
        let selected = OutboundChunks::Multiple {
            chunks,
            start: 1,
            end: 7,
        };
        let mut destination = vec![42];
        selected.copy_to_vec(&mut destination);
        assert_eq!(&destination, b"*bcdefg");
        assert_eq!(LOCAL.with(|value| value.get()), (6, 0, 0, 0, 0, 0));
        assert_eq!(OutboundChunks::new_empty().to_vec(), Vec::<u8>::new());
        assert_eq!(LOCAL.with(|value| value.get()), (6, 0, 0, 0, 0, 0));
    }

    #[test]
    fn observer_counts_deframer_appends_and_only_shifted_pending_bytes() {
        LOCAL.with(|value| value.set((0, 0, 0, 0, 0, 0)));
        let mut buffer = DeframerVecBuffer::default();
        assert_eq!(buffer.extend(b""), 0..0);
        assert_eq!(buffer.extend(b"abcdef"), 0..6);
        buffer.discard(0);
        assert_eq!(buffer.filled_mut(), b"abcdef");
        buffer.discard(2);
        assert_eq!(buffer.filled_mut(), b"cdef");
        assert_eq!(buffer.extend(b"ghij"), 4..8);
        buffer.discard(3);
        assert_eq!(buffer.filled_mut(), b"fghij");
        assert_eq!(LOCAL.with(|value| value.get()), (0, 0, 10, 9, 0, 0));
        buffer.discard(5);
        buffer.discard(99);
        assert!(buffer.filled_mut().is_empty());
        assert_eq!(LOCAL.with(|value| value.get()), (0, 0, 10, 9, 0, 0));
    }

    #[test]
    fn observer_counts_coalescer_overlap_but_not_self_or_empty_moves() {
        LOCAL.with(|value| value.set((0, 0, 0, 0, 0, 0)));
        let mut buffer = *b"0123456789";
        let mut coalescer = Coalescer::new(&mut buffer);
        coalescer.copy_within(1..4, 5..8);
        coalescer.copy_within(5..8, 6..9);
        coalescer.copy_within(2..5, 2..5);
        coalescer.copy_within(1..1, 8..8);
        assert_eq!(buffer, *b"0123411239");
        assert_eq!(LOCAL.with(|value| value.get()), (0, 0, 0, 6, 0, 0));
    }

    #[test]
    fn observer_counts_record_clones_but_not_owned_encode_moves() {
        LOCAL.with(|value| value.set((0, 0, 0, 0, 0, 0)));
        let record = OutboundOpaqueMessage::new(
            ContentType::ApplicationData,
            ProtocolVersion::TLSv1_2,
            PrefixedPayload::from(b"data"),
        );
        let cloned = record.clone();
        let original_body_address = record.payload.as_ref().as_ptr();
        let encoded = record.encode();
        assert_eq!(&encoded[HEADER_SIZE..], b"data");
        assert_eq!(encoded[HEADER_SIZE..].as_ptr(), original_body_address);
        assert_eq!(LOCAL.with(|value| value.get()), (0, 0, 0, 0, 9, 4));
        let plaintext = cloned.into_plain_message();
        assert_eq!(plaintext.payload.bytes(), b"data");
        assert_eq!(LOCAL.with(|value| value.get()), (0, 0, 0, 0, 13, 4));
    }

    #[test]
    fn observer_counts_record_appends_without_recounting_source_chunks() {
        LOCAL.with(|value| value.set((0, 0, 0, 0, 0, 0)));
        let mut payload = PrefixedPayload::with_capacity(5);
        payload.extend_from_slice(b"ab");
        payload.extend(b"c".iter());
        payload.extend_from_chunks(&b"de"[..].into());
        assert_eq!(payload.as_ref(), b"abcde");
        assert_eq!(LOCAL.with(|value| value.get()), (2, 0, 0, 0, 0, 3));
        let record = OutboundOpaqueMessage::new(
            ContentType::ApplicationData,
            ProtocolVersion::TLSv1_2,
            payload,
        );
        assert_eq!(record.into_plain_message().payload.bytes(), b"abcde");
        assert_eq!(LOCAL.with(|value| value.get()), (2, 0, 0, 0, 5, 3));
    }
}
