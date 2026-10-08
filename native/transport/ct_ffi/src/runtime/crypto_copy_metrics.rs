//! Actual bulk crypto staging copies, independent of transport counters.
//! Nonce/tag construction and cipher processing are excluded. An attached tag
//! copied along with a ciphertext body is included. These counters do not
//! cover serializer/framing, Dart bridges or crypto operations outside this ABI.

use super::constants::{ERR_INVALID_ARGUMENT, SUCCESS};
use std::sync::atomic::{AtomicU64, Ordering};

static PLAINTEXT: AtomicU64 = AtomicU64::new(0);
static CIPHERTEXT: AtomicU64 = AtomicU64::new(0);

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CtE2eeCopyMetricsInfo {
    pub plaintext_staging_copy_bytes_total: u64,
    pub ciphertext_staging_copy_bytes_total: u64,
}

#[cfg(test)]
thread_local! {
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
