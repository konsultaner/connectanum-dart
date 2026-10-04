use super::*;
use ct_core::{parse_message, WampPayload, WampRawFrame};

fn encrypted_message(ciphertext: &[u8], opaque: bool) -> StoredMessage {
    assert!(ciphertext.len() <= u8::MAX as usize);
    let payload = if opaque {
        WampPayload {
            transparent: Some(Bytes::copy_from_slice(ciphertext)),
            ..WampPayload::default()
        }
    } else {
        let mut args = vec![0x81, 0x58, ciphertext.len() as u8];
        args.extend_from_slice(ciphertext);
        WampPayload {
            args: Some(Bytes::from(args)),
            ..WampPayload::default()
        }
    };
    let wire = ct_core::encode_flatbuffers_message(&WampMessage::Invocation {
        request_id: 1,
        registration_id: 2,
        details: Default::default(),
        payload,
    })
    .unwrap();
    // Socket receives own just the frame bytes. The backwards encoder returns
    // a slice with unused builder storage before it; do not model that prefix
    // as part of a fresh receive allocation for the pointer-identity contract.
    let wire = Bytes::from(wire.to_vec());
    parsed_message_value(parse_message(RawSocketSerializer::Flatbuffers, wire).unwrap())
}

fn plaintext(direct: bool) -> Vec<u8> {
    let value = if direct {
        serde_cbor::Value::Bytes(vec![0, 255, 37])
    } else {
        serde_cbor::Value::Text("payload".into())
    };
    serde_cbor::to_vec(&serde_cbor::Value::Map(
        [
            (
                serde_cbor::Value::Text("args".into()),
                serde_cbor::Value::Array(vec![value]),
            ),
            (
                serde_cbor::Value::Text("kwargs".into()),
                serde_cbor::Value::Null,
            ),
        ]
        .into_iter()
        .collect(),
    ))
    .unwrap()
}

#[test]
fn flatbuffers_e2ee_unique_aes_decrypt_reuses_receive_allocation() {
    let key = [19; 32];
    for opaque in [true, false] {
        for direct in [true, false] {
            let plaintext = plaintext(direct);
            let ciphertext = encrypt_e2ee_aes256_gcm_payload(&key, &plaintext).unwrap();
            let message = encrypted_message(&ciphertext, opaque);
            let raw = message.raw.as_contiguous().unwrap();
            let allocation = raw.as_ptr() as usize..raw.as_ptr() as usize + raw.len();

            let result = decrypt_e2ee_message_payload_owned(message, &key, 2).unwrap();

            assert_eq!(
                result.kind,
                if direct {
                    CT_E2EE_DECRYPTED_PAYLOAD_DIRECT_BINARY
                } else {
                    CT_E2EE_DECRYPTED_PAYLOAD_PPT
                }
            );
            assert_eq!(
                &result.bytes[result.range.clone()],
                if direct {
                    &[0, 255, 37][..]
                } else {
                    &plaintext
                }
            );
            let start = result.bytes.as_ptr() as usize + result.range.start;
            assert!(allocation.contains(&start));
            assert!(start + result.range.len() <= allocation.end);
        }
    }
}

#[test]
fn flatbuffers_e2ee_shared_aes_decrypt_preserves_exported_ciphertext() {
    let key = [29; 32];
    let plaintext = plaintext(true);
    let ciphertext = encrypt_e2ee_aes256_gcm_payload(&key, &plaintext).unwrap();
    for opaque in [true, false] {
        let message = encrypted_message(&ciphertext, opaque);
        let retained = message.raw.as_contiguous().unwrap().clone();
        let original = retained.to_vec();
        let allocation = retained.as_ptr() as usize..retained.as_ptr() as usize + retained.len();

        let result = decrypt_e2ee_message_payload_owned(message, &key, 2).unwrap();

        assert_eq!(&result.bytes[result.range.clone()], &[0, 255, 37]);
        assert_eq!(result.kind, CT_E2EE_DECRYPTED_PAYLOAD_DIRECT_BINARY);
        assert!(!allocation.contains(&(result.bytes.as_ptr() as usize)));
        assert_eq!(retained.as_ref(), original);
        let retained = parsed_message_value(
            parse_message(RawSocketSerializer::Flatbuffers, retained).unwrap(),
        );
        let decrypted = decrypt_e2ee_message_payload_copied(&retained, &key, 2).unwrap();
        assert_eq!(&decrypted.bytes[decrypted.range], &[0, 255, 37]);
    }
}

#[test]
fn flatbuffers_e2ee_segmented_and_xsalsa_paths_preserve_plaintext_kind() {
    let key = [39; 32];
    for cipher in [1, 2] {
        for direct in [true, false] {
            let plaintext = plaintext(direct);
            let ciphertext = if cipher == 1 {
                encrypt_e2ee_payload(&key, &plaintext).unwrap()
            } else {
                encrypt_e2ee_aes256_gcm_payload(&key, &plaintext).unwrap()
            };
            let mut message = encrypted_message(&ciphertext, true);
            let raw = message.raw.as_contiguous().unwrap().clone();
            let split = raw.len() / 2;
            message.raw = StoredRawFrame::from_raw(WampRawFrame::Segmented {
                len: raw.len(),
                segments: vec![raw.slice(..split), raw.slice(split..)],
            });
            assert!(message.raw.is_segmented());
            assert!(!message.raw.has_contiguous_cache());

            let result = decrypt_e2ee_message_payload_owned(message, &key, cipher).unwrap();

            assert_eq!(
                result.kind,
                if direct {
                    CT_E2EE_DECRYPTED_PAYLOAD_DIRECT_BINARY
                } else {
                    CT_E2EE_DECRYPTED_PAYLOAD_PPT
                }
            );
            assert_eq!(
                &result.bytes[result.range],
                if direct {
                    &[0, 255, 37][..]
                } else {
                    &plaintext
                }
            );
        }
    }
}

#[test]
fn flatbuffers_e2ee_rejects_mixed_or_truncated_ciphertext() {
    let key = [49; 32];
    let ciphertext = encrypt_e2ee_aes256_gcm_payload(&key, &plaintext(true)).unwrap();
    let mut mixed = encrypted_message(&ciphertext, true);
    mixed.args = Some(Bytes::from_static(&[0x80]));
    assert!(matches!(
        decrypt_e2ee_message_payload_owned(mixed, &key, 2),
        Err(ERR_UNSUPPORTED)
    ));
    let mut kwargs = encrypted_message(&ciphertext, true);
    kwargs.kwargs = Some(Bytes::from_static(&[0xa0]));
    assert!(matches!(
        decrypt_e2ee_message_payload_owned(kwargs, &key, 2),
        Err(ERR_UNSUPPORTED)
    ));
    let mut wrong_serializer = encrypted_message(&ciphertext, true);
    wrong_serializer.serializer = RawSocketSerializer::Cbor;
    assert!(matches!(
        decrypt_e2ee_message_payload_owned(wrong_serializer, &key, 2),
        Err(ERR_UNSUPPORTED)
    ));
    assert!(matches!(
        decrypt_e2ee_message_payload_owned(encrypted_message(&[1, 2], true), &key, 2),
        Err(ERR_INVALID_ARGUMENT)
    ));
}

#[test]
fn flatbuffers_e2ee_separate_ciphertext_allocation_uses_copy_fallback() {
    let key = [69; 32];
    let ciphertext = encrypt_e2ee_aes256_gcm_payload(&key, &plaintext(true)).unwrap();
    for opaque in [true, false] {
        let mut message = encrypted_message(&ciphertext, opaque);
        let unrelated_raw = Bytes::from(vec![0xcc; message.raw.bytes().len()]);
        let allocation =
            unrelated_raw.as_ptr() as usize..unrelated_raw.as_ptr() as usize + unrelated_raw.len();
        message.raw = StoredRawFrame::from_bytes(unrelated_raw);

        let result = decrypt_e2ee_message_payload_owned(message, &key, 2).unwrap();

        assert_eq!(&result.bytes[result.range], &[0, 255, 37]);
        assert_eq!(result.kind, CT_E2EE_DECRYPTED_PAYLOAD_DIRECT_BINARY);
        assert!(!allocation.contains(&(result.bytes.as_ptr() as usize)));
    }
}

#[test]
fn flatbuffers_e2ee_borrowed_api_decrypts_both_ciphers_without_consuming_handle() {
    let _guard = crate::tests::test_guard();
    let key = [59; 32];
    let keyring = ct_e2ee_keyring_new();
    assert_eq!(
        ct_e2ee_keyring_add_key(keyring, b"key".as_ptr().cast(), 3, key.as_ptr(), 32, 1),
        SUCCESS
    );
    let session = ct_e2ee_session_new(keyring, ptr::null(), 0);
    for opaque in [true, false] {
        for cipher in [1, 2] {
            let plaintext = plaintext(true);
            let ciphertext = if cipher == 1 {
                encrypt_e2ee_payload(&key, &plaintext).unwrap()
            } else {
                encrypt_e2ee_aes256_gcm_payload(&key, &plaintext).unwrap()
            };
            let handle =
                super::super::message_handles::insert(encrypted_message(&ciphertext, opaque))
                    .unwrap();
            let mut output = CtExternalByteBuffer {
                ptr: ptr::null_mut(),
                len: 0,
                owner: ptr::null_mut(),
            };
            assert_eq!(
                ct_e2ee_session_decrypt_message_single_binary_argument_wide(
                    session,
                    b"key".as_ptr().cast(),
                    3,
                    handle as i64,
                    cipher,
                    &mut output,
                ),
                SUCCESS
            );
            assert_eq!(
                unsafe { slice::from_raw_parts(output.ptr, output.len) },
                &[0, 255, 37]
            );
            assert!(super::super::message_handles::with_message(handle, |_| ()).is_some());
            ct_external_byte_buffer_free(output.owner);
            ct_message_release_wide(handle as i64);
        }
    }
    assert_eq!(ct_e2ee_session_release(session), SUCCESS);
    assert_eq!(ct_e2ee_keyring_release(keyring), SUCCESS);
}
