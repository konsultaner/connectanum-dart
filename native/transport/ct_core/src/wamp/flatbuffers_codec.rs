use super::{
    flatbuffers_cbor, flatbuffers_schema as schema, flatbuffers_wire as wire, ParseError,
    ParsedMessage, Payload, RawFrame, Serializer, ValueMap, WampMessage,
};
use serde_value::Value as CborValue;
use wire::{Fields, Value};

pub(super) fn parse(raw: RawFrame) -> Result<ParsedMessage, ParseError> {
    if raw.len() > wire::MAX_BYTES {
        return Err(wire::invalid("byte limit"));
    }
    let bytes = raw.into_bytes();
    let fields = wire::read(bytes.clone())?;
    let tag = integer(&fields, "msg_type")? as usize;
    let reference = *schema::TABLES[schema::ROOT].fields[1]
        .values
        .get(tag)
        .ok_or_else(|| wire::invalid("union discriminator"))?;
    let reference = usize::try_from(reference).map_err(|_| wire::invalid("union discriminator"))?;
    let name = schema::TABLES[reference].name;
    let body = match fields.get("msg") {
        Some(Value::Table(table)) => table,
        _ => return Err(wire::invalid("message table")),
    };
    if name != "Welcome" && name != "Heartbeat" && integer(body, "session")? != 0 {
        return Err(wire::invalid("non-WELCOME session"));
    }
    let no_dictionary = [
        "Published",
        "Subscribed",
        "Unsubscribe",
        "Registered",
        "Unregister",
        "EventReceived",
    ]
    .contains(&name);
    let dictionary = match fields.get("metadata") {
        Some(Value::Bytes(bytes)) if !no_dictionary => {
            flatbuffers_cbor::validate(bytes, 5, true)?;
            match serde_cbor::from_slice::<CborValue>(bytes)
                .map_err(|_| wire::invalid("metadata value"))?
            {
                CborValue::Map(map) => map,
                _ => return Err(wire::invalid("metadata dictionary")),
            }
        }
        Some(Value::Null) if no_dictionary => ValueMap::new(),
        _ => return Err(wire::invalid("metadata presence")),
    };
    let encoded_metadata = match fields.get("metadata") {
        Some(Value::Bytes(bytes)) => Some(bytes.clone()),
        _ => None,
    };
    if name != "Heartbeat" {
        super::flatbuffers_projection::agree(name, body, &dictionary, reference)?;
    }
    let args = byte_vector(body, "args")?;
    let kwargs = byte_vector(body, "kwargs")?;
    let transparent = byte_vector(body, "payload")?;
    if transparent.is_some() && (args.is_some() || kwargs.is_some()) {
        return Err(wire::invalid("mixed transparent and ordinary payload"));
    }
    if let Some(args) = &args {
        flatbuffers_cbor::validate(args, 4, false)?;
    }
    if let Some(kwargs) = &kwargs {
        flatbuffers_cbor::validate(kwargs, 5, false)?;
    }
    let payload = Payload {
        args,
        kwargs,
        transparent,
    };
    let request = || integer(body, "request");
    let message = match name {
        "Hello" => WampMessage::Hello {
            realm: text(body, "realm")?,
            details: dictionary,
        },
        "Welcome" => WampMessage::Welcome {
            session_id: integer(body, "session")?,
            details: dictionary,
        },
        "Abort" => WampMessage::Abort {
            reason: text(body, "reason")?,
            details: dictionary,
            payload,
        },
        "Challenge" => WampMessage::Challenge {
            auth_method: challenge(body)?,
            extra: dictionary,
        },
        "Authenticate" => WampMessage::Authenticate {
            signature: text(body, "signature")?,
            extra: dictionary,
        },
        "Goodbye" => WampMessage::Goodbye {
            reason: text(body, "reason")?,
            details: dictionary,
            payload,
        },
        "Heartbeat" => {
            let presence = integer(body, "presence")?;
            if presence & !7 != 0 {
                return Err(wire::invalid("HEARTBEAT presence"));
            }
            let control = |name, bit| -> Result<Option<u64>, ParseError> {
                let value = integer(body, name)?;
                if presence & bit == 0 {
                    if value != 0 {
                        return Err(wire::invalid("absent HEARTBEAT control"));
                    }
                    Ok(None)
                } else {
                    Ok(Some(value))
                }
            };
            WampMessage::Heartbeat {
                details: dictionary,
                ping: control("ping", 1)?,
                incoming: control("incoming", 2)?,
                outgoing: control("outgoing", 4)?,
            }
        }
        "Error" => {
            let request_type = integer(body, "request_type")?;
            if ![16, 32, 34, 48, 64, 66, 68].contains(&request_type) {
                return Err(wire::invalid("ERROR request type"));
            }
            WampMessage::Error {
                request_type,
                request_id: request()?,
                error: text(body, "error")?,
                details: dictionary,
                payload,
            }
        }
        "Publish" => WampMessage::Publish {
            request_id: request()?,
            topic: text(body, "topic")?,
            options: dictionary,
            payload,
        },
        "Published" => WampMessage::Published {
            request_id: request()?,
            publication_id: integer(body, "publication")?,
        },
        "Subscribe" => WampMessage::Subscribe {
            request_id: request()?,
            topic: text(body, "topic")?,
            options: dictionary,
        },
        "Subscribed" => WampMessage::Subscribed {
            request_id: request()?,
            subscription_id: integer(body, "subscription")?,
        },
        "Unsubscribe" => WampMessage::Unsubscribe {
            request_id: request()?,
            subscription_id: integer(body, "subscription")?,
        },
        "Unsubscribed" => WampMessage::Unsubscribed {
            request_id: request()?,
            details: dictionary,
        },
        "Event" => WampMessage::Event {
            subscription_id: integer(body, "subscription")?,
            publication_id: integer(body, "publication")?,
            details: dictionary,
            payload,
        },
        "Call" => WampMessage::Call {
            request_id: request()?,
            procedure: text(body, "procedure")?,
            options: dictionary,
            payload,
        },
        "Cancel" => WampMessage::Cancel {
            request_id: request()?,
            options: dictionary,
        },
        "Result" => WampMessage::Result {
            request_id: request()?,
            details: dictionary,
            payload,
        },
        "Register" => WampMessage::Register {
            request_id: request()?,
            procedure: text(body, "procedure")?,
            options: dictionary,
        },
        "Registered" => WampMessage::Registered {
            request_id: request()?,
            registration_id: integer(body, "registration")?,
        },
        "Unregister" => WampMessage::Unregister {
            request_id: request()?,
            registration_id: integer(body, "registration")?,
        },
        "Unregistered" => WampMessage::Unregistered {
            request_id: request()?,
            details: dictionary,
        },
        "Invocation" => WampMessage::Invocation {
            request_id: request()?,
            registration_id: integer(body, "registration")?,
            details: dictionary,
            payload,
        },
        "Interrupt" => WampMessage::Interrupt {
            request_id: request()?,
            options: dictionary,
        },
        "Yield" => WampMessage::Yield {
            request_id: request()?,
            options: dictionary,
            payload,
        },
        _ => return Err(wire::invalid("unsupported message type")),
    };
    Ok(ParsedMessage {
        message,
        raw: RawFrame::Contiguous(bytes),
        serializer: Serializer::Flatbuffers,
        encoded_metadata,
    })
}
fn integer(fields: &Fields, key: &'static str) -> Result<u64, ParseError> {
    match fields.get(key) {
        Some(Value::Integer(value)) => Ok(*value),
        _ => Err(wire::invalid("integer field")),
    }
}
fn text(fields: &Fields, key: &'static str) -> Result<String, ParseError> {
    match fields.get(key) {
        Some(Value::Text(value)) => Ok(value.to_string()),
        _ => Err(wire::invalid("text field")),
    }
}
fn byte_vector(fields: &Fields, key: &'static str) -> Result<Option<bytes::Bytes>, ParseError> {
    match fields.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Bytes(value)) => Ok(Some(value.clone())),
        _ => Err(wire::invalid("byte vector")),
    }
}
fn challenge(body: &Fields) -> Result<String, ParseError> {
    const METHODS: [&str; 5] = ["anonymous", "ticket", "wampcra", "wamp-scram", "cryptosign"];
    let method = integer(body, "method")? as usize;
    let known = METHODS
        .get(method)
        .ok_or_else(|| wire::invalid("authentication method"))?;
    match body.get("method_name") {
        Some(Value::Text(name)) if !name.is_empty() => {
            if METHODS.contains(&name.as_ref()) {
                if name.as_ref() != *known {
                    return Err(wire::invalid("contradictory authentication method"));
                }
            } else if method != 0 {
                return Err(wire::invalid("custom authentication method"));
            }
            Ok(name.to_string())
        }
        Some(Value::Null) => Ok(known.to_string()),
        _ => Err(wire::invalid("authentication method name")),
    }
}

#[cfg(test)]
mod tests {
    use super::super::flatbuffers_generated::wamp::proto as generated;
    use super::*;
    use bytes::Bytes;
    use flatbuffers::FlatBufferBuilder;

    fn call(timeout: u32, metadata: &[u8], args: Option<&[u8]>, kwargs: Option<&[u8]>) -> Bytes {
        let mut builder = FlatBufferBuilder::new();
        let procedure = builder.create_string("com.example.proc");
        let metadata = builder.create_vector(metadata);
        let args = args.map(|bytes| builder.create_vector(bytes));
        let kwargs = kwargs.map(|bytes| builder.create_vector(bytes));
        let call = generated::Call::create(
            &mut builder,
            &generated::CallArgs {
                request: 77,
                procedure: Some(procedure),
                timeout,
                args,
                kwargs,
                ..Default::default()
            },
        );
        let root = generated::Message::create(
            &mut builder,
            &generated::MessageArgs {
                msg_type: generated::AnyMessage::Call,
                msg: Some(call.as_union_value()),
                metadata: Some(metadata),
            },
        );
        generated::finish_message_buffer(&mut builder, root);
        Bytes::copy_from_slice(builder.finished_data())
    }

    #[test]
    fn contradictory_typed_metadata_is_rejected() {
        let metadata = serde_cbor::to_vec(&ValueMap::from([(
            CborValue::String("timeout".into()),
            CborValue::U64(4),
        )]))
        .unwrap();
        assert!(parse(RawFrame::Contiguous(call(3, &metadata, None, None))).is_err());
        assert!(parse(RawFrame::Contiguous(call(4, &metadata, None, None))).is_ok());
    }

    #[test]
    fn payload_slices_keep_the_original_allocation_alive() {
        let frame = call(
            0,
            &[0xa0],
            Some(&[0x82, 1, 2]),
            Some(&[0xa1, 0x61, b'x', 3]),
        );
        let root = generated::root_as_message(&frame).unwrap();
        let expected = root.msg_as_call().unwrap().args().unwrap().bytes().as_ptr();
        let parsed = parse(RawFrame::Contiguous(frame.clone())).unwrap();
        let WampMessage::Call { payload, .. } = parsed.message else {
            panic!("CALL expected");
        };
        drop(frame);
        drop(parsed.raw);
        assert_eq!(payload.args.as_ref().unwrap().as_ptr(), expected);
        assert_eq!(payload.args.unwrap().as_ref(), &[0x82, 1, 2]);
        assert_eq!(payload.kwargs.unwrap().as_ref(), &[0xa1, 0x61, b'x', 3]);
    }

    #[test]
    fn invalid_cbor_boundaries_and_dictionary_keys_are_rejected() {
        for metadata in [&[0x80][..], &[0xa1, 1, 2], &[0xa0, 0], &[0xa1, 0x61, b'x']] {
            assert!(parse(RawFrame::Contiguous(call(0, metadata, None, None))).is_err());
        }
        for args in [&[0xa0][..], &[0x81], &[0x80, 0]] {
            assert!(parse(RawFrame::Contiguous(call(0, &[0xa0], Some(args), None))).is_err());
        }
        for kwargs in [
            &[0x80][..],
            &[0xa1, 1, 2],
            &[0xa2, 0x61, b'x', 1, 0x61, b'x', 2],
        ] {
            assert!(parse(RawFrame::Contiguous(call(0, &[0xa0], None, Some(kwargs)))).is_err());
        }
        // Numeric keys in maps nested inside ordinary arguments are legal.
        assert!(parse(RawFrame::Contiguous(call(
            0,
            &[0xa0],
            Some(&[0x81, 0xa1, 1, 2]),
            None
        )))
        .is_ok());
    }

    #[test]
    fn segmented_frames_preserve_encoded_payload_values() {
        let bytes = call(0, &[0xa0], Some(&[0x81, 0x01]), None);
        for split in 0..=bytes.len() {
            let parsed = parse(RawFrame::from_segments(vec![
                bytes.slice(..split),
                bytes.slice(split..),
            ]))
            .unwrap();
            let WampMessage::Call { payload, .. } = parsed.message else {
                panic!("CALL expected");
            };
            assert_eq!(payload.args.unwrap().as_ref(), &[0x81, 0x01]);
            assert!(parsed.raw.as_contiguous().is_some());
        }
    }

    #[test]
    fn identifiers_accept_the_portable_limit_and_reject_larger_values() {
        let original = call(0, &[0xa0], None, None);
        let root = generated::root_as_message(&original).unwrap();
        let table = root.msg_as_call().unwrap()._tab;
        let field = table.loc() + table.vtable().get(generated::Call::VT_REQUEST) as usize;
        for (value, valid) in [
            (9_007_199_254_740_992u64, true),
            (9_007_199_254_740_993, false),
            (u64::MAX, false),
        ] {
            let mut bytes = original.to_vec();
            bytes[field..field + 8].copy_from_slice(&value.to_le_bytes());
            assert_eq!(
                parse(RawFrame::Contiguous(Bytes::from(bytes))).is_ok(),
                valid,
                "{value}"
            );
        }
    }

    #[test]
    fn bounded_reader_accepts_all_pinned_fixtures_and_never_panics_on_mutations() {
        let cases: Vec<serde_json::Value> = serde_json::from_str(include_str!(
            "../../../../../schemas/wamp_flatbuffers/fixtures.json"
        ))
        .unwrap();
        for case in cases {
            let name = case["name"].as_str().unwrap();
            let bytes = Bytes::from(
                std::fs::read(
                    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                        .join("../../../schemas/wamp_flatbuffers/fixtures")
                        .join(format!("{name}.bin")),
                )
                .unwrap(),
            );
            assert!(wire::read(bytes.clone()).is_ok(), "{name}");
            for length in 0..bytes.len() {
                assert!(
                    std::panic::catch_unwind(|| parse(RawFrame::Contiguous(bytes.slice(..length))))
                        .is_ok(),
                    "{name} prefix {length}"
                );
            }
            for index in 0..bytes.len() {
                let mut changed = bytes.to_vec();
                changed[index] ^= 0xff;
                assert!(
                    std::panic::catch_unwind(|| parse(RawFrame::Contiguous(Bytes::from(changed))))
                        .is_ok(),
                    "{name} mutation {index}"
                );
            }
        }
    }
}
