//! Explicit raw-frame coalescing and cross-segment range copies.
use std::sync::atomic::{AtomicU64, Ordering};

static COALESCED: AtomicU64 = AtomicU64::new(0);
static RANGES: AtomicU64 = AtomicU64::new(0);
static SINGLE_REQUESTS: AtomicU64 = AtomicU64::new(0);
static MULTI_REQUESTS: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RawFrameCopyMetricsSnapshot {
    pub coalescing_copy_bytes_total: u64,
    pub range_copy_bytes_total: u64,
    pub single_segment_contiguous_requests_total: u64,
    pub multi_segment_contiguous_requests_total: u64,
}

pub fn snapshot() -> RawFrameCopyMetricsSnapshot {
    RawFrameCopyMetricsSnapshot {
        coalescing_copy_bytes_total: COALESCED.load(Ordering::Relaxed),
        range_copy_bytes_total: RANGES.load(Ordering::Relaxed),
        single_segment_contiguous_requests_total: SINGLE_REQUESTS.load(Ordering::Relaxed),
        multi_segment_contiguous_requests_total: MULTI_REQUESTS.load(Ordering::Relaxed),
    }
}

#[cfg(test)]
thread_local! {
    static OBSERVED: std::cell::Cell<RawFrameCopyMetricsSnapshot> = const {
        std::cell::Cell::new(RawFrameCopyMetricsSnapshot {
            coalescing_copy_bytes_total: 0, range_copy_bytes_total: 0,
            single_segment_contiguous_requests_total: 0,
            multi_segment_contiguous_requests_total: 0,
        })
    };
}

pub(super) fn record_contiguous_request(segments: usize) {
    if segments == 1 {
        SINGLE_REQUESTS.fetch_add(1, Ordering::Relaxed);
        #[cfg(test)]
        OBSERVED.with(|cell| {
            let mut value = cell.get();
            value.single_segment_contiguous_requests_total += 1;
            cell.set(value);
        });
    } else if segments > 1 {
        MULTI_REQUESTS.fetch_add(1, Ordering::Relaxed);
        #[cfg(test)]
        OBSERVED.with(|cell| {
            let mut value = cell.get();
            value.multi_segment_contiguous_requests_total += 1;
            cell.set(value);
        });
    }
}

pub(super) fn record_coalescing_copy(bytes: usize) {
    COALESCED.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|cell| {
        let mut value = cell.get();
        value.coalescing_copy_bytes_total += bytes as u64;
        cell.set(value);
    });
}

pub(super) fn record_range_copy(bytes: usize) {
    RANGES.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|cell| {
        let mut value = cell.get();
        value.range_copy_bytes_total += bytes as u64;
        cell.set(value);
    });
}

#[cfg(test)]
pub(super) fn observed_on_current_thread() -> RawFrameCopyMetricsSnapshot {
    OBSERVED.with(std::cell::Cell::get)
}
