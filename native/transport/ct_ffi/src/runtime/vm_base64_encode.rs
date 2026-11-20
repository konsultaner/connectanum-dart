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
    let Some(encoded_length) = base64::encoded_len(length as usize, true) else {
        return ERR_UNSUPPORTED;
    };
    let Some(total) = encoded_length
        .checked_add(prefix as usize)
        .and_then(|n| n.checked_add(suffix as usize))
        .filter(|n| *n <= i32::MAX as usize)
    else {
        return ERR_UNSUPPORTED;
    };
    let source = if length == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(data, length as usize) }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::ffi::ct_external_byte_buffer_free;
    struct Input { bytes: Vec<u8>, kind: i32, length: isize, acquired: bool, releases: usize, acquire_error: bool, release_error: bool }
    impl Input { fn new(bytes: Vec<u8>) -> Self { let length=bytes.len() as isize; Self {bytes,kind:2,length,acquired:false,releases:0,acquire_error:false,release_error:false} } }
    unsafe extern "C" fn acquire(p:*mut c_void,kind:*mut i32,data:*mut *mut u8,len:*mut isize)->*mut c_void {
        let i=unsafe { &mut *p.cast::<Input>() }; assert!(!i.acquired);
        if i.acquire_error { return 1usize as *mut c_void; }
        i.acquired=true;
        unsafe { *kind=i.kind; *data=i.bytes.as_mut_ptr(); *len=i.length; }
        ptr::null_mut()
    }
    unsafe extern "C" fn release(p:*mut c_void)->*mut c_void {
        let i=unsafe { &mut *p.cast::<Input>() };assert!(i.acquired);i.acquired=false;i.releases+=1;
        if i.release_error {1usize as *mut c_void} else {ptr::null_mut()}
    }
    unsafe extern "C" fn is_error(p:*mut c_void)->bool { !p.is_null() }
    fn output()->CtExternalByteBuffer { CtExternalByteBuffer {ptr:ptr::null_mut(),len:0,owner:ptr::null_mut()} }
    fn encode(i:&mut Input,prefix:i32,suffix:i32,o:&mut CtExternalByteBuffer)->i32 {
        ct_base64_encode_canonical_vm_bytes((i as *mut Input).cast(),prefix,suffix,Some(acquire),Some(release),Some(is_error),o)
    }
    #[test]
    fn borrowed_encoding_matches_canonical_bytes_and_releases_before_publish() {
        for kind in [2,3] {for length in [0,1,2,3,31,32,33,65537] {for prefix in [0,1,58,4096] {
            let mut input=Input::new((0..length).map(|i| (i*37+11) as u8).collect());input.kind=kind;
            let expected=Base64Engine.encode(&input.bytes);let mut out=output();
            assert_eq!(encode(&mut input,prefix,3,&mut out),0);assert!(!input.acquired);assert_eq!(input.releases,1);
            assert!(!out.owner.is_null());let wire=unsafe {slice::from_raw_parts_mut(out.ptr,out.len)};
            assert_eq!(wire.len(),prefix as usize+expected.len()+3);
            assert!(wire[..prefix as usize].iter().all(|b| *b==0));assert!(wire[wire.len()-3..].iter().all(|b| *b==0));
            input.bytes.fill(0xee);assert_eq!(&wire[prefix as usize..wire.len()-3],expected.as_bytes());
            wire[0]^=255;ct_external_byte_buffer_free(out.owner);
        }}}
    }
    #[test]
    fn borrowed_encoding_releases_once_on_unsupported_data_and_release_error() {
        for (kind,length,acquire_error,release_error,releases) in [(1,3,false,false,1),(2,-1,false,false,1),(2,i32::MAX as isize,false,false,1),(2,3,true,false,0),(2,3,false,true,1)] {
            let mut i=Input::new(vec![1,2,3]);i.kind=kind;i.length=length;i.acquire_error=acquire_error;i.release_error=release_error;
            let mut out=output();assert_eq!(encode(&mut i,0,0,&mut out),ERR_UNSUPPORTED);assert!(!i.acquired);assert_eq!(i.releases,releases);
            assert!(out.owner.is_null());assert!(out.ptr.is_null());assert_eq!(out.len,0);
        }
        let mut i=Input::new(vec![1,2,3]);let mut out=output();assert_eq!(encode(&mut i,4097,0,&mut out),ERR_INVALID_ARGUMENT);assert_eq!(i.releases,0);
        assert_eq!(ct_base64_encode_canonical_vm_bytes((&mut i as *mut Input).cast(),0,0,None,Some(release),Some(is_error),&mut out),ERR_UNSUPPORTED);assert_eq!(i.releases,0);
    }
}
