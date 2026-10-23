//! Sparse reader compatibility: metadata presence and scalar/reference defaults.
use super::flatbuffers_wire::Value as WireValue;
use super::{
    encode_flatbuffers_message, flatbuffers_codec, flatbuffers_wire, flatbuffers_writer, Payload,
    RawFrame, ValueMap, WampMessage,
};
use bytes::Bytes;
use serde_value::Value as Cbor;
use std::sync::Arc;

fn parse(frame: Bytes) -> Result<super::ParsedMessage, super::ParseError> {
    flatbuffers_codec::parse(RawFrame::Contiguous(frame))
}
fn metadata(frame: &Bytes, bytes: Option<Bytes>) -> Bytes {
    let original = flatbuffers_wire::read(frame.clone()).unwrap();
    let mut fields = original.as_ref().clone();
    if let Some(bytes) = bytes {
        fields.insert("metadata", WireValue::Bytes(bytes));
    } else {
        fields.remove("metadata");
    }
    flatbuffers_writer::write(&fields).unwrap()
}
fn roundtrip(message: &WampMessage) -> Bytes {
    let frame = encode_flatbuffers_message(message).unwrap();
    let parsed = parse(frame.clone()).unwrap();
    assert_eq!(parsed.message.code(), message.code());
    assert_eq!(encode_flatbuffers_message(&parsed.message).unwrap(), frame);
    frame
}

#[test]
fn flatbuffers_sparse_control_metadata_presence() {
    let controls = [
        WampMessage::Published {
            request_id: 1,
            publication_id: 2,
        },
        WampMessage::Subscribed {
            request_id: 1,
            subscription_id: 2,
        },
        WampMessage::Unsubscribe {
            request_id: 1,
            subscription_id: 2,
        },
        WampMessage::Registered {
            request_id: 1,
            registration_id: 2,
        },
        WampMessage::Unregister {
            request_id: 1,
            registration_id: 2,
        },
    ];
    for message in controls {
        let frame = roundtrip(&message);
        assert!(parse(metadata(&frame, Some(Bytes::from_static(b"\xa0")))).is_err());
    }
    // Empty required dictionaries remain present on the wire; omission must not
    // silently become an empty dictionary for other message kinds.
    let dictionaries = [
        WampMessage::Unsubscribed {
            request_id: 1,
            details: ValueMap::new(),
        },
        WampMessage::Unregistered {
            request_id: 1,
            details: ValueMap::new(),
        },
        WampMessage::Hello {
            realm: "realm".into(),
            details: ValueMap::new(),
        },
    ];
    for message in dictionaries {
        let frame = roundtrip(&message);
        assert!(parse(metadata(&frame, None)).is_err());
    }
}

#[test]
fn flatbuffers_sparse_map_null_and_known_methods() {
    for method in ["anonymous", "ticket", "wampcra", "wamp-scram", "cryptosign"] {
        let extra = ValueMap::from([(Cbor::String("nonce".into()), Cbor::Unit)]);
        let message = WampMessage::Challenge {
            auth_method: method.into(),
            extra: extra.clone(),
        };
        let canonical = roundtrip(&message);
        // The normal encoder deliberately projects only string-valued Map
        // entries and explicitly writes method_name. Build the valid alternate
        // typed-null/implicit-method representation to exercise both defaults.
        let mut fields = flatbuffers_wire::read(canonical.clone())
            .unwrap()
            .as_ref()
            .clone();
        let Some(WireValue::Table(body)) = fields.get_mut("msg") else {
            panic!("missing challenge table");
        };
        let body = Arc::make_mut(body);
        body.remove("method_name");
        body.insert(
            "extra",
            WireValue::Table(Arc::new(flatbuffers_wire::Fields::from([
                ("key", WireValue::Text("nonce".into())),
                ("value", WireValue::Null),
            ]))),
        );
        let frame = flatbuffers_writer::write(&fields).unwrap();
        let parsed = parse(frame.clone()).unwrap();
        assert_eq!(
            encode_flatbuffers_message(&parsed.message).unwrap(),
            canonical
        );
        match parsed.message {
            WampMessage::Challenge {
                auth_method,
                extra: parsed,
            } => {
                assert_eq!(auth_method, method);
                assert_eq!(parsed, extra);
            }
            _ => panic!("challenge kind changed"),
        }
        for contradictory in [
            ValueMap::new(),
            ValueMap::from([(
                Cbor::String("nonce".into()),
                Cbor::String("not a unit".into()),
            )]),
        ] {
            let bytes = Bytes::from(serde_cbor::to_vec(&contradictory).unwrap());
            assert!(parse(metadata(&frame, Some(bytes))).is_err());
        }
    }
}

#[test]
fn flatbuffers_sparse_scalar_defaults_and_false_metadata() {
    let message = WampMessage::Published {
        request_id: 0,
        publication_id: 0,
    };
    let frame = roundtrip(&message);
    match parse(frame).unwrap().message {
        WampMessage::Published {
            request_id,
            publication_id,
        } => {
            assert_eq!((request_id, publication_id), (0, 0));
        }
        _ => panic!("published kind changed"),
    }
    let options = ValueMap::from([(Cbor::String("acknowledge".into()), Cbor::Bool(false))]);
    let publish = WampMessage::Publish {
        request_id: 0,
        options: options.clone(),
        topic: "topic".into(),
        payload: Payload::default(),
    };
    let frame = roundtrip(&publish);
    match parse(frame).unwrap().message {
        WampMessage::Publish {
            request_id,
            options: parsed,
            ..
        } => {
            assert_eq!(request_id, 0);
            assert_eq!(parsed, options);
        }
        _ => panic!("publish kind changed"),
    }
}
