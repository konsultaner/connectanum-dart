use super::*;

#[test]
fn generic_value_codecs_preserve_nested_values_and_report_failures() {
    let value = Value::Seq(vec![
        Value::String("hello\u{1f642}".into()),
        Value::Bool(true),
        Value::Unit,
        Value::Map(BTreeMap::from([(
            Value::String("nested".into()),
            Value::Seq(vec![Value::Bool(false), Value::String("value".into())]),
        )])),
    ]);
    for serializer in SERIALIZERS {
        let expected_wire = wire(
            serializer,
            &json!(["hello\u{1f642}", true, null, {"nested": [false, "value"]}]),
        );
        let encoded = serialize_value(serializer, &value).assert_success();
        assert_eq!(encoded, expected_wire);
        for split in 0..=encoded.len() {
            for frame in [
                RawFrame::Contiguous(encoded.clone()),
                RawFrame::from_segments(fragments(&encoded, split)),
            ] {
                assert_eq!(
                    deserialize_value(serializer, &frame).assert_success(),
                    value
                );
            }
        }
        for frame in [
            RawFrame::Contiguous(Bytes::new()),
            RawFrame::Segmented {
                segments: vec![Bytes::new()],
                len: 0,
            },
        ] {
            assert_condition!(matches!(
                deserialize_value(serializer, &frame),
                Err(ParseError::Deserialize(_))
            ));
        }
    }
    for serializer in [Serializer::Ubjson, Serializer::Flatbuffers] {
        assert_condition!(matches!(
            serialize_value(serializer, &value),
            Err(ParseError::UnsupportedSerializer(actual)) if actual == serializer
        ));
        assert_condition!(matches!(
            deserialize_value(serializer, &RawFrame::Contiguous(Bytes::new())),
            Err(ParseError::UnsupportedSerializer(actual)) if actual == serializer
        ));
    }
    let invalid_json_key = Value::Map(BTreeMap::from([(
        Value::Seq(vec![Value::Bool(true)]),
        Value::Unit,
    )]));
    assert_condition!(matches!(
        serialize_value(Serializer::Json, &invalid_json_key),
        Err(ParseError::PayloadEncode(_))
    ));
}

#[test]
fn typed_field_helpers_preserve_signed_ids_unicode_and_error_labels() {
    for (value, expected) in [
        (Value::I8(0), 0),
        (Value::I8(127), 127),
        (Value::I16(1234), 1234),
        (Value::I32(123_456), 123_456),
        (Value::I64(i64::MAX), i64::MAX as u64),
    ] {
        assert_eq!(value_as_u64(&value, "id").assert_success(), expected);
    }
    for value in [
        Value::I8(-1),
        Value::I16(-1),
        Value::I32(-1),
        Value::I64(-1),
    ] {
        assert_condition!(matches!(
            value_as_u64(&value, "id"),
            Err(ParseError::ExpectedIdentifier("id"))
        ));
    }
    for (value, expected) in [
        (Value::String("com.example.echo".into()), "com.example.echo"),
        (Value::Char('x'), "x"),
        (Value::Char('\u{1f642}'), "\u{1f642}"),
    ] {
        assert_eq!(expect_string(&value, "uri").assert_success(), expected);
    }
    assert_condition!(matches!(
        expect_string(&Value::U8(7), "uri"),
        Err(ParseError::ExpectedString("uri"))
    ));
}

#[test]
fn payload_replacement_preserves_every_non_payload_message() {
    let mut count = 0;
    for (_, expected, _) in message_cases() {
        let mut actual = expected.clone();
        if payload_mut(&mut actual).is_some() {
            continue;
        }
        replace_message_payload(
            &mut actual,
            Payload {
                args: Some(Bytes::from_static(b"[true]")),
                kwargs: Some(Bytes::from_static(b"{\"flag\":false}")),
                transparent: None,
            },
        );
        assert_eq!(actual, expected);
        count += 1;
    }
    assert_eq!(count, 17);
}

#[test]
fn extracted_payload_preserves_present_empty_and_nested_values() {
    let arguments = Value::Seq(vec![
        Value::String("kept".into()),
        Value::U64(17),
        Value::Bool(true),
        Value::Map(BTreeMap::from([(
            Value::String("nested".into()),
            Value::Bool(false),
        )])),
    ]);
    let keywords = Value::Map(BTreeMap::from([
        (Value::String("flag".into()), Value::Bool(false)),
        (Value::String("unicode".into()), Value::String("☃".into())),
    ]));
    for serializer in SERIALIZERS {
        let payload = extract_payload(
            serializer,
            "args",
            Some(&arguments),
            "kwargs",
            Some(&keywords),
        )
        .assert_success();
        assert_eq!(
            payload.args,
            Some(wire(
                serializer,
                &json!(["kept", 17, true, {"nested": false}])
            ))
        );
        assert_eq!(
            payload.kwargs,
            Some(wire(serializer, &json!({"flag": false, "unicode": "☃"})))
        );
        assert_eq!(payload.transparent, None);
        let empty = extract_payload(
            serializer,
            "args",
            Some(&Value::Seq(vec![])),
            "kwargs",
            Some(&Value::Map(BTreeMap::new())),
        )
        .assert_success();
        assert_eq!(empty.args, Some(wire(serializer, &json!([]))));
        assert_eq!(empty.kwargs, Some(wire(serializer, &json!({}))));
        let absent = extract_payload(serializer, "args", Some(&Value::Unit), "kwargs", None)
            .assert_success();
        assert_eq!(absent.args, None);
        assert_eq!(absent.kwargs, None);
    }
}
