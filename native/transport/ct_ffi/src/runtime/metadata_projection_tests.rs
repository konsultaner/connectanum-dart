use super::*;
use serde_json::json;

const SERIALIZERS: [RawSocketSerializer; 3] = [
    RawSocketSerializer::Json,
    RawSocketSerializer::MessagePack,
    RawSocketSerializer::Cbor,
];

const NULLABLE_BOOLS: [(u64, &str, u32); 13] = [
    (16, "acknowledge", CT_MESSAGE_FLAG_DETAIL_BOOL_A_TRUE),
    (16, "exclude_me", CT_MESSAGE_FLAG_DETAIL_BOOL_B_TRUE),
    (16, "disclose_me", CT_MESSAGE_FLAG_DETAIL_BOOL_C_TRUE),
    (16, "retain", CT_MESSAGE_FLAG_DETAIL_BOOL_D_TRUE),
    (32, "get_retained", CT_MESSAGE_FLAG_DETAIL_BOOL_A_TRUE),
    (48, "receive_progress", CT_MESSAGE_FLAG_DETAIL_BOOL_A_TRUE),
    (48, "progress", CT_MESSAGE_FLAG_DETAIL_BOOL_C_TRUE),
    (48, "disclose_me", CT_MESSAGE_FLAG_DETAIL_BOOL_B_TRUE),
    (64, "disclose_caller", CT_MESSAGE_FLAG_DETAIL_BOOL_A_TRUE),
    (64, "forward_timeout", CT_MESSAGE_FLAG_DETAIL_BOOL_B_TRUE),
    (50, "progress", CT_MESSAGE_FLAG_DETAIL_BOOL_A_TRUE),
    (68, "receive_progress", CT_MESSAGE_FLAG_DETAIL_BOOL_A_TRUE),
    (68, "progress", CT_MESSAGE_FLAG_DETAIL_BOOL_B_TRUE),
];

fn encoded(serializer: RawSocketSerializer, value: &JsonValue) -> Bytes {
    Bytes::from(match serializer {
        RawSocketSerializer::Json => serde_json::to_vec(value).unwrap(),
        RawSocketSerializer::MessagePack => rmp_serde::to_vec(value).unwrap(),
        RawSocketSerializer::Cbor => serde_cbor::to_vec(value).unwrap(),
        _ => unreachable!(),
    })
}

fn decoded(serializer: RawSocketSerializer, bytes: &[u8]) -> JsonValue {
    let result: Result<JsonValue, String> = match serializer {
        RawSocketSerializer::Json => serde_json::from_slice(bytes).map_err(|e| e.to_string()),
        RawSocketSerializer::MessagePack => rmp_serde::from_slice(bytes).map_err(|e| e.to_string()),
        RawSocketSerializer::Cbor => serde_cbor::from_slice(bytes).map_err(|e| e.to_string()),
        _ => unreachable!(),
    };
    assert!(result.is_ok(), "invalid exported metadata: {result:?}");
    result.unwrap()
}

fn message(serializer: RawSocketSerializer, code: u64, details: &JsonValue) -> StoredMessage {
    let wire = match code {
        1 => json!([1, "realm.test", details]),
        2 => json!([2, 41, details]),
        3 | 6 => json!([code, details, "wamp.close.normal"]),
        8 => json!([8, 48, 41, details, "wamp.error.test", [17], {"key": "value"}]),
        16 | 48 => json!([code, 41, details, "com.test", [17], {"key": "value"}]),
        32 | 64 => json!([code, 41, details, "com.test"]),
        36 | 68 => json!([code, 41, 62, details, [17], {"key": "value"}]),
        50 | 70 => json!([code, 41, details, [17], {"key": "value"}]),
        35 | 49 | 69 => json!([code, 41, details]),
        _ => panic!("unexpected test message code"),
    };
    let parsed = ct_core::parse_message(serializer, encoded(serializer, &wire));
    assert!(parsed.is_ok(), "valid WAMP frame must parse: {parsed:?}");
    parsed_message_value(parsed.unwrap())
}

fn assert_metadata(msg: &StoredMessage, expected: &JsonValue, direct: bool) -> CtMessageInfo {
    let info = build_message_info(msg, false);
    assert_eq!(info.message_code, msg.code);
    assert_ne!(info.flags & CT_MESSAGE_FLAG_METADATA_BIND, 0);
    assert_eq!(
        info.flags & CT_MESSAGE_FLAG_DIRECT_BIND != 0,
        direct,
        "{:?} code={} details={expected}",
        msg.serializer,
        msg.code
    );
    assert!(info.frame_ptr.is_null());
    assert_eq!(
        info.frame_len, 0,
        "metadata binding must not flatten the frame"
    );
    assert!(!info.details_ptr.is_null());
    assert!(info.details_len > 0);
    // The owning StoredMessage remains alive while inspecting these borrowed views.
    let bytes = unsafe { std::slice::from_raw_parts(info.details_ptr, info.details_len) };
    assert_eq!(decoded(msg.serializer, bytes), *expected);
    for (part, pointer, length) in [
        (&msg.args, info.args_ptr, info.args_len),
        (&msg.kwargs, info.kwargs_ptr, info.kwargs_len),
    ] {
        match part {
            Some(bytes) => {
                assert_eq!(pointer, bytes.as_ptr());
                assert_eq!(length, bytes.len());
            }
            None => {
                assert!(pointer.is_null());
                assert_eq!(length, 0);
            }
        }
    }
    info
}

#[test]
fn nullable_false_requires_lossless_metadata_fallback() {
    for serializer in SERIALIZERS {
        for (code, key, _) in NULLABLE_BOOLS {
            let details = json!({key: false, "trace": {"nested": [1, null, true]}});
            assert_metadata(&message(serializer, code, &details), &details, false);
        }
    }
}

#[test]
fn nullable_true_and_absent_remain_distinguishable_in_direct_metadata() {
    let bool_mask = CT_MESSAGE_FLAG_DETAIL_BOOL_A_TRUE
        | CT_MESSAGE_FLAG_DETAIL_BOOL_B_TRUE
        | CT_MESSAGE_FLAG_DETAIL_BOOL_C_TRUE
        | CT_MESSAGE_FLAG_DETAIL_BOOL_D_TRUE;
    for serializer in SERIALIZERS {
        for (code, key, flag) in NULLABLE_BOOLS {
            for value in [None, Some(true)] {
                let mut details = json!({"trace": [false, null]});
                if let Some(value) = value {
                    details[key] = json!(value);
                }
                let info = assert_metadata(&message(serializer, code, &details), &details, true);
                assert_eq!(
                    info.flags & bool_mask,
                    if value.is_some() { flag } else { 0 }
                );
            }
        }
    }
}

#[test]
fn malformed_nullable_booleans_preserve_original_values_for_fallback() {
    for serializer in SERIALIZERS {
        for (code, key, _) in NULLABLE_BOOLS {
            for value in [
                json!(null),
                json!(0),
                json!(1),
                json!("false"),
                json!([]),
                json!({}),
            ] {
                let details = json!({key: value});
                assert_metadata(&message(serializer, code, &details), &details, false);
            }
        }
    }
}

#[test]
fn yield_progress_is_nonnullable_and_keeps_its_false_fast_path() {
    for serializer in SERIALIZERS {
        for value in [None, Some(false), Some(true)] {
            let mut details = json!({});
            if let Some(value) = value {
                details["progress"] = json!(value);
            }
            let info = assert_metadata(&message(serializer, 70, &details), &details, true);
            assert_eq!(
                info.flags & CT_MESSAGE_FLAG_DETAIL_BOOL_A_TRUE != 0,
                value == Some(true)
            );
        }
        for value in [json!(null), json!(0), json!("true"), json!([])] {
            let details = json!({"progress": value});
            assert_metadata(&message(serializer, 70, &details), &details, false);
        }
    }
}

#[test]
fn mixed_boolean_options_do_not_drop_false_fields_or_leak_previous_flags() {
    for serializer in SERIALIZERS {
        for code in [16, 48, 64, 68] {
            let fields: Vec<_> = NULLABLE_BOOLS
                .iter()
                .filter(|(c, _, _)| *c == code)
                .collect();
            for false_index in 0..fields.len() {
                let mut details = json!({});
                for (index, (_, key, _)) in fields.iter().enumerate() {
                    details[*key] = json!(index != false_index);
                }
                assert_metadata(&message(serializer, code, &details), &details, false);
                let empty = json!({});
                let info = assert_metadata(&message(serializer, code, &empty), &empty, true);
                assert_eq!(
                    info.flags,
                    CT_MESSAGE_FLAG_DIRECT_BIND | CT_MESSAGE_FLAG_METADATA_BIND
                );
            }
        }
    }
}

#[test]
fn numeric_metadata_validates_types_and_preserves_zero_presence() {
    for serializer in SERIALIZERS {
        for (code, key, second) in [
            (36, "publisher", false),
            (36, "trustlevel", true),
            (48, "timeout", false),
            (68, "caller", false),
            (68, "timeout", true),
            (35, "subscription", false),
        ] {
            for value in [0, 1, (1_u64 << 53) - 1] {
                let details = json!({key: value});
                let info = assert_metadata(&message(serializer, code, &details), &details, true);
                let (actual, flag) = if second {
                    (
                        info.detail_number_b,
                        CT_MESSAGE_FLAG_DETAIL_NUMBER_B_PRESENT,
                    )
                } else {
                    (
                        info.detail_number_a,
                        CT_MESSAGE_FLAG_DETAIL_NUMBER_A_PRESENT,
                    )
                };
                assert_eq!(actual, value);
                assert_ne!(info.flags & flag, 0);
            }
            for value in [
                json!(-1),
                json!(1.5),
                json!(false),
                json!("1"),
                json!(null),
                json!([]),
            ] {
                let details = json!({key: value});
                assert_metadata(&message(serializer, code, &details), &details, false);
            }
        }
    }
}

#[test]
fn string_metadata_retains_utf8_and_rejects_nonstring_fast_paths() {
    let mut fields = vec![
        (1, "authid", 1),
        (1, "authrole", 2),
        (1, "authmethod", 3),
        (1, "authprovider", 4),
        (2, "realm", 0),
        (2, "authid", 1),
        (2, "authrole", 2),
        (2, "authmethod", 3),
        (2, "authprovider", 4),
        (3, "message", 1),
        (6, "message", 1),
        (8, "message", 1),
        (32, "match", 1),
        (32, "meta_topic", 2),
        (35, "reason", 0),
        (36, "topic", 0),
        (49, "mode", 0),
        (64, "match", 1),
        (64, "invoke", 2),
        (68, "procedure", 0),
        (69, "mode", 0),
    ];
    for code in [16, 36, 48, 50, 68, 70] {
        for (offset, key) in ["ppt_scheme", "ppt_serializer", "ppt_cipher", "ppt_keyid"]
            .into_iter()
            .enumerate()
        {
            fields.push((code, key, offset + usize::from(code != 50 && code != 70)));
        }
    }
    for serializer in SERIALIZERS {
        for &(code, key, slot) in &fields {
            for value in ["", "a\0b\n\\\"", "\u{00fc}\u{1f680}"] {
                let details = json!({key: value});
                let msg = message(serializer, code, &details);
                let info = assert_metadata(&msg, &details, true);
                let strings = [
                    (info.string_a_ptr, info.string_a_len),
                    (info.string_b_ptr, info.string_b_len),
                    (info.string_c_ptr, info.string_c_len),
                    (info.string_d_ptr, info.string_d_len),
                    (info.string_e_ptr, info.string_e_len),
                ];
                let (pointer, length) = strings[slot];
                assert_eq!(length, value.len());
                assert!(!pointer.is_null());
                assert_eq!(
                    unsafe { std::slice::from_raw_parts(pointer, length) },
                    value.as_bytes()
                );
            }
            for value in [json!(false), json!(17), json!(null), json!([]), json!({})] {
                let details = json!({key: value});
                assert_metadata(&message(serializer, code, &details), &details, false);
            }
        }
    }
}

#[test]
fn routing_lists_and_unrepresentable_extensions_keep_metadata_fallback() {
    for serializer in SERIALIZERS {
        for key in [
            "exclude",
            "exclude_authid",
            "exclude_authrole",
            "eligible",
            "eligible_authid",
            "eligible_authrole",
        ] {
            let details = json!({key: ["consumer"], "acknowledge": true});
            assert_metadata(&message(serializer, 16, &details), &details, false);
        }
        for code in [35, 49, 69] {
            let details = json!({"trace": false});
            assert_metadata(&message(serializer, code, &details), &details, false);
        }
    }
}

#[test]
fn every_metadata_projector_rejects_nonstring_map_keys() {
    type Projector =
        fn(&mut CtMessageInfo, &std::collections::BTreeMap<SerdeValue, SerdeValue>) -> bool;
    let projectors: [Projector; 12] = [
        populate_event_details_info,
        populate_result_details_info,
        populate_invocation_details_info,
        populate_welcome_details_info,
        populate_hello_details_info,
        populate_message_only_details_info,
        populate_publish_options_info,
        populate_subscribe_options_info,
        populate_call_options_info,
        populate_cancel_options_info,
        populate_register_options_info,
        populate_yield_options_info,
    ];
    for projector in projectors
        .into_iter()
        .chain([populate_unsubscribed_details_info as Projector])
    {
        for key in [
            SerdeValue::U64(17),
            SerdeValue::Bool(true),
            SerdeValue::Unit,
        ] {
            let details = [(key, SerdeValue::String("not an option".into()))]
                .into_iter()
                .collect();
            assert!(!projector(&mut CtMessageInfo::default(), &details));
        }
    }
}

#[test]
fn numeric_metadata_conversion_preserves_integer_widths_and_rejects_coercion() {
    for (value, expected) in [
        (SerdeValue::U8(u8::MAX), u8::MAX as u64),
        (SerdeValue::U16(u16::MAX), u16::MAX as u64),
        (SerdeValue::U32(u32::MAX), u32::MAX as u64),
        (SerdeValue::U64(u64::MAX), u64::MAX),
        (SerdeValue::I8(0), 0),
        (SerdeValue::I16(0), 0),
        (SerdeValue::I32(0), 0),
        (SerdeValue::I64(0), 0),
        (SerdeValue::I8(i8::MAX), i8::MAX as u64),
        (SerdeValue::I16(i16::MAX), i16::MAX as u64),
        (SerdeValue::I32(i32::MAX), i32::MAX as u64),
        (SerdeValue::I64(i64::MAX), i64::MAX as u64),
    ] {
        assert_eq!(serde_value_u64(&value), Some(expected));
    }
    for value in [
        SerdeValue::I8(-1),
        SerdeValue::I16(-1),
        SerdeValue::I32(-1),
        SerdeValue::I64(-1),
        SerdeValue::F32(1.0),
        SerdeValue::F64(1.0),
        SerdeValue::Bool(true),
        SerdeValue::String("1".into()),
        SerdeValue::Unit,
    ] {
        assert_eq!(serde_value_u64(&value), None);
    }
}
