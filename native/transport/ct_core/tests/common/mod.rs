use bytes::Bytes;
use ct_core::{RawSocketSerializer, WampMessage, WampPayload};
use serde_json::{json, Value as JsonValue};
use serde_value::Value;
use std::collections::BTreeMap;

pub struct Scenario {
    pub name: &'static str,
    pub json: JsonValue,
}

pub fn scenarios() -> Vec<Scenario> {
    vec![
        Scenario {
            name: "hello",
            json: json!([1, "realm.one", {"roles": {"caller": {}}}]),
        },
        Scenario {
            name: "welcome",
            json: json!([2, 42, {"roles": {"broker": {}}}]),
        },
        Scenario {
            name: "abort",
            json: json!([
                3,
                {"message": "invalid"},
                "wamp.error.not_authorized",
                ["info"],
                {"retry": false}
            ]),
        },
        Scenario {
            name: "challenge",
            json: json!([4, "wampcra", {"challenge": "nonce"}]),
        },
        Scenario {
            name: "authenticate",
            json: json!([5, "signature", {"nonce": "abc"}]),
        },
        Scenario {
            name: "goodbye",
            json: json!([
                6,
                {"message": "bye"},
                "wamp.error.goodbye_and_out",
                ["take care"],
                {"code": 200}
            ]),
        },
        Scenario {
            name: "heartbeat",
            json: json!([7, {"interval": 1000}, 10, 20, 30]),
        },
        Scenario {
            name: "error",
            json: json!([
                8,
                48,
                9001,
                {"details": true},
                "wamp.error.generic",
                ["arg"],
                {"kw": 1}
            ]),
        },
        Scenario {
            name: "publish",
            json: json!([
                16,
                1,
                {"acknowledge": true},
                "com.example.topic",
                [1, 2],
                {"kw": 3}
            ]),
        },
        Scenario {
            name: "published",
            json: json!([17, 1, 777]),
        },
        Scenario {
            name: "subscribe",
            json: json!([32, 44, {"match": "prefix"}, "com.example.topic"]),
        },
        Scenario {
            name: "subscribed",
            json: json!([33, 44, 55]),
        },
        Scenario {
            name: "unsubscribe",
            json: json!([34, 44, 55]),
        },
        Scenario {
            name: "unsubscribed",
            json: json!([35, 44, {"reason": "done"}]),
        },
        Scenario {
            name: "event",
            json: json!([
                36,
                100,
                200,
                {"publisher": 2, "topic": "com.example.topic"},
                [1],
                {"flag": true}
            ]),
        },
        Scenario {
            name: "call",
            json: json!([
                48,
                500,
                {"timeout": 100},
                "com.example.proc",
                ["arg"],
                {"kw": "value"}
            ]),
        },
        Scenario {
            name: "cancel",
            json: json!([49, 500, {"mode": "kill"}]),
        },
        Scenario {
            name: "result",
            json: json!([
                50,
                500,
                {"progress": false},
                ["res"],
                {"meta": 1}
            ]),
        },
        Scenario {
            name: "register",
            json: json!([64, 501, {"match": "wildcard"}, "com.example.proc"]),
        },
        Scenario {
            name: "registered",
            json: json!([65, 501, 678]),
        },
        Scenario {
            name: "unregister",
            json: json!([66, 501, 678]),
        },
        Scenario {
            name: "unregistered",
            json: json!([67, 501]),
        },
        Scenario {
            name: "invocation",
            json: json!([
                68,
                700,
                800,
                {"caller": 1},
                ["arg"],
                {"kw": true}
            ]),
        },
        Scenario {
            name: "interrupt",
            json: json!([69, 700, {"mode": "killnowait"}]),
        },
        Scenario {
            name: "yield",
            json: json!([
                70,
                700,
                {"progress": true},
                ["interim"],
                {"status": "ok"}
            ]),
        },
        Scenario {
            name: "cbor_binary",
            json: json!([
                8,
                48,
                9001,
                {"details": true},
                "wamp.error.generic",
                [{"bin": "AQID"}]
            ]),
        },
        Scenario {
            name: "unknown",
            json: json!([71, "extra", 5]),
        },
    ]
}

pub fn message_to_json(message: &WampMessage, serializer: RawSocketSerializer) -> JsonValue {
    match message {
        WampMessage::Hello { realm, details } => json!([1, realm, map_to_json(details)]),
        WampMessage::Welcome {
            session_id,
            details,
        } => json!([2, session_id, map_to_json(details)]),
        WampMessage::Abort {
            details,
            reason,
            payload,
        } => {
            let mut arr = vec![json!(3), map_to_json(details), json!(reason)];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Challenge { auth_method, extra } => {
            json!([4, auth_method, map_to_json(extra)])
        }
        WampMessage::Authenticate { signature, extra } => {
            json!([5, signature, map_to_json(extra)])
        }
        WampMessage::Goodbye {
            details,
            reason,
            payload,
        } => {
            let mut arr = vec![json!(6), map_to_json(details), json!(reason)];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Heartbeat {
            details,
            ping,
            incoming,
            outgoing,
        } => JsonValue::Array(vec![
            json!(7),
            map_to_json(details),
            json!(ping),
            json!(incoming),
            json!(outgoing),
        ]),
        WampMessage::Error {
            request_type,
            request_id,
            details,
            error,
            payload,
        } => {
            let mut arr = vec![
                json!(8),
                json!(request_type),
                json!(request_id),
                map_to_json(details),
                json!(error),
            ];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Publish {
            request_id,
            options,
            topic,
            payload,
        } => {
            let mut arr = vec![
                json!(16),
                json!(request_id),
                map_to_json(options),
                json!(topic),
            ];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Published {
            request_id,
            publication_id,
        } => json!([17, request_id, publication_id]),
        WampMessage::Subscribe {
            request_id,
            options,
            topic,
        } => json!([32, request_id, map_to_json(options), topic]),
        WampMessage::Subscribed {
            request_id,
            subscription_id,
        } => json!([33, request_id, subscription_id]),
        WampMessage::Unsubscribe {
            request_id,
            subscription_id,
        } => json!([34, request_id, subscription_id]),
        WampMessage::Unsubscribed {
            request_id,
            details,
        } => {
            json!([35, request_id, map_to_json(details)])
        }
        WampMessage::Event {
            subscription_id,
            publication_id,
            details,
            payload,
        } => {
            let mut arr = vec![
                json!(36),
                json!(subscription_id),
                json!(publication_id),
                map_to_json(details),
            ];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Call {
            request_id,
            options,
            procedure,
            payload,
        } => {
            let mut arr = vec![
                json!(48),
                json!(request_id),
                map_to_json(options),
                json!(procedure),
            ];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Cancel {
            request_id,
            options,
        } => {
            json!([49, request_id, map_to_json(options)])
        }
        WampMessage::Result {
            request_id,
            details,
            payload,
        } => {
            let mut arr = vec![json!(50), json!(request_id), map_to_json(details)];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Register {
            request_id,
            options,
            procedure,
        } => json!([64, request_id, map_to_json(options), procedure]),
        WampMessage::Registered {
            request_id,
            registration_id,
        } => json!([65, request_id, registration_id]),
        WampMessage::Unregister {
            request_id,
            registration_id,
        } => json!([66, request_id, registration_id]),
        WampMessage::Unregistered { request_id } => json!([67, request_id]),
        WampMessage::Invocation {
            request_id,
            registration_id,
            details,
            payload,
        } => {
            let mut arr = vec![
                json!(68),
                json!(request_id),
                json!(registration_id),
                map_to_json(details),
            ];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Interrupt {
            request_id,
            options,
        } => {
            json!([69, request_id, map_to_json(options)])
        }
        WampMessage::Yield {
            request_id,
            options,
            payload,
        } => {
            let mut arr = vec![json!(70), json!(request_id), map_to_json(options)];
            append_payload(&mut arr, payload, serializer);
            JsonValue::Array(arr)
        }
        WampMessage::Unknown { code, fields } => {
            let mut arr = vec![json!(code)];
            arr.extend(fields.iter().map(value_to_json));
            JsonValue::Array(arr)
        }
    }
}

fn append_payload(
    array: &mut Vec<JsonValue>,
    payload: &WampPayload,
    serializer: RawSocketSerializer,
) {
    if let Some(args) = payload.args.as_ref() {
        array.push(decode_payload(serializer, args));
        if let Some(kwargs) = payload.kwargs.as_ref() {
            array.push(decode_payload(serializer, kwargs));
        }
    } else if let Some(kwargs) = payload.kwargs.as_ref() {
        array.push(JsonValue::Array(vec![]));
        array.push(decode_payload(serializer, kwargs));
    }
}

fn decode_payload(serializer: RawSocketSerializer, bytes: &Bytes) -> JsonValue {
    match serializer {
        RawSocketSerializer::Json => serde_json::from_slice(bytes).expect("decode json"),
        RawSocketSerializer::MessagePack => rmp_serde::from_slice(bytes).expect("decode msgpack"),
        RawSocketSerializer::Cbor => serde_cbor::from_slice(bytes).expect("decode cbor"),
        RawSocketSerializer::Ubjson | RawSocketSerializer::Flatbuffers => {
            panic!("unsupported serializer for payload decoding")
        }
    }
}

fn map_to_json(map: &BTreeMap<Value, Value>) -> JsonValue {
    serde_json::to_value(map).expect("map to json")
}

fn value_to_json(value: &Value) -> JsonValue {
    serde_json::to_value(value).expect("value to json")
}
