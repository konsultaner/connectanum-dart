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
    if let WampMessage::Invocation {
        request_id,
        registration_id,
        details,
        payload,
    } = message
    {
        if let Some(parts) =
            simple_ppt_envelope(*request_id, Some(*registration_id), details, payload)?
        {
            return Ok(parts);
        }
    }
    if matches!(
        message,
        WampMessage::Published { .. }
            | WampMessage::Subscribed { .. }
            | WampMessage::Registered { .. }
    ) {
        if let Some(frame) = control_ack(message) {
            return Ok(vec![frame]);
        }
    }
    flatbuffers_writer::write_segments(&fields(message)?)
}

// These acknowledgement variants contain only two WAMP IDs. Build their pinned
// tables directly rather than allocating the generic root/control field maps.
// All other shapes and IDs keep the ordinary writer and its validation.
fn control_ack(message: &WampMessage) -> Option<Bytes> {
    use super::codec_copy_metrics::CodecAllocator;
    use super::flatbuffers_generated::wamp::proto as generated;
    let (request, other) = match message {
        WampMessage::Published {
            request_id,
            publication_id,
        } => (*request_id, *publication_id),
        WampMessage::Subscribed {
            request_id,
            subscription_id,
        } => (*request_id, *subscription_id),
        WampMessage::Registered {
            request_id,
            registration_id,
        } => (*request_id, *registration_id),
        _ => return None,
    };
    if !(1..=9_007_199_254_740_992).contains(&request)
        || !(1..=9_007_199_254_740_992).contains(&other)
    {
        return None;
    }
    // These fixed ID-only envelopes occupy 56 bytes, including both tables.
    let mut builder = flatbuffers::FlatBufferBuilder::new_in(CodecAllocator::with_capacity(64));
    let (tag, body) = match message {
        WampMessage::Published { .. } => (
            generated::AnyMessage::Published,
            generated::Published::create(
                &mut builder,
                &generated::PublishedArgs {
                    request,
                    publication: other,
                    ..Default::default()
                },
            )
            .as_union_value(),
        ),
        WampMessage::Subscribed { .. } => (
            generated::AnyMessage::Subscribed,
            generated::Subscribed::create(
                &mut builder,
                &generated::SubscribedArgs {
                    request,
                    subscription: other,
                    ..Default::default()
                },
            )
            .as_union_value(),
        ),
        WampMessage::Registered { .. } => (
            generated::AnyMessage::Registered,
            generated::Registered::create(
                &mut builder,
                &generated::RegisteredArgs {
                    request,
                    registration: other,
                    ..Default::default()
                },
            )
            .as_union_value(),
        ),
        _ => return None,
    };
    let root = generated::Message::create(
        &mut builder,
        &generated::MessageArgs {
            msg_type: tag,
            msg: Some(body),
            metadata: None,
        },
    );
    builder.finish(root, None);
    let (allocation, start) = builder.collapse_in();
    Some(Bytes::from(allocation.into_vec()).slice(start..))
}

// Common opaque RESULT/INVOCATION headers can use the pinned generated tables
// while retaining the complete dictionary and original application allocation.
// Other dictionaries and ordinary argument vectors keep the generic writer.
fn simple_ppt_result(
    request: u64,
    details: &ValueMap,
    payload: &Payload,
) -> Result<Option<Vec<Bytes>>, ParseError> {
    simple_ppt_envelope(request, None, details, payload)
}

fn simple_ppt_envelope(
    request: u64,
    registration: Option<u64>,
    details: &ValueMap,
    payload: &Payload,
) -> Result<Option<Vec<Bytes>>, ParseError> {
    use super::codec_copy_metrics::{self, CodecAllocator};
    use super::flatbuffers_generated::wamp::proto as generated;
    let invocation = registration.is_some();
    if registration.is_some_and(|id| id == 0 || id > 9_007_199_254_740_992)
        || request == 0
        || request > 9_007_199_254_740_992
        || !(2..=if invocation { 4 } else { 3 }).contains(&details.len())
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
    let mut progress = None;
    let mut receive_progress = None;
    for (key, value) in details {
        match (key, value) {
            (Cbor::String(key), Cbor::String(value)) if key == "ppt_scheme" => {
                scheme = Some(value.as_str());
            }
            (Cbor::String(key), Cbor::String(value)) if key == "ppt_serializer" => {
                serializer = Some(value.as_str());
            }
            (Cbor::String(key), Cbor::Bool(value)) if key == "progress" => {
                progress = Some(*value);
            }
            (Cbor::String(key), Cbor::Bool(value)) if invocation && key == "receive_progress" => {
                receive_progress = Some(*value);
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

    // Both optional booleans have fixed encoded sizes; only the scheme has
    // variable length. The standard CBOR writer retains the complete map,
    // including absent versus explicit false and INVOCATION's metadata-only
    // progress key (the pinned INVOCATION table has no progress field).
    const FIXED_BYTES: usize =
        1 + 1 + "ppt_scheme".len() + 1 + "ppt_serializer".len() + 1 + "flatbuffers".len();
    let fixed_bytes = FIXED_BYTES
        + usize::from(progress.is_some()) * (1 + "progress".len() + 1)
        + usize::from(receive_progress.is_some()) * (1 + "receive_progress".len() + 1);
    let scheme_header = match scheme.len() {
        0..=23 => 1,
        24..=255 => 2,
        256..=65535 => 3,
        _ => 5,
    };
    let Some(metadata_len) = fixed_bytes
        .checked_add(scheme_header)
        .and_then(|size| size.checked_add(scheme.len()))
        .filter(|size| *size <= 1024 * 1024)
    else {
        return Ok(None);
    };
    // Preserve the generic writer's conservative table/vector budget as well
    // as the final encoded-frame bound. Both tables and both vectors occur.
    let tag = if invocation {
        generated::AnyMessage::Invocation
    } else {
        generated::AnyMessage::Result
    };
    let reference = schema::TABLES[schema::ROOT].fields[1].values[usize::from(tag.0)] as usize;
    let budget_overhead = 2 * 8
        + 16 * (schema::TABLES[schema::ROOT].fields.len() + schema::TABLES[reference].fields.len())
        + 2 * 8;
    if metadata_len
        .checked_add(body.len())
        .and_then(|size| size.checked_add(budget_overhead))
        .is_none_or(|size| size > wire::MAX_BYTES)
    {
        return Ok(None);
    }
    // Small control metadata need not allocate a temporary Vec. Keep the
    // standard CBOR writer and retry with heap storage if its bounded writer
    // fails, preserving the existing error and generic-fallback behavior.
    let mut inline_metadata = [0u8; 128];
    let mut heap_metadata = Vec::new();
    let mut inline_writer = std::io::Cursor::new(inline_metadata.as_mut_slice());
    let use_inline = metadata_len <= inline_writer.get_ref().len()
        && serde_cbor::to_writer(&mut inline_writer, details).is_ok();
    let metadata: &[u8] = if use_inline {
        if inline_writer.position() as usize != metadata_len {
            return Ok(None);
        }
        &inline_metadata[..metadata_len]
    } else {
        heap_metadata.reserve_exact(metadata_len);
        serde_cbor::to_writer(&mut heap_metadata, details)
            .map_err(|_| wire::invalid("metadata encoding"))?;
        if heap_metadata.len() != metadata_len {
            return Ok(None);
        }
        &heap_metadata
    };

    // Reserve the pinned control tables alongside metadata, including root
    // alignment. The checked 1 MiB metadata limit makes this addition bounded;
    // rounding capacity to eight keeps the external payload vector tail aligned.
    let header_reserve = if invocation { 128 } else { 96 };
    let capacity = (metadata_len + header_reserve).next_multiple_of(8);
    let mut builder =
        flatbuffers::FlatBufferBuilder::new_in(CodecAllocator::with_capacity(capacity));
    let vector = builder.create_vector::<u8>(&[]);
    let metadata = builder.create_vector(metadata);
    codec_copy_metrics::record_vector_copy(metadata_len);
    let scheme = match scheme {
        "cryptobox" => generated::PPTScheme::CRYPTOBOX,
        "mqtt" => generated::PPTScheme::MQTT,
        "xbr" => generated::PPTScheme::XBR,
        "opaque" => generated::PPTScheme::OPAQUE,
        _ => generated::PPTScheme::NONE,
    };
    let body_table = if let Some(registration) = registration {
        generated::Invocation::create(
            &mut builder,
            &generated::InvocationArgs {
                request,
                registration,
                receive_progress: receive_progress.unwrap_or(false),
                payload: Some(vector),
                ppt_scheme: scheme,
                ppt_serializer: generated::PPTSerializer::FLATBUFFERS,
                ..Default::default()
            },
        )
        .as_union_value()
    } else {
        generated::Result::create(
            &mut builder,
            &generated::ResultArgs {
                request,
                progress: progress.unwrap_or(false),
                payload: Some(vector),
                ppt_scheme: scheme,
                ppt_serializer: generated::PPTSerializer::FLATBUFFERS,
                ..Default::default()
            },
        )
        .as_union_value()
    };
    let root = generated::Message::create(
        &mut builder,
        &generated::MessageArgs {
            msg_type: tag,
            msg: Some(body_table),
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
    if matches!(
        message,
        WampMessage::Published { .. }
            | WampMessage::Subscribed { .. }
            | WampMessage::Registered { .. }
    ) {
        if let Some(frame) = control_ack(message) {
            return Ok(frame);
        }
    }
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

    fn typed_invocation(
        request: u64,
        registration: u64,
        scheme: &str,
        bytes: Bytes,
        flags: (Option<bool>, Option<bool>),
    ) -> WampMessage {
        let WampMessage::Result {
            mut details,
            payload,
            ..
        } = typed_result(request, scheme, bytes)
        else {
            unreachable!()
        };
        for (key, value) in [("progress", flags.0), ("receive_progress", flags.1)] {
            if let Some(value) = value {
                details.insert(Cbor::String(key.into()), Cbor::Bool(value));
            }
        }
        WampMessage::Invocation {
            request_id: request,
            registration_id: registration,
            details,
            payload,
        }
    }

    #[test]
    fn typed_invocations_preserve_metadata_without_growth() {
        use super::super::codec_copy_metrics::observed_on_current_thread;
        use super::super::flatbuffers_generated::wamp::proto as generated;
        let mut schemes = vec![
            "cryptobox".into(),
            "mqtt".into(),
            "xbr".into(),
            "opaque".into(),
            "é".repeat(44),
            "🚀".repeat(22),
        ];
        schemes.extend(
            [
                1, 23, 24, 25, 58, 59, 60, 61, 86, 87, 88, 127, 128, 255, 256, 65535, 65536,
            ]
            .map(|n| "x".repeat(n)),
        );
        for scheme in schemes {
            for flags in [None, Some(false), Some(true)]
                .into_iter()
                .flat_map(|p| [None, Some(false), Some(true)].map(|r| (p, r)))
            {
                for (request, registration) in
                    [(1, 9_007_199_254_740_992), (9_007_199_254_740_992, 1)]
                {
                    let body = Bytes::from(vec![0x71, 0, 0xff, 0x83, 0x27, 0x14, 0x51]);
                    let message =
                        typed_invocation(request, registration, &scheme, body.clone(), flags);
                    let WampMessage::Invocation { details, .. } = &message else {
                        unreachable!()
                    };
                    let metadata = serde_cbor::to_vec(details).unwrap();
                    let before = observed_on_current_thread();
                    let parts = encode_segments(&message).unwrap();
                    let after = observed_on_current_thread();
                    assert_eq!(
                        after.growth_copy_bytes_total,
                        before.growth_copy_bytes_total,
                        "scheme bytes {}, flags {:?}",
                        scheme.len(),
                        flags
                    );
                    assert_eq!(
                        after.vector_copy_bytes_total - before.vector_copy_bytes_total,
                        metadata.len() as u64
                    );
                    assert_eq!(parts.len(), 2);
                    assert_eq!(parts[1].as_ptr(), body.as_ptr());
                    assert_eq!(parts[0].len() % 8, 0);
                    let joined: Vec<u8> = parts.iter().flat_map(|p| p.iter().copied()).collect();
                    let root = generated::root_as_message(&joined).unwrap();
                    let invocation = root.msg_as_invocation().unwrap();
                    assert_eq!(invocation.request(), request);
                    assert_eq!(invocation.registration(), registration);
                    assert_eq!(invocation.receive_progress(), flags.1.unwrap_or(false));
                    assert_eq!(root.metadata().unwrap().bytes(), metadata);
                    assert_segmented_result_matches_generic(&message);
                }
            }
        }
    }

    #[test]
    fn typed_invocation_other_shapes_preserve_generic_fallback() {
        for (key, value) in [
            ("caller", Cbor::U64(7)),
            ("caller_authid", Cbor::String("alice".into())),
            ("procedure", Cbor::String("com.example.echo".into())),
            ("progress", Cbor::Unit),
            ("progress", Cbor::String("true".into())),
            ("receive_progress", Cbor::U8(1)),
            ("ppt_cipher", Cbor::String("xsalsa20poly1305".into())),
            ("ppt_keyid", Cbor::String("key".into())),
            ("ppt_scheme", Cbor::String(String::new())),
            ("ppt_serializer", Cbor::String("json".into())),
            ("custom", Cbor::Map(ValueMap::new())),
        ] {
            let mut message =
                typed_invocation(73, 91, "opaque", Bytes::from(vec![1, 2, 3]), (None, None));
            let WampMessage::Invocation {
                details, payload, ..
            } = &mut message
            else {
                unreachable!()
            };
            details.insert(Cbor::String(key.into()), value);
            assert!(simple_ppt_envelope(73, Some(91), details, payload)
                .unwrap()
                .is_none());
            assert_segmented_result_matches_generic(&message);
        }
        for missing in ["ppt_scheme", "ppt_serializer"] {
            let mut message = typed_invocation(73, 91, "opaque", Bytes::new(), (None, None));
            let WampMessage::Invocation {
                details, payload, ..
            } = &mut message
            else {
                unreachable!()
            };
            details.remove(&Cbor::String(missing.into()));
            assert!(simple_ppt_envelope(73, Some(91), details, payload)
                .unwrap()
                .is_none());
            assert_segmented_result_matches_generic(&message);
        }
        let mut invalid_key = typed_invocation(73, 91, "opaque", Bytes::new(), (None, None));
        let WampMessage::Invocation {
            details, payload, ..
        } = &mut invalid_key
        else {
            unreachable!()
        };
        details.remove(&Cbor::String("ppt_serializer".into()));
        details.insert(Cbor::U64(1), Cbor::String("flatbuffers".into()));
        assert!(simple_ppt_envelope(73, Some(91), details, payload)
            .unwrap()
            .is_none());
        assert_segmented_result_matches_generic(&invalid_key);
        for (request, registration) in [
            (0, 91),
            (73, 0),
            (9_007_199_254_740_993, 91),
            (73, 9_007_199_254_740_993),
            (u64::MAX, u64::MAX),
        ] {
            let message =
                typed_invocation(request, registration, "opaque", Bytes::new(), (None, None));
            let WampMessage::Invocation {
                details, payload, ..
            } = &message
            else {
                unreachable!()
            };
            assert!(
                simple_ppt_envelope(request, Some(registration), details, payload)
                    .unwrap()
                    .is_none()
            );
            assert_segmented_result_matches_generic(&message);
        }
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
            let mut message = typed_invocation(73, 91, "opaque", Bytes::new(), (None, None));
            let WampMessage::Invocation {
                payload: target, ..
            } = &mut message
            else {
                unreachable!()
            };
            *target = payload;
            let WampMessage::Invocation {
                details, payload, ..
            } = &message
            else {
                unreachable!()
            };
            assert!(simple_ppt_envelope(73, Some(91), details, payload)
                .unwrap()
                .is_none());
            assert_segmented_result_matches_generic(&message);
        }
    }

    #[test]
    fn typed_invocation_limits_and_body_ownership_match_generic() {
        // The encoded CBOR metadata ceiling is independent of the full frame budget.
        for n in [1_048_504, 1_048_505] {
            let message = typed_invocation(
                73,
                91,
                &"x".repeat(n),
                Bytes::new(),
                (Some(true), Some(true)),
            );
            let WampMessage::Invocation {
                details, payload, ..
            } = &message
            else {
                unreachable!()
            };
            let size = serde_cbor::to_vec(details).unwrap().len();
            assert_eq!(size, n + 72);
            assert_eq!(
                simple_ppt_envelope(73, Some(91), details, payload)
                    .unwrap()
                    .is_some(),
                size <= 1_048_576
            );
            assert_segmented_result_matches_generic(&message);
        }
        let mut message = typed_invocation(73, 91, "opaque", Bytes::new(), (None, None));
        let WampMessage::Invocation {
            details, payload, ..
        } = &mut message
        else {
            unreachable!()
        };
        let tag =
            super::super::flatbuffers_generated::wamp::proto::AnyMessage::Invocation.0 as usize;
        let reference = schema::TABLES[schema::ROOT].fields[1].values[tag] as usize;
        let overhead = 2 * 8
            + 16 * (schema::TABLES[schema::ROOT].fields.len()
                + schema::TABLES[reference].fields.len())
            + 2 * 8;
        let len = wire::MAX_BYTES - overhead - serde_cbor::to_vec(details).unwrap().len() + 1;
        payload.transparent = Some(Bytes::from(vec![0x71; len]));
        assert!(simple_ppt_envelope(73, Some(91), details, payload)
            .unwrap()
            .is_none());
        assert!(fields(&message)
            .and_then(|f| flatbuffers_writer::write_segments(&f))
            .is_err());
        assert!(encode_segments(&message).is_err());
        drop(message);

        for n in [0, 1, 7, 8, 255] {
            let message = typed_invocation(
                73,
                91,
                "opaque",
                Bytes::from((0..n).map(|i| i as u8).collect::<Vec<_>>()),
                (Some(false), Some(true)),
            );
            let expected = typed_invocation(
                73,
                91,
                "opaque",
                Bytes::from((0..n).map(|i| i as u8).collect::<Vec<_>>()),
                (Some(false), Some(true)),
            );
            let parts = encode_segments(&message).unwrap();
            drop(message);
            std::thread::spawn(move || {
                let joined = Bytes::from(
                    parts
                        .iter()
                        .flat_map(|p| p.iter().copied())
                        .collect::<Vec<_>>(),
                );
                assert_eq!(
                    super::super::parse_message_segments(Serializer::Flatbuffers, parts)
                        .unwrap()
                        .message,
                    expected
                );
                for split in 0..=joined.len() {
                    assert_eq!(
                        super::super::parse_message_segments(
                            Serializer::Flatbuffers,
                            vec![joined.slice(..split), joined.slice(split..)]
                        )
                        .unwrap()
                        .message,
                        expected
                    );
                }
                for end in 0..joined.len() {
                    assert!(parse_message(Serializer::Flatbuffers, joined.slice(..end)).is_err());
                }
            })
            .join()
            .unwrap();
        }
    }

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
                }
                | WampMessage::Invocation {
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
            ("progress", Cbor::Unit),
            ("progress", Cbor::U64(1)),
            ("progress", Cbor::String("true".into())),
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
    fn simple_result_metadata_boundaries_preserve_schema_without_growth() {
        use super::super::codec_copy_metrics::observed_on_current_thread;
        use super::super::flatbuffers_generated::wamp::proto as generated;
        let mut schemes = vec![
            "cryptobox".to_owned(),
            "mqtt".to_owned(),
            "xbr".to_owned(),
            "opaque".to_owned(),
            "é".repeat(43),
            "é".repeat(44),
            "🚀".repeat(21),
            "🚀".repeat(22),
        ];
        schemes.extend(
            [1, 23, 24, 25, 86, 87, 88, 127, 128, 255, 256, 65535, 65536]
                .map(|length| "x".repeat(length)),
        );
        for scheme in schemes {
            for request in [1, 9_007_199_254_740_992] {
                let body = Bytes::from(vec![0x71, 0x00, 0xff, 0x83, 0x27, 0x14, 0x51]);
                let message = typed_result(request, &scheme, body.clone());
                let WampMessage::Result {
                    request_id,
                    details,
                    payload,
                } = &message
                else {
                    unreachable!()
                };
                let expected_metadata = serde_cbor::to_vec(details).unwrap();
                let before = observed_on_current_thread();
                let parts = simple_ppt_result(*request_id, details, payload)
                    .unwrap()
                    .unwrap();
                let after = observed_on_current_thread();
                assert_eq!(
                    after.growth_copy_bytes_total,
                    before.growth_copy_bytes_total,
                    "scheme byte length {}",
                    scheme.len()
                );
                assert_eq!(
                    after.vector_copy_bytes_total - before.vector_copy_bytes_total,
                    expected_metadata.len() as u64
                );
                assert_eq!(parts.len(), 2);
                assert_eq!(parts[0].len() % 8, 0);
                assert_eq!(parts[1].as_ptr(), body.as_ptr());
                let frame: Vec<u8> = parts.iter().flat_map(|part| part.iter().copied()).collect();
                let root = generated::root_as_message(&frame).unwrap();
                assert_eq!(root.metadata().unwrap().bytes(), expected_metadata);
                let result = root.msg_as_result().unwrap();
                assert_eq!(result.request(), request);
                assert_eq!(result.payload().unwrap().bytes(), body);
                assert_segmented_result_matches_generic(&message);
            }
        }
    }

    #[test]
    fn simple_result_metadata_storage_survives_drop_and_fragmentation() {
        use super::super::parse_message_segments;
        for length in [87, 88, 256] {
            let scheme = "x".repeat(length);
            let expected_body = vec![0x11, 0x0, 0xff, 0x83, 0x45, 0x32, 0x70, 0x99, 0x3];
            let message = typed_result(73, &scheme, Bytes::from(expected_body.clone()));
            let parts = encode_segments(&message).unwrap();
            drop(message);
            let expected = typed_result(73, &scheme, Bytes::from(expected_body));
            std::thread::spawn(move || {
                let frame = Bytes::from(
                    parts
                        .iter()
                        .flat_map(|part| part.iter().copied())
                        .collect::<Vec<_>>(),
                );
                assert_eq!(
                    parse_message_segments(Serializer::Flatbuffers, parts)
                        .unwrap()
                        .message,
                    expected
                );
                for split in 0..=frame.len() {
                    let fragments = vec![frame.slice(..split), frame.slice(split..)];
                    assert_eq!(
                        parse_message_segments(Serializer::Flatbuffers, fragments)
                            .unwrap()
                            .message,
                        expected
                    );
                }
                for end in 0..frame.len() {
                    assert!(parse_message(Serializer::Flatbuffers, frame.slice(..end)).is_err());
                }
            })
            .join()
            .unwrap();
        }
    }

    #[test]
    fn typed_progressive_results_preserve_controls_and_metadata_limits() {
        use super::super::codec_copy_metrics::observed_on_current_thread;
        use super::super::flatbuffers_generated::wamp::proto as generated;
        for progress in [false, true] {
            for length in [25, 76, 77, 78, 255, 256, 1024 * 1024 - 54, 1024 * 1024 - 53] {
                let scheme = match length {
                    76 => "é".repeat(38),
                    78 => "é".repeat(39),
                    _ => "x".repeat(length),
                };
                let message = typed_result(42, &scheme, Bytes::from_static(b"body"));
                let WampMessage::Result {
                    request_id,
                    mut details,
                    payload,
                } = message
                else {
                    unreachable!()
                };
                details.insert(Cbor::String("progress".into()), Cbor::Bool(progress));
                let expected_metadata = serde_cbor::to_vec(&details).unwrap();
                let before = observed_on_current_thread();
                let actual = simple_ppt_result(request_id, &details, &payload).unwrap();
                let after = observed_on_current_thread();
                if expected_metadata.len() <= 1024 * 1024 {
                    let parts =
                        actual.expect("valid typed progressive RESULT uses generated writer");
                    assert_eq!(parts.len(), 2);
                    assert_eq!(
                        parts[1].as_ptr(),
                        payload.transparent.as_ref().unwrap().as_ptr()
                    );
                    assert_eq!(
                        after.growth_copy_bytes_total,
                        before.growth_copy_bytes_total
                    );
                    assert_eq!(
                        after.vector_copy_bytes_total - before.vector_copy_bytes_total,
                        expected_metadata.len() as u64
                    );
                    let frame: Vec<u8> =
                        parts.iter().flat_map(|part| part.iter().copied()).collect();
                    let root = generated::root_as_message(&frame).unwrap();
                    assert_eq!(root.metadata().unwrap().bytes(), expected_metadata);
                    let result = root.msg_as_result().unwrap();
                    assert_eq!(result.progress(), progress);
                    assert_eq!(result.request(), request_id);
                } else {
                    assert!(actual.is_none());
                    assert_eq!(after, before);
                }
                assert_segmented_result_matches_generic(&WampMessage::Result {
                    request_id,
                    details,
                    payload,
                });
            }
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
                assert_eq!(
                    after.growth_copy_bytes_total,
                    before.growth_copy_bytes_total
                );
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

#[cfg(test)]
mod control_ack_tests {
    use super::super::flatbuffers_generated::wamp::proto as generated;
    use super::super::{parse_message, parse_message_segments};
    use super::*;
    use crate::rawsocket::Serializer;

    fn ack(kind: usize, request: u64, other: u64) -> WampMessage {
        match kind {
            0 => WampMessage::Published {
                request_id: request,
                publication_id: other,
            },
            1 => WampMessage::Subscribed {
                request_id: request,
                subscription_id: other,
            },
            2 => WampMessage::Registered {
                request_id: request,
                registration_id: other,
            },
            _ => unreachable!(),
        }
    }

    #[test]
    fn both_ack_writers_preserve_pinned_fields_at_id_boundaries() {
        for kind in 0..3 {
            for request in [1, 255, 256, 9_007_199_254_740_992] {
                for other in [1, 255, 256, 9_007_199_254_740_992] {
                    let message = ack(kind, request, other);
                    let frame = encode(&message).unwrap();
                    let parts = encode_segments(&message).unwrap();
                    assert_eq!(parts.len(), 1);
                    assert_eq!(parts[0], frame);
                    assert_eq!(frame.len(), 56);
                    assert_eq!(
                        parse_message(Serializer::Flatbuffers, frame.clone())
                            .unwrap()
                            .message,
                        message
                    );
                    let root = generated::root_as_message(&frame).unwrap();
                    assert!(root.metadata().is_none());
                    match kind {
                        0 => {
                            assert_eq!(root.msg_type(), generated::AnyMessage::Published);
                            let body = root.msg_as_published().unwrap();
                            assert_eq!(
                                (body.session(), body.request(), body.publication()),
                                (0, request, other)
                            );
                        }
                        1 => {
                            assert_eq!(root.msg_type(), generated::AnyMessage::Subscribed);
                            let body = root.msg_as_subscribed().unwrap();
                            assert_eq!(
                                (body.session(), body.request(), body.subscription()),
                                (0, request, other)
                            );
                        }
                        _ => {
                            assert_eq!(root.msg_type(), generated::AnyMessage::Registered);
                            let body = root.msg_as_registered().unwrap();
                            assert_eq!(
                                (body.session(), body.request(), body.registration()),
                                (0, request, other)
                            );
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn generated_ack_layout_keeps_segmented_and_truncated_validation() {
        for kind in 0..3 {
            let message = ack(kind, 9_007_199_254_740_992, 9_007_199_254_740_992);
            let frame = encode(&message).unwrap();
            for split in 0..=frame.len() {
                let pieces = vec![frame.slice(..split), frame.slice(split..)];
                assert_eq!(
                    parse_message_segments(Serializer::Flatbuffers, pieces)
                        .unwrap()
                        .message,
                    message
                );
            }
            for end in 0..frame.len() {
                assert!(
                    parse_message(Serializer::Flatbuffers, frame.slice(..end)).is_err(),
                    "kind{kind} truncated{end}"
                );
            }
        }
    }

    #[test]
    fn invalid_ack_ids_and_other_shapes_keep_generic_writer_behavior() {
        let mut cases = Vec::new();
        for kind in 0..3 {
            for request in [0, 1, 9_007_199_254_740_993, u64::MAX] {
                for other in [0, 1, 9_007_199_254_740_993, u64::MAX] {
                    if request == 1 && other == 1 {
                        continue;
                    }
                    cases.push(ack(kind, request, other));
                }
            }
        }
        cases.push(WampMessage::Hello {
            realm: "realm.α".into(),
            details: ValueMap::from([(
                Cbor::String("custom".into()),
                Cbor::Seq(vec![Cbor::U64(7)]),
            )]),
        });
        cases.push(WampMessage::Hello {
            realm: "realm".into(),
            details: ValueMap::from([(Cbor::U64(7), Cbor::Bool(true))]),
        });
        cases.push(WampMessage::Result {
            request_id: 1,
            details: ValueMap::new(),
            payload: Payload {
                args: Some(Bytes::from_static(&[0x81, 0x01])),
                ..Payload::default()
            },
        });
        for message in cases {
            assert!(control_ack(&message).is_none());
            let generic = fields(&message)
                .and_then(|value| flatbuffers_writer::write(&value))
                .map_err(|error| format!("{error:?}"));
            assert_eq!(
                encode(&message).map_err(|error| format!("{error:?}")),
                generic
            );
            let generic = fields(&message)
                .and_then(|value| flatbuffers_writer::write_segments(&value))
                .map_err(|error| format!("{error:?}"));
            assert_eq!(
                encode_segments(&message).map_err(|error| format!("{error:?}")),
                generic
            );
        }
    }

    #[test]
    fn encoded_acknowledgements_keep_storage_after_builder_and_sender_drop() {
        let messages = (0..3)
            .map(|kind| ack(kind, 257, 9_007_199_254_740_992))
            .collect::<Vec<_>>();
        let frames = messages
            .iter()
            .map(|message| encode(message).unwrap())
            .collect::<Vec<_>>();
        let retained = frames.clone();
        drop(frames);
        let parsed = std::thread::spawn(move || {
            retained
                .into_iter()
                .map(|frame| {
                    parse_message(Serializer::Flatbuffers, frame)
                        .unwrap()
                        .message
                })
                .collect::<Vec<_>>()
        })
        .join()
        .unwrap();
        assert_eq!(parsed, messages);
    }
}
