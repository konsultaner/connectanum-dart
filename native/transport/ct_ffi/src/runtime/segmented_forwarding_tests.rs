use super::*;
use ct_core::WampPayload;
use serde_json::json;
use std::collections::BTreeMap;

const SERIALIZERS: [RawSocketSerializer; 3] = [
    RawSocketSerializer::Json,
    RawSocketSerializer::MessagePack,
    RawSocketSerializer::Cbor,
];
const REQUEST: u64 = (1 << 53) - 1;
const REGISTRATION: u64 = (1 << 32) + 7;

fn guarded_value(serializer: RawSocketSerializer, value: &JsonValue) -> Bytes {
    let encoded = match serializer {
        RawSocketSerializer::Json => serde_json::to_vec(value).unwrap(),
        RawSocketSerializer::MessagePack => rmp_serde::to_vec(value).unwrap(),
        RawSocketSerializer::Cbor => serde_cbor::to_vec(value).unwrap(),
        _ => unreachable!(),
    };
    let end = 3 + encoded.len();
    let mut guarded = vec![0xff, 0xfe, 0xfd];
    guarded.extend(encoded);
    guarded.extend([0xfc, 0xfb]);
    Bytes::from(guarded).slice(3..end)
}

fn payload(serializer: RawSocketSerializer, shape: usize) -> WampPayload {
    WampPayload {
        args: (shape & 1 != 0).then(|| {
            guarded_value(
                serializer,
                &json!(["a,\"b\n", {"nested": [null, true, 17]}]),
            )
        }),
        kwargs: (shape & 2 != 0)
            .then(|| guarded_value(serializer, &json!({"key": [false, "\\", 42]}))),
    }
}

fn stored(serializer: RawSocketSerializer, message: WampMessage) -> StoredMessage {
    let (args, kwargs) = extract_payload_slices(&message);
    StoredMessage {
        serializer,
        code: message.code(),
        raw: StoredRawFrame::from_bytes(Bytes::new()),
        message,
        details: None,
        args,
        kwargs,
    }
}

fn successful_segments(result: Result<Vec<Bytes>, c_int>) -> Vec<Bytes> {
    assert!(result.is_ok(), "valid forwarding must succeed: {result:?}");
    result.unwrap()
}

fn assert_frame(
    serializer: RawSocketSerializer,
    segments: Vec<Bytes>,
    payload: WampPayload,
    mut expected: JsonValue,
) {
    for bytes in [&payload.args, &payload.kwargs].into_iter().flatten() {
        assert_eq!(
            segments
                .iter()
                .filter(|segment| segment.as_ptr() == bytes.as_ptr() && segment.len() == bytes.len())
                .count(),
            1,
            "{serializer:?}: forwarding must retain each exact allocation slice once"
        );
    }
    let fields = expected.as_array_mut().unwrap();
    if payload.args.is_some() || payload.kwargs.is_some() {
        fields.push(if payload.args.is_some() {
            json!(["a,\"b\n", {"nested": [null, true, 17]}])
        } else {
            json!([])
        });
    }
    if payload.kwargs.is_some() {
        fields.push(json!({"key": [false, "\\", 42]}));
    }
    // Only the outbound segments retain the source allocations at decode time.
    drop(payload);
    let frame: Vec<u8> = segments
        .iter()
        .flat_map(|part| part.iter().copied())
        .collect();
    let decoded: Result<JsonValue, String> = match serializer {
        RawSocketSerializer::Json => serde_json::from_slice(&frame).map_err(|e| e.to_string()),
        RawSocketSerializer::MessagePack => {
            rmp_serde::from_slice(&frame).map_err(|e| e.to_string())
        }
        RawSocketSerializer::Cbor => serde_cbor::from_slice(&frame).map_err(|e| e.to_string()),
        _ => unreachable!(),
    };
    assert!(
        decoded.is_ok(),
        "{serializer:?}: forwarding must produce a valid frame: {decoded:?}"
    );
    assert_eq!(decoded.unwrap(), expected, "{serializer:?}");
}

fn ppt_options() -> BTreeMap<SerdeValue, SerdeValue> {
    [
        ("ppt_scheme", "x_test"),
        ("ppt_serializer", "cbor"),
        ("ppt_cipher", "aes-256-gcm"),
        ("ppt_keyid", "key-7"),
        ("publisher", "untrusted"),
        ("topic", "untrusted.topic"),
        ("caller_authid", "untrusted"),
        ("vendor_private", "not-for-peer"),
    ]
    .into_iter()
    .map(|(key, value)| {
        (
            SerdeValue::String(key.into()),
            SerdeValue::String(value.into()),
        )
    })
    .collect()
}

fn ppt_details() -> JsonValue {
    json!({"ppt_scheme": "x_test", "ppt_serializer": "cbor",
        "ppt_cipher": "aes-256-gcm", "ppt_keyid": "key-7"})
}

#[test]
fn events_preserve_all_payload_shapes_and_only_authorized_disclosure() {
    for serializer in SERIALIZERS {
        for shape in 0..4 {
            for disclosure in 0..4 {
                let payload = payload(serializer, shape);
                let message = stored(
                    serializer,
                    WampMessage::Publish {
                        request_id: 1,
                        options: ppt_options(),
                        topic: "private.topic".into(),
                        payload: payload.clone(),
                    },
                );
                let publisher = (disclosure & 1 != 0).then_some(87);
                let topic = (disclosure & 2 != 0).then_some("matched.topic");
                let segments = successful_segments(encode_event_segments(
                    &message,
                    REGISTRATION,
                    REQUEST,
                    publisher,
                    topic,
                ));
                drop(message);
                let mut details = ppt_details();
                if let Some(publisher) = publisher {
                    details["publisher"] = json!(publisher);
                }
                if let Some(topic) = topic {
                    details["topic"] = json!(topic);
                }
                assert_frame(
                    serializer,
                    segments,
                    payload,
                    json!([36, REGISTRATION, REQUEST, details]),
                );
            }
        }
    }
}

#[test]
fn invocations_preserve_payload_and_independent_progress_flags() {
    for serializer in SERIALIZERS {
        for shape in 0..4 {
            for receive in [None, Some(false), Some(true)] {
                for progress in [None, Some(false), Some(true)] {
                    for disclose in [false, true] {
                        let payload = payload(serializer, shape);
                        let message = stored(
                            serializer,
                            WampMessage::Call {
                                request_id: 1,
                                options: ppt_options(),
                                procedure: "private.procedure".into(),
                                payload: payload.clone(),
                            },
                        );
                        let segments = successful_segments(encode_invocation_segments(
                            &message,
                            REQUEST,
                            REGISTRATION,
                            disclose.then_some(87),
                            disclose.then_some("alice"),
                            disclose.then_some("member"),
                            disclose.then_some("matched.procedure"),
                            receive,
                            progress,
                        ));
                        drop(message);
                        let mut details = ppt_details();
                        if disclose {
                            details["caller"] = json!(87);
                            details["caller_authid"] = json!("alice");
                            details["caller_authrole"] = json!("member");
                            details["procedure"] = json!("matched.procedure");
                        }
                        if let Some(receive) = receive {
                            details["receive_progress"] = json!(receive);
                        }
                        if let Some(progress) = progress {
                            details["progress"] = json!(progress);
                        }
                        assert_frame(
                            serializer,
                            segments,
                            payload,
                            json!([68, REQUEST, REGISTRATION, details]),
                        );
                    }
                }
            }
        }
    }
}

#[test]
fn replies_preserve_payload_shapes_and_replace_only_routing_fields() {
    for serializer in SERIALIZERS {
        for shape in 0..4 {
            for progress in [false, true] {
                let payload = payload(serializer, shape);
                let message = stored(
                    serializer,
                    WampMessage::Yield {
                        request_id: 1,
                        options: BTreeMap::from([(
                            SerdeValue::String("vendor".into()),
                            SerdeValue::U64(7),
                        )]),
                        payload: payload.clone(),
                    },
                );
                let segments =
                    successful_segments(encode_result_segments(&message, REQUEST, progress));
                drop(message);
                let mut details = json!({"vendor": 7});
                if progress {
                    details["progress"] = json!(true);
                }
                assert_frame(serializer, segments, payload, json!([50, REQUEST, details]));
            }
            let payload = payload(serializer, shape);
            let message = stored(
                serializer,
                WampMessage::Call {
                    request_id: 1,
                    options: ppt_options(),
                    procedure: "private.procedure".into(),
                    payload: payload.clone(),
                },
            );
            let segments = successful_segments(encode_result_segments_from_call(&message, REQUEST));
            drop(message);
            assert_frame(serializer, segments, payload, json!([50, REQUEST, {}]));

            let payload = self::payload(serializer, shape);
            let message = stored(
                serializer,
                WampMessage::Error {
                    request_type: 68,
                    request_id: 1,
                    details: BTreeMap::from([(
                        SerdeValue::String("retry".into()),
                        SerdeValue::Bool(false),
                    )]),
                    error: "wamp.error.not_authorized".into(),
                    payload: payload.clone(),
                },
            );
            let segments = successful_segments(encode_error_segments(&message, 48, REQUEST));
            drop(message);
            assert_frame(
                serializer,
                segments,
                payload,
                json!([8, 48, REQUEST, {"retry": false}, "wamp.error.not_authorized"]),
            );
        }
    }
}

#[test]
fn ppt_metadata_rejects_each_non_string_field_for_every_serializer() {
    for serializer in SERIALIZERS {
        for key in ["ppt_scheme", "ppt_serializer", "ppt_cipher", "ppt_keyid"] {
            for value in [
                SerdeValue::Bool(false),
                SerdeValue::U64(7),
                SerdeValue::Unit,
                SerdeValue::Bytes(vec![1]),
                SerdeValue::Seq(vec![]),
                SerdeValue::Map(BTreeMap::new()),
            ] {
                let mut options = ppt_options();
                options.insert(SerdeValue::String(key.into()), value.clone());
                let publish = stored(
                    serializer,
                    WampMessage::Publish {
                        request_id: 1,
                        options: options.clone(),
                        topic: "topic".into(),
                        payload: payload(serializer, 3),
                    },
                );
                assert_eq!(
                    encode_event_segments(&publish, 7, 8, None, None),
                    Err(ERR_INVALID_ARGUMENT),
                    "{serializer:?}: {key}={value:?}"
                );
                let call = stored(
                    serializer,
                    WampMessage::Call {
                        request_id: 1,
                        options,
                        procedure: "procedure".into(),
                        payload: payload(serializer, 3),
                    },
                );
                assert_eq!(
                    encode_invocation_segments(&call, 7, 8, None, None, None, None, None, None),
                    Err(ERR_INVALID_ARGUMENT),
                    "{serializer:?}: {key}={value:?}"
                );
            }
        }
    }
}

#[test]
fn forwarding_rejects_wrong_message_kinds_without_consuming_payloads() {
    for serializer in SERIALIZERS {
        let original = payload(serializer, 3);
        let message = stored(
            serializer,
            WampMessage::Error {
                request_type: 68,
                request_id: 1,
                details: BTreeMap::new(),
                error: "wamp.error.test".into(),
                payload: original.clone(),
            },
        );
        assert_eq!(
            encode_event_segments(&message, 7, 8, None, None),
            Err(ERR_INVALID_ARGUMENT)
        );
        assert_eq!(
            encode_invocation_segments(&message, 7, 8, None, None, None, None, None, None),
            Err(ERR_INVALID_ARGUMENT)
        );
        assert_eq!(
            encode_result_segments(&message, 7, false),
            Err(ERR_INVALID_ARGUMENT)
        );
        assert_eq!(
            encode_result_segments_from_call(&message, 7),
            Err(ERR_INVALID_ARGUMENT)
        );
        let segments = successful_segments(encode_error_segments(&message, 48, 7));
        drop(message);
        assert_frame(
            serializer,
            segments,
            original,
            json!([8, 48, 7, {}, "wamp.error.test"]),
        );
    }
}

#[test]
fn unsupported_forwarding_serializers_return_errors_for_every_message_kind() {
    for serializer in [
        RawSocketSerializer::Ubjson,
        RawSocketSerializer::Flatbuffers,
    ] {
        let empty = WampPayload {
            args: None,
            kwargs: None,
        };
        let publish = stored(
            serializer,
            WampMessage::Publish {
                request_id: 1,
                options: BTreeMap::new(),
                topic: "topic".into(),
                payload: empty.clone(),
            },
        );
        assert_eq!(
            encode_event_segments(&publish, 7, 8, None, None),
            Err(ERR_UNSUPPORTED)
        );
        assert_eq!(
            encode_error_segments(&publish, 48, 7),
            Err(ERR_INVALID_ARGUMENT)
        );
        let call = stored(
            serializer,
            WampMessage::Call {
                request_id: 1,
                options: BTreeMap::new(),
                procedure: "procedure".into(),
                payload: empty.clone(),
            },
        );
        assert_eq!(
            encode_invocation_segments(&call, 7, 8, None, None, None, None, None, None),
            Err(ERR_UNSUPPORTED)
        );
        assert_eq!(
            encode_result_segments_from_call(&call, 7),
            Err(ERR_UNSUPPORTED)
        );
        let result = stored(
            serializer,
            WampMessage::Yield {
                request_id: 1,
                options: BTreeMap::new(),
                payload: empty.clone(),
            },
        );
        assert_eq!(
            encode_result_segments(&result, 7, false),
            Err(ERR_UNSUPPORTED)
        );
        let error = stored(
            serializer,
            WampMessage::Error {
                request_type: 68,
                request_id: 1,
                details: BTreeMap::new(),
                error: "wamp.error.test".into(),
                payload: empty,
            },
        );
        assert_eq!(encode_error_segments(&error, 48, 7), Err(ERR_UNSUPPORTED));
    }
}

struct Export(CtExternalByteBuffer);

impl Drop for Export {
    fn drop(&mut self) {
        ct_external_byte_buffer_free(self.0.owner);
    }
}

#[test]
fn external_buffer_exports_exact_subranges_without_copying_or_losing_kind() {
    for (bytes, range) in [
        (vec![], 0..0),
        (vec![10, 20, 30], 0..0),
        (vec![10, 20, 30], 3..3),
        (vec![10, 20, 30], 0..3),
        (vec![10, 20, 30], 1..3),
        (vec![10, 20, 30], 1..2),
    ] {
        for kind in [
            CT_E2EE_DECRYPTED_PAYLOAD_DIRECT_BINARY,
            CT_E2EE_DECRYPTED_PAYLOAD_PPT,
        ] {
            let mut allocation = bytes.clone();
            let expected_ptr = unsafe { allocation.as_mut_ptr().add(range.start) };
            let mut output = Export(CtExternalByteBuffer {
                ptr: ptr::null_mut(),
                len: 0,
                owner: ptr::null_mut(),
            });
            let mut output_kind = -1;
            assert_eq!(
                write_external_byte_buffer_range(
                    allocation,
                    range.clone(),
                    kind,
                    &mut output.0,
                    &mut output_kind
                ),
                SUCCESS
            );
            assert_eq!(output.0.ptr, expected_ptr);
            assert_eq!(output.0.len, range.len());
            assert_eq!(output_kind, kind);
            assert!(!output.0.owner.is_null());
            assert_eq!(
                unsafe { slice::from_raw_parts(output.0.ptr, output.0.len) },
                &bytes[range.clone()]
            );
        }
    }
}

#[test]
fn invalid_external_ranges_and_null_outputs_leave_outputs_untouched() {
    for (range, null_buffer, null_kind) in [
        (std::ops::Range { start: 2, end: 1 }, false, false),
        (0..4, false, false),
        (4..4, false, false),
        (0..3, true, false),
        (0..3, false, true),
        (0..3, true, true),
    ] {
        let mut sentinel = [77u8];
        let mut output = CtExternalByteBuffer {
            ptr: sentinel.as_mut_ptr(),
            len: 19,
            owner: ptr::null_mut(),
        };
        let mut kind = -7;
        let result = write_external_byte_buffer_range(
            vec![1, 2, 3],
            range,
            2,
            if null_buffer {
                ptr::null_mut()
            } else {
                &mut output
            },
            if null_kind {
                ptr::null_mut()
            } else {
                &mut kind
            },
        );
        assert_eq!(result, ERR_INVALID_ARGUMENT);
        assert_eq!(output.ptr, sentinel.as_mut_ptr());
        assert_eq!(output.len, 19);
        assert!(output.owner.is_null());
        assert_eq!(kind, -7);
        assert_eq!(sentinel, [77]);
    }
}
