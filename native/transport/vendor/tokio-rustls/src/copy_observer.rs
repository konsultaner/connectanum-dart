//! Actual plaintext extraction copies into an AsyncRead caller's buffer.
//! Borrowed AsyncBufRead views, consumption, growth and TLS crypto are excluded.
//! This process-wide observation does not certify complete TLS-copy coverage.

use std::sync::atomic::{AtomicU64, Ordering};

static PLAINTEXT_EXTRACTION: AtomicU64 = AtomicU64::new(0);

/// Cumulative bytes copied at the source's successful ReadBuf::put_slice site.
pub fn plaintext_extract_copy_bytes() -> u64 {
    PLAINTEXT_EXTRACTION.load(Ordering::Relaxed)
}

#[cfg(test)]
std::thread_local! {
    static OBSERVED: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

pub(crate) fn plaintext_extract_copy(bytes: usize) {
    PLAINTEXT_EXTRACTION.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|value| value.set(value.get() + bytes as u64));
}

#[cfg(test)]
pub(crate) fn observed_on_current_thread() -> u64 {
    OBSERVED.with(std::cell::Cell::get)
}
