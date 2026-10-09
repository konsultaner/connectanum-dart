use super::*;
use ct_core::parse_message;
use serde_json::json;
use std::collections::BTreeMap;

fn flat_message(value: JsonValue) -> Bytes {
    let parsed = parse_message(
        RawSocketSerializer::Cbor,
        Bytes::from(serde_cbor::to_vec(&value).unwrap()),
    )
    .unwrap();
    ct_core::encode_flatbuffers_message(&parsed.message).unwrap()
}

#[test]
fn flatbuffers_ffi_preserves_borrowed_metadata_after_frame_owner_release() {
    let expected =
        json!({"timeout": 42, "receive_progress": false, "x_vendor": {"items": [1, "two"]}});
    let frame = flat_message(json!([48, 19, expected, "com.example.proc", [7], {"answer": 9}]));
    let start = frame.as_ptr() as usize;
    let end = start + frame.len();
    let stored = parsed_message_value(
        parse_message(RawSocketSerializer::Flatbuffers, frame.clone()).unwrap(),
    );
    let info = build_message_info(&stored, true);
    assert_eq!(info.message_code, 48);
    let metadata = stored
        .details
        .as_ref()
        .expect("FlatBuffers dictionary must be exported")
        .clone();
    assert!(metadata.as_ptr() as usize >= start);
    assert!(metadata.as_ptr() as usize + metadata.len() <= end);
    assert_eq!(info.details_ptr, metadata.as_ptr());
    assert_eq!(info.details_len, metadata.len());
    assert_eq!(
        serde_cbor::from_slice::<JsonValue>(stored.args.as_ref().unwrap()).unwrap(),
        json!([7])
    );
    assert_eq!(
        serde_cbor::from_slice::<JsonValue>(stored.kwargs.as_ref().unwrap()).unwrap(),
        json!({"answer": 9})
    );
    drop(frame);
    drop(stored);
    assert_eq!(
        serde_cbor::from_slice::<JsonValue>(&metadata).unwrap(),
        expected
    );
}

#[cfg(feature = "ffi-test")]
#[test]
fn flatbuffers_metadata_is_delivered_through_narrow_and_wide_c_abi() {
    let _guard = crate::tests::test_guard();
    assert_eq!(ct_start_runtime(), SUCCESS);
    struct StartedRuntime;
    impl Drop for StartedRuntime {
        fn drop(&mut self) {
            let _ = ct_shutdown();
        }
    }
    let _runtime = StartedRuntime;
    let expected = json!({"timeout": 42, "x_vendor": [1, "two"]});
    let frame = flat_message(json!([48, 19, expected, "com.example.proc"]));
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
        assert_eq!(info.message_code, 48);
        assert!(!info.details_ptr.is_null());
        let bytes = unsafe { std::slice::from_raw_parts(info.details_ptr, info.details_len) };
        assert_eq!(
            serde_cbor::from_slice::<JsonValue>(bytes).unwrap(),
            expected
        );
        let frame_start = info.frame_ptr as usize;
        assert!(info.details_ptr as usize >= frame_start);
        assert!(info.details_ptr as usize + info.details_len <= frame_start + info.frame_len);
        ct_message_release_wide(handle);
    }
}

#[test]
fn flatbuffers_ffi_messages_without_dictionary_export_no_dictionary() {
    for value in [
        json!([17, 19, 29]),
        json!([33, 19, 29]),
        json!([65, 19, 29]),
        json!([34, 19, 29]),
        json!([66, 19, 29]),
    ] {
        let stored = parsed_message_value(
            parse_message(RawSocketSerializer::Flatbuffers, flat_message(value)).unwrap(),
        );
        assert!(stored.details.is_none(), "message {}", stored.code);
        let info = build_message_info(&stored, true);
        assert!(info.details_ptr.is_null());
        assert_eq!(info.details_len, 0);
    }
}

#[test]
fn flatbuffers_ffi_heartbeat_keeps_nullable_controls_and_metadata() {
    for presence in 0..8 {
        let frame = ct_core::encode_flatbuffers_message(&WampMessage::Heartbeat {
            details: BTreeMap::from([(
                SerdeValue::String("x_vendor".into()),
                SerdeValue::String("retained".into()),
            )]),
            ping: (presence & 1 != 0).then_some(0),
            incoming: (presence & 2 != 0).then_some(0),
            outgoing: (presence & 4 != 0).then_some(5),
        })
        .unwrap();
        let stored =
            parsed_message_value(parse_message(RawSocketSerializer::Flatbuffers, frame).unwrap());
        let metadata = stored
            .details
            .as_ref()
            .expect("heartbeat metadata must be exported");
        let mut expected = json!({"details": {"x_vendor": "retained"}});
        for (bit, name, value) in [(1, "ping", 0), (2, "incoming", 0), (4, "outgoing", 5)] {
            if presence & bit != 0 {
                expected[name] = json!(value);
            }
        }
        assert_eq!(
            serde_cbor::from_slice::<JsonValue>(metadata).unwrap(),
            expected
        );
    }
}
