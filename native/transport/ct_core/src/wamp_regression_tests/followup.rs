use super::*;

fn accepted<T: std::fmt::Debug>(result: Result<T, ParseError>) -> T {
    assert_eq!(
        result.as_ref().err().map(|error| format!("{error:?}")),
        None
    );
    result.assert_success()
}

#[test]
fn cbor_all_payload_messages_retain_original_encoding_and_allocation() {
    let args = Bytes::from_static(&[0x9f, 0x18, 0x01, 0x43, 0, 0x80, 0xff, 0xff]);
    let kwargs = Bytes::from_static(&[0xbf, 0x61, b'k', 0x18, 0x02, 0xff]);
    let mut checked = 0;
    for (template, mut expected, _) in message_cases() {
        let Some(expected_payload) = payload_mut(&mut expected) else {
            continue;
        };
        *expected_payload = Payload {
            args: Some(args.clone()),
            kwargs: Some(kwargs.clone()),
        };
        let mut data = wire(Serializer::Cbor, &template).to_vec();
        assert_condition!((0x80..=0x97).contains(&data[0]));
        data[0] += 2;
        let args_start = data.len();
        data.extend_from_slice(&args);
        let kwargs_start = data.len();
        data.extend_from_slice(&kwargs);
        let raw = Bytes::from(data);
        let mut parsed = accepted(parse_message(Serializer::Cbor, raw.clone()));
        assert_eq!(parsed.message, expected);
        let payload = payload_mut(&mut parsed.message).assert_success();
        assert_eq!(
            payload.args.as_ref().assert_success().as_ptr(),
            raw[args_start..].as_ptr()
        );
        assert_eq!(
            payload.kwargs.as_ref().assert_success().as_ptr(),
            raw[kwargs_start..].as_ptr()
        );
        drop(parsed.raw);
        drop(raw);
        assert_eq!(payload.args.as_ref(), Some(&args));
        assert_eq!(payload.kwargs.as_ref(), Some(&kwargs));
        checked += 1;
    }
    assert_eq!(checked, 9);
}

#[test]
fn cbor_header_widths_preserve_every_byte_and_accept_exact_empty_headers() {
    for (header, width, expected) in [
        (vec![0x98, 0xa5], 1, 0xa5u64),
        (vec![0x99, 0x12, 0x34], 2, 0x1234),
        (vec![0x9a, 0x12, 0x34, 0x56, 0x78], 4, 0x1234_5678),
        (
            vec![0x9b, 1, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef],
            8,
            0x0123_4567_89ab_cdef,
        ),
    ] {
        assert_eq!(accepted(cbor_header_integer(&header, width)), expected);
        if let Ok(length) = usize::try_from(expected) {
            assert_eq!(
                accepted(cbor_array_header(&header)),
                (width + 1, Some(length))
            );
        } else {
            assert_condition!(cbor_array_header(&header).is_err());
        }
        for len in 0..header.len() {
            assert_condition!(matches!(
                cbor_header_integer(&header[..len], width),
                Err(ParseError::Deserialize(_))
            ));
        }
        let mut empty = vec![header[0]];
        empty.resize(width + 1, 0);
        assert_eq!(accepted(cbor_array_header(&empty)), (width + 1, Some(0)));
        assert_condition!(matches!(
            parse_message(Serializer::Cbor, Bytes::from(empty)),
            Err(ParseError::MissingElement("message code"))
        ));
    }
}

#[test]
fn msgpack_length_words_preserve_nonzero_bytes_at_each_offset_and_segment() {
    for prefix in 0..=4 {
        let mut bytes = vec![0xee; prefix];
        bytes.extend([0x12, 0x34, 0x56, 0x78, 0x7f]);
        let raw = Bytes::from(bytes);
        for split in 0..=raw.len() {
            for frame in [
                RawFrame::Contiguous(raw.clone()),
                RawFrame::from_segments(fragments(&raw, split)),
            ] {
                let mut offset = prefix;
                assert_eq!(accepted(read_u16(&frame, &mut offset)), 0x1234);
                assert_eq!(offset, prefix + 2);
                assert_eq!(accepted(read_u16(&frame, &mut offset)), 0x5678);
                assert_eq!(offset, prefix + 4);
                assert_eq!(accepted(read_u8(&frame, &mut offset)), 0x7f);
                let mut offset = prefix;
                assert_eq!(accepted(read_u32(&frame, &mut offset)), 0x1234_5678);
                assert_eq!(offset, prefix + 4);
                assert_eq!(accepted(read_u8(&frame, &mut offset)), 0x7f);
            }
        }
        for width in [2, 4] {
            for available in 0..width {
                let raw = raw.slice(..prefix + available);
                for frame in [
                    RawFrame::Contiguous(raw.clone()),
                    RawFrame::from_segments(fragments(&raw, raw.len() / 2)),
                ] {
                    let mut offset = prefix;
                    let result = if width == 2 {
                        read_u16(&frame, &mut offset).map(u32::from)
                    } else {
                        read_u32(&frame, &mut offset)
                    };
                    assert_condition!(matches!(result, Err(ParseError::Deserialize(_))));
                    assert_eq!(offset, prefix);
                }
            }
        }
    }
}

#[test]
fn msgpack_payload_collection_headers_preserve_wire_bytes_at_all_widths() {
    for count in [0, 1] {
        for mut args in [
            vec![0x90 + count],
            vec![0xdc, 0, count],
            vec![0xdd, 0, 0, 0, count],
        ] {
            if count == 1 {
                args.push(0xc3);
            }
            for mut kwargs in [
                vec![0x80 + count],
                vec![0xde, 0, count],
                vec![0xdf, 0, 0, 0, count],
            ] {
                if count == 1 {
                    kwargs.extend([0xa1, b'k', 0xc2]);
                }
                let mut bytes = vec![0x95, 50, 7, 0x80];
                bytes.extend(&args);
                bytes.extend(&kwargs);
                let raw = Bytes::from(bytes);
                let expected = WampMessage::Result {
                    request_id: 7,
                    details: ValueMap::new(),
                    payload: Payload {
                        args: Some(Bytes::from(args.clone())),
                        kwargs: Some(Bytes::from(kwargs.clone())),
                    },
                };
                assert_eq!(
                    accepted(parse_message(Serializer::MessagePack, raw.clone())).message,
                    expected
                );
                for split in 0..=raw.len() {
                    assert_eq!(
                        accepted(parse_message_segments(
                            Serializer::MessagePack,
                            fragments(&raw, split)
                        ))
                        .message,
                        expected
                    );
                }
            }
        }
    }
}

#[test]
fn heartbeat_null_counters_preserve_existing_serializer_contracts() {
    for serializer in SERIALIZERS {
        for ping in [None, Some(17u64)] {
            for incoming in [None, Some(29u64)] {
                for outgoing in [None, Some(43u64)] {
                    let value = json!([7, {}, ping, incoming, outgoing]);
                    let expected = WampMessage::Heartbeat {
                        details: ValueMap::new(),
                        ping,
                        incoming,
                        outgoing,
                    };
                    let missing = [ping, incoming, outgoing].iter().position(Option::is_none);
                    if serializer == Serializer::Cbor && missing.is_some() {
                        let label = ["heartbeat.ping", "heartbeat.incoming", "heartbeat.outgoing"]
                            [missing.assert_success()];
                        let raw = wire(serializer, &value);
                        assert_condition!(
                            matches!(parse_message(serializer, raw.clone()), Err(ParseError::ExpectedIdentifier(actual)) if actual == label)
                        );
                        for split in 0..=raw.len() {
                            assert_condition!(
                                matches!(parse_message_segments(serializer, fragments(&raw, split)), Err(ParseError::ExpectedIdentifier(actual)) if actual == label)
                            );
                        }
                    } else {
                        check_valid(serializer, &value, &expected);
                    }
                }
            }
        }
    }
}

#[test]
fn call_identifiers_preserve_integer_widths_and_reject_negative_wraparound() {
    for serializer in SERIALIZERS {
        for request_id in [
            1u64,
            255,
            256,
            65_535,
            65_536,
            4_294_967_295,
            4_294_967_296,
            9_007_199_254_740_991,
        ] {
            let value = json!([48, request_id, {}, "com.example.echo"]);
            let expected = WampMessage::Call {
                request_id,
                options: ValueMap::new(),
                procedure: "com.example.echo".into(),
                payload: Payload::default(),
            };
            check_valid(serializer, &value, &expected);
        }
        for request_id in [
            -1i64,
            -128,
            -129,
            -32_768,
            -32_769,
            -2_147_483_648,
            -2_147_483_649,
            i64::MIN,
        ] {
            let value = json!([48, request_id, {}, "com.example.echo"]);
            let raw = wire(serializer, &value);
            assert_condition!(matches!(
                parse_message(serializer, raw.clone()),
                Err(ParseError::ExpectedIdentifier("call.request_id"))
            ));
            for split in 0..=raw.len() {
                assert_condition!(matches!(
                    parse_message_segments(serializer, fragments(&raw, split)),
                    Err(ParseError::ExpectedIdentifier("call.request_id"))
                ));
            }
        }
    }
}
