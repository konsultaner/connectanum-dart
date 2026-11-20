use super::{
    write_external_byte_buffer, Base64Engine, CtExternalByteBuffer, ERR_INVALID_ARGUMENT,
    ERR_UNSUPPORTED,
};
use base64::Engine as _;
use std::{ffi::c_void, ptr, slice};
type Acquire = unsafe extern "C" fn(*mut c_void, *mut i32, *mut *mut u8, *mut isize) -> *mut c_void;
type Release = unsafe extern "C" fn(*mut c_void) -> *mut c_void;
type IsError = unsafe extern "C" fn(*mut c_void) -> bool;
struct Acquired {
    input: *mut c_void,
    release: Release,
    active: bool,
}
impl Acquired {
    fn finish(mut self) -> *mut c_void {
        self.active = false;
        unsafe { (self.release)(self.input) }
    }
}
impl Drop for Acquired {
    fn drop(&mut self) {
        if self.active {
            unsafe {
                (self.release)(self.input);
            }
        }
    }
}
/// Synchronous Handle FFI scope; acquire once, release before returning.
/// The encoded output has independent native ownership, including reserved bytes.
#[no_mangle]
pub extern "C" fn ct_base64_encode_canonical_vm_bytes(
    input: *mut c_void,
    prefix: i32,
    suffix: i32,
    acquire: Option<Acquire>,
    release: Option<Release>,
    is_error: Option<IsError>,
    out: *mut CtExternalByteBuffer,
) -> i32 {
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe {
        (*out).ptr = ptr::null_mut();
        (*out).len = 0;
        (*out).owner = ptr::null_mut();
    }
    if input.is_null() || !(0..=4096).contains(&prefix) || !(0..=4096).contains(&suffix) {
        return ERR_INVALID_ARGUMENT;
    }
    let (Some(acquire), Some(release), Some(is_error)) = (acquire, release, is_error) else {
        return ERR_UNSUPPORTED;
    };
    let mut kind = 0;
    let mut data = ptr::null_mut();
    let mut length = 0isize;
    let result = unsafe { acquire(input, &mut kind, &mut data, &mut length) };
    if unsafe { is_error(result) } {
        return ERR_UNSUPPORTED;
    }
    let guard = Acquired {
        input,
        release,
        active: true,
    };
    // Public Dart_TypedData_Type: Uint8=2, Uint8Clamped=3. No Dart allocation
    // or Dart-code execution occurs while these bytes are acquired.
    if ![2, 3].contains(&kind)
        || length < 0
        || length > i32::MAX as isize
        || (length > 0 && data.is_null())
    {
        return ERR_UNSUPPORTED;
    }
    let source = if length == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(data, length as usize) }
    };
    let Some(encoded_length) = base64::encoded_len(source.len(), true) else {
        return ERR_UNSUPPORTED;
    };
    let Some(total) = encoded_length
        .checked_add(prefix as usize)
        .and_then(|n| n.checked_add(suffix as usize))
        .filter(|n| *n <= i32::MAX as usize)
    else {
        return ERR_UNSUPPORTED;
    };
    let mut bytes = vec![0u8; total];
    let body = &mut bytes[prefix as usize..prefix as usize + encoded_length];
    match Base64Engine.encode_slice(source, body) {
        Ok(written) if written == encoded_length => {}
        _ => return ERR_UNSUPPORTED,
    }
    let released = guard.finish();
    if unsafe { is_error(released) } {
        return ERR_UNSUPPORTED;
    }
    write_external_byte_buffer(bytes, out)
}
