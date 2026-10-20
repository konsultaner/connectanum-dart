use super::*;
use bytes::Bytes;
use serde_value::Value;

fn guarded(bytes: Vec<u8>) -> Bytes {
    let len = bytes.len();
    let mut allocation = vec![0xaa; 3];
    allocation.extend(bytes);
    allocation.extend([0xbb; 5]);
    Bytes::from(allocation).slice(3..3 + len)
}

fn assert_segments(message: WampMessage, payload: Payload) {
    let segments = encode_flatbuffers_message_segments(&message).unwrap();
    for bytes in [&payload.args, &payload.kwargs, &payload.transparent]
        .into_iter()
        .flatten()
    {
        if bytes.is_empty() {
            continue;
        }
        assert_eq!(
            segments
                .iter()
                .filter(|s| s.as_ptr() == bytes.as_ptr() && s.len() == bytes.len())
                .count(),
            1,
            "each application vector must retain its original allocation slice"
        );
    }
    let expected = parse_message(
        crate::rawsocket::Serializer::Flatbuffers,
        encode_flatbuffers_message(&message).unwrap(),
    )
    .unwrap()
    .message;
    drop(message);
    drop(payload);
    let wire = Bytes::from(
        segments
            .iter()
            .flat_map(|s| s.iter().copied())
            .collect::<Vec<_>>(),
    );
    super::flatbuffers_generated::wamp::proto::root_as_message(&wire)
        .expect("the pinned generated verifier accepts the assembled frame");
    let decoded = parse_message(crate::rawsocket::Serializer::Flatbuffers, wire.clone()).unwrap();
    assert_eq!(decoded.message, expected);
    for split in [0, 1, 3, wire.len() / 2, wire.len()] {
        let decoded = parse_message_segments(
            crate::rawsocket::Serializer::Flatbuffers,
            vec![wire.slice(..split), wire.slice(split..)],
        )
        .unwrap();
        assert_eq!(decoded.message, expected);
    }
}

#[test]
fn flatbuffers_segments_retain_application_allocations_and_valid_offsets() {
    for length in 0..40 {
        let args = guarded(
            serde_cbor::to_vec(&Value::Seq(vec![Value::Bytes(vec![0x5a; length])])).unwrap(),
        );
        let payload = Payload {
            args: Some(args),
            kwargs: Some(guarded(vec![0xa1, 0x61, b'k', 0x01])),
            transparent: None,
        };
        assert_segments(
            WampMessage::Call {
                request_id: 7,
                options: ValueMap::new(),
                procedure: "com.echo".into(),
                payload: payload.clone(),
            },
            payload,
        );
    }
}

#[test]
fn flatbuffers_segments_preserve_empty_absent_and_opaque_vectors() {
    for payload in [
        Payload::default(),
        Payload {
            args: None,
            kwargs: Some(guarded(vec![0xa0])),
            transparent: None,
        },
        Payload {
            args: None,
            kwargs: None,
            transparent: Some(Bytes::new()),
        },
        Payload {
            args: None,
            kwargs: None,
            transparent: Some(guarded(vec![0xff, 0, 0x80])),
        },
    ] {
        assert_segments(
            WampMessage::Event {
                subscription_id: 11,
                publication_id: 12,
                details: ValueMap::new(),
                payload: payload.clone(),
            },
            payload,
        );
    }
}

#[test]
fn flatbuffers_segments_keep_large_binary_payloads_in_their_original_storage() {
    let payload = Payload {
        args: Some(guarded(
            serde_cbor::to_vec(&Value::Seq(vec![Value::Bytes(vec![0x37; 128 * 1024])])).unwrap(),
        )),
        kwargs: None,
        transparent: None,
    };
    assert_segments(
        WampMessage::Result {
            request_id: 9,
            details: ValueMap::new(),
            payload: payload.clone(),
        },
        payload,
    );
}

#[test]
fn flatbuffers_segments_cover_all_public_models_with_the_generated_verifier() {
    let cases: Vec<serde_json::Value> = serde_json::from_str(include_str!(
        "../../../../../schemas/wamp_flatbuffers/codec_cases.json"
    ))
    .unwrap();
    assert_eq!(cases.len(), 25);
    for case in cases {
        let message = parse_message(
            crate::rawsocket::Serializer::Cbor,
            Bytes::from(serde_cbor::to_vec(&case["message"]).unwrap()),
        )
        .unwrap()
        .message;
        let payload = match &message {
            WampMessage::Publish { payload, .. }
            | WampMessage::Event { payload, .. }
            | WampMessage::Call { payload, .. }
            | WampMessage::Result { payload, .. }
            | WampMessage::Invocation { payload, .. }
            | WampMessage::Yield { payload, .. }
            | WampMessage::Error { payload, .. }
            | WampMessage::Abort { payload, .. }
            | WampMessage::Goodbye { payload, .. } => payload.clone(),
            _ => Payload::default(),
        };
        assert_segments(message, payload);
    }
}

#[test]
fn composed_flatbuffers_frames_cover_all_public_models_with_the_generated_verifier() {
    let cases: Vec<serde_json::Value> = serde_json::from_str(include_str!(
        "../../../../../schemas/wamp_flatbuffers/codec_cases.json"
    ))
    .unwrap();
    assert_eq!(cases.len(), 25);
    for case in cases {
        let expected = parse_message(
            crate::rawsocket::Serializer::Cbor,
            Bytes::from(serde_cbor::to_vec(&case["message"]).unwrap()),
        )
        .unwrap()
        .message;
        let mut control_message = expected.clone();
        let payload = match &mut control_message {
            WampMessage::Publish { payload, .. }
            | WampMessage::Event { payload, .. }
            | WampMessage::Call { payload, .. }
            | WampMessage::Result { payload, .. }
            | WampMessage::Invocation { payload, .. }
            | WampMessage::Yield { payload, .. }
            | WampMessage::Error { payload, .. }
            | WampMessage::Abort { payload, .. }
            | WampMessage::Goodbye { payload, .. } => std::mem::take(payload),
            _ => Payload::default(),
        };
        let control = encode_flatbuffers_message(&control_message).unwrap();
        let segments = compose_flatbuffers_message_segments(control, payload.clone()).unwrap();
        for bytes in [&payload.args, &payload.kwargs, &payload.transparent]
            .into_iter()
            .flatten()
        {
            assert_eq!(
                segments
                    .iter()
                    .filter(|part| part.as_ptr() == bytes.as_ptr() && part.len() == bytes.len())
                    .count(),
                1
            );
        }
        let wire = Bytes::from(
            segments
                .iter()
                .flat_map(|part| part.iter().copied())
                .collect::<Vec<_>>(),
        );
        super::flatbuffers_generated::wamp::proto::root_as_message(&wire)
            .expect("generated verifier accepts composed frame");
        assert_eq!(
            parse_message(crate::rawsocket::Serializer::Flatbuffers, wire)
                .unwrap()
                .message,
            expected
        );
    }
}

#[test]
fn codec_observation_distinguishes_borrowed_and_copied_application_vectors() {
    let message = WampMessage::Call {
        request_id: 7,
        options: ValueMap::new(),
        procedure: "com.echo".into(),
        payload: Payload {
            args: None,
            kwargs: None,
            transparent: Some(guarded(vec![0x5a; 129])),
        },
    };
    let before = codec_copy_metrics::observed_on_current_thread();
    let segments = encode_flatbuffers_message_segments(&message).unwrap();
    let borrowed = codec_copy_metrics::observed_on_current_thread();
    assert_eq!(
        borrowed.vector_copy_bytes_total - before.vector_copy_bytes_total,
        1 // the empty CBOR options dictionary; application bytes stay borrowed
    );
    let borrowed_strings = borrowed.string_copy_bytes_total - before.string_copy_bytes_total;
    assert!(
        borrowed_strings >= 16,
        "both UTF-8 model storage and wire writes are observed"
    );
    assert!(segments.iter().any(|part| part.len() == 129));
    encode_flatbuffers_message(&message).unwrap();
    let copied = codec_copy_metrics::observed_on_current_thread();
    assert_eq!(
        copied.vector_copy_bytes_total - borrowed.vector_copy_bytes_total,
        130 // application vector plus its one-byte options dictionary
    );
    assert_eq!(
        copied.string_copy_bytes_total - borrowed.string_copy_bytes_total,
        borrowed_strings
    );
}

#[test]
fn segmented_parser_counts_only_bytes_actually_read() {
    let before = codec_copy_metrics::observed_on_current_thread();
    let mut reader = SegmentedFrameReader::new(vec![
        Bytes::from_static(&[1, 2, 3]),
        Bytes::new(),
        Bytes::from_static(&[4, 5]),
    ]);
    let mut destination = [0; 4];
    assert_eq!(reader.read(&mut []).unwrap(), 0);
    assert_eq!(reader.read(&mut destination).unwrap(), 4);
    assert_eq!(destination, [1, 2, 3, 4]);
    assert_eq!(reader.read(&mut destination).unwrap(), 1);
    assert_eq!(destination[0], 5);
    assert_eq!(reader.read(&mut destination).unwrap(), 0);
    let after = codec_copy_metrics::observed_on_current_thread();
    assert_eq!(
        after.parser_read_copy_bytes_total - before.parser_read_copy_bytes_total,
        5
    );
}
