use super::{
    flatbuffers_cbor, flatbuffers_projection, flatbuffers_schema as schema,
    flatbuffers_wire::{self as wire, Fields, Value},
    flatbuffers_writer, ParseError, Payload, ValueMap, WampMessage,
};
use bytes::Bytes;
use serde_value::Value as Cbor;
use std::sync::Arc;

/// Encode the extended, pinned WAMP FlatBuffers binding.
/// Ordinary argument spans must already be CBOR; transparent spans remain opaque.
pub fn encode_segments(message: &WampMessage) -> Result<Vec<Bytes>, ParseError> {
    flatbuffers_writer::write_segments(&fields(message)?)
}

pub fn encode(message: &WampMessage) -> Result<Bytes, ParseError> {
    flatbuffers_writer::write(&fields(message)?)
}

fn fields(message: &WampMessage) -> Result<Fields, ParseError> {
    let mut controls = Fields::new();
    let (name, dictionary, payload): (&str, Option<&ValueMap>, Option<&Payload>) = match message {
        WampMessage::Hello { realm, details } => {
            text(&mut controls, "realm", realm);
            ("Hello", Some(details), None)
        }
        WampMessage::Welcome {
            session_id,
            details,
        } => {
            integer(&mut controls, "session", *session_id);
            ("Welcome", Some(details), None)
        }
        WampMessage::Abort {
            reason,
            details,
            payload,
        } => {
            text(&mut controls, "reason", reason);
            ("Abort", Some(details), Some(payload))
        }
        WampMessage::Challenge { auth_method, extra } => {
            if auth_method.is_empty() {
                return Err(wire::invalid("authentication method name"));
            }
            let known = ["anonymous", "ticket", "wampcra", "wamp-scram", "cryptosign"];
            integer(
                &mut controls,
                "method",
                known
                    .iter()
                    .position(|name| *name == auth_method)
                    .unwrap_or(0) as u64,
            );
            text(&mut controls, "method_name", auth_method);
            ("Challenge", Some(extra), None)
        }
        WampMessage::Authenticate { signature, extra } => {
            text(&mut controls, "signature", signature);
            ("Authenticate", Some(extra), None)
        }
        WampMessage::Goodbye {
            reason,
            details,
            payload,
        } => {
            text(&mut controls, "reason", reason);
            ("Goodbye", Some(details), Some(payload))
        }
        WampMessage::Heartbeat {
            details,
            ping,
            incoming,
            outgoing,
        } => {
            let mut presence = 0;
            for (key, value, bit) in [
                ("ping", ping, 1),
                ("incoming", incoming, 2),
                ("outgoing", outgoing, 4),
            ] {
                if let Some(value) = value {
                    integer(&mut controls, key, *value);
                    presence |= bit;
                }
            }
            integer(&mut controls, "presence", presence);
            ("Heartbeat", Some(details), None)
        }
        WampMessage::Error {
            request_type,
            request_id,
            error,
            details,
            payload,
        } => {
            if ![16, 32, 34, 48, 64, 66, 68].contains(request_type) {
                return Err(wire::invalid("ERROR request type"));
            }
            integer(&mut controls, "request_type", *request_type);
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "error", error);
            ("Error", Some(details), Some(payload))
        }
        WampMessage::Publish {
            request_id,
            topic,
            options,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "topic", topic);
            ("Publish", Some(options), Some(payload))
        }
        WampMessage::Published {
            request_id,
            publication_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "publication", *publication_id);
            ("Published", None, None)
        }
        WampMessage::Subscribe {
            request_id,
            topic,
            options,
        } => {
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "topic", topic);
            ("Subscribe", Some(options), None)
        }
        WampMessage::Subscribed {
            request_id,
            subscription_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "subscription", *subscription_id);
            ("Subscribed", None, None)
        }
        WampMessage::Unsubscribe {
            request_id,
            subscription_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "subscription", *subscription_id);
            ("Unsubscribe", None, None)
        }
        WampMessage::Unsubscribed {
            request_id,
            details,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Unsubscribed", Some(details), None)
        }
        WampMessage::Event {
            subscription_id,
            publication_id,
            details,
            payload,
        } => {
            integer(&mut controls, "subscription", *subscription_id);
            integer(&mut controls, "publication", *publication_id);
            ("Event", Some(details), Some(payload))
        }
        WampMessage::Call {
            request_id,
            procedure,
            options,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "procedure", procedure);
            ("Call", Some(options), Some(payload))
        }
        WampMessage::Cancel {
            request_id,
            options,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Cancel", Some(options), None)
        }
        WampMessage::Result {
            request_id,
            details,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Result", Some(details), Some(payload))
        }
        WampMessage::Register {
            request_id,
            procedure,
            options,
        } => {
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "procedure", procedure);
            ("Register", Some(options), None)
        }
        WampMessage::Registered {
            request_id,
            registration_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "registration", *registration_id);
            ("Registered", None, None)
        }
        WampMessage::Unregister {
            request_id,
            registration_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "registration", *registration_id);
            ("Unregister", None, None)
        }
        WampMessage::Unregistered {
            request_id,
            details,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Unregistered", Some(details), None)
        }
        WampMessage::Invocation {
            request_id,
            registration_id,
            details,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "registration", *registration_id);
            ("Invocation", Some(details), Some(payload))
        }
        WampMessage::Interrupt {
            request_id,
            options,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Interrupt", Some(options), None)
        }
        WampMessage::Yield {
            request_id,
            options,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Yield", Some(options), Some(payload))
        }
        WampMessage::Unknown { .. } => return Err(wire::invalid("unsupported message type")),
    };
    let reference = schema::TABLES
        .iter()
        .position(|table| table.name == name)
        .ok_or_else(|| wire::invalid("message table"))?;
    let tag = schema::TABLES[schema::ROOT].fields[1]
        .values
        .iter()
        .position(|value| *value == reference as i64)
        .ok_or_else(|| wire::invalid("union discriminator"))?;
    let mut body = if let Some(dictionary) = dictionary {
        validate_dictionary(dictionary)?;
        if name == "Heartbeat" {
            Fields::new()
        } else {
            flatbuffers_projection::project(name, dictionary, reference)?
        }
    } else {
        Fields::new()
    };
    body.extend(controls);
    if let Some(payload) = payload {
        if payload.transparent.is_some() && (payload.args.is_some() || payload.kwargs.is_some()) {
            return Err(wire::invalid("mixed transparent and ordinary payload"));
        }
        for (key, bytes, major) in [
            ("args", &payload.args, Some(4)),
            ("kwargs", &payload.kwargs, Some(5)),
            ("payload", &payload.transparent, None),
        ] {
            if let Some(bytes) = bytes {
                if let Some(major) = major {
                    flatbuffers_cbor::validate(bytes, major, false)?;
                }
                body.insert(key, Value::Bytes(bytes.clone()));
            }
        }
    }
    let mut root = Fields::from([
        ("msg_type", Value::Integer(tag as u64)),
        ("msg", Value::Table(Arc::new(body))),
    ]);
    if let Some(dictionary) = dictionary {
        let metadata =
            serde_cbor::to_vec(dictionary).map_err(|_| wire::invalid("metadata encoding"))?;
        flatbuffers_cbor::validate(&metadata, 5, true)?;
        root.insert("metadata", Value::Bytes(Bytes::from(metadata)));
    }
    Ok(root)
}
fn text(fields: &mut Fields, key: &'static str, value: &str) {
    fields.insert(key, Value::Text(Arc::from(value)));
}
fn integer(fields: &mut Fields, key: &'static str, value: u64) {
    fields.insert(key, Value::Integer(value));
}

// Validate before recursive serde serialization and before metadata projection.
fn validate_dictionary(dictionary: &ValueMap) -> Result<(), ParseError> {
    let mut stack = Vec::new();
    for (key, value) in dictionary {
        if !matches!(key, Cbor::String(_)) {
            return Err(wire::invalid("metadata dictionary key"));
        }
        stack.push((key, 1));
        stack.push((value, 1));
    }
    let mut size = 0usize;
    let mut items = 0usize;
    while let Some((value, depth)) = stack.pop() {
        items += 1;
        if depth > 64 || items > 1000000 {
            return Err(wire::invalid("metadata depth or item limit"));
        }
        let bytes = match value {
            Cbor::String(value) => value.len(),
            Cbor::Bytes(value) => value.len(),
            Cbor::Seq(values) => {
                for value in values {
                    stack.push((value, depth + 1));
                }
                0
            }
            Cbor::Map(map) => {
                for (key, value) in map {
                    if !matches!(key, Cbor::String(_)) {
                        return Err(wire::invalid("metadata dictionary key"));
                    }
                    stack.push((key, depth + 1));
                    stack.push((value, depth + 1));
                }
                0
            }
            Cbor::Newtype(value) | Cbor::Option(Some(value)) => {
                stack.push((value, depth + 1));
                0
            }
            _ => 0,
        };
        size = size
            .checked_add(bytes + 1)
            .ok_or_else(|| wire::invalid("metadata size"))?;
        if size > 1024 * 1024 {
            return Err(wire::invalid("metadata size"));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::super::{parse_message, Serializer};
    use super::*;

    #[test]
    fn all_public_messages_round_trip_without_a_whole_message_cbor_shim() {
        let cases: Vec<serde_json::Value> = serde_json::from_str(include_str!(
            "../../../../../schemas/wamp_flatbuffers/codec_cases.json"
        ))
        .unwrap();
        assert_eq!(cases.len(), 25);
        for case in cases {
            let name = case["name"].as_str().unwrap();
            let original = parse_message(
                Serializer::Cbor,
                Bytes::from(serde_cbor::to_vec(&case["message"]).unwrap()),
            )
            .unwrap();
            let frame = encode(&original.message).unwrap_or_else(|error| panic!("{name}: {error}"));
            let result = parse_message(Serializer::Flatbuffers, frame.clone())
                .unwrap_or_else(|error| panic!("{name}: {error}"));
            assert_eq!(result.message, original.message, "{name}");
            super::super::flatbuffers_generated::wamp::proto::root_as_message(&frame).unwrap();
            if let Ok(directory) = std::env::var("CONNECTANUM_FLATBUFFERS_CODEC_DIR") {
                let directory = std::path::Path::new(&directory);
                std::fs::write(directory.join(format!("rust_codec_{name}.bin")), &frame).unwrap();
                let dart_path = directory.join(format!("dart_codec_{name}.bin"));
                if dart_path.exists() {
                    let dart = parse_message(
                        Serializer::Flatbuffers,
                        Bytes::from(std::fs::read(dart_path).unwrap()),
                    )
                    .unwrap();
                    assert_eq!(dart.message, original.message, "Dart {name}");
                }
            }
        }
    }

    #[test]
    fn heartbeat_preserves_all_nullable_control_combinations() {
        for mask in 0..8 {
            let message = WampMessage::Heartbeat {
                details: ValueMap::new(),
                ping: (mask & 1 != 0).then_some(0),
                incoming: (mask & 2 != 0).then_some(0),
                outgoing: (mask & 4 != 0).then_some(0),
            };
            assert_eq!(
                parse_message(Serializer::Flatbuffers, encode(&message).unwrap())
                    .unwrap()
                    .message,
                message
            );
        }
    }

    #[test]
    fn unsupported_control_payloads_are_rejected_instead_of_lost() {
        let payload = Payload {
            args: Some(Bytes::from_static(&[0x81, 1])),
            ..Default::default()
        };
        for message in [
            WampMessage::Abort {
                details: ValueMap::new(),
                reason: "wamp.error.abort".into(),
                payload: payload.clone(),
            },
            WampMessage::Goodbye {
                details: ValueMap::new(),
                reason: "wamp.close.normal".into(),
                payload,
            },
        ] {
            assert!(encode(&message).is_err());
        }
    }

    #[test]
    fn unregistered_metadata_survives_native_model_reencoding() {
        use super::super::flatbuffers_generated::wamp::proto as generated;
        let mut builder = flatbuffers::FlatBufferBuilder::new();
        let metadata = serde_cbor::to_vec(&ValueMap::from([(
            Cbor::String("x_vendor".into()),
            Cbor::String("revoked".into()),
        )]))
        .unwrap();
        let metadata = builder.create_vector(&metadata);
        let body = generated::Unregistered::create(
            &mut builder,
            &generated::UnregisteredArgs {
                request: 16,
                ..Default::default()
            },
        );
        let root = generated::Message::create(
            &mut builder,
            &generated::MessageArgs {
                msg_type: generated::AnyMessage::Unregistered,
                msg: Some(body.as_union_value()),
                metadata: Some(metadata),
            },
        );
        generated::finish_message_buffer(&mut builder, root);
        let original = Bytes::copy_from_slice(builder.finished_data());
        let parsed = parse_message(Serializer::Flatbuffers, original.clone()).unwrap();
        let encoded = encode(&parsed.message).unwrap();
        let original = generated::root_as_message(&original).unwrap();
        let encoded = generated::root_as_message(&encoded).unwrap();
        assert_eq!(
            encoded.metadata().unwrap().bytes(),
            original.metadata().unwrap().bytes()
        );
    }

    #[test]
    fn transparent_payloads_remain_opaque_and_do_not_mix_with_cbor() {
        let mut message = WampMessage::Call {
            request_id: 1,
            procedure: "com.typed".into(),
            options: ValueMap::from([
                (
                    Cbor::String("ppt_scheme".into()),
                    Cbor::String("opaque".into()),
                ),
                (
                    Cbor::String("ppt_serializer".into()),
                    Cbor::String("flatbuffers".into()),
                ),
            ]),
            payload: Payload {
                transparent: Some(Bytes::from_static(&[0xff, 0, 0x80])),
                ..Default::default()
            },
        };
        let frame = encode(&message).unwrap();
        assert_eq!(
            parse_message(Serializer::Flatbuffers, frame)
                .unwrap()
                .message,
            message
        );
        let WampMessage::Call { payload, .. } = &mut message else {
            unreachable!()
        };
        payload.args = Some(Bytes::from_static(&[0x80]));
        assert!(encode(&message).is_err());
    }
}
