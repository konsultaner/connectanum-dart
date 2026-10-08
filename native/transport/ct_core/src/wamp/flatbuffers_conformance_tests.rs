use super::flatbuffers_generated::wamp::proto as wire;
use flatbuffers::FlatBufferBuilder;
use serde_json::Value;
use std::path::Path;

fn fixture(name: &str) -> Vec<u8> {
    std::fs::read(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../schemas/wamp_flatbuffers/fixtures")
            .join(format!("{name}.bin")),
    )
    .expect("checked-in FlatBuffers fixture")
}

#[test]
fn pinned_compiler_fixtures_verify_with_independent_message_discriminators() {
    let cases: Vec<Value> = serde_json::from_str(include_str!(
        "../../../../../schemas/wamp_flatbuffers/fixtures.json"
    ))
    .expect("fixture manifest");
    assert_eq!(cases.len(), 42);
    for case in cases {
        let name = case["name"].as_str().expect("case name");
        let bytes = fixture(name);
        let message = wire::root_as_message(&bytes).expect("verified fixture");
        assert_eq!(
            message.msg_type().0 as u64,
            case["union_tag"].as_u64().expect("union ordinal"),
            "{name}"
        );
        assert!(message.msg().loc() < bytes.len(), "{name}");
        match case["wire"].get("metadata") {
            Some(expected) => {
                let expected: Vec<u8> = serde_json::from_value(expected.clone()).unwrap();
                assert_eq!(message.metadata().unwrap().bytes(), expected, "{name}");
                assert!(
                    matches!(
                        serde_cbor::from_slice::<serde_cbor::Value>(&expected).unwrap(),
                        serde_cbor::Value::Map(_)
                    ),
                    "{name}"
                );
            }
            None => assert!(message.metadata().is_none(), "{name}"),
        }
        if name == "call_metadata" {
            assert_eq!(
                message.metadata().unwrap().bytes(),
                &[0xa1, 0x61, 0x78, 0x18, 0x2a]
            );
        } else if name == "heartbeat" {
            let heartbeat = message.msg_as_heartbeat().unwrap();
            assert_eq!(heartbeat.outgoing(), 3);
            assert_eq!(heartbeat.presence(), 7);
        } else if name.starts_with("heartbeat_zero_mask_") {
            let heartbeat = message.msg_as_heartbeat().unwrap();
            assert_eq!(
                heartbeat.presence() as u64,
                case["wire"]["msg"]["presence"].as_u64().unwrap()
            );
            assert_eq!(
                (heartbeat.ping(), heartbeat.incoming(), heartbeat.outgoing()),
                (0, 0, 0)
            );
        } else if name == "challenge_custom" || name == "challenge_scram_ack" {
            let challenge = message.msg_as_challenge().unwrap();
            assert_eq!(
                challenge.method_name(),
                case["wire"]["msg"]["method_name"].as_str()
            );
            assert_eq!(
                challenge.method(),
                if name == "challenge_custom" {
                    wire::AuthMethod::NULL
                } else {
                    wire::AuthMethod::SCRAM
                }
            );
        } else if name == "call_typed_payload" {
            let call = message.msg_as_call().unwrap();
            assert_eq!(call.ppt_scheme(), wire::PPTScheme::OPAQUE);
            assert_eq!(call.ppt_serializer(), wire::PPTSerializer::FLATBUFFERS);
            assert!(call.args().is_none());
            assert!(call.kwargs().is_none());
            let payload = call.payload().unwrap().bytes();
            let inner = wire::root_as_message(payload).unwrap();
            assert_eq!(inner.msg_as_call().unwrap().request(), 77);
            assert!(message.metadata().is_some());
        }
    }
}

#[test]
fn extension_builders_preserve_zero_presence_and_custom_method_control() {
    for mask in [0, 1, 7] {
        let mut builder = FlatBufferBuilder::new();
        let heartbeat = wire::Heartbeat::create(
            &mut builder,
            &wire::HeartbeatArgs {
                presence: mask,
                ..Default::default()
            },
        );
        let root = wire::Message::create(
            &mut builder,
            &wire::MessageArgs {
                msg_type: wire::AnyMessage::Heartbeat,
                msg: Some(heartbeat.as_union_value()),
                ..Default::default()
            },
        );
        wire::finish_message_buffer(&mut builder, root);
        let bytes = builder.finished_data();
        let root = wire::root_as_message(bytes).unwrap();
        let heartbeat = root.msg_as_heartbeat().unwrap();
        assert_eq!(heartbeat.presence(), mask);
        assert_eq!(
            (heartbeat.ping(), heartbeat.incoming(), heartbeat.outgoing()),
            (0, 0, 0)
        );
        if let Ok(directory) = std::env::var("CONNECTANUM_FLATBUFFERS_EMIT_DIR") {
            let directory = Path::new(&directory);
            std::fs::write(directory.join(format!("rust_heartbeat_{mask}.bin")), bytes).unwrap();
            let dart = std::fs::read(directory.join(format!("dart_heartbeat_{mask}.bin"))).unwrap();
            assert_eq!(
                wire::root_as_message(&dart)
                    .unwrap()
                    .msg_as_heartbeat()
                    .unwrap()
                    .presence(),
                mask
            );
        }
    }
    let mut builder = FlatBufferBuilder::new();
    let method = builder.create_string("com.example.custom");
    let challenge = wire::Challenge::create(
        &mut builder,
        &wire::ChallengeArgs {
            method: wire::AuthMethod::NULL,
            method_name: Some(method),
            ..Default::default()
        },
    );
    let root = wire::Message::create(
        &mut builder,
        &wire::MessageArgs {
            msg_type: wire::AnyMessage::Challenge,
            msg: Some(challenge.as_union_value()),
            ..Default::default()
        },
    );
    wire::finish_message_buffer(&mut builder, root);
    let bytes = builder.finished_data();
    let root = wire::root_as_message(bytes).unwrap();
    let challenge = root.msg_as_challenge().unwrap();
    assert_eq!(challenge.method(), wire::AuthMethod::NULL);
    assert_eq!(challenge.method_name(), Some("com.example.custom"));
    if let Ok(directory) = std::env::var("CONNECTANUM_FLATBUFFERS_EMIT_DIR") {
        let directory = Path::new(&directory);
        std::fs::write(directory.join("rust_challenge_custom.bin"), bytes).unwrap();
        let dart = std::fs::read(directory.join("dart_challenge_custom.bin")).unwrap();
        assert_eq!(
            wire::root_as_message(&dart)
                .unwrap()
                .msg_as_challenge()
                .unwrap()
                .method_name(),
            Some("com.example.custom")
        );
    }
}

#[test]
fn compiler_call_fields_and_binary_payload_are_borrowed_from_the_input() {
    let bytes = fixture("call");
    let message = wire::root_as_message(&bytes).unwrap();
    assert_eq!(message.msg_type(), wire::AnyMessage::Call);
    assert_eq!(wire::AnyMessage::Call.0, 16);
    assert_eq!(wire::MessageType::CALL.0, 48);
    let call = message.msg_as_call().unwrap();
    assert_eq!(call.request(), 77);
    assert_eq!(call.procedure(), "com.example.proc");
    assert_eq!(call.timeout(), 2500);
    assert!(call.receive_progress());
    let args = call.args().unwrap().bytes();
    let kwargs = call.kwargs().unwrap().bytes();
    assert_eq!(args, &[0x82, 1, 0x65, b'h', b'e', b'l', b'l', b'o']);
    assert_eq!(kwargs, &[0xa1, 0x63, b'k', b'e', b'y', 0x42, 0, 255]);
    let start = bytes.as_ptr() as usize;
    let end = start + bytes.len();
    for view in [args, kwargs] {
        assert!((start..end).contains(&(view.as_ptr() as usize)));
        assert!(view.as_ptr() as usize + view.len() <= end);
    }
}

#[test]
fn rust_builder_preserves_the_append_only_root_layout() {
    let mut builder = FlatBufferBuilder::new();
    let procedure = builder.create_string("com.example.proc");
    let args = builder.create_vector(&[0x82u8, 1, 0x65, b'h', b'e', b'l', b'l', b'o']);
    let metadata = builder.create_vector(&[0xa1u8, 0x61, 0x78, 0x18, 0x2a]);
    let call = wire::Call::create(
        &mut builder,
        &wire::CallArgs {
            request: 77,
            procedure: Some(procedure),
            args: Some(args),
            ..Default::default()
        },
    );
    let root = wire::Message::create(
        &mut builder,
        &wire::MessageArgs {
            msg_type: wire::AnyMessage::Call,
            msg: Some(call.as_union_value()),
            metadata: Some(metadata),
        },
    );
    wire::finish_message_buffer(&mut builder, root);
    let bytes = builder.finished_data();
    let message = wire::root_as_message(bytes).unwrap();
    assert_eq!(message.msg_type().0, 16);
    assert_eq!(message.msg_as_call().unwrap().request(), 77);
    assert_eq!(
        message.metadata().unwrap().bytes(),
        &[0xa1, 0x61, 0x78, 0x18, 0x2a]
    );
    if let Ok(directory) = std::env::var("CONNECTANUM_FLATBUFFERS_EMIT_DIR") {
        std::fs::create_dir_all(&directory).unwrap();
        std::fs::write(Path::new(&directory).join("rust_call_metadata.bin"), bytes).unwrap();
        let python = std::fs::read(Path::new(&directory).join("python_call.bin")).unwrap();
        let received = wire::root_as_message(&python).unwrap();
        let call = received.msg_as_call().unwrap();
        assert_eq!(call.request(), 77);
        assert_eq!(call.procedure(), "com.example.proc");
        assert_eq!(
            call.args().unwrap().bytes(),
            &[0x82, 1, 0x65, b'h', b'e', b'l', b'l', b'o']
        );
        assert!(received.metadata().is_none());
        let dart = std::fs::read(Path::new(&directory).join("dart_call_metadata.bin")).unwrap();
        assert_eq!(
            wire::root_as_message(&dart)
                .unwrap()
                .msg_as_call()
                .unwrap()
                .caller(),
            9007199254740992
        );
        let publication =
            std::fs::read(Path::new(&directory).join("dart_publish_ids.bin")).unwrap();
        let publication = wire::root_as_message(&publication).unwrap();
        assert_eq!(
            publication
                .msg_as_publish()
                .unwrap()
                .exclude()
                .unwrap()
                .iter()
                .collect::<Vec<_>>(),
            [1, 4294967296, 9007199254740991, 9007199254740992],
        );
        let empty =
            std::fs::read(Path::new(&directory).join("dart_publish_empty_ids.bin")).unwrap();
        let empty = wire::root_as_message(&empty).unwrap();
        assert!(empty
            .msg_as_publish()
            .unwrap()
            .exclude()
            .unwrap()
            .is_empty());
    }
}

#[test]
fn verifier_rejects_missing_roots_and_out_of_bounds_offsets() {
    let bytes = fixture("call");
    for length in 0..8 {
        assert!(wire::root_as_message(&bytes[..length]).is_err());
    }
    let mut bad = bytes.clone();
    bad[..4].copy_from_slice(&u32::MAX.to_le_bytes());
    assert!(wire::root_as_message(&bad).is_err());
}
