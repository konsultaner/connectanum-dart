//! Actual bulk crypto staging copies, independent of transport counters.
//! Nonce/tag assembly has a separate additive scalar counter. Cipher processing
//! is excluded. An attached tag
//! copied along with a ciphertext body is included. These counters do not
//! cover serializer/framing, Dart bridges or crypto operations outside this ABI.

use super::constants::{ERR_INVALID_ARGUMENT, SUCCESS};
use std::sync::atomic::{AtomicU64, Ordering};

static PLAINTEXT: AtomicU64 = AtomicU64::new(0);
static CIPHERTEXT: AtomicU64 = AtomicU64::new(0);
static NONCE_TAG: AtomicU64 = AtomicU64::new(0);

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CtE2eeCopyMetricsInfo {
    pub plaintext_staging_copy_bytes_total: u64,
    pub ciphertext_staging_copy_bytes_total: u64,
}

#[cfg(test)]
thread_local! {
    static OBSERVED_NONCE_TAG: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
    // Per-thread oracle observes the real staging sites without parallel-test
    // noise in the public process-wide counters.
    static OBSERVED: std::cell::Cell<CtE2eeCopyMetricsInfo> = const {
        std::cell::Cell::new(CtE2eeCopyMetricsInfo {
            plaintext_staging_copy_bytes_total: 0,
            ciphertext_staging_copy_bytes_total: 0,
        })
    };
}

pub(super) fn record_plaintext_copy(bytes: usize) {
    PLAINTEXT.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|value| {
        let mut observed = value.get();
        observed.plaintext_staging_copy_bytes_total += bytes as u64;
        value.set(observed);
    });
}

pub(super) fn record_ciphertext_copy(bytes: usize) {
    CIPHERTEXT.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|value| {
        let mut observed = value.get();
        observed.ciphertext_staging_copy_bytes_total += bytes as u64;
        value.set(observed);
    });
}

#[cfg(test)]
pub(super) fn observed_on_current_thread() -> CtE2eeCopyMetricsInfo {
    OBSERVED.with(std::cell::Cell::get)
}

#[no_mangle]
pub extern "C" fn ct_e2ee_copy_metrics_abi_version() -> u32 {
    1
}

/// Cumulative process counters; authentication failures still count actual
/// staging work. A snapshot does not synchronize concurrent crypto operations.
#[no_mangle]
pub extern "C" fn ct_e2ee_copy_metrics_snapshot(out: *mut CtE2eeCopyMetricsInfo) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe {
        out.write(CtE2eeCopyMetricsInfo {
            plaintext_staging_copy_bytes_total: PLAINTEXT.load(Ordering::Relaxed),
            ciphertext_staging_copy_bytes_total: CIPHERTEXT.load(Ordering::Relaxed),
        });
    }
    SUCCESS
}

/// Explicit nonce/tag copies in Connectanum framing; excludes cipher internals.
pub(super) fn record_nonce_tag_copy(bytes: usize) {
    NONCE_TAG.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED_NONCE_TAG.with(|value| value.set(value.get() + bytes as u64));
}

#[cfg(test)]
pub(super) fn observed_nonce_tag_on_current_thread() -> u64 {
    OBSERVED_NONCE_TAG.with(std::cell::Cell::get)
}

/// Additive scalar observation. The existing 16-byte v1 ABI is unchanged.
#[no_mangle]
pub extern "C" fn ct_e2ee_nonce_tag_copy_metrics_snapshot(out: *mut u64) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe {
        out.write(NONCE_TAG.load(Ordering::Relaxed));
    }
    SUCCESS
}

static PLAINTEXT_FRAMING: AtomicU64 = AtomicU64::new(0);

#[cfg(test)]
thread_local! {
    static OBSERVED_PLAINTEXT_FRAMING: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

/// Explicit CBOR plaintext wrapper/header copies, including native file input.
/// File reads and cipher output computation are not memory-copy observations.
pub(super) fn record_plaintext_framing_copy(bytes: usize) {
    PLAINTEXT_FRAMING.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED_PLAINTEXT_FRAMING.with(|value| value.set(value.get() + bytes as u64));
}

#[cfg(test)]
pub(super) fn observed_plaintext_framing_on_current_thread() -> u64 {
    OBSERVED_PLAINTEXT_FRAMING.with(std::cell::Cell::get)
}

/// Additive scalar; existing crypto metric structs and versions are unchanged.
#[no_mangle]
pub extern "C" fn ct_e2ee_plaintext_framing_copy_metrics_snapshot(out: *mut u64) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe {
        out.write(PLAINTEXT_FRAMING.load(Ordering::Relaxed));
    }
    SUCCESS
}
