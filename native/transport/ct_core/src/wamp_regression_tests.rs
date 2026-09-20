use super::test_support::{assert_condition, AssertError, AssertSuccess};
use super::*;
#[path = "wamp_regression_tests/followup.rs"]
mod followup;
#[path = "wamp_regression_tests/helper_contracts.rs"]
mod helper_contracts;
use serde_json::{json, Value as Json};

const SERIALIZERS: [Serializer; 3] = [Serializer::Json, Serializer::MessagePack, Serializer::Cbor];

fn wire(serializer: Serializer, value: &Json) -> Bytes {
    Bytes::from(match serializer {
        Serializer::Json => serde_json::to_vec(value).assert_success(),
        Serializer::MessagePack => rmp_serde::to_vec(value).assert_success(),
        Serializer::Cbor => serde_cbor::to_vec(value).assert_success(),
        _ => unreachable!(),
    })
}

fn fragments(bytes: &Bytes, at: usize) -> Vec<Bytes> {
    vec![
        Bytes::new(),
        bytes.slice(..at),
        Bytes::new(),
        bytes.slice(at..),
        Bytes::new(),
    ]
}

#[test]
fn message_boundary_rejects_trailing_values_and_garbage() {
    let mut accepted = Vec::new();
    for serializer in SERIALIZERS {
        let valid = wire(serializer, &json!([67, 7]));
        let tails = [
            wire(serializer, &json!([67, 8])),
            wire(serializer, &json!(null)),
            Bytes::from_static(&[0xff]),
        ];
        for (tail_index, tail) in tails.into_iter().enumerate() {
            let mut bytes = valid.to_vec();
            bytes.extend_from_slice(&tail);
            let bytes = Bytes::from(bytes);
            if parse_message(serializer, bytes.clone()).is_ok() {
                accepted.push(format!("{serializer:?} contiguous tail={tail_index}"));
            }
            for split in 0..=bytes.len() {
                if parse_message_segments(serializer, fragments(&bytes, split)).is_ok() {
                    accepted.push(format!("{serializer:?} split={split} tail={tail_index}"));
                }
            }
        }
    }
    assert_condition!(
        accepted.is_empty(),
        "accepted bytes outside the WAMP message: {accepted:?}"
    );
}

#[test]
fn json_message_boundary_permits_only_json_whitespace() {
    let raw = Bytes::from_static(b" \t\r\n[67,7] \t\r\n");
    for split in 0..=raw.len() {
        let parsed =
            parse_message_segments(Serializer::Json, fragments(&raw, split)).assert_success();
        assert_eq!(parsed.message, WampMessage::Unregistered { request_id: 7 });
        assert_eq!(parsed.raw.into_bytes(), raw);
    }
}

fn metadata() -> ValueMap {
    BTreeMap::from([(Value::String("flag".into()), Value::Bool(true))])
}

// Distinct identifiers make request/resource swaps observable. These literal
// wire messages and expected variants are independent of the parser dispatch.
fn message_cases() -> Vec<(Json, WampMessage, Vec<&'static str>)> {
    let empty = Payload::default();
    vec![
        (
            json!([1,"realm",{"flag":true}]),
            WampMessage::Hello {
                realm: "realm".into(),
                details: metadata(),
            },
            vec!["hello.realm", "hello.details"],
        ),
        (
            json!([2,17,{"flag":true}]),
            WampMessage::Welcome {
                session_id: 17,
                details: metadata(),
            },
            vec!["welcome.session_id", "welcome.details"],
        ),
        (
            json!([3,{"flag":true},"reason"]),
            WampMessage::Abort {
                details: metadata(),
                reason: "reason".into(),
                payload: empty.clone(),
            },
            vec!["abort.details", "abort.reason"],
        ),
        (
            json!([4,"ticket",{"flag":true}]),
            WampMessage::Challenge {
                auth_method: "ticket".into(),
                extra: metadata(),
            },
            vec!["challenge.auth_method", "challenge.extra"],
        ),
        (
            json!([5, "proof"]),
            WampMessage::Authenticate {
                signature: "proof".into(),
                extra: ValueMap::new(),
            },
            vec!["authenticate.signature"],
        ),
        (
            json!([6,{"flag":true},"reason"]),
            WampMessage::Goodbye {
                details: metadata(),
                reason: "reason".into(),
                payload: empty.clone(),
            },
            vec!["goodbye.details", "goodbye.reason"],
        ),
        (
            json!([7,{"flag":true},17,29,43]),
            WampMessage::Heartbeat {
                details: metadata(),
                ping: Some(17),
                incoming: Some(29),
                outgoing: Some(43),
            },
            vec!["heartbeat.details"],
        ),
        (
            json!([8,48,17,{"flag":true},"error"]),
            WampMessage::Error {
                request_type: 48,
                request_id: 17,
                details: metadata(),
                error: "error".into(),
                payload: empty.clone(),
            },
            vec![
                "error.request_type",
                "error.request_id",
                "error.details",
                "error.uri",
            ],
        ),
        (
            json!([16,17,{"flag":true},"topic"]),
            WampMessage::Publish {
                request_id: 17,
                options: metadata(),
                topic: "topic".into(),
                payload: empty.clone(),
            },
            vec!["publish.request_id", "publish.options", "publish.topic"],
        ),
        (
            json!([17, 17, 29]),
            WampMessage::Published {
                request_id: 17,
                publication_id: 29,
            },
            vec!["published.request_id", "published.publication_id"],
        ),
        (
            json!([32,17,{"flag":true},"topic"]),
            WampMessage::Subscribe {
                request_id: 17,
                options: metadata(),
                topic: "topic".into(),
            },
            vec![
                "subscribe.request_id",
                "subscribe.options",
                "subscribe.topic",
            ],
        ),
        (
            json!([33, 17, 29]),
            WampMessage::Subscribed {
                request_id: 17,
                subscription_id: 29,
            },
            vec!["subscribed.request_id", "subscribed.subscription_id"],
        ),
        (
            json!([34, 17, 29]),
            WampMessage::Unsubscribe {
                request_id: 17,
                subscription_id: 29,
            },
            vec!["unsubscribe.request_id", "unsubscribe.subscription_id"],
        ),
        (
            json!([35, 17]),
            WampMessage::Unsubscribed {
                request_id: 17,
                details: ValueMap::new(),
            },
            vec!["unsubscribed.request_id"],
        ),
        (
            json!([36,17,29,{"flag":true}]),
            WampMessage::Event {
                subscription_id: 17,
                publication_id: 29,
                details: metadata(),
                payload: empty.clone(),
            },
            vec![
                "event.subscription_id",
                "event.publication_id",
                "event.details",
            ],
        ),
        (
            json!([48,17,{"flag":true},"procedure"]),
            WampMessage::Call {
                request_id: 17,
                options: metadata(),
                procedure: "procedure".into(),
                payload: empty.clone(),
            },
            vec!["call.request_id", "call.options", "call.procedure"],
        ),
        (
            json!([49,17,{"flag":true}]),
            WampMessage::Cancel {
                request_id: 17,
                options: metadata(),
            },
            vec!["cancel.request_id", "cancel.options"],
        ),
        (
            json!([50,17,{"flag":true}]),
            WampMessage::Result {
                request_id: 17,
                details: metadata(),
                payload: empty.clone(),
            },
            vec!["result.request_id", "result.details"],
        ),
        (
            json!([64,17,{"flag":true},"procedure"]),
            WampMessage::Register {
                request_id: 17,
                options: metadata(),
                procedure: "procedure".into(),
            },
            vec![
                "register.request_id",
                "register.options",
                "register.procedure",
            ],
        ),
        (
            json!([65, 17, 29]),
            WampMessage::Registered {
                request_id: 17,
                registration_id: 29,
            },
            vec!["registered.request_id", "registered.registration_id"],
        ),
        (
            json!([66, 17, 29]),
            WampMessage::Unregister {
                request_id: 17,
                registration_id: 29,
            },
            vec!["unregister.request_id", "unregister.registration_id"],
        ),
        (
            json!([67, 17]),
            WampMessage::Unregistered { request_id: 17 },
            vec!["unregistered.request_id"],
        ),
        (
            json!([68,17,29,{"flag":true}]),
            WampMessage::Invocation {
                request_id: 17,
                registration_id: 29,
                details: metadata(),
                payload: empty.clone(),
            },
            vec![
                "invocation.request_id",
                "invocation.registration_id",
                "invocation.details",
            ],
        ),
        (
            json!([69,17,{"flag":true}]),
            WampMessage::Interrupt {
                request_id: 17,
                options: metadata(),
            },
            vec!["interrupt.request_id", "interrupt.options"],
        ),
        (
            json!([70,17,{"flag":true}]),
            WampMessage::Yield {
                request_id: 17,
                options: metadata(),
                payload: empty,
            },
            vec!["yield.request_id", "yield.options"],
        ),
        (
            json!([127, "future", true]),
            WampMessage::Unknown {
                code: 127,
                fields: vec![Value::String("future".into()), Value::Bool(true)],
            },
            vec![],
        ),
    ]
}

fn check_valid(serializer: Serializer, value: &Json, expected: &WampMessage) {
    let raw = wire(serializer, value);
    let parsed = parse_message(serializer, raw.clone()).assert_success();
    assert_eq!(&parsed.message, expected, "{serializer:?}: {value}");
    assert_eq!(parsed.message.code(), value[0].as_u64().assert_success());
    assert_eq!(parsed.serializer, serializer);
    assert_eq!(parsed.raw.into_bytes(), raw);
    for split in 0..=raw.len() {
        let parsed = parse_message_segments(serializer, fragments(&raw, split)).assert_success();
        assert_eq!(
            &parsed.message, expected,
            "{serializer:?} split={split}: {value}"
        );
        assert_eq!(parsed.raw.into_bytes(), raw);
    }
}

#[test]
fn all_message_fields_survive_every_segment_boundary() {
    for serializer in SERIALIZERS {
        for (value, expected, _) in message_cases() {
            check_valid(serializer, &value, &expected);
        }
    }
}

#[test]
fn missing_and_wrong_required_fields_have_specific_errors() {
    for serializer in SERIALIZERS {
        for (value, _, labels) in message_cases() {
            let fields = value.as_array().assert_success();
            for (offset, label) in labels.into_iter().enumerate() {
                let index = offset + 1;
                let missing = Json::Array(fields[..index].to_vec());
                let mut wrong = value.clone();
                wrong[index] = json!(true);
                for segmented in [false, true] {
                    let parse = |value: &Json| {
                        let raw = wire(serializer, value);
                        if segmented {
                            parse_message_segments(serializer, fragments(&raw, 1))
                        } else {
                            parse_message(serializer, raw)
                        }
                    };
                    assert_condition!(
                        matches!(parse(&missing), Err(ParseError::MissingElement(actual)) if actual == label),
                        "{serializer:?} segmented={segmented} missing={missing} label={label}"
                    );
                    let error = parse(&wrong).assert_error();
                    let correct = match &fields[index] {
                        Json::String(_) if serializer == Serializer::Json => {
                            matches!(&error, ParseError::Deserialize(message) if message.contains("expected a string"))
                        }
                        Json::String(_) => {
                            matches!(error, ParseError::ExpectedString(actual) if actual == label)
                        }
                        Json::Number(_) => {
                            matches!(error, ParseError::ExpectedIdentifier(actual) if actual == label)
                        }
                        Json::Object(_) => {
                            matches!(error, ParseError::ExpectedMap(actual) if actual == label)
                        }
                        _ => panic!("unsupported test fixture field"),
                    };
                    assert_condition!(
                        correct,
                        "{serializer:?} segmented={segmented}: {wrong}: {error:?}"
                    );
                }
            }
        }
    }
}

#[test]
fn empty_non_array_and_invalid_code_messages_fail_closed() {
    for serializer in SERIALIZERS {
        for value in [
            json!([]),
            json!({}),
            json!(true),
            json!([null]),
            json!([-1]),
            json!(["48"]),
        ] {
            let raw = wire(serializer, &value);
            for split in 0..=raw.len() {
                let error =
                    parse_message_segments(serializer, fragments(&raw, split)).assert_error();
                if value == json!([]) {
                    assert_condition!(matches!(error, ParseError::MissingElement("message code")));
                } else if value.is_array() {
                    assert_condition!(matches!(
                        error,
                        ParseError::ExpectedIdentifier("message code")
                    ));
                } else {
                    assert_condition!(matches!(
                        error,
                        ParseError::ExpectedArray | ParseError::Deserialize(_)
                    ));
                }
            }
        }
        for (value, _, labels) in message_cases() {
            for (offset, label) in labels.into_iter().enumerate() {
                let index = offset + 1;
                if !value[index].is_string() && !value[index].is_number() {
                    continue;
                }
                let mut invalid = value.clone();
                invalid[index] = Json::Null;
                let raw = wire(serializer, &invalid);
                for segmented in [false, true] {
                    let error = if segmented {
                        parse_message_segments(serializer, fragments(&raw, 1))
                    } else {
                        parse_message(serializer, raw.clone())
                    }
                    .assert_error();
                    let correct = if value[index].is_string() {
                        matches!(error, ParseError::ExpectedString(actual) if actual == label)
                    } else {
                        matches!(error, ParseError::ExpectedIdentifier(actual) if actual == label)
                    };
                    assert_condition!(
                        correct,
                        "{serializer:?} segmented={segmented} null {label}: {error:?}"
                    );
                }
            }
        }
    }
    for serializer in [Serializer::Ubjson, Serializer::Flatbuffers] {
        for segmented in [false, true] {
            let raw = Bytes::from_static(b"[67,7]");
            let result = if segmented {
                parse_message_segments(serializer, fragments(&raw, 1))
            } else {
                parse_message(serializer, raw)
            };
            assert_condition!(
                matches!(result, Err(ParseError::UnsupportedSerializer(actual)) if actual == serializer)
            );
        }
    }
}

fn payload_mut(message: &mut WampMessage) -> Option<&mut Payload> {
    match message {
        WampMessage::Abort { payload, .. }
        | WampMessage::Goodbye { payload, .. }
        | WampMessage::Error { payload, .. }
        | WampMessage::Publish { payload, .. }
        | WampMessage::Event { payload, .. }
        | WampMessage::Call { payload, .. }
        | WampMessage::Result { payload, .. }
        | WampMessage::Invocation { payload, .. }
        | WampMessage::Yield { payload, .. } => Some(payload),
        _ => None,
    }
}

#[test]
fn all_payload_messages_preserve_absent_null_empty_and_populated_arguments() {
    for serializer in SERIALIZERS {
        for (template, expected, _) in message_cases() {
            if payload_mut(&mut expected.clone()).is_none() {
                continue;
            }
            for args in [Json::Null, json!([]), json!(["hello", true, [1, 2]])] {
                for kwargs in [
                    None,
                    Some(Json::Null),
                    Some(json!({})),
                    Some(json!({"name":"value"})),
                ] {
                    let mut value = template.clone();
                    value.as_array_mut().assert_success().push(args.clone());
                    if let Some(kwargs) = &kwargs {
                        value.as_array_mut().assert_success().push(kwargs.clone());
                    }
                    let mut expected = expected.clone();
                    *payload_mut(&mut expected).assert_success() = Payload {
                        args: (!args.is_null()).then(|| wire(serializer, &args)),
                        kwargs: kwargs
                            .filter(|value| !value.is_null())
                            .map(|value| wire(serializer, &value)),
                    };
                    check_valid(serializer, &value, &expected);
                }
            }
        }
    }
}

#[test]
fn optional_metadata_and_heartbeat_counters_preserve_their_fields() {
    for serializer in SERIALIZERS {
        for (template, label) in [
            (json!([5, "proof"]), "authenticate.extra"),
            (json!([35, 17]), "unsubscribed.details"),
        ] {
            for value in [Json::Null, json!({}), json!({"flag":true})] {
                let mut raw = template.clone();
                raw.as_array_mut().assert_success().push(value.clone());
                let map = if value == json!({"flag":true}) {
                    metadata()
                } else {
                    ValueMap::new()
                };
                let expected = if template[0] == 5 {
                    WampMessage::Authenticate {
                        signature: "proof".into(),
                        extra: map,
                    }
                } else {
                    WampMessage::Unsubscribed {
                        request_id: 17,
                        details: map,
                    }
                };
                check_valid(serializer, &raw, &expected);
            }
            let mut invalid = template;
            invalid.as_array_mut().assert_success().push(json!([]));
            assert_condition!(
                matches!(parse_message(serializer, wire(serializer, &invalid)), Err(ParseError::ExpectedMap(actual)) if actual == label)
            );
        }
        for count in 0..=3 {
            let counters = [17, 29, 43];
            let mut value = json!([7, {}]);
            value
                .as_array_mut()
                .assert_success()
                .extend(counters[..count].iter().map(|n| json!(n)));
            let expected = WampMessage::Heartbeat {
                details: ValueMap::new(),
                ping: (count > 0).then_some(17),
                incoming: (count > 1).then_some(29),
                outgoing: (count > 2).then_some(43),
            };
            check_valid(serializer, &value, &expected);
        }
        for (index, label) in ["heartbeat.ping", "heartbeat.incoming", "heartbeat.outgoing"]
            .into_iter()
            .enumerate()
        {
            let mut value = json!([7, {}, 17, 29, 43]);
            value[index + 2] = json!(-1);
            let raw = wire(serializer, &value);
            assert_condition!(
                matches!(parse_message(serializer, raw.clone()), Err(ParseError::ExpectedIdentifier(actual)) if actual == label)
            );
            assert_condition!(
                matches!(parse_message_segments(serializer, fragments(&raw, 1)), Err(ParseError::ExpectedIdentifier(actual)) if actual == label)
            );
        }
    }
}

#[test]
fn payload_shape_errors_identify_the_message_and_argument_slot() {
    let labels = [
        (3, "abort"),
        (6, "goodbye"),
        (8, "error"),
        (16, "publish"),
        (36, "event"),
        (48, "call"),
        (50, "result"),
        (68, "invocation"),
        (70, "yield"),
    ];
    for serializer in SERIALIZERS {
        for (template, expected, _) in message_cases() {
            if payload_mut(&mut expected.clone()).is_none() {
                continue;
            }
            let prefix = labels
                .iter()
                .find(|(code, _)| template[0] == *code)
                .assert_success()
                .1;
            for kwargs in [false, true] {
                for wrong in [
                    json!(true),
                    json!(17),
                    json!("wrong"),
                    if kwargs { json!([]) } else { json!({}) },
                ] {
                    let mut value = template.clone();
                    if kwargs {
                        value.as_array_mut().assert_success().push(json!([]));
                    }
                    value.as_array_mut().assert_success().push(wrong);
                    let raw = wire(serializer, &value);
                    let expected_label = format!(
                        "{prefix}.{}",
                        if kwargs { "argumentsKw" } else { "arguments" }
                    );
                    for segmented in [false, true] {
                        let result = if segmented {
                            parse_message_segments(serializer, fragments(&raw, 1))
                        } else {
                            parse_message(serializer, raw.clone())
                        };
                        let correct = if kwargs {
                            matches!(result, Err(ParseError::ExpectedMap(label)) if label == expected_label)
                        } else {
                            matches!(result, Err(ParseError::ExpectedList(label)) if label == expected_label)
                        };
                        assert_condition!(correct, "{serializer:?} segmented={segmented}: {value}: expected {expected_label}");
                    }
                }
            }
        }
    }
}

#[test]
fn msgpack_marker_widths_preserve_lazy_payload_ranges_and_reject_every_truncation() {
    let mut values: Vec<Vec<u8>> = vec![
        vec![0],
        vec![127],
        vec![0xe0],
        vec![0xff],
        vec![0xc0],
        vec![0xc2],
        vec![0xc3],
        vec![0xa0],
        vec![0xa2, b'h', b'i'],
        vec![0x90],
        vec![0x92, 0xc0, 0xc3],
        vec![0x80],
        vec![0x81, 0xa1, b'k', 0x91, 0xc2],
    ];
    for (marker, len) in [
        (0xcc, 1),
        (0xcd, 2),
        (0xce, 4),
        (0xcf, 8),
        (0xd0, 1),
        (0xd1, 2),
        (0xd2, 4),
        (0xd3, 8),
        (0xca, 4),
        (0xcb, 8),
    ] {
        let mut value = vec![marker];
        value.extend(vec![0; len]);
        values.push(value);
    }
    for (marker, width) in [
        (0xd9, 1),
        (0xda, 2),
        (0xdb, 4),
        (0xc4, 1),
        (0xc5, 2),
        (0xc6, 4),
        (0xc7, 1),
        (0xc8, 2),
        (0xc9, 4),
    ] {
        let mut value = vec![marker];
        value.extend(vec![0; width - 1]);
        value.push(2);
        if matches!(marker, 0xc7..=0xc9) {
            value.push(1);
        }
        value.extend([b'a', b'b']);
        values.push(value);
    }
    for (marker, width) in [(0xdc, 2), (0xdd, 4), (0xde, 2), (0xdf, 4)] {
        let mut value = vec![marker];
        value.extend(vec![0; width - 1]);
        value.extend([1, 0xc3]);
        if matches!(marker, 0xde | 0xdf) {
            value.push(0xc2);
        }
        values.push(value);
    }
    for (marker, len) in [(0xd4, 1), (0xd5, 2), (0xd6, 4), (0xd7, 8), (0xd8, 16)] {
        let mut value = vec![marker, 1];
        value.extend(vec![0x41; len]);
        values.push(value);
    }
    for value in values {
        let marker = value[0];
        let mut raw = vec![0x94, 50, 7, 0x80, 0x91];
        raw.extend(&value);
        let raw = Bytes::from(raw);
        let expected = WampMessage::Result {
            request_id: 7,
            details: ValueMap::new(),
            payload: Payload {
                args: Some(raw.slice(4..)),
                kwargs: None,
            },
        };
        for split in 0..=raw.len() {
            let parsed = parse_message_segments(Serializer::MessagePack, fragments(&raw, split))
                .assert_success();
            assert_eq!(parsed.message, expected, "marker={marker:x} split={split}");
        }
        for length in 0..raw.len() {
            let truncated = raw.slice(..length);
            assert_condition!(
                parse_message(Serializer::MessagePack, truncated.clone()).is_err(),
                "marker={marker:x} length={length}"
            );
            assert_condition!(
                parse_message_segments(Serializer::MessagePack, fragments(&truncated, length / 2))
                    .is_err(),
                "segmented marker={marker:x} length={length}"
            );
        }
        let mut with_sentinel = value.clone();
        with_sentinel.push(0x7f);
        let data = RawFrame::Contiguous(Bytes::from(with_sentinel));
        let mut offset = 0;
        assert_eq!(
            msgpack_read_value_range(&data, &mut offset).assert_success(),
            0..value.len()
        );
        assert_eq!(offset, value.len());
        assert_eq!(read_u8(&data, &mut offset).assert_success(), 0x7f);
    }
    let reserved = Bytes::from_static(&[0x94, 50, 7, 0x80, 0x91, 0xc1]);
    assert_condition!(
        matches!(parse_message(Serializer::MessagePack, reserved), Err(ParseError::Deserialize(message)) if message.contains("reserved MessagePack marker"))
    );
}

#[test]
fn binary_array_headers_decode_all_widths_and_reject_truncation() {
    for (serializer, headers, body) in [
        (
            Serializer::MessagePack,
            vec![vec![0x92], vec![0xdc, 0, 2], vec![0xdd, 0, 0, 0, 2]],
            vec![67, 7],
        ),
        (
            Serializer::Cbor,
            vec![
                vec![0x82],
                vec![0x98, 2],
                vec![0x99, 0, 2],
                vec![0x9a, 0, 0, 0, 2],
                vec![0x9b, 0, 0, 0, 0, 0, 0, 0, 2],
            ],
            vec![0x18, 67, 7],
        ),
    ] {
        for header in headers {
            let mut raw = header.clone();
            raw.extend(&body);
            let raw = Bytes::from(raw);
            let expected = WampMessage::Unregistered { request_id: 7 };
            assert_eq!(
                parse_message(serializer, raw.clone())
                    .assert_success()
                    .message,
                expected
            );
            for split in 0..=raw.len() {
                assert_eq!(
                    parse_message_segments(serializer, fragments(&raw, split))
                        .assert_success()
                        .message,
                    expected
                );
            }
            for length in 0..raw.len() {
                assert_condition!(
                    parse_message(serializer, raw.slice(..length)).is_err(),
                    "{serializer:?} header={header:?} length={length}"
                );
            }
        }
    }
    for raw in [
        vec![0x9c],
        vec![0x9d],
        vec![0x9e],
        vec![0x9f, 0x18, 67],
        vec![0x80, 0x00],
    ] {
        assert_condition!(matches!(
            parse_message(Serializer::Cbor, Bytes::from(raw)),
            Err(ParseError::Deserialize(_))
        ));
    }
    let indefinite = Bytes::from_static(&[0x9f, 0x18, 67, 7, 0xff]);
    assert_eq!(
        parse_message(Serializer::Cbor, indefinite)
            .assert_success()
            .message,
        WampMessage::Unregistered { request_id: 7 }
    );
}

#[test]
fn raw_frame_ranges_preserve_bytes_and_storage_ownership() {
    let raw = Bytes::from_static(b"abcdefgh");
    for split in 0..=raw.len() {
        let frame = RawFrame::from_segments(fragments(&raw, split));
        assert_eq!(frame.len(), 8);
        assert_condition!(frame.as_contiguous().is_none());
        assert_eq!(frame.clone().into_bytes(), raw);
        for index in 0..raw.len() {
            assert_eq!(frame.read_byte(index).assert_success(), raw[index]);
        }
        assert_condition!(matches!(
            frame.read_byte(8),
            Err(ParseError::Deserialize(_))
        ));
        for start in 0..=raw.len() {
            for end in start..=raw.len() {
                let slice = frame.slice_or_copy(&(start..end)).assert_success();
                assert_eq!(
                    slice,
                    raw.slice(start..end),
                    "split={split} range={start}..{end}"
                );
                if start < end && (end <= split || start >= split) {
                    assert_condition!(
                        frame.contains_slice(&slice),
                        "in-segment range must remain zero-copy"
                    );
                }
            }
        }
        assert_condition!(matches!(
            frame.slice_or_copy(&(0..9)),
            Err(ParseError::Deserialize(_))
        ));
        let retained = frame.slice_or_copy(&(1..7)).assert_success();
        drop(frame);
        assert_eq!(retained.as_ref(), b"bcdefg");
    }
    let contiguous = RawFrame::Contiguous(raw.clone());
    assert_eq!(contiguous.as_contiguous(), Some(&raw));
    assert_condition!(matches!(
        contiguous.read_byte(8),
        Err(ParseError::Deserialize(_))
    ));
    assert_condition!(matches!(
        contiguous.slice_or_copy(&(7..9)),
        Err(ParseError::Deserialize(_))
    ));
}

#[test]
fn segmented_reader_respects_empty_reads_partial_reads_and_eof() {
    let mut reader = SegmentedFrameReader::new(vec![
        Bytes::new(),
        Bytes::from_static(b"ab"),
        Bytes::new(),
        Bytes::from_static(b"cde"),
        Bytes::new(),
    ]);
    assert_eq!(reader.read(&mut []).assert_success(), 0);
    let mut buffer = [0xaa; 3];
    assert_eq!(reader.read(&mut buffer).assert_success(), 3);
    assert_eq!(buffer, *b"abc");
    assert_eq!(reader.read(&mut []).assert_success(), 0);
    assert_eq!(reader.read(&mut buffer).assert_success(), 2);
    assert_eq!(buffer, *b"dec");
    assert_eq!(reader.read(&mut buffer).assert_success(), 0);
    assert_eq!(reader.read(&mut buffer).assert_success(), 0);
    assert_eq!(buffer, *b"dec");
}
