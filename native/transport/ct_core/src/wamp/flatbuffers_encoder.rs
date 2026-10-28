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
    if let WampMessage::Result {
        request_id,
        details,
        payload,
    } = message
    {
        if let Some(parts) = simple_ppt_result(*request_id, details, payload)? {
            return Ok(parts);
        }
    }
    flatbuffers_writer::write_segments(&fields(message)?)
}

// An opaque RESULT with only the two PPT strings has no additional controls
// to project. Use the pinned generated tables while keeping the complete
// dictionary and the original application allocation. Extended dictionaries
// and ordinary argument vectors retain the generic writer.
fn simple_ppt_result(
    request: u64,
    details: &ValueMap,
    payload: &Payload,
) -> Result<Option<Vec<Bytes>>, ParseError> {
    use super::codec_copy_metrics::{self, CodecAllocator};
    use super::flatbuffers_generated::wamp::proto as generated;
    if request == 0
        || request > 9_007_199_254_740_992
        || details.len() != 2
        || payload.args.is_some()
        || payload.kwargs.is_some()
    {
        return Ok(None);
    }
    let Some(body) = &payload.transparent else {
        return Ok(None);
    };
    if body.len() > wire::MAX_BYTES {
        return Ok(None);
    }
    let Ok(body_len) = u32::try_from(body.len()) else {
        return Ok(None);
    };
    let mut scheme = None;
    let mut serializer = None;
    for (key, value) in details {
        match (key, value) {
            (Cbor::String(key), Cbor::String(value)) if key == "ppt_scheme" => {
                scheme = Some(value.as_str());
            }
            (Cbor::String(key), Cbor::String(value)) if key == "ppt_serializer" => {
                serializer = Some(value.as_str());
            }
            _ => return Ok(None),
        }
    }
    let Some(scheme) = scheme.filter(|scheme| !scheme.is_empty()) else {
        return Ok(None);
    };
    if serializer != Some("flatbuffers") {
        return Ok(None);
    }

    // Only the scheme has variable length. The standard CBOR writer still
    // encodes the complete map; reserve its exact canonical string size.
    const FIXED_BYTES: usize =
        1 + 1 + "ppt_scheme".len() + 1 + "ppt_serializer".len() + 1 + "flatbuffers".len();
    let scheme_header = match scheme.len() {
        0..=23 => 1,
        24..=255 => 2,
        256..=65535 => 3,
        _ => 5,
    };
    let Some(metadata_len) = FIXED_BYTES
        .checked_add(scheme_header)
        .and_then(|size| size.checked_add(scheme.len()))
        .filter(|size| *size <= 1024 * 1024)
    else {
        return Ok(None);
    };
    // Preserve the generic writer's conservative table/vector budget as well
    // as the final encoded-frame bound. Both tables and both vectors occur.
    let result_reference = schema::TABLES[schema::ROOT].fields[1].values
        [usize::from(generated::AnyMessage::Result.0)] as usize;
    let budget_overhead = 2 * 8
        + 16 * (schema::TABLES[schema::ROOT].fields.len()
            + schema::TABLES[result_reference].fields.len())
        + 2 * 8;
    if metadata_len
        .checked_add(body.len())
        .and_then(|size| size.checked_add(budget_overhead))
        .is_none_or(|size| size > wire::MAX_BYTES)
    {
        return Ok(None);
    }
    let mut metadata = Vec::with_capacity(metadata_len);
    serde_cbor::to_writer(&mut metadata, details)
        .map_err(|_| wire::invalid("metadata encoding"))?;
    if metadata.len() != metadata_len {
        return Ok(None);
    }

    let mut builder = flatbuffers::FlatBufferBuilder::new_in(CodecAllocator::with_capacity(256));
    let vector = builder.create_vector::<u8>(&[]);
    let metadata = builder.create_vector(&metadata);
    codec_copy_metrics::record_vector_copy(metadata_len);
    let scheme = match scheme {
        "cryptobox" => generated::PPTScheme::CRYPTOBOX,
        "mqtt" => generated::PPTScheme::MQTT,
        "xbr" => generated::PPTScheme::XBR,
        "opaque" => generated::PPTScheme::OPAQUE,
        _ => generated::PPTScheme::NONE,
    };
    let result = generated::Result::create(
        &mut builder,
        &generated::ResultArgs {
            request,
            payload: Some(vector),
            ppt_scheme: scheme,
            ppt_serializer: generated::PPTSerializer::FLATBUFFERS,
            ..Default::default()
        },
    );
    let root = generated::Message::create(
        &mut builder,
        &generated::MessageArgs {
            msg_type: generated::AnyMessage::Result,
            msg: Some(result.as_union_value()),
            metadata: Some(metadata),
        },
    );
    builder.finish(root, None);
    let (mut allocation, start) = builder.collapse_in();
    let end = allocation.len();
    let control_len = end - start;
    if vector.value() != 4
        || control_len % 8 != 0
        || control_len > wire::MAX_BYTES
        || body.len() > wire::MAX_BYTES - control_len
    {
        return Ok(None);
    }
    allocation[end - 4..].copy_from_slice(&body_len.to_le_bytes());
    let control = Bytes::from(allocation.into_vec()).slice(start..);
    Ok(Some(vec![control, body.clone()]))
}

pub fn encode(message: &WampMessage) -> Result<Bytes, ParseError> {
    flatbuffers_writer::write(&fields(message)?)
}

/// Compose a verified control-only envelope with independently owned encoded
/// application spans. Ordinary spans are CBOR containers; transparent spans
/// are uninterpreted. No application span is copied or materialized.
pub fn compose_segments(control: Bytes, supplied: Payload) -> Result<Vec<Bytes>, ParseError> {
    let (parsed, mut fields) =
        super::flatbuffers_codec::parse_with_fields(super::RawFrame::Contiguous(control.clone()))?;
    let supplied_present =
        supplied.args.is_some() || supplied.kwargs.is_some() || supplied.transparent.is_some();
    let target = match &parsed.message {
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
    };
    if let Some(target) = target {
        if target.args.is_some()
            || target.kwargs.is_some()
            || target
                .transparent
                .as_ref()
                .is_some_and(|bytes| !bytes.is_empty())
        {
            return Err(wire::invalid("control envelope contains application data"));
        }
        if target.transparent.is_some() && (supplied.args.is_some() || supplied.kwargs.is_some()) {
            return Err(wire::invalid(
                "opaque control conflicts with ordinary payload",
            ));
        }
    } else if supplied_present {
        return Err(wire::invalid("message has no application payload"));
    }
    if !supplied_present {
        return Ok(vec![control]);
    }
    // The original controls, typed projections and encoded metadata have all
    // passed the ordinary parser. Only the application slots change here, so
    // retain that validated metadata instead of projecting and encoding it a
    // second time. Newly supplied application containers still need validation.
    super::validate_flatbuffers_payload(&supplied)?;
    let root = Arc::make_mut(&mut fields);
    let Some(Value::Table(body)) = root.get_mut("msg") else {
        return Err(wire::invalid("message table"));
    };
    // Borrow the Arc in place: cloning it out would force make_mut to clone
    // the body even though composition owns the validated field tree.
    let body = Arc::make_mut(body);
    for (key, bytes) in [
        ("args", supplied.args),
        ("kwargs", supplied.kwargs),
        ("payload", supplied.transparent),
    ] {
        if let Some(bytes) = bytes {
            body.insert(key, Value::Bytes(bytes));
        } else {
            body.remove(key);
        }
    }
    flatbuffers_writer::write_segments(&fields)
}

fn fields(message: &WampMessage) -> Result<Fields, ParseError> {
    let mut controls = Fields::with_capacity(4);
    let (name, dictionary, payload, tag) = match message {
        WampMessage::Hello { realm, details } => {
            text(&mut controls, "realm", realm);
            ("Hello", Some(details), None, 1)
        }
        WampMessage::Welcome {
            session_id,
            details,
        } => {
            integer(&mut controls, "session", *session_id);
            ("Welcome", Some(details), None, 2)
        }
        WampMessage::Abort {
            reason,
            details,
            payload,
        } => {
            text(&mut controls, "reason", reason);
            ("Abort", Some(details), Some(payload), 3)
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
            ("Challenge", Some(extra), None, 4)
        }
        WampMessage::Authenticate { signature, extra } => {
            text(&mut controls, "signature", signature);
            ("Authenticate", Some(extra), None, 5)
        }
        WampMessage::Goodbye {
            reason,
            details,
            payload,
        } => {
            text(&mut controls, "reason", reason);
            ("Goodbye", Some(details), Some(payload), 6)
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
            ("Heartbeat", Some(details), None, 26)
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
            ("Error", Some(details), Some(payload), 7)
        }
        WampMessage::Publish {
            request_id,
            topic,
            options,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "topic", topic);
            ("Publish", Some(options), Some(payload), 8)
        }
        WampMessage::Published {
            request_id,
            publication_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "publication", *publication_id);
            ("Published", None, None, 9)
        }
        WampMessage::Subscribe {
            request_id,
            topic,
            options,
        } => {
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "topic", topic);
            ("Subscribe", Some(options), None, 10)
        }
        WampMessage::Subscribed {
            request_id,
            subscription_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "subscription", *subscription_id);
            ("Subscribed", None, None, 11)
        }
        WampMessage::Unsubscribe {
            request_id,
            subscription_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "subscription", *subscription_id);
            ("Unsubscribe", None, None, 12)
        }
        WampMessage::Unsubscribed {
            request_id,
            details,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Unsubscribed", Some(details), None, 13)
        }
        WampMessage::Event {
            subscription_id,
            publication_id,
            details,
            payload,
        } => {
            integer(&mut controls, "subscription", *subscription_id);
            integer(&mut controls, "publication", *publication_id);
            ("Event", Some(details), Some(payload), 14)
        }
        WampMessage::Call {
            request_id,
            procedure,
            options,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "procedure", procedure);
            ("Call", Some(options), Some(payload), 16)
        }
        WampMessage::Cancel {
            request_id,
            options,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Cancel", Some(options), None, 17)
        }
        WampMessage::Result {
            request_id,
            details,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Result", Some(details), Some(payload), 18)
        }
        WampMessage::Register {
            request_id,
            procedure,
            options,
        } => {
            integer(&mut controls, "request", *request_id);
            text(&mut controls, "procedure", procedure);
            ("Register", Some(options), None, 19)
        }
        WampMessage::Registered {
            request_id,
            registration_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "registration", *registration_id);
            ("Registered", None, None, 20)
        }
        WampMessage::Unregister {
            request_id,
            registration_id,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "registration", *registration_id);
            ("Unregister", None, None, 21)
        }
        WampMessage::Unregistered {
            request_id,
            details,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Unregistered", Some(details), None, 22)
        }
        WampMessage::Invocation {
            request_id,
            registration_id,
            details,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            integer(&mut controls, "registration", *registration_id);
            ("Invocation", Some(details), Some(payload), 23)
        }
        WampMessage::Interrupt {
            request_id,
            options,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Interrupt", Some(options), None, 24)
        }
        WampMessage::Yield {
            request_id,
            options,
            payload,
        } => {
            integer(&mut controls, "request", *request_id);
            ("Yield", Some(options), Some(payload), 25)
        }
        WampMessage::Unknown { .. } => return Err(wire::invalid("unsupported message type")),
    };
    // FlatBuffers union tags are already known from the message variant. Use
    // that tag as the schema union index instead of scanning all tables and
    // then scanning the union references for this table.
    let union = &schema::TABLES[schema::ROOT].fields[1];
    let reference = usize::try_from(
        *union
            .values
            .get(tag)
            .ok_or_else(|| wire::invalid("union discriminator"))?,
    )
    .map_err(|_| wire::invalid("union discriminator"))?;
    if schema::TABLES
        .get(reference)
        .is_none_or(|table| table.name != name)
    {
        return Err(wire::invalid("message table"));
    }
    let mut body = if let Some(dictionary) = dictionary {
        validate_dictionary(dictionary)?;
        if name == "Heartbeat" {
            Fields::with_capacity(schema::TABLES[reference].fields.len())
        } else {
            flatbuffers_projection::project(name, dictionary, reference)?
        }
    } else {
        Fields::with_capacity(schema::TABLES[reference].fields.len())
    };
    body.extend(controls);
    if let Some(payload) = payload {
        super::validate_flatbuffers_payload(payload)?;
        for (key, bytes) in [
            ("args", &payload.args),
            ("kwargs", &payload.kwargs),
            ("payload", &payload.transparent),
        ] {
            if let Some(bytes) = bytes {
                body.insert(key, Value::Bytes(bytes.clone()));
            }
        }
    }
    let mut root = Fields::with_capacity(3);
    root.extend([
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
    fields.insert(
        key,
        Value::Text(super::codec_copy_metrics::copy_text_arc(value)),
    );
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

    fn typed_result(request: u64, scheme: &str, bytes: Bytes) -> WampMessage {
        WampMessage::Result {
            request_id: request,
            details: ValueMap::from([
                (
                    Cbor::String("ppt_scheme".into()),
                    Cbor::String(scheme.into()),
                ),
                (
                    Cbor::String("ppt_serializer".into()),
                    Cbor::String("flatbuffers".into()),
                ),
            ]),
            payload: Payload {
                transparent: Some(bytes),
                ..Default::default()
            },
        }
    }

    fn assert_segmented_result_matches_generic(message: &WampMessage) {
        let generic =
            fields(message).and_then(|fields| flatbuffers_writer::write_segments(&fields));
        let actual = encode_segments(message);
        match (generic, actual) {
            (Ok(generic), Ok(actual)) => {
                let concatenate = |parts: &[Bytes]| {
                    Bytes::from(
                        parts
                            .iter()
                            .flat_map(|part| part.iter().copied())
                            .collect::<Vec<_>>(),
                    )
                };
                let expected =
                    parse_message(Serializer::Flatbuffers, concatenate(&generic)).unwrap();
                let actual_frame = concatenate(&actual);
                let observed =
                    parse_message(Serializer::Flatbuffers, actual_frame.clone()).unwrap();
                assert!(
                    observed.message == expected.message,
                    "decoded control/payload differs"
                );
                super::super::flatbuffers_generated::wamp::proto::root_as_message(&actual_frame)
                    .unwrap();
                if let WampMessage::Result {
                    payload:
                        Payload {
                            transparent: Some(body),
                            ..
                        },
                    ..
                } = message
                {
                    assert!(actual
                        .iter()
                        .any(|part| part.as_ptr() == body.as_ptr() && part.len() == body.len()));
                }
            }
            (Err(_), Err(_)) => (),
            (expected, actual) => panic!(
                "different acceptance: generic_error={:?}, actual_error={:?}",
                expected.err(),
                actual.err()
            ),
        }
    }

    #[test]
    fn simple_typed_results_match_generic_controls_and_body_boundaries() {
        for length in [0, 1, 3, 4, 7, 8, 31, 255, 256, 65535, 65536] {
            let message = typed_result(42, "x_objectbox", Bytes::from(vec![0x71; length]));
            let WampMessage::Result {
                request_id,
                details,
                payload,
            } = &message
            else {
                unreachable!()
            };
            assert!(simple_ppt_result(*request_id, details, payload)
                .unwrap()
                .is_some());
            assert_segmented_result_matches_generic(&message);
        }
        for request in [0, 1, 9_007_199_254_740_992, 9_007_199_254_740_993, u64::MAX] {
            assert_segmented_result_matches_generic(&typed_result(
                request,
                "opaque",
                Bytes::from_static(b"body"),
            ));
        }
        for scheme in ["cryptobox", "mqtt", "xbr", "opaque", " ", "é中😀", ""] {
            assert_segmented_result_matches_generic(&typed_result(
                42,
                scheme,
                Bytes::from_static(b"body"),
            ));
        }
        for length in [23, 24, 255, 256, 65535, 65536] {
            assert_segmented_result_matches_generic(&typed_result(
                42,
                &"x".repeat(length),
                Bytes::from_static(b"body"),
            ));
        }
    }

    #[test]
    fn extended_or_invalid_result_controls_retain_generic_acceptance() {
        for (key, value) in [
            ("progress", Cbor::Bool(false)),
            ("progress", Cbor::Bool(true)),
            ("callee", Cbor::U64(0)),
            ("callee_authid", Cbor::String(String::new())),
            ("callee_authrole", Cbor::String("role".into())),
            ("forward_for", Cbor::Seq(vec![])),
            ("x_extra", Cbor::Bytes(vec![0, 255])),
            ("ppt_cipher", Cbor::String("aes256gcm".into())),
            ("ppt_keyid", Cbor::String("key-1".into())),
            ("ppt_scheme", Cbor::Unit),
            ("ppt_scheme", Cbor::U64(7)),
            ("ppt_serializer", Cbor::Unit),
            ("ppt_serializer", Cbor::Bool(false)),
            ("ppt_serializer", Cbor::String("future".into())),
            ("ppt_serializer", Cbor::String("msgpack".into())),
            ("ppt_serializer", Cbor::String("cbor".into())),
        ] {
            let mut message = typed_result(42, "x_objectbox", Bytes::from_static(b"body"));
            let WampMessage::Result {
                request_id,
                details,
                payload,
            } = &mut message
            else {
                unreachable!()
            };
            details.insert(Cbor::String(key.into()), value);
            assert!(simple_ppt_result(*request_id, details, payload)
                .unwrap()
                .is_none());
            assert_segmented_result_matches_generic(&message);
        }
        let mut invalid_key = typed_result(42, "x_objectbox", Bytes::from_static(b"body"));
        if let WampMessage::Result { details, .. } = &mut invalid_key {
            details.remove(&Cbor::String("ppt_serializer".into()));
            details.insert(Cbor::U64(1), Cbor::String("flatbuffers".into()));
        }
        assert_segmented_result_matches_generic(&invalid_key);
        for payload in [
            Payload::default(),
            Payload {
                args: Some(Bytes::from_static(&[0x80])),
                ..Default::default()
            },
            Payload {
                kwargs: Some(Bytes::from_static(&[0xa0])),
                ..Default::default()
            },
            Payload {
                args: Some(Bytes::from_static(&[0x80])),
                transparent: Some(Bytes::from_static(b"body")),
                ..Default::default()
            },
            Payload {
                kwargs: Some(Bytes::from_static(&[0xa0])),
                transparent: Some(Bytes::from_static(b"body")),
                ..Default::default()
            },
        ] {
            let mut message = typed_result(42, "x_objectbox", Bytes::new());
            if let WampMessage::Result {
                payload: target, ..
            } = &mut message
            {
                *target = payload;
            }
            assert_segmented_result_matches_generic(&message);
        }
    }

    #[test]
    fn simple_result_metadata_limit_and_copy_accounting_are_exact() {
        use super::super::codec_copy_metrics::observed_on_current_thread;
        for scheme_length in [25, 1024 * 1024 - 44, 1024 * 1024 - 43] {
            let message = typed_result(42, &"x".repeat(scheme_length), Bytes::from_static(b"body"));
            let WampMessage::Result {
                request_id,
                details,
                payload,
            } = &message
            else {
                unreachable!()
            };
            let encoded = serde_cbor::to_vec(details).unwrap();
            let before = observed_on_current_thread();
            let actual = simple_ppt_result(*request_id, details, payload).unwrap();
            let after = observed_on_current_thread();
            if encoded.len() <= 1024 * 1024 {
                assert!(actual.is_some());
                assert_eq!(
                    after.vector_copy_bytes_total - before.vector_copy_bytes_total,
                    encoded.len() as u64
                );
                if scheme_length == 25 {
                    assert_eq!(
                        after.growth_copy_bytes_total,
                        before.growth_copy_bytes_total
                    );
                } else {
                    assert!(after.growth_copy_bytes_total > before.growth_copy_bytes_total);
                }
            } else {
                assert!(actual.is_none());
                assert_eq!(
                    after.vector_copy_bytes_total,
                    before.vector_copy_bytes_total
                );
            }
            assert_segmented_result_matches_generic(&message);
        }
    }

    #[test]
    fn simple_result_preserves_payload_owner_after_source_drop() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        struct Owner {
            bytes: Vec<u8>,
            drops: Arc<AtomicUsize>,
        }
        impl AsRef<[u8]> for Owner {
            fn as_ref(&self) -> &[u8] {
                &self.bytes
            }
        }
        impl Drop for Owner {
            fn drop(&mut self) {
                self.drops.fetch_add(1, Ordering::SeqCst);
            }
        }
        let drops = Arc::new(AtomicUsize::new(0));
        let body = Bytes::from_owner(Owner {
            bytes: vec![0x71; 65536],
            drops: drops.clone(),
        });
        let pointer = body.as_ptr();
        let message = typed_result(42, "x_objectbox", body);
        let parts = encode_segments(&message).unwrap();
        assert_eq!(parts[1].as_ptr(), pointer);
        drop(message);
        assert_eq!(drops.load(Ordering::SeqCst), 0);
        assert!(parts[1].iter().all(|byte| *byte == 0x71));
        drop(parts);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn simple_result_preserves_generic_budget_and_rejection_accounting() {
        use super::super::codec_copy_metrics::observed_on_current_thread;
        let storage = Bytes::from(vec![0x71; wire::MAX_BYTES]);
        let message_for = |length| typed_result(42, "x_objectbox", storage.slice(..length));
        let generic = |message: &WampMessage| {
            fields(message).and_then(|fields| flatbuffers_writer::write_segments(&fields))
        };
        // Discover the existing writer's bound independently of its estimates.
        let (mut low, mut high) = (0, wire::MAX_BYTES + 1);
        while low + 1 < high {
            let middle = low + (high - low) / 2;
            if generic(&message_for(middle)).is_ok() {
                low = middle;
            } else {
                high = middle;
            }
        }
        let at_limit = message_for(low);
        let parts = encode_segments(&at_limit).unwrap();
        assert!(parts.iter().map(Bytes::len).sum::<usize>() <= wire::MAX_BYTES);
        assert_eq!(parts[1].as_ptr(), storage.as_ptr());
        let too_large = message_for(high);
        let before = observed_on_current_thread();
        assert!(generic(&too_large).is_err());
        let baseline = observed_on_current_thread();
        assert!(encode_segments(&too_large).is_err());
        let after = observed_on_current_thread();
        assert_eq!(
            after.vector_copy_bytes_total - baseline.vector_copy_bytes_total,
            baseline.vector_copy_bytes_total - before.vector_copy_bytes_total
        );
        assert_eq!(
            after.growth_copy_bytes_total - baseline.growth_copy_bytes_total,
            baseline.growth_copy_bytes_total - before.growth_copy_bytes_total
        );
    }

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
                for language in ["dart", "dart_segments"] {
                    let dart_path = directory.join(format!("{language}_codec_{name}.bin"));
                    if dart_path.exists() {
                        let dart = parse_message(
                            Serializer::Flatbuffers,
                            Bytes::from(std::fs::read(dart_path).unwrap()),
                        )
                        .unwrap();
                        assert_eq!(dart.message, original.message, "{language} {name}");
                    }
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
