use super::*;
use ct_core::WampPayload;
use serde_json::json;
use std::collections::BTreeMap;

const SERIALIZERS: [RawSocketSerializer; 4] = [
    RawSocketSerializer::Json,
    RawSocketSerializer::MessagePack,
    RawSocketSerializer::Cbor,
    RawSocketSerializer::Flatbuffers,
];
const REQUEST: u64 = (1 << 53) - 1;
const REGISTRATION: u64 = (1 << 32) + 7;

#[test]
fn cbor_flatbuffers_mixed_envelopes_retain_all_argument_shapes() {
    for (source, target) in [
        (RawSocketSerializer::Cbor, RawSocketSerializer::Flatbuffers),
        (RawSocketSerializer::Flatbuffers, RawSocketSerializer::Cbor),
    ] {
        for shape in 0..4 {
            let original = payload(source, shape);
            let publish = stored(
                source,
                WampMessage::Publish {
                    request_id: 1,
                    options: BTreeMap::new(),
                    topic: "source.topic".into(),
                    payload: original.clone(),
                },
            );
            assert_eq!(reusable_forwarding_serializer(&publish, target), Ok(target));
            let segments = successful_segments(encode_event_segments_for_serializer(
                &publish,
                target,
                REGISTRATION,
                REQUEST,
                Some(87),
                Some("matched.topic"),
            ));
            drop(publish);
            assert_frame(
                target,
                segments,
                original.clone(),
                json!([36, REGISTRATION, REQUEST, {"publisher":87,"topic":"matched.topic"}]),
            );

            let call = stored(
                source,
                WampMessage::Call {
                    request_id: 1,
                    options: BTreeMap::new(),
                    procedure: "source.proc".into(),
                    payload: original.clone(),
                },
            );
            let invocation = successful_segments(encode_invocation_segments_for_serializer(
                &call,
                target,
                REQUEST,
                REGISTRATION,
                Some(87),
                Some("alice"),
                Some("user"),
                Some("matched.proc"),
                Some(true),
                Some(false),
            ));
            let result = successful_segments(encode_result_segments_from_call_for_serializer(
                &call, target, REQUEST,
            ));
            drop(call);
            assert_frame(
                target,
                invocation,
                original.clone(),
                json!([68,REQUEST,REGISTRATION,{
                    "caller":87,"caller_authid":"alice","caller_authrole":"user",
                    "procedure":"matched.proc","receive_progress":true,"progress":false
                }]),
            );
            assert_frame(target, result, original.clone(), json!([50, REQUEST, {}]));

            let yielded = stored(
                source,
                WampMessage::Yield {
                    request_id: 1,
                    options: BTreeMap::new(),
                    payload: original.clone(),
                },
            );
            let result = successful_segments(encode_result_segments_for_serializer(
                &yielded, target, REQUEST, true,
            ));
            drop(yielded);
            assert_frame(
                target,
                result,
                original.clone(),
                json!([50,REQUEST,{"progress":true}]),
            );

            let error = stored(
                source,
                WampMessage::Error {
                    request_type: 68,
                    request_id: 1,
                    details: BTreeMap::new(),
                    error: "com.failure".into(),
                    payload: original.clone(),
                },
            );
            let result = successful_segments(encode_error_segments_for_serializer(
                &error, target, 48, REQUEST,
            ));
            drop(error);
            assert_frame(
                target,
                result,
                original,
                json!([8, 48, REQUEST, {}, "com.failure"]),
            );
        }
    }
}

#[test]
fn mixed_forwarding_query_rejects_incompatible_codecs_and_ppt_without_consuming() {
    for source in SERIALIZERS {
        let handle = crate::runtime::message_handles::insert(stored(
            source,
            WampMessage::Call {
                request_id: 1,
                options: BTreeMap::new(),
                procedure: "proc".into(),
                payload: payload(source, 3),
            },
        ))
        .unwrap();
        for target in SERIALIZERS {
            let expected = source == target
                || matches!(
                    (source, target),
                    (RawSocketSerializer::Cbor, RawSocketSerializer::Flatbuffers)
                        | (RawSocketSerializer::Flatbuffers, RawSocketSerializer::Cbor)
                );
            assert_eq!(
                ct_message_can_forward_to_v1_wide(handle as i64, serializer_id(target).into()),
                i32::from(expected)
            );
            assert!(crate::runtime::message_handles::retain_allocation(handle).is_some());
        }
        crate::runtime::message_handles::remove(handle).unwrap();
        assert_eq!(
            ct_message_can_forward_to_v1_wide(handle as i64, 3),
            ERR_INVALID_ARGUMENT
        );
    }
    for source in [RawSocketSerializer::Cbor, RawSocketSerializer::Flatbuffers] {
        let target = if source == RawSocketSerializer::Cbor {
            RawSocketSerializer::Flatbuffers
        } else {
            RawSocketSerializer::Cbor
        };
        for options in [
            ppt_options(),
            BTreeMap::from([(
                SerdeValue::String("ppt_scheme".into()),
                SerdeValue::String("wamp".into()),
            )]),
        ] {
            let message = stored(
                source,
                WampMessage::Call {
                    request_id: 1,
                    options,
                    procedure: "proc".into(),
                    payload: payload(source, 3),
                },
            );
            assert_eq!(
                reusable_forwarding_serializer(&message, target),
                Err(ERR_UNSUPPORTED)
            );
            assert_eq!(reusable_forwarding_serializer(&message, source), Ok(source));
        }
    }
}

#[test]
fn mixed_forwarding_validates_flatbuffers_container_limits_and_transparent_mode() {
    for original in [
        WampPayload {
            kwargs: Some(Bytes::from_static(&[0xa1, 0x01, 0x02])),
            ..Default::default()
        },
        WampPayload {
            kwargs: Some(Bytes::from_static(&[0xa2, 0x61, b'a', 1, 0x61, b'a', 2])),
            ..Default::default()
        },
        WampPayload {
            args: Some(Bytes::from_static(&[0x80, 0x00])),
            ..Default::default()
        },
        WampPayload {
            transparent: Some(Bytes::from_static(b"opaque")),
            ..Default::default()
        },
        WampPayload {
            args: Some(Bytes::from(vec![0x81; 65])),
            ..Default::default()
        },
    ] {
        let message = stored(
            RawSocketSerializer::Cbor,
            WampMessage::Call {
                request_id: 1,
                options: BTreeMap::new(),
                procedure: "proc".into(),
                payload: original,
            },
        );
        assert_eq!(
            reusable_forwarding_serializer(&message, RawSocketSerializer::Flatbuffers),
            Err(ERR_UNSUPPORTED)
        );
    }
    assert_eq!(
        ct_message_can_forward_to_v1_wide(0, 3),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_message_can_forward_to_v1_wide(1, 99),
        ERR_INVALID_ARGUMENT
    );
}

macro_rules! binary_ppt_direction_test {
    ($name:ident, $source:ident, $target:ident) => {
        #[test]
        fn $name() {
            let _guard = crate::tests::test_guard();
            assert_binary_ppt_forwarding(
                RawSocketSerializer::$source,
                RawSocketSerializer::$target,
            );
        }
    };
}

binary_ppt_direction_test!(binary_ppt_cbor_to_msgpack, Cbor, MessagePack);
binary_ppt_direction_test!(binary_ppt_cbor_to_flatbuffers, Cbor, Flatbuffers);
binary_ppt_direction_test!(binary_ppt_msgpack_to_cbor, MessagePack, Cbor);
binary_ppt_direction_test!(binary_ppt_msgpack_to_flatbuffers, MessagePack, Flatbuffers);
binary_ppt_direction_test!(binary_ppt_flatbuffers_to_cbor, Flatbuffers, Cbor);
binary_ppt_direction_test!(binary_ppt_flatbuffers_to_msgpack, Flatbuffers, MessagePack);
binary_ppt_direction_test!(binary_ppt_cbor_control, Cbor, Cbor);
binary_ppt_direction_test!(binary_ppt_msgpack_control, MessagePack, MessagePack);
binary_ppt_direction_test!(binary_ppt_flatbuffers_control, Flatbuffers, Flatbuffers);

const EMPTY_CBOR_MAPS: &[&[u8]] = &[
    &[0xa0],
    &[0xb8, 0],
    &[0xb9, 0, 0],
    &[0xba, 0, 0, 0, 0],
    &[0xbb, 0, 0, 0, 0, 0, 0, 0, 0],
    &[0xbf, 0xff],
];
const EMPTY_MSGPACK_MAPS: &[&[u8]] = &[&[0x80], &[0xde, 0, 0], &[0xdf, 0, 0, 0, 0]];

macro_rules! empty_ppt_kwargs_direction_test {
    ($name:ident, $source:ident, $target:ident, $maps:ident) => {
        #[test]
        fn $name() {
            let _guard = crate::tests::test_guard();
            for kwargs in $maps {
                assert_empty_ppt_keywords_parse(RawSocketSerializer::$source, kwargs);
                assert_binary_ppt_forwarding_with_kwargs(
                    RawSocketSerializer::$source,
                    RawSocketSerializer::$target,
                    Some(kwargs),
                );
            }
        }
    };
}

fn assert_empty_ppt_keywords_parse(source: RawSocketSerializer, kwargs: &[u8]) {
    let value = SerdeValue::Seq(vec![
        SerdeValue::U8(48),
        SerdeValue::U8(1),
        SerdeValue::Map(ppt_options()),
        SerdeValue::String("private".into()),
        SerdeValue::Seq(vec![SerdeValue::Bytes(b"opaque".to_vec())]),
        SerdeValue::Map(BTreeMap::new()),
    ]);
    let mut frame = if source == RawSocketSerializer::Cbor {
        serde_cbor::to_vec(&value).unwrap()
    } else {
        rmp_serde::to_vec(&value).unwrap()
    };
    assert_eq!(
        frame.pop(),
        Some(if source == RawSocketSerializer::Cbor {
            0xa0
        } else {
            0x80
        })
    );
    frame.extend_from_slice(kwargs);
    let parsed = ct_core::parse_message(source, Bytes::from(frame))
        .unwrap()
        .message;
    let WampMessage::Call { payload, .. } = parsed else {
        panic!("expected CALL")
    };
    assert_eq!(payload.kwargs.as_deref(), Some(kwargs));
    assert_eq!(
        single_binary_argument(source, payload.args.as_ref().unwrap()).unwrap(),
        b"opaque"
    );
}

empty_ppt_kwargs_direction_test!(
    empty_ppt_kwargs_cbor_to_msgpack,
    Cbor,
    MessagePack,
    EMPTY_CBOR_MAPS
);
empty_ppt_kwargs_direction_test!(
    empty_ppt_kwargs_cbor_to_flatbuffers,
    Cbor,
    Flatbuffers,
    EMPTY_CBOR_MAPS
);
empty_ppt_kwargs_direction_test!(
    empty_ppt_kwargs_msgpack_to_cbor,
    MessagePack,
    Cbor,
    EMPTY_MSGPACK_MAPS
);
empty_ppt_kwargs_direction_test!(
    empty_ppt_kwargs_msgpack_to_flatbuffers,
    MessagePack,
    Flatbuffers,
    EMPTY_MSGPACK_MAPS
);

#[test]
fn binary_ppt_rejected_shapes_keep_the_source_handle() {
    let _guard = crate::tests::test_guard();
    for source in [
        RawSocketSerializer::Cbor,
        RawSocketSerializer::MessagePack,
        RawSocketSerializer::Flatbuffers,
    ] {
        let valid = if source == RawSocketSerializer::Flatbuffers {
            WampPayload {
                transparent: Some(Bytes::from_static(b"opaque")),
                ..Default::default()
            }
        } else {
            let value = SerdeValue::Seq(vec![SerdeValue::Bytes(b"opaque".to_vec())]);
            let encoded = if source == RawSocketSerializer::Cbor {
                serde_cbor::to_vec(&value).unwrap()
            } else {
                rmp_serde::to_vec(&value).unwrap()
            };
            WampPayload {
                args: Some(Bytes::from(encoded)),
                ..Default::default()
            }
        };
        let valid_metadata = ppt_options();
        let mut cases = Vec::new();
        for key in ["ppt_scheme", "ppt_serializer", "ppt_cipher", "ppt_keyid"] {
            let mut metadata = valid_metadata.clone();
            metadata.insert(SerdeValue::String(key.into()), SerdeValue::Bool(true));
            cases.push((valid.clone(), metadata));
        }
        for scheme in [None, Some(SerdeValue::String(String::new()))] {
            let mut metadata = valid_metadata.clone();
            let key = SerdeValue::String("ppt_scheme".into());
            metadata.remove(&key);
            if let Some(scheme) = scheme {
                metadata.insert(key, scheme);
            }
            // Without a scheme, an encoded CBOR argument list is ordinary
            // payload and may still share the CBOR/FlatBuffers representation.
            // A raw FlatBuffers transparent body has no such interpretation.
            if source != RawSocketSerializer::Flatbuffers
                && !metadata.contains_key(&SerdeValue::String("ppt_scheme".into()))
            {
                continue;
            }
            cases.push((valid.clone(), metadata));
        }
        for empty in [true, false] {
            if empty && source != RawSocketSerializer::Flatbuffers {
                continue;
            }
            let value = if empty {
                SerdeValue::Map(BTreeMap::new())
            } else {
                SerdeValue::Map(BTreeMap::from([(
                    SerdeValue::String("x".into()),
                    SerdeValue::U8(1),
                )]))
            };
            let encoded = if source == RawSocketSerializer::MessagePack {
                rmp_serde::to_vec(&value).unwrap()
            } else {
                serde_cbor::to_vec(&value).unwrap()
            };
            let mut payload = valid.clone();
            payload.kwargs = Some(Bytes::from(encoded));
            cases.push((payload, valid_metadata.clone()));
        }
        let malformed_kwargs: &[&[u8]] = if source == RawSocketSerializer::MessagePack {
            &[
                &[],
                &[0x80, 0],
                &[0xde],
                &[0xde, 0],
                &[0xde, 0, 1],
                &[0xdf, 0, 0, 0],
                &[0xdf, 0, 0, 0, 0, 0],
                &[0x90],
                &[0xa0],
                &[0xc0],
            ]
        } else {
            &[
                &[],
                &[0xa0, 0],
                &[0xb8],
                &[0xb8, 1],
                &[0xb9, 0],
                &[0xba, 0, 0, 0],
                &[0xbb, 0, 0, 0, 0, 0, 0, 0],
                &[0xbf],
                &[0xbf, 0xff, 0],
                &[0x80],
                &[0xf6],
            ]
        };
        for kwargs in malformed_kwargs {
            let mut payload = valid.clone();
            payload.kwargs = Some(Bytes::copy_from_slice(kwargs));
            cases.push((payload, valid_metadata.clone()));
        }
        let malformed: &[&[u8]] = if source == RawSocketSerializer::MessagePack {
            &[
                &[0x90],
                &[0x91, 1],
                &[0x92, 0xc4, 0, 0xc4, 0],
                &[0x91, 0xc6, 0xff, 0xff, 0xff, 0xff],
                &[0x91, 0xc4, 0, 0],
            ]
        } else {
            &[
                &[0x80],
                &[0x81, 1],
                &[0x82, 0x40, 0x40],
                &[0x81, 0x5a, 0xff, 0xff, 0xff, 0xff],
                &[0x81, 0x40, 0],
                &[0x9f, 0x40, 0xff],
                &[0x81, 0x5f, 0xff],
            ]
        };
        for args in malformed {
            cases.push((
                WampPayload {
                    args: Some(Bytes::copy_from_slice(args)),
                    ..Default::default()
                },
                valid_metadata.clone(),
            ));
        }
        if source == RawSocketSerializer::Flatbuffers {
            let mut mixed = valid.clone();
            mixed.args = Some(Bytes::from_static(&[0x80]));
            cases.push((mixed, valid_metadata.clone()));
        }
        for (payload, metadata) in cases {
            let handle = crate::runtime::message_handles::insert(stored(
                source,
                WampMessage::Call {
                    request_id: 1,
                    procedure: "private".into(),
                    options: metadata,
                    payload,
                },
            ))
            .unwrap();
            for target in SERIALIZERS.into_iter().filter(|target| *target != source) {
                assert_eq!(
                    ct_message_can_forward_to_v1_wide(handle as i64, serializer_id(target).into()),
                    0,
                    "invalid PPT must use fallback: {source:?} -> {target:?}"
                );
                assert!(crate::runtime::message_handles::retain_allocation(handle).is_some());
            }
            crate::runtime::message_handles::remove(handle).unwrap();
        }
        let handle = crate::runtime::message_handles::insert(stored(
            source,
            WampMessage::Call {
                request_id: 1,
                procedure: "private".into(),
                options: valid_metadata,
                payload: valid,
            },
        ))
        .unwrap();
        assert_eq!(
            ct_message_can_forward_to_v1_wide(
                handle as i64,
                serializer_id(RawSocketSerializer::Json).into()
            ),
            0,
            "JSON still requires its binary conversion"
        );
        crate::runtime::message_handles::remove(handle).unwrap();
    }
}

fn assert_binary_ppt_forwarding(source: RawSocketSerializer, target: RawSocketSerializer) {
    assert_binary_ppt_forwarding_with_kwargs(source, target, None);
}

fn assert_binary_ppt_forwarding_with_kwargs(
    source: RawSocketSerializer,
    target: RawSocketSerializer,
    kwargs: Option<&[u8]>,
) {
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Producer {
        bytes: Vec<u8>,
        released: Arc<AtomicUsize>,
    }
    impl AsRef<[u8]> for Producer {
        fn as_ref(&self) -> &[u8] {
            &self.bytes
        }
    }
    impl Drop for Producer {
        fn drop(&mut self) {
            self.released.fetch_add(1, Ordering::SeqCst);
        }
    }
    for size in [0, 1, 23, 24, 255, 256, 65_535, 65_536, 128 * 1024] {
        let body: Vec<u8> = (0..size).map(|i| [0xff, 0, 0x80, 37][i % 4]).collect();
        for route in 0..5 {
            let released = Arc::new(AtomicUsize::new(0));
            let value = SerdeValue::Seq(vec![SerdeValue::Bytes(body.clone())]);
            let encoded = match source {
                RawSocketSerializer::Cbor => serde_cbor::to_vec(&value).unwrap(),
                RawSocketSerializer::MessagePack => rmp_serde::to_vec(&value).unwrap(),
                RawSocketSerializer::Flatbuffers => body.clone(),
                _ => unreachable!(),
            };
            let encoded = Bytes::from_owner(Producer {
                bytes: encoded,
                released: released.clone(),
            });
            let body_ptr = if source == RawSocketSerializer::Flatbuffers {
                encoded.as_ptr()
            } else {
                single_binary_argument(source, &encoded).unwrap().as_ptr()
            } as usize;
            let payload = if source == RawSocketSerializer::Flatbuffers {
                WampPayload {
                    transparent: Some(encoded),
                    ..Default::default()
                }
            } else {
                WampPayload {
                    args: Some(encoded),
                    kwargs: kwargs.map(Bytes::copy_from_slice),
                    ..Default::default()
                }
            };
            let ppt: BTreeMap<SerdeValue, SerdeValue> = ppt_options()
                .into_iter()
                .filter(|(key, _)| serde_key_str(key).is_some_and(|key| key.starts_with("ppt_")))
                .collect();
            let message = match route {
                0 => WampMessage::Publish {
                    request_id: 1,
                    options: ppt.clone(),
                    topic: "private".into(),
                    payload,
                },
                1 | 3 => WampMessage::Call {
                    request_id: 1,
                    options: ppt.clone(),
                    procedure: "private".into(),
                    payload,
                },
                2 => WampMessage::Yield {
                    request_id: 1,
                    options: ppt.clone(),
                    payload,
                },
                _ => WampMessage::Error {
                    request_type: 68,
                    request_id: 1,
                    details: ppt.clone(),
                    error: "wamp.error.test".into(),
                    payload,
                },
            };
            let handle = crate::runtime::message_handles::insert(stored(source, message)).unwrap();
            assert_eq!(
                ct_message_can_forward_to_v1_wide(handle as i64, serializer_id(target).into()),
                1,
                "binary PPT must be eligible: {source:?} -> {target:?}, route {route}"
            );
            let message = crate::runtime::message_handles::retain_allocation(handle).unwrap();
            let segments = successful_segments(match route {
                0 => encode_event_segments_for_serializer(
                    &message,
                    target,
                    REGISTRATION,
                    REQUEST,
                    None,
                    None,
                ),
                1 => encode_invocation_segments_for_serializer(
                    &message,
                    target,
                    REQUEST,
                    REGISTRATION,
                    None,
                    None,
                    None,
                    None,
                    Some(true),
                    Some(false),
                ),
                2 => encode_result_segments_for_serializer(&message, target, REQUEST, true),
                3 => encode_result_segments_from_call_for_serializer(&message, target, REQUEST),
                _ => encode_error_segments_for_serializer(&message, target, 48, REQUEST),
            });
            if !body.is_empty() {
                assert!(
                    segments.iter().any(|part| {
                        let start = part.as_ptr() as usize;
                        body_ptr >= start && body_ptr + body.len() <= start + part.len()
                    }),
                    "body allocation must be retained without copying"
                );
            }
            drop(message);
            crate::runtime::message_handles::remove(handle).unwrap();
            assert_eq!(
                released.load(Ordering::SeqCst),
                0,
                "source producer must survive delayed consumers, including empty bodies"
            );
            let wire = Bytes::from(
                segments
                    .iter()
                    .flat_map(|part| part.iter().copied())
                    .collect::<Vec<_>>(),
            );
            let parsed = ct_core::parse_message(target, wire).unwrap().message;
            let (details, decoded) = match &parsed {
                WampMessage::Event {
                    subscription_id,
                    publication_id,
                    details,
                    payload,
                } => {
                    assert_eq!((*subscription_id, *publication_id), (REGISTRATION, REQUEST));
                    (details, payload)
                }
                WampMessage::Invocation {
                    request_id,
                    registration_id,
                    details,
                    payload,
                } => {
                    assert_eq!((*request_id, *registration_id), (REQUEST, REGISTRATION));
                    (details, payload)
                }
                WampMessage::Result {
                    request_id,
                    details,
                    payload,
                } => {
                    assert_eq!(*request_id, REQUEST);
                    (details, payload)
                }
                WampMessage::Error {
                    request_type,
                    request_id,
                    error,
                    details,
                    payload,
                } => {
                    assert_eq!((*request_type, *request_id), (48, REQUEST));
                    assert_eq!(error, "wamp.error.test");
                    (details, payload)
                }
                _ => panic!("wrong forwarding message kind"),
            };
            let mut expected_details = ppt;
            if route == 1 {
                expected_details.insert(
                    SerdeValue::String("receive_progress".into()),
                    SerdeValue::Bool(true),
                );
                expected_details.insert(
                    SerdeValue::String("progress".into()),
                    SerdeValue::Bool(false),
                );
            } else if route == 2 {
                expected_details.insert(
                    SerdeValue::String("progress".into()),
                    SerdeValue::Bool(true),
                );
            }
            assert_eq!(
                *details, expected_details,
                "PPT metadata and routing flags must survive"
            );
            assert!(decoded.kwargs.is_none());
            if target == RawSocketSerializer::Flatbuffers {
                assert_eq!(decoded.transparent.as_deref(), Some(body.as_slice()));
                assert!(decoded.args.is_none());
            } else {
                assert_eq!(
                    single_binary_argument(target, decoded.args.as_ref().unwrap()).unwrap(),
                    body
                );
                assert!(decoded.transparent.is_none());
            }
            let delayed = segments.clone();
            drop(segments);
            assert_eq!(
                released.load(Ordering::SeqCst),
                0,
                "fan-out retains the producer for its final consumer"
            );
            drop(delayed);
            assert_eq!(
                released.load(Ordering::SeqCst),
                1,
                "producer is released exactly once"
            );
        }
    }
}

fn guarded_value(serializer: RawSocketSerializer, value: &JsonValue) -> Bytes {
    let encoded = match serializer {
        RawSocketSerializer::Json => serde_json::to_vec(value).unwrap(),
        RawSocketSerializer::MessagePack => rmp_serde::to_vec(value).unwrap(),
        RawSocketSerializer::Cbor | RawSocketSerializer::Flatbuffers => {
            serde_cbor::to_vec(value).unwrap()
        }
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
        transparent: None,
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
    let flatbuffers_expected = if serializer == RawSocketSerializer::Flatbuffers {
        let mut message = ct_core::parse_message(
            RawSocketSerializer::Cbor,
            Bytes::from(serde_cbor::to_vec(&expected).unwrap()),
        )
        .unwrap()
        .message;
        // FlatBuffers can distinguish an absent args vector from the empty
        // positional placeholder required by list-based WAMP encodings.
        match &mut message {
            WampMessage::Event {
                payload: expected, ..
            }
            | WampMessage::Invocation {
                payload: expected, ..
            }
            | WampMessage::Result {
                payload: expected, ..
            }
            | WampMessage::Error {
                payload: expected, ..
            } => {
                *expected = WampPayload {
                    args: payload
                        .args
                        .as_ref()
                        .map(|bytes| Bytes::copy_from_slice(bytes)),
                    kwargs: payload
                        .kwargs
                        .as_ref()
                        .map(|bytes| Bytes::copy_from_slice(bytes)),
                    transparent: payload
                        .transparent
                        .as_ref()
                        .map(|bytes| Bytes::copy_from_slice(bytes)),
                };
            }
            _ => unreachable!(),
        }
        Some(message)
    } else {
        None
    };
    // Only the outbound segments retain the source allocations at decode time.
    drop(payload);
    let frame: Vec<u8> = segments
        .iter()
        .flat_map(|part| part.iter().copied())
        .collect();
    if let Some(expected) = flatbuffers_expected {
        let decoded = ct_core::parse_message(serializer, Bytes::from(frame))
            .unwrap()
            .message;
        assert_eq!(decoded, expected, "{serializer:?}");
        return;
    }
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
    for serializer in [RawSocketSerializer::Ubjson] {
        let empty = WampPayload {
            args: None,
            kwargs: None,
            transparent: None,
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

#[test]
fn flatbuffers_forwarding_retains_opaque_owners_until_the_last_segment_is_released() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    struct Producer {
        bytes: Vec<u8>,
        released: Arc<AtomicUsize>,
    }
    impl AsRef<[u8]> for Producer {
        fn as_ref(&self) -> &[u8] {
            &self.bytes
        }
    }
    impl Drop for Producer {
        fn drop(&mut self) {
            self.released.fetch_add(1, Ordering::SeqCst);
        }
    }
    for shape in 0..4 {
        for opaque in [vec![], vec![0xff, 0x00, 0x80], vec![0x53; 128 * 1024]] {
            for route in 0..5 {
                let released = Arc::new(AtomicUsize::new(0));
                let mut original = payload(RawSocketSerializer::Flatbuffers, shape);
                original.transparent = Some(Bytes::from_owner(Producer {
                    bytes: opaque.clone(),
                    released: released.clone(),
                }));
                let (source, expected) = match route {
                    0 => (
                        WampMessage::Publish {
                            request_id: 1,
                            options: BTreeMap::new(),
                            topic: "private".into(),
                            payload: original.clone(),
                        },
                        WampMessage::Event {
                            subscription_id: REGISTRATION,
                            publication_id: REQUEST,
                            details: BTreeMap::new(),
                            payload: original.clone(),
                        },
                    ),
                    1 => (
                        WampMessage::Call {
                            request_id: 1,
                            options: BTreeMap::new(),
                            procedure: "private".into(),
                            payload: original.clone(),
                        },
                        WampMessage::Invocation {
                            request_id: REQUEST,
                            registration_id: REGISTRATION,
                            details: BTreeMap::new(),
                            payload: original.clone(),
                        },
                    ),
                    2 => (
                        WampMessage::Yield {
                            request_id: 1,
                            options: BTreeMap::new(),
                            payload: original.clone(),
                        },
                        WampMessage::Result {
                            request_id: REQUEST,
                            details: BTreeMap::new(),
                            payload: original.clone(),
                        },
                    ),
                    3 => (
                        WampMessage::Call {
                            request_id: 1,
                            options: BTreeMap::new(),
                            procedure: "private".into(),
                            payload: original.clone(),
                        },
                        WampMessage::Result {
                            request_id: REQUEST,
                            details: BTreeMap::new(),
                            payload: original.clone(),
                        },
                    ),
                    _ => (
                        WampMessage::Error {
                            request_type: 68,
                            request_id: 1,
                            details: BTreeMap::new(),
                            error: "wamp.error.test".into(),
                            payload: original.clone(),
                        },
                        WampMessage::Error {
                            request_type: 48,
                            request_id: REQUEST,
                            details: BTreeMap::new(),
                            error: "wamp.error.test".into(),
                            payload: original.clone(),
                        },
                    ),
                };
                let source = stored(RawSocketSerializer::Flatbuffers, source);
                let result = match route {
                    0 => encode_event_segments(&source, REGISTRATION, REQUEST, None, None),
                    1 => encode_invocation_segments(
                        &source,
                        REQUEST,
                        REGISTRATION,
                        None,
                        None,
                        None,
                        None,
                        None,
                        None,
                    ),
                    2 => encode_result_segments(&source, REQUEST, false),
                    3 => encode_result_segments_from_call(&source, REQUEST),
                    _ => encode_error_segments(&source, 48, REQUEST),
                };
                if shape != 0 {
                    assert_eq!(
                        result,
                        Err(ERR_INVALID_ARGUMENT),
                        "opaque and ordinary vectors cannot mix"
                    );
                    drop(source);
                    drop(original);
                    drop(expected);
                    assert_eq!(
                        released.load(Ordering::SeqCst),
                        1,
                        "rejection must not retain the producer"
                    );
                    continue;
                }
                // Make the comparison model independent of the borrowed producer.
                let expected_wire = ct_core::encode_flatbuffers_message(&expected).unwrap();
                drop(expected);
                let expected =
                    ct_core::parse_message(RawSocketSerializer::Flatbuffers, expected_wire)
                        .unwrap()
                        .message;
                let segments = successful_segments(result);
                for bytes in [&original.args, &original.kwargs, &original.transparent]
                    .into_iter()
                    .flatten()
                {
                    if !bytes.is_empty() {
                        assert_eq!(
                            segments
                                .iter()
                                .filter(|part| part.as_ptr() == bytes.as_ptr()
                                    && part.len() == bytes.len())
                                .count(),
                            1
                        );
                    }
                }
                drop(source);
                drop(original);
                assert_eq!(
                    released.load(Ordering::SeqCst),
                    0,
                    "producer must survive delayed consumers"
                );
                let frame = Bytes::from(
                    segments
                        .iter()
                        .flat_map(|part| part.iter().copied())
                        .collect::<Vec<_>>(),
                );
                assert_eq!(
                    ct_core::parse_message(RawSocketSerializer::Flatbuffers, frame)
                        .unwrap()
                        .message,
                    expected
                );
                drop(segments);
                assert_eq!(
                    released.load(Ordering::SeqCst),
                    1,
                    "producer must release exactly once after the final segment"
                );
            }
        }
    }
}
