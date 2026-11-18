//! Exclusive, initialized bytes whose backing pages leave the process on drop.
//! The opaque owner is published to exactly one SDK typed-data finalizer.

use super::constants::{ERR_INVALID_ARGUMENT, ERR_IO, SUCCESS};
use memmap2::MmapMut;
use std::ffi::c_void;
use std::{io, ptr};

#[repr(C)]
pub struct CtMappedBytes {
    pub ptr: *mut u8,
    pub len: usize,
    pub owner: *mut c_void,
}

struct Owner {
    mapping: MmapMut,
    #[cfg(test)]
    lifetime: std::sync::Arc<()>,
}

#[cfg(any(test, feature = "ffi-test"))]
static LIVE: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

#[cfg(any(test, feature = "ffi-test"))]
impl Drop for Owner {
    fn drop(&mut self) {
        LIVE.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
    }
}

fn allocate_with(
    length: i32,
    out: *mut CtMappedBytes,
    map: impl FnOnce(usize) -> io::Result<MmapMut>,
) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe {
        out.write(CtMappedBytes {
            ptr: ptr::null_mut(),
            len: 0,
            owner: ptr::null_mut(),
        });
    }
    if length <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let mapping = match map(length as usize) {
        Ok(mapping) => mapping,
        Err(_) => return ERR_IO,
    };
    let mut owner = Box::new(Owner {
        mapping,
        #[cfg(test)]
        lifetime: std::sync::Arc::new(()),
    });
    let data = owner.mapping.as_mut_ptr();
    #[cfg(any(test, feature = "ffi-test"))]
    LIVE.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    unsafe {
        out.write(CtMappedBytes {
            ptr: data,
            len: length as usize,
            owner: Box::into_raw(owner).cast(),
        });
    }
    SUCCESS
}

/// Allocate nonempty, zero-initialized mutable bytes independently of a runtime.
/// `out` must be an aligned writable slot; its previous contents remain the
/// caller's responsibility and must not hold an unreleased owner.
/// On failure a nonnull output is cleared and no ownership escapes. On success
/// transfer the owner once to `ct_mapped_bytes_finalizer`, only after every
/// derived view dies. Neither the data pointer nor an arbitrary token is an owner.
#[no_mangle]
pub extern "C" fn ct_mapped_bytes_allocate(length: i32, out: *mut CtMappedBytes) -> i32 {
    allocate_with(length, out, MmapMut::map_anon)
}

/// Takes exactly the opaque owner returned by allocate, once, on any thread.
/// Dropping the mapping returns its pages without tuning the process allocator.
#[no_mangle]
pub extern "C" fn ct_mapped_bytes_finalizer(owner: *mut c_void) {
    if !owner.is_null() {
        unsafe {
            drop(Box::from_raw(owner.cast::<Owner>()));
        }
    }
}

#[cfg(any(test, feature = "ffi-test"))]
#[no_mangle]
pub extern "C" fn ct_test_mapped_bytes_live_allocations() -> usize {
    LIVE.load(std::sync::atomic::Ordering::SeqCst)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn poisoned() -> CtMappedBytes {
        CtMappedBytes {
            ptr: ptr::NonNull::<u8>::dangling().as_ptr(),
            len: 99,
            owner: ptr::NonNull::<u8>::dangling().as_ptr().cast(),
        }
    }

    #[test]
    fn validates_and_clears_output_before_allocating() {
        assert_eq!(
            allocate_with(1, ptr::null_mut(), |_| panic!("must not map")),
            ERR_INVALID_ARGUMENT
        );
        for length in [0, -1, i32::MIN] {
            let mut out = poisoned();
            assert_eq!(
                allocate_with(length, &mut out, |_| panic!("must not map")),
                ERR_INVALID_ARGUMENT
            );
            assert!(out.ptr.is_null() && out.owner.is_null());
            assert_eq!(out.len, 0);
        }
        ct_mapped_bytes_finalizer(ptr::null_mut());
    }

    #[test]
    fn mapping_failure_publishes_no_owner() {
        let mut out = poisoned();
        assert_eq!(
            allocate_with(65536, &mut out, |_| Err(io::Error::other(
                "controlled mapping failure"
            ))),
            ERR_IO
        );
        assert!(out.ptr.is_null() && out.owner.is_null());
        assert_eq!(out.len, 0);
    }

    #[test]
    fn initialized_mutable_mapping_is_released_on_another_thread() {
        for length in [1, 16384, 65537, 1 << 20] {
            let mut out = poisoned();
            assert_eq!(ct_mapped_bytes_allocate(length, &mut out), SUCCESS);
            assert_eq!(out.len, length as usize);
            assert!(!out.ptr.is_null() && !out.owner.is_null());
            assert_eq!(out.ptr as usize % 8, 0);
            let lifetime =
                unsafe { std::sync::Arc::downgrade(&(*out.owner.cast::<Owner>()).lifetime) };
            unsafe {
                let bytes = std::slice::from_raw_parts_mut(out.ptr, out.len);
                assert!(bytes.iter().all(|byte| *byte == 0));
                bytes[0] = 7;
                bytes[out.len - 1] = 9;
                assert_eq!(bytes[out.len - 1], 9);
            }
            let token = out.owner as usize;
            std::thread::spawn(move || ct_mapped_bytes_finalizer(token as *mut c_void))
                .join()
                .unwrap();
            assert!(lifetime.upgrade().is_none());
        }
    }
}
