use super::*;
use ct_core::parse_message;
use serde_json::json;

fn opaque_message(value: JsonValue, opaque: Bytes) -> Bytes {
    let mut message = parse_message(
        RawSocketSerializer::Cbor,
        Bytes::from(serde_cbor::to_vec(&value).unwrap()),
    )
    .unwrap()
    .message;
    match &mut message {
        WampMessage::Publish { payload, .. }
        | WampMessage::Event { payload, .. }
        | WampMessage::Call { payload, .. }
        | WampMessage::Result { payload, .. }
        | WampMessage::Invocation { payload, .. }
        | WampMessage::Yield { payload, .. }
        | WampMessage::Error { payload, .. } => {
            assert!(payload.args.is_none() && payload.kwargs.is_none());
            payload.transparent = Some(opaque);
        }
        _ => panic!("Test case requires an application payload"),
    }
    ct_core::encode_flatbuffers_message(&message).unwrap()
}

fn cases() -> Vec<JsonValue> {
    vec![
        json!([16, 1, {}, "com.topic"]),
        json!([36, 1, 2, {}]),
        json!([48, 1, {}, "com.proc"]),
        json!([50, 1, {}]),
        json!([68, 1, 2, {}]),
        json!([70, 1, {}]),
        json!([8, 48, 1, {}, "wamp.error.runtime_error"]),
    ]
}

#[test]
fn flatbuffers_opaque_info_preserves_presence_and_original_allocation() {
    for case in cases() {
        for expected in [Bytes::new(), Bytes::from_static(&[0, 255, 1, 2])] {
            let frame = opaque_message(case.clone(), expected.clone());
            let stored = parsed_message_value(
                parse_message(RawSocketSerializer::Flatbuffers, frame.clone()).unwrap(),
            );
            let opaque = extract_transparent_payload(&stored.message)
                .unwrap()
                .clone();
            let info = build_message_info(&stored, false);
            assert_eq!(
                info.flags & CT_MESSAGE_FLAG_TRANSPARENT_BINARY_PAYLOAD,
                CT_MESSAGE_FLAG_TRANSPARENT_BINARY_PAYLOAD
            );
            assert_eq!(info.binary_arg_ptr, opaque.as_ptr());
            assert_eq!(info.binary_arg_len, expected.len());
            assert!(info.frame_ptr.is_null());
            assert!(stored.args.is_none() && stored.kwargs.is_none());
            if !expected.is_empty() {
                assert!(opaque.as_ptr() as usize >= frame.as_ptr() as usize);
                assert!(
                    opaque.as_ptr() as usize + opaque.len()
                        <= frame.as_ptr() as usize + frame.len()
                );
            }
            drop(frame);
            drop(stored);
            assert_eq!(opaque, expected);
        }
    }
}

#[cfg(feature = "ffi-test")]
#[test]
fn flatbuffers_opaque_export_survives_narrow_and_wide_handle_release() {
    let _guard = crate::tests::test_guard();
    for expected in [
        None,
        Some(Bytes::new()),
        Some(Bytes::from_static(&[0, 255, 1, 2])),
    ] {
        let case = json!([48, 1, {}, "com.proc"]);
        let frame = if let Some(opaque) = &expected {
            opaque_message(case, opaque.clone())
        } else {
            let message = parse_message(
                RawSocketSerializer::Cbor,
                Bytes::from(serde_cbor::to_vec(&case).unwrap()),
            )
            .unwrap()
            .message;
            ct_core::encode_flatbuffers_message(&message).unwrap()
        };
        for wide in [false, true] {
            let handle = if wide {
                ct_test_message_enqueue_wide(1, 5, frame.as_ptr(), frame.len() as i32)
            } else {
                i64::from(ct_test_message_enqueue(
                    1,
                    5,
                    frame.as_ptr(),
                    frame.len() as i32,
                ))
            };
            assert!(handle > 0);
            let mut info = CtMessageInfo::default();
            assert_eq!(ct_message_get_wide(handle, &mut info), SUCCESS);
            let mut view = CtMessageByteView {
                ptr: ptr::null(),
                len: 0,
                owner: ptr::null_mut(),
            };
            let status = if wide {
                ct_message_buffer_export_wide(handle, 5, &mut view)
            } else {
                ct_message_buffer_export(handle as c_int, 5, &mut view)
            };
            assert_eq!(status, SUCCESS);
            assert_eq!(
                info.flags & CT_MESSAGE_FLAG_TRANSPARENT_BINARY_PAYLOAD != 0,
                expected.is_some()
            );
            if expected.as_ref().is_none_or(Bytes::is_empty) {
                // The existing byte-view ABI returns no owner for absent/empty
                // spans. Presence is conveyed by the explicit message-info flag.
                assert_eq!(view.len, 0);
                assert!(view.ptr.is_null());
                assert!(view.owner.is_null());
                ct_message_release_wide(handle);
                continue;
            }
            let expected = expected.as_ref().unwrap();
            assert_eq!(view.ptr, info.binary_arg_ptr);
            assert_eq!(view.len, expected.len());
            assert!(!view.owner.is_null());
            ct_message_release_wide(handle);
            assert_eq!(
                unsafe { slice::from_raw_parts(view.ptr, view.len) },
                expected.as_ref()
            );
            ct_message_buffer_free(view.owner);
        }
    }
}
