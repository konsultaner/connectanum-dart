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
