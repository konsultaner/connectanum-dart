// Keep the canonical padded alphabet and strict decoding policy. The engine
// selects the available SIMD instructions at runtime on supported CPUs.
#[cfg(any(target_arch = "x86_64", target_arch = "aarch64"))]
pub(super) static STANDARD: std::sync::LazyLock<base64::engine::simd::Simd> =
    std::sync::LazyLock::new(|| {
        base64::engine::simd::Simd::standard(base64::engine::general_purpose::PAD)
    });

#[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
pub(super) use base64::engine::general_purpose::STANDARD;

#[cfg(test)]
mod tests {
    use super::STANDARD;
    use base64::Engine as _;
    use base64_reference::Engine as _;

    #[test]
    fn canonical_base64_matches_previous_engine_at_vector_boundaries_and_tails() {
        let reference = base64_reference::engine::general_purpose::STANDARD;
        for length in (0..=1024).chain([4095, 4096, 4097, 65535, 65536, 65537, 4194304]) {
            let input: Vec<u8> = (0..length).map(|index| (index * 37 + 11) as u8).collect();
            let encoded = reference.encode(&input);
            assert_eq!(STANDARD.encode(&input), encoded, "length {length}");
            assert_eq!(STANDARD.decode(&encoded).unwrap(), input, "length {length}");
        }
    }

    #[test]
    fn canonical_base64_preserves_strict_rejection_at_every_vector_lane() {
        let reference = base64_reference::engine::general_purpose::STANDARD;
        for length in [47, 48, 49, 95, 96, 97, 191, 192, 193] {
            let valid = reference.encode(vec![0x5a; length]);
            for offset in 0..valid.len() {
                for byte in [b'!', b'-', b'_', b' ', b'\n', 0, 0x7f, 0x80, 0xff, b'='] {
                    let mut invalid = valid.as_bytes().to_vec();
                    invalid[offset] = byte;
                    assert_eq!(
                        STANDARD.decode(&invalid).ok(),
                        reference.decode(&invalid).ok(),
                        "length {length}, offset {offset}, byte {byte}"
                    );
                }
            }
        }
        for input in [
            "A", "AA", "AAA", "AA=", "AA===", "AAAA=", "AB==", "AAB=", "AA==\n", "AA==AA==",
        ] {
            assert!(
                reference.decode(input).is_err(),
                "reference accepted {input}"
            );
            assert!(STANDARD.decode(input).is_err(), "SIMD accepted {input}");
        }
        // Exhaust all discarded-bit variants after complete vector blocks.
        let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for prefix_length in [0, 48, 96, 192] {
            let prefix = reference.encode(vec![0x5a; prefix_length]);
            for byte in alphabet {
                for tail in [vec![b'A', *byte, b'=', b'='], vec![b'A', b'A', *byte, b'=']] {
                    let mut input = prefix.as_bytes().to_vec();
                    input.extend(tail);
                    assert_eq!(STANDARD.decode(&input).ok(), reference.decode(&input).ok());
                }
            }
        }
    }

    #[test]
    fn canonical_base64_ffi_outputs_own_independent_mutable_storage() {
        use super::super::ffi::{
            ct_base64_decode_canonical, ct_base64_encode_canonical, ct_external_byte_buffer_free,
            CtExternalByteBuffer,
        };
        use std::{ptr, slice};
        fn empty() -> CtExternalByteBuffer {
            CtExternalByteBuffer {
                ptr: ptr::null_mut(),
                len: 0,
                owner: ptr::null_mut(),
            }
        }
        for length in [0usize, 1, 2, 47, 48, 49, 127, 128, 129, 65537] {
            let mut input: Vec<u8> = (0..length).map(|n| n as u8).collect();
            let expected = input.clone();
            let mut encoded = empty();
            assert_eq!(
                ct_base64_encode_canonical(input.as_ptr(), length as i32, &mut encoded),
                0
            );
            assert!(!encoded.owner.is_null());
            let expected_encoded =
                base64_reference::engine::general_purpose::STANDARD.encode(&input);
            // Empty FFI buffers may use a null pointer; never construct a slice from it.
            if encoded.len > 0 {
                assert_eq!(
                    unsafe { slice::from_raw_parts(encoded.ptr, encoded.len) },
                    expected_encoded.as_bytes()
                );
            }
            input.fill(0xee);
            let mut decoded = empty();
            assert_eq!(
                ct_base64_decode_canonical(encoded.ptr, encoded.len as i32, &mut decoded),
                0
            );
            assert!(!decoded.owner.is_null());
            assert_ne!(encoded.owner, decoded.owner);
            ct_external_byte_buffer_free(encoded.owner);
            if decoded.len > 0 {
                let bytes = unsafe { slice::from_raw_parts_mut(decoded.ptr, decoded.len) };
                assert_eq!(bytes, expected);
                bytes[0] ^= 0xff;
                assert_eq!(input[0], 0xee);
            }
            assert_eq!(decoded.len, length);
            ct_external_byte_buffer_free(decoded.owner);
        }
    }
}

/// Called synchronously through Dart FFI with a Handle argument. The FFI
/// trampoline owns the API scope; the VM copy is read before that scope exits.
/// The returned decoded buffer has independent native ownership.
#[no_mangle]
pub extern "C" fn ct_base64_decode_canonical_vm_string(
    input: *mut std::ffi::c_void,
    start: i32,
    end: i32,
    utf16_length: i32,
    to_utf8: Option<
        unsafe extern "C" fn(
            *mut std::ffi::c_void,
            *mut *mut u8,
            *mut isize,
        ) -> *mut std::ffi::c_void,
    >,
    is_error: Option<unsafe extern "C" fn(*mut std::ffi::c_void) -> bool>,
    out: *mut super::ffi::CtExternalByteBuffer,
) -> i32 {
    use super::constants::{ERR_INVALID_ARGUMENT, ERR_UNSUPPORTED};
    if out.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    unsafe {
        (*out).ptr = std::ptr::null_mut();
        (*out).len = 0;
        (*out).owner = std::ptr::null_mut();
    }
    if input.is_null() || start < 0 || end < start || utf16_length < 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let (Some(to_utf8), Some(is_error)) = (to_utf8, is_error) else {
        return ERR_UNSUPPORTED;
    };
    let mut bytes = std::ptr::null_mut();
    let mut length = 0isize;
    let result = unsafe { to_utf8(input, &mut bytes, &mut length) };
    if unsafe { is_error(result) } {
        return ERR_UNSUPPORTED;
    }
    if length < end as isize {
        return ERR_INVALID_ARGUMENT;
    }
    // UTF-8 has the same length as UTF-16 only for an entirely ASCII String.
    // Unicode outside the selected span is handled by the original Dart path.
    if length != utf16_length as isize || (length != 0 && bytes.is_null()) {
        return ERR_UNSUPPORTED;
    }
    let bytes = if length == 0 {
        bytes
    } else {
        unsafe { bytes.add(start as usize) }
    };
    super::ffi::ct_base64_decode_canonical(bytes, end - start, out)
}

#[cfg(test)]
mod vm_string_tests {
    use super::super::{
        constants::{ERR_INVALID_ARGUMENT, ERR_UNSUPPORTED, SUCCESS},
        ffi::{ct_external_byte_buffer_free, CtExternalByteBuffer},
    };
    use super::ct_base64_decode_canonical_vm_string as decode;
    use base64_reference::Engine as _;
    use std::ffi::c_void;

    struct Input {
        bytes: Vec<u8>,
        fail: bool,
    }
    unsafe extern "C" fn to_utf8(
        input: *mut c_void,
        bytes: *mut *mut u8,
        length: *mut isize,
    ) -> *mut c_void {
        let input = unsafe { &*(input as *const Input) };
        unsafe {
            *bytes = input.bytes.as_ptr().cast_mut();
            *length = input.bytes.len() as isize;
        }
        if input.fail {
            1usize as *mut c_void
        } else {
            std::ptr::null_mut()
        }
    }
    unsafe extern "C" fn is_error(result: *mut c_void) -> bool {
        !result.is_null()
    }
    fn handle(input: &Input) -> *mut c_void {
        (input as *const Input).cast_mut().cast()
    }
    fn output() -> CtExternalByteBuffer {
        CtExternalByteBuffer {
            ptr: std::ptr::null_mut(),
            len: 0,
            owner: std::ptr::null_mut(),
        }
    }

    #[test]
    fn vm_string_spans_match_reference_and_return_independent_mutable_storage() {
        for size in (0..=256).chain([4095, 4096, 4097, 65537, 4194304]) {
            let expected: Vec<u8> = (0..size).map(|index| (index * 37 + 11) as u8).collect();
            let encoded = base64_reference::engine::general_purpose::STANDARD.encode(&expected);
            let mut input = Input {
                bytes: format!("prefix:{encoded}:suffix").into_bytes(),
                fail: false,
            };
            let mut first = output();
            let mut second = output();
            for out in [&mut first, &mut second] {
                assert_eq!(
                    decode(
                        handle(&input),
                        7,
                        7 + encoded.len() as i32,
                        input.bytes.len() as i32,
                        Some(to_utf8),
                        Some(is_error),
                        out
                    ),
                    SUCCESS
                );
                assert!(!out.owner.is_null());
                assert_eq!(
                    unsafe { std::slice::from_raw_parts(out.ptr, out.len) },
                    expected
                );
            }
            input.bytes.fill(b'?');
            if !expected.is_empty() {
                unsafe {
                    *first.ptr ^= 255;
                }
                assert_ne!(first.ptr, second.ptr);
                assert_eq!(
                    unsafe { std::slice::from_raw_parts(second.ptr, second.len) },
                    expected
                );
            }
            ct_external_byte_buffer_free(first.owner);
            assert_eq!(
                unsafe { std::slice::from_raw_parts(second.ptr, second.len) },
                expected
            );
            ct_external_byte_buffer_free(second.owner);
        }
    }

    #[test]
    fn vm_string_accepts_empty_and_rejects_missing_nonempty_api_storage() {
        unsafe extern "C" fn no_storage(
            input: *mut c_void,
            bytes: *mut *mut u8,
            length: *mut isize,
        ) -> *mut c_void {
            unsafe {
                *bytes = std::ptr::null_mut();
                *length = (*(input as *const Input)).bytes.len() as isize;
            }
            std::ptr::null_mut()
        }
        for text in ["", "AQID"] {
            let input = Input {
                bytes: text.as_bytes().to_vec(),
                fail: false,
            };
            let mut out = output();
            assert_eq!(
                decode(
                    handle(&input),
                    0,
                    text.len() as i32,
                    text.len() as i32,
                    Some(no_storage),
                    Some(is_error),
                    &mut out
                ),
                if text.is_empty() {
                    SUCCESS
                } else {
                    ERR_UNSUPPORTED
                }
            );
            if text.is_empty() {
                assert_eq!(out.len, 0);
                ct_external_byte_buffer_free(out.owner);
            } else {
                assert!(out.ptr.is_null() && out.owner.is_null() && out.len == 0);
            }
        }
    }

    #[test]
    fn vm_string_rejections_clear_output_and_preserve_canonical_policy() {
        for text in [
            "A", "AA", "AAA", "AB==", "AAB=", "AA--", "AA__", "AA==\n", "AA==AA==", "éAQID",
            "💡AQID",
        ] {
            let input = Input {
                bytes: text.as_bytes().to_vec(),
                fail: false,
            };
            let mut out = CtExternalByteBuffer {
                ptr: 1usize as *mut u8,
                len: 999,
                owner: 1usize as *mut c_void,
            };
            let utf16 = text.encode_utf16().count() as i32;
            assert_eq!(
                decode(
                    handle(&input),
                    0,
                    utf16,
                    utf16,
                    Some(to_utf8),
                    Some(is_error),
                    &mut out
                ),
                ERR_UNSUPPORTED,
                "{text}"
            );
            assert!(out.ptr.is_null() && out.owner.is_null());
            assert_eq!(out.len, 0);
        }
    }

    #[test]
    fn vm_string_rejects_invalid_ranges_missing_apis_and_api_errors() {
        let input = Input {
            bytes: b"AQID".to_vec(),
            fail: false,
        };
        for (start, end, full) in [(-1, 4, 4), (2, 1, 4), (0, 4, -1), (0, 5, 4)] {
            let mut out = output();
            assert_eq!(
                decode(
                    handle(&input),
                    start,
                    end,
                    full,
                    Some(to_utf8),
                    Some(is_error),
                    &mut out
                ),
                ERR_INVALID_ARGUMENT
            );
            assert!(out.ptr.is_null() && out.owner.is_null() && out.len == 0);
        }
        let mut out = output();
        assert_eq!(
            decode(
                std::ptr::null_mut(),
                0,
                4,
                4,
                Some(to_utf8),
                Some(is_error),
                &mut out
            ),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(
            decode(
                handle(&input),
                0,
                4,
                4,
                Some(to_utf8),
                Some(is_error),
                std::ptr::null_mut()
            ),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(
            decode(handle(&input), 0, 4, 4, None, Some(is_error), &mut out),
            ERR_UNSUPPORTED
        );
        assert_eq!(
            decode(handle(&input), 0, 4, 4, Some(to_utf8), None, &mut out),
            ERR_UNSUPPORTED
        );
        assert_eq!(
            decode(
                handle(&input),
                0,
                4,
                5,
                Some(to_utf8),
                Some(is_error),
                &mut out
            ),
            ERR_UNSUPPORTED
        );
        let failed = Input {
            bytes: input.bytes,
            fail: true,
        };
        assert_eq!(
            decode(
                handle(&failed),
                0,
                4,
                4,
                Some(to_utf8),
                Some(is_error),
                &mut out
            ),
            ERR_UNSUPPORTED
        );
        assert!(out.ptr.is_null() && out.owner.is_null() && out.len == 0);
    }
}
