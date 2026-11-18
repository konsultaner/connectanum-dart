//! Controlled ABI failures for the Dart owner-transfer cleanup regression.
use std::ffi::c_void;
use std::sync::atomic::{AtomicUsize, Ordering};

#[repr(C)]
pub struct MappedBytes {
    data: *mut u8,
    length: usize,
    owner: *mut c_void,
}

static MODE: AtomicUsize = AtomicUsize::new(0);
static RELEASED: AtomicUsize = AtomicUsize::new(0);

#[no_mangle]
pub extern "C" fn fixture_mode(mode: usize) {
    MODE.store(mode, Ordering::SeqCst);
}

#[no_mangle]
pub extern "C" fn fixture_released() -> usize {
    RELEASED.load(Ordering::SeqCst)
}

#[no_mangle]
pub unsafe extern "C" fn ct_mapped_bytes_allocate(_: i32, out: *mut MappedBytes) -> i32 {
    out.write(MappedBytes {
        data: std::ptr::null_mut(),
        length: 0,
        owner: std::ptr::null_mut(),
    });
    if MODE.load(Ordering::SeqCst) == 0 {
        return -4;
    }
    let owner = Box::into_raw(Box::new(0u8));
    // Invalid external-data length makes the SDK reject view construction.
    // The successfully allocated opaque owner must still be released once.
    out.write(MappedBytes {
        data: owner,
        length: usize::MAX,
        owner: owner.cast(),
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn ct_mapped_bytes_finalizer(owner: *mut c_void) {
    drop(Box::from_raw(owner.cast::<u8>()));
    RELEASED.fetch_add(1, Ordering::SeqCst);
}
