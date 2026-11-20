use bytes::{Buf, Bytes};
use serde::{de::IgnoredAny, Deserialize};
use serde_value::Value;
use std::collections::{BTreeMap, VecDeque};
use std::convert::TryFrom;
use std::io::{Cursor, Read};
use std::ops::Range;

use crate::rawsocket::Serializer;

#[cfg(test)]
mod flatbuffers_conformance_tests;
#[cfg(test)]
#[allow(unused_imports)]
mod flatbuffers_generated;

mod flatbuffers_cbor;
mod flatbuffers_codec;
mod flatbuffers_encoder;
mod flatbuffers_projection;
mod flatbuffers_schema;
mod flatbuffers_wire;
mod flatbuffers_writer;

pub use flatbuffers_encoder::compose_segments as compose_flatbuffers_message_segments;
pub use flatbuffers_encoder::encode as encode_flatbuffers_message;
pub use flatbuffers_encoder::encode_segments as encode_flatbuffers_message_segments;
#[cfg(test)]
mod flatbuffers_segmented_tests;
#[cfg(test)]
mod test_allocations;

use serde_json::value::RawValue;

type ValueMap = BTreeMap<Value, Value>;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Payload {
    pub args: Option<Bytes>,
    pub kwargs: Option<Bytes>,
    /// Transparent FlatBuffers application data, independent of CBOR arguments.
    pub transparent: Option<Bytes>,
}

/// Validate ordinary argument containers against the FlatBuffers binding's
/// structural and size limits without decoding their application values.
pub fn validate_flatbuffers_payload(payload: &Payload) -> Result<(), ParseError> {
    if payload.transparent.is_some() && (payload.args.is_some() || payload.kwargs.is_some()) {
        return Err(flatbuffers_wire::invalid(
            "mixed transparent and ordinary payload",
        ));
    }
    for (bytes, major) in [(&payload.args, 4), (&payload.kwargs, 5)] {
        if let Some(bytes) = bytes {
            flatbuffers_cbor::validate(bytes, major, false)?;
        }
    }
    Ok(())
}

#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("unsupported serializer for parsing: {0:?}")]
    UnsupportedSerializer(Serializer),
    #[error("failed to deserialize payload: {0}")]
    Deserialize(String),
    #[error("expected array for WAMP message")]
    ExpectedArray,
    #[error("expected element for {0}")]
    MissingElement(&'static str),
    #[error("expected numeric identifier for {0}")]
    ExpectedIdentifier(&'static str),
    #[error("expected string for {0}")]
    ExpectedString(&'static str),
    #[error("expected map for {0}")]
    ExpectedMap(&'static str),
    #[error("expected list for {0}")]
    ExpectedList(&'static str),
    #[error("failed to serialize payload: {0}")]
    PayloadEncode(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WampMessage {
    Hello {
        realm: String,
        details: ValueMap,
    },
    Welcome {
        session_id: u64,
        details: ValueMap,
    },
    Abort {
        details: ValueMap,
        reason: String,
        payload: Payload,
    },
    Challenge {
        auth_method: String,
        extra: ValueMap,
    },
    Authenticate {
        signature: String,
        extra: ValueMap,
    },
    Goodbye {
        details: ValueMap,
        reason: String,
        payload: Payload,
    },
    Heartbeat {
        details: ValueMap,
        ping: Option<u64>,
        incoming: Option<u64>,
        outgoing: Option<u64>,
    },
    Error {
        request_type: u64,
        request_id: u64,
        details: ValueMap,
        error: String,
        payload: Payload,
    },
    Publish {
        request_id: u64,
        options: ValueMap,
        topic: String,
        payload: Payload,
    },
    Published {
        request_id: u64,
        publication_id: u64,
    },
    Subscribe {
        request_id: u64,
        options: ValueMap,
        topic: String,
    },
    Subscribed {
        request_id: u64,
        subscription_id: u64,
    },
    Unsubscribe {
        request_id: u64,
        subscription_id: u64,
    },
    Unsubscribed {
        request_id: u64,
        details: ValueMap,
    },
    Event {
        subscription_id: u64,
        publication_id: u64,
        details: ValueMap,
        payload: Payload,
    },
    Call {
        request_id: u64,
        options: ValueMap,
        procedure: String,
        payload: Payload,
    },
    Cancel {
        request_id: u64,
        options: ValueMap,
    },
    Result {
        request_id: u64,
        details: ValueMap,
        payload: Payload,
    },
    Register {
        request_id: u64,
        options: ValueMap,
        procedure: String,
    },
    Registered {
        request_id: u64,
        registration_id: u64,
    },
    Unregister {
        request_id: u64,
        registration_id: u64,
    },
    Unregistered {
        request_id: u64,
        details: ValueMap,
    },
    Invocation {
        request_id: u64,
        registration_id: u64,
        details: ValueMap,
        payload: Payload,
    },
    Interrupt {
        request_id: u64,
        options: ValueMap,
    },
    Yield {
        request_id: u64,
        options: ValueMap,
        payload: Payload,
    },
    Unknown {
        code: u64,
        fields: Vec<Value>,
    },
}

impl WampMessage {
    pub fn code(&self) -> u64 {
        match self {
            WampMessage::Hello { .. } => 1,
            WampMessage::Welcome { .. } => 2,
            WampMessage::Abort { .. } => 3,
            WampMessage::Challenge { .. } => 4,
            WampMessage::Authenticate { .. } => 5,
            WampMessage::Goodbye { .. } => 6,
            WampMessage::Heartbeat { .. } => 7,
            WampMessage::Error { .. } => 8,
            WampMessage::Publish { .. } => 16,
            WampMessage::Published { .. } => 17,
            WampMessage::Subscribe { .. } => 32,
            WampMessage::Subscribed { .. } => 33,
            WampMessage::Unsubscribe { .. } => 34,
            WampMessage::Unsubscribed { .. } => 35,
            WampMessage::Event { .. } => 36,
            WampMessage::Call { .. } => 48,
            WampMessage::Cancel { .. } => 49,
            WampMessage::Result { .. } => 50,
            WampMessage::Register { .. } => 64,
            WampMessage::Registered { .. } => 65,
            WampMessage::Unregister { .. } => 66,
            WampMessage::Unregistered { .. } => 67,
            WampMessage::Invocation { .. } => 68,
            WampMessage::Interrupt { .. } => 69,
            WampMessage::Yield { .. } => 70,
            WampMessage::Unknown { code, .. } => *code,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ParsedMessage {
    pub message: WampMessage,
    pub raw: RawFrame,
    pub serializer: Serializer,
    /// Validated dictionary bytes in the binding's inner encoding. FlatBuffers
    /// dictionaries use CBOR and retain the original frame allocation.
    pub encoded_metadata: Option<Bytes>,
}

#[derive(Debug, Clone)]
pub enum RawFrame {
    Contiguous(Bytes),
    Segmented { segments: Vec<Bytes>, len: usize },
}

impl RawFrame {
    pub fn from_segments(segments: Vec<Bytes>) -> Self {
        let len = segments.iter().map(|segment| segment.len()).sum();
        Self::Segmented { segments, len }
    }

    pub fn len(&self) -> usize {
        match self {
            RawFrame::Contiguous(bytes) => bytes.len(),
            RawFrame::Segmented { len, .. } => *len,
        }
    }

    pub fn as_contiguous(&self) -> Option<&Bytes> {
        match self {
            RawFrame::Contiguous(bytes) => Some(bytes),
            RawFrame::Segmented { .. } => None,
        }
    }

    pub fn into_bytes(self) -> Bytes {
        match self {
            RawFrame::Contiguous(bytes) => bytes,
            RawFrame::Segmented { segments, len } => {
                let mut flattened = Vec::with_capacity(len);
                for segment in segments {
                    flattened.extend_from_slice(segment.as_ref());
                }
                Bytes::from(flattened)
            }
        }
    }

    fn read_byte(&self, index: usize) -> Result<u8, ParseError> {
        let missing = || ParseError::Deserialize("unexpected end of message data".into());
        match self {
            RawFrame::Contiguous(bytes) => bytes.get(index).copied().ok_or_else(missing),
            RawFrame::Segmented { segments, .. } => {
                let mut offset = index;
                for segment in segments {
                    if let Some(byte) = segment.get(offset) {
                        return Ok(*byte);
                    }
                    offset = offset.saturating_sub(segment.len());
                }
                Err(missing())
            }
        }
    }

    fn slice_or_copy(&self, range: &Range<usize>) -> Result<Bytes, ParseError> {
        let length = range
            .end
            .checked_sub(range.start)
            .ok_or_else(|| ParseError::Deserialize("payload range starts after its end".into()))?;
        if range.end > self.len() {
            return Err(ParseError::Deserialize(
                "payload range exceeds message bounds".into(),
            ));
        }
        match self {
            RawFrame::Contiguous(bytes) => bytes
                .get(range.clone())
                .map(|slice| bytes.slice_ref(slice))
                .ok_or_else(|| {
                    ParseError::Deserialize("payload range exceeds message bounds".into())
                }),
            RawFrame::Segmented { segments, .. } => {
                let mut absolute = 0usize;
                for segment in segments {
                    if let (Some(start), Some(end)) = (
                        range.start.checked_sub(absolute),
                        range.end.checked_sub(absolute),
                    ) {
                        if let Some(slice) = segment.get(start..end) {
                            return Ok(segment.slice_ref(slice));
                        }
                    }
                    absolute = absolute.saturating_add(segment.len());
                }

                let mut copied = Vec::with_capacity(length);
                let mut absolute = 0usize;
                for segment in segments {
                    let start = range.start.saturating_sub(absolute).min(segment.len());
                    let end = range.end.saturating_sub(absolute).min(segment.len());
                    let slice = segment.get(start..end).ok_or_else(|| {
                        ParseError::Deserialize("payload range exceeds segment bounds".into())
                    })?;
                    copied.extend_from_slice(slice);
                    absolute = absolute.saturating_add(segment.len());
                }
                Ok(Bytes::from(copied))
            }
        }
    }

    #[cfg(test)]
    fn contains_slice(&self, slice: &Bytes) -> bool {
        match self {
            RawFrame::Contiguous(raw) => {
                let base = raw.as_ptr() as usize;
                let ptr = slice.as_ptr() as usize;
                let Some(offset) = ptr.checked_sub(base) else {
                    return false;
                };
                offset + slice.len() <= raw.len()
            }
            RawFrame::Segmented { segments, .. } => segments.iter().any(|segment| {
                let base = segment.as_ptr() as usize;
                let ptr = slice.as_ptr() as usize;
                let Some(offset) = ptr.checked_sub(base) else {
                    return false;
                };
                offset + slice.len() <= segment.len()
            }),
        }
    }
}

pub fn parse_message(
    serializer: Serializer,
    raw_payload: Bytes,
) -> Result<ParsedMessage, ParseError> {
    parse_message_frame(serializer, RawFrame::Contiguous(raw_payload))
}

pub fn parse_message_segments(
    serializer: Serializer,
    segments: Vec<Bytes>,
) -> Result<ParsedMessage, ParseError> {
    parse_message_frame(serializer, RawFrame::from_segments(segments))
}

fn parse_message_frame(
    serializer: Serializer,
    raw_payload: RawFrame,
) -> Result<ParsedMessage, ParseError> {
    match serializer {
        Serializer::Json => parse_json_message(raw_payload),
        Serializer::MessagePack => parse_msgpack_message(raw_payload),
        Serializer::Cbor => parse_cbor_message(raw_payload),
        Serializer::Flatbuffers => flatbuffers_codec::parse(raw_payload),
        other => parse_value_message(other, raw_payload),
    }
}

fn parse_value_message(
    serializer: Serializer,
    raw_payload: RawFrame,
) -> Result<ParsedMessage, ParseError> {
    let value = deserialize_value(serializer, &raw_payload)?;
    let seq = match value {
        Value::Seq(seq) => seq,
        _ => return Err(ParseError::ExpectedArray),
    };
    if seq.is_empty() {
        return Err(ParseError::MissingElement("message code"));
    }
    let (code_value, rest) = seq.split_first().unwrap();
    let code = value_as_u64(code_value, "message code")?;
    let message = parse_value_parts(serializer, code, rest)?;
    Ok(ParsedMessage {
        message,
        raw: raw_payload,
        serializer,
        encoded_metadata: None,
    })
}

fn parse_value_parts(
    serializer: Serializer,
    code: u64,
    rest: &[Value],
) -> Result<WampMessage, ParseError> {
    let message = match code {
        1 => parse_hello(rest)?,
        2 => parse_welcome(rest)?,
        3 => parse_abort(serializer, rest)?,
        4 => parse_challenge(rest)?,
        5 => parse_authenticate(rest)?,
        6 => parse_goodbye(serializer, rest)?,
        7 => parse_heartbeat(rest)?,
        8 => parse_error(serializer, rest)?,
        16 => parse_publish(serializer, rest)?,
        17 => parse_published(rest)?,
        32 => parse_subscribe(rest)?,
        33 => parse_subscribed(rest)?,
        34 => parse_unsubscribe(rest)?,
        35 => parse_unsubscribed(rest)?,
        36 => parse_event(serializer, rest)?,
        48 => parse_call(serializer, rest)?,
        49 => parse_cancel(rest)?,
        50 => parse_result(serializer, rest)?,
        64 => parse_register(rest)?,
        65 => parse_registered(rest)?,
        66 => parse_unregister(rest)?,
        67 => parse_unregistered(rest)?,
        68 => parse_invocation(serializer, rest)?,
        69 => parse_interrupt(rest)?,
        70 => parse_yield(serializer, rest)?,
        _ => WampMessage::Unknown {
            code,
            fields: rest.to_vec(),
        },
    };
    Ok(message)
}

fn parse_cbor_message(raw_payload: RawFrame) -> Result<ParsedMessage, ParseError> {
    let ranges = cbor_top_level_ranges(&raw_payload)?;
    if ranges.is_empty() {
        return Err(ParseError::MissingElement("message code"));
    }
    let code_value = cbor_value(&raw_payload, &ranges[0])?;
    let code = value_as_u64(&code_value, "message code")?;
    let payload_spec = cbor_payload_spec(code);
    let payload = payload_spec
        .map(|spec| cbor_payload(&raw_payload, &ranges, spec))
        .transpose()?;

    let mut rest = Vec::with_capacity(ranges.len().saturating_sub(1));
    for (index, range) in ranges.iter().enumerate().skip(1) {
        let value = match (payload_spec, payload.as_ref()) {
            (Some(spec), Some(payload)) if index == spec.args_index => {
                if payload.args.is_some() {
                    Value::Seq(Vec::new())
                } else {
                    Value::Unit
                }
            }
            (Some(spec), Some(payload)) if index == spec.kwargs_index => {
                if payload.kwargs.is_some() {
                    Value::Map(BTreeMap::new())
                } else {
                    Value::Unit
                }
            }
            _ => cbor_value(&raw_payload, range)?,
        };
        rest.push(value);
    }

    let mut message = parse_value_parts(Serializer::Cbor, code, &rest)?;
    if let Some(payload) = payload {
        replace_message_payload(&mut message, payload);
    }
    Ok(ParsedMessage {
        message,
        raw: raw_payload,
        serializer: Serializer::Cbor,
        encoded_metadata: None,
    })
}

#[derive(Clone, Copy)]
struct CborPayloadSpec {
    args_index: usize,
    args_label: &'static str,
    kwargs_index: usize,
    kwargs_label: &'static str,
}

fn cbor_payload_spec(code: u64) -> Option<CborPayloadSpec> {
    let (args_index, args_label, kwargs_index, kwargs_label) = match code {
        3 => (3, "abort.arguments", 4, "abort.argumentsKw"),
        6 => (3, "goodbye.arguments", 4, "goodbye.argumentsKw"),
        8 => (5, "error.arguments", 6, "error.argumentsKw"),
        16 => (4, "publish.arguments", 5, "publish.argumentsKw"),
        36 => (4, "event.arguments", 5, "event.argumentsKw"),
        48 => (4, "call.arguments", 5, "call.argumentsKw"),
        50 => (3, "result.arguments", 4, "result.argumentsKw"),
        68 => (4, "invocation.arguments", 5, "invocation.argumentsKw"),
        70 => (3, "yield.arguments", 4, "yield.argumentsKw"),
        _ => return None,
    };
    Some(CborPayloadSpec {
        args_index,
        args_label,
        kwargs_index,
        kwargs_label,
    })
}

fn cbor_payload(
    raw_payload: &RawFrame,
    ranges: &[Range<usize>],
    spec: CborPayloadSpec,
) -> Result<Payload, ParseError> {
    let args = cbor_payload_part(
        raw_payload,
        ranges.get(spec.args_index),
        4,
        spec.args_label,
        ParseError::ExpectedList,
    )?;
    let kwargs = cbor_payload_part(
        raw_payload,
        ranges.get(spec.kwargs_index),
        5,
        spec.kwargs_label,
        ParseError::ExpectedMap,
    )?;
    Ok(Payload {
        args,
        kwargs,
        transparent: None,
    })
}

fn cbor_payload_part(
    raw_payload: &RawFrame,
    range: Option<&Range<usize>>,
    expected_major: u8,
    label: &'static str,
    wrong_type: fn(&'static str) -> ParseError,
) -> Result<Option<Bytes>, ParseError> {
    let Some(range) = range else {
        return Ok(None);
    };
    let slice = raw_payload.slice_or_copy(range)?;
    if slice.as_ref() == [0xf6] {
        return Ok(None);
    }
    if slice.first().map(|byte| byte >> 5) != Some(expected_major) {
        return Err(wrong_type(label));
    }
    Ok(Some(slice))
}

fn replace_message_payload(message: &mut WampMessage, payload: Payload) {
    match message {
        WampMessage::Abort {
            payload: current, ..
        }
        | WampMessage::Goodbye {
            payload: current, ..
        }
        | WampMessage::Error {
            payload: current, ..
        }
        | WampMessage::Publish {
            payload: current, ..
        }
        | WampMessage::Event {
            payload: current, ..
        }
        | WampMessage::Call {
            payload: current, ..
        }
        | WampMessage::Result {
            payload: current, ..
        }
        | WampMessage::Invocation {
            payload: current, ..
        }
        | WampMessage::Yield {
            payload: current, ..
        } => *current = payload,
        _ => {}
    }
}

fn cbor_value(raw_payload: &RawFrame, range: &Range<usize>) -> Result<Value, ParseError> {
    let slice = raw_payload.slice_or_copy(range)?;
    let mut de = serde_cbor::Deserializer::from_slice(slice.as_ref());
    Value::deserialize(&mut de).map_err(|err| ParseError::Deserialize(err.to_string()))
}

fn cbor_top_level_ranges(data: &RawFrame) -> Result<Vec<Range<usize>>, ParseError> {
    let prefix = data.slice_or_copy(&(0..data.len().min(9)))?;
    let (header_len, length) = cbor_array_header(prefix.as_ref())?;
    match data {
        RawFrame::Contiguous(bytes) => {
            let body = bytes.get(header_len..).ok_or_else(|| {
                ParseError::Deserialize("truncated CBOR message array header".into())
            })?;
            let mut de = serde_cbor::Deserializer::from_slice(body);
            cbor_value_ranges(data, header_len, length, || {
                IgnoredAny::deserialize(&mut de)
                    .map_err(|err| ParseError::Deserialize(err.to_string()))?;
                Ok(de.byte_offset())
            })
        }
        RawFrame::Segmented { segments, .. } => {
            let mut reader = SegmentedFrameReader::new(segments.clone());
            let mut header = [0u8; 9];
            let header = header.get_mut(..header_len).ok_or_else(|| {
                ParseError::Deserialize(
                    "CBOR message array header exceeds its maximum width".into(),
                )
            })?;
            reader
                .read_exact(header)
                .map_err(|err| ParseError::Deserialize(err.to_string()))?;
            let body_len = reader.remaining;
            cbor_value_ranges(data, header_len, length, || {
                reader.read_cbor_value()?;
                body_len.checked_sub(reader.remaining).ok_or_else(|| {
                    ParseError::Deserialize("CBOR reader advanced before its body".into())
                })
            })
        }
    }
}

fn cbor_value_ranges(
    data: &RawFrame,
    header_len: usize,
    length: Option<usize>,
    mut read_value_end: impl FnMut() -> Result<usize, ParseError>,
) -> Result<Vec<Range<usize>>, ParseError> {
    let mut offset = header_len;
    let mut ranges = Vec::with_capacity(length.unwrap_or(8).min(data.len()));
    loop {
        if let Some(length) = length {
            if ranges.len() == length {
                break;
            }
        } else if data.read_byte(offset).ok() == Some(0xff) {
            break;
        }
        if offset >= data.len() {
            return Err(ParseError::Deserialize(
                "unexpected end of CBOR message array".into(),
            ));
        }
        let start = offset;
        let value_end = read_value_end()?;
        let next_offset = header_len
            .checked_add(value_end)
            .ok_or_else(|| ParseError::Deserialize("CBOR value range overflow".into()))?;
        if next_offset <= offset {
            return Err(ParseError::Deserialize(
                "CBOR value parser made no progress".into(),
            ));
        }
        offset = next_offset;
        ranges.push(start..offset);
    }
    let message_end = if length.is_some() {
        offset
    } else {
        offset
            .checked_add(1)
            .ok_or_else(|| ParseError::Deserialize("CBOR message range overflow".into()))?
    };
    if message_end != data.len() {
        return Err(ParseError::Deserialize(
            "trailing data after CBOR message array".into(),
        ));
    }
    Ok(ranges)
}

fn cbor_array_header(data: &[u8]) -> Result<(usize, Option<usize>), ParseError> {
    let Some(&initial) = data.first() else {
        return Err(ParseError::Deserialize("empty CBOR message".into()));
    };
    if initial >> 5 != 4 {
        return Err(ParseError::ExpectedArray);
    }
    let additional = initial & 0x1f;
    if additional == 31 {
        return Ok((1, None));
    }
    let (header_len, length) = match additional {
        0..=23 => (1, additional as u64),
        24 => (2, cbor_header_integer(data, 1)?),
        25 => (3, cbor_header_integer(data, 2)?),
        26 => (5, cbor_header_integer(data, 4)?),
        27 => (9, cbor_header_integer(data, 8)?),
        _ => {
            return Err(ParseError::Deserialize(
                "reserved CBOR array additional information".into(),
            ));
        }
    };
    let length = usize::try_from(length)
        .map_err(|_| ParseError::Deserialize("CBOR array length exceeds usize".into()))?;
    Ok((header_len, Some(length)))
}

fn cbor_header_integer(data: &[u8], byte_count: usize) -> Result<u64, ParseError> {
    let truncated = || ParseError::Deserialize("truncated CBOR array header".into());
    let source = data
        .get(1..)
        .and_then(|bytes| bytes.get(..byte_count))
        .ok_or_else(truncated)?;
    let start = 8usize.checked_sub(byte_count).ok_or_else(truncated)?;
    let mut encoded = [0u8; 8];
    encoded[start..].copy_from_slice(source);
    Ok(u64::from_be_bytes(encoded))
}

#[derive(Deserialize)]
struct BorrowedFields<'a>(#[serde(borrow)] Vec<&'a RawValue>);

fn parse_json_message(raw_payload: RawFrame) -> Result<ParsedMessage, ParseError> {
    let raw_payload = raw_payload.into_bytes();
    let slice = raw_payload.as_ref();
    let mut deserializer = serde_json::Deserializer::from_slice(slice);
    let BorrowedFields(fields) = BorrowedFields::deserialize(&mut deserializer)
        .map_err(|err| ParseError::Deserialize(err.to_string()))?;
    deserializer
        .end()
        .map_err(|err| ParseError::Deserialize(err.to_string()))?;

    if fields.is_empty() {
        return Err(ParseError::MissingElement("message code"));
    }

    let code = json_u64(fields[0], "message code")?;
    let message = match code {
        1 => {
            let realm_raw = json_get(&fields, 1, "hello.realm")?;
            let details_raw = json_get(&fields, 2, "hello.details")?;
            let realm = json_string(realm_raw, "hello.realm")?;
            let details = json_map(details_raw, "hello.details")?;
            WampMessage::Hello { realm, details }
        }
        2 => {
            let session_raw = json_get(&fields, 1, "welcome.session_id")?;
            let details_raw = json_get(&fields, 2, "welcome.details")?;
            let session_id = json_u64(session_raw, "welcome.session_id")?;
            let details = json_map(details_raw, "welcome.details")?;
            WampMessage::Welcome {
                session_id,
                details,
            }
        }
        3 => {
            let details_raw = json_get(&fields, 1, "abort.details")?;
            let reason_raw = json_get(&fields, 2, "abort.reason")?;
            let payload = json_payload(
                &raw_payload,
                "abort.arguments",
                fields.get(3).copied(),
                "abort.argumentsKw",
                fields.get(4).copied(),
            )?;
            WampMessage::Abort {
                details: json_map(details_raw, "abort.details")?,
                reason: json_string(reason_raw, "abort.reason")?,
                payload,
            }
        }
        4 => {
            let method_raw = json_get(&fields, 1, "challenge.auth_method")?;
            let extra_raw = json_get(&fields, 2, "challenge.extra")?;
            WampMessage::Challenge {
                auth_method: json_string(method_raw, "challenge.auth_method")?,
                extra: json_map(extra_raw, "challenge.extra")?,
            }
        }
        5 => {
            let signature_raw = json_get(&fields, 1, "authenticate.signature")?;
            let extra_raw = fields.get(2).copied();
            WampMessage::Authenticate {
                signature: json_string(signature_raw, "authenticate.signature")?,
                extra: json_optional_map(extra_raw, "authenticate.extra")?,
            }
        }
        6 => {
            let details_raw = json_get(&fields, 1, "goodbye.details")?;
            let reason_raw = json_get(&fields, 2, "goodbye.reason")?;
            let payload = json_payload(
                &raw_payload,
                "goodbye.arguments",
                fields.get(3).copied(),
                "goodbye.argumentsKw",
                fields.get(4).copied(),
            )?;
            WampMessage::Goodbye {
                details: json_map(details_raw, "goodbye.details")?,
                reason: json_string(reason_raw, "goodbye.reason")?,
                payload,
            }
        }
        7 => {
            let details_raw = json_get(&fields, 1, "heartbeat.details")?;
            let ping = json_optional_u64(fields.get(2).copied(), "heartbeat.ping")?;
            let incoming = json_optional_u64(fields.get(3).copied(), "heartbeat.incoming")?;
            let outgoing = json_optional_u64(fields.get(4).copied(), "heartbeat.outgoing")?;
            WampMessage::Heartbeat {
                details: json_map(details_raw, "heartbeat.details")?,
                ping,
                incoming,
                outgoing,
            }
        }
        8 => {
            let request_type_raw = json_get(&fields, 1, "error.request_type")?;
            let request_id_raw = json_get(&fields, 2, "error.request_id")?;
            let details_raw = json_get(&fields, 3, "error.details")?;
            let error_raw = json_get(&fields, 4, "error.uri")?;
            let payload = json_payload(
                &raw_payload,
                "error.arguments",
                fields.get(5).copied(),
                "error.argumentsKw",
                fields.get(6).copied(),
            )?;
            WampMessage::Error {
                request_type: json_u64(request_type_raw, "error.request_type")?,
                request_id: json_u64(request_id_raw, "error.request_id")?,
                details: json_map(details_raw, "error.details")?,
                error: json_string(error_raw, "error.uri")?,
                payload,
            }
        }
        16 => {
            let request_raw = json_get(&fields, 1, "publish.request_id")?;
            let options_raw = json_get(&fields, 2, "publish.options")?;
            let topic_raw = json_get(&fields, 3, "publish.topic")?;
            let payload = json_payload(
                &raw_payload,
                "publish.arguments",
                fields.get(4).copied(),
                "publish.argumentsKw",
                fields.get(5).copied(),
            )?;
            WampMessage::Publish {
                request_id: json_u64(request_raw, "publish.request_id")?,
                options: json_map(options_raw, "publish.options")?,
                topic: json_string(topic_raw, "publish.topic")?,
                payload,
            }
        }
        17 => {
            let request_raw = json_get(&fields, 1, "published.request_id")?;
            let publication_raw = json_get(&fields, 2, "published.publication_id")?;
            WampMessage::Published {
                request_id: json_u64(request_raw, "published.request_id")?,
                publication_id: json_u64(publication_raw, "published.publication_id")?,
            }
        }
        32 => {
            let request_raw = json_get(&fields, 1, "subscribe.request_id")?;
            let options_raw = json_get(&fields, 2, "subscribe.options")?;
            let topic_raw = json_get(&fields, 3, "subscribe.topic")?;
            WampMessage::Subscribe {
                request_id: json_u64(request_raw, "subscribe.request_id")?,
                options: json_map(options_raw, "subscribe.options")?,
                topic: json_string(topic_raw, "subscribe.topic")?,
            }
        }
        33 => {
            let request_raw = json_get(&fields, 1, "subscribed.request_id")?;
            let subscription_raw = json_get(&fields, 2, "subscribed.subscription_id")?;
            WampMessage::Subscribed {
                request_id: json_u64(request_raw, "subscribed.request_id")?,
                subscription_id: json_u64(subscription_raw, "subscribed.subscription_id")?,
            }
        }
        34 => {
            let request_raw = json_get(&fields, 1, "unsubscribe.request_id")?;
            let subscription_raw = json_get(&fields, 2, "unsubscribe.subscription_id")?;
            WampMessage::Unsubscribe {
                request_id: json_u64(request_raw, "unsubscribe.request_id")?,
                subscription_id: json_u64(subscription_raw, "unsubscribe.subscription_id")?,
            }
        }
        35 => {
            let request_raw = json_get(&fields, 1, "unsubscribed.request_id")?;
            let details_raw = fields.get(2).copied();
            WampMessage::Unsubscribed {
                request_id: json_u64(request_raw, "unsubscribed.request_id")?,
                details: json_optional_map(details_raw, "unsubscribed.details")?,
            }
        }
        36 => {
            let subscription_raw = json_get(&fields, 1, "event.subscription_id")?;
            let publication_raw = json_get(&fields, 2, "event.publication_id")?;
            let details_raw = json_get(&fields, 3, "event.details")?;
            let payload = json_payload(
                &raw_payload,
                "event.arguments",
                fields.get(4).copied(),
                "event.argumentsKw",
                fields.get(5).copied(),
            )?;
            WampMessage::Event {
                subscription_id: json_u64(subscription_raw, "event.subscription_id")?,
                publication_id: json_u64(publication_raw, "event.publication_id")?,
                details: json_map(details_raw, "event.details")?,
                payload,
            }
        }
        48 => {
            let request_raw = json_get(&fields, 1, "call.request_id")?;
            let options_raw = json_get(&fields, 2, "call.options")?;
            let procedure_raw = json_get(&fields, 3, "call.procedure")?;
            let payload = json_payload(
                &raw_payload,
                "call.arguments",
                fields.get(4).copied(),
                "call.argumentsKw",
                fields.get(5).copied(),
            )?;
            WampMessage::Call {
                request_id: json_u64(request_raw, "call.request_id")?,
                options: json_map(options_raw, "call.options")?,
                procedure: json_string(procedure_raw, "call.procedure")?,
                payload,
            }
        }
        49 => {
            let request_raw = json_get(&fields, 1, "cancel.request_id")?;
            let options_raw = json_get(&fields, 2, "cancel.options")?;
            WampMessage::Cancel {
                request_id: json_u64(request_raw, "cancel.request_id")?,
                options: json_map(options_raw, "cancel.options")?,
            }
        }
        50 => {
            let request_raw = json_get(&fields, 1, "result.request_id")?;
            let details_raw = json_get(&fields, 2, "result.details")?;
            let payload = json_payload(
                &raw_payload,
                "result.arguments",
                fields.get(3).copied(),
                "result.argumentsKw",
                fields.get(4).copied(),
            )?;
            WampMessage::Result {
                request_id: json_u64(request_raw, "result.request_id")?,
                details: json_map(details_raw, "result.details")?,
                payload,
            }
        }
        64 => {
            let request_raw = json_get(&fields, 1, "register.request_id")?;
            let options_raw = json_get(&fields, 2, "register.options")?;
            let procedure_raw = json_get(&fields, 3, "register.procedure")?;
            WampMessage::Register {
                request_id: json_u64(request_raw, "register.request_id")?,
                options: json_map(options_raw, "register.options")?,
                procedure: json_string(procedure_raw, "register.procedure")?,
            }
        }
        65 => {
            let request_raw = json_get(&fields, 1, "registered.request_id")?;
            let registration_raw = json_get(&fields, 2, "registered.registration_id")?;
            WampMessage::Registered {
                request_id: json_u64(request_raw, "registered.request_id")?,
                registration_id: json_u64(registration_raw, "registered.registration_id")?,
            }
        }
        66 => {
            let request_raw = json_get(&fields, 1, "unregister.request_id")?;
            let registration_raw = json_get(&fields, 2, "unregister.registration_id")?;
            WampMessage::Unregister {
                request_id: json_u64(request_raw, "unregister.request_id")?,
                registration_id: json_u64(registration_raw, "unregister.registration_id")?,
            }
        }
        67 => {
            let request_raw = json_get(&fields, 1, "unregistered.request_id")?;
            WampMessage::Unregistered {
                request_id: json_u64(request_raw, "unregistered.request_id")?,
                details: json_optional_map(fields.get(2).copied(), "unregistered.details")?,
            }
        }
        68 => {
            let request_raw = json_get(&fields, 1, "invocation.request_id")?;
            let registration_raw = json_get(&fields, 2, "invocation.registration_id")?;
            let details_raw = json_get(&fields, 3, "invocation.details")?;
            let payload = json_payload(
                &raw_payload,
                "invocation.arguments",
                fields.get(4).copied(),
                "invocation.argumentsKw",
                fields.get(5).copied(),
            )?;
            WampMessage::Invocation {
                request_id: json_u64(request_raw, "invocation.request_id")?,
                registration_id: json_u64(registration_raw, "invocation.registration_id")?,
                details: json_map(details_raw, "invocation.details")?,
                payload,
            }
        }
        69 => {
            let request_raw = json_get(&fields, 1, "interrupt.request_id")?;
            let options_raw = json_get(&fields, 2, "interrupt.options")?;
            WampMessage::Interrupt {
                request_id: json_u64(request_raw, "interrupt.request_id")?,
                options: json_map(options_raw, "interrupt.options")?,
            }
        }
        70 => {
            let request_raw = json_get(&fields, 1, "yield.request_id")?;
            let options_raw = json_get(&fields, 2, "yield.options")?;
            let payload = json_payload(
                &raw_payload,
                "yield.arguments",
                fields.get(3).copied(),
                "yield.argumentsKw",
                fields.get(4).copied(),
            )?;
            WampMessage::Yield {
                request_id: json_u64(request_raw, "yield.request_id")?,
                options: json_map(options_raw, "yield.options")?,
                payload,
            }
        }
        _ => {
            let mut extras = Vec::new();
            for raw in fields.iter().skip(1) {
                let value: serde_json::Value = serde_json::from_str(raw.get())
                    .map_err(|err| ParseError::Deserialize(err.to_string()))?;
                let value = serde_value::to_value(value)
                    .map_err(|err| ParseError::Deserialize(err.to_string()))?;
                extras.push(value);
            }
            WampMessage::Unknown {
                code,
                fields: extras,
            }
        }
    };

    Ok(ParsedMessage {
        message,
        raw: RawFrame::Contiguous(raw_payload),
        serializer: Serializer::Json,
        encoded_metadata: None,
    })
}

fn parse_msgpack_message(raw_payload: RawFrame) -> Result<ParsedMessage, ParseError> {
    let mut offset = 0;
    let len = msgpack_read_array_len(&raw_payload, &mut offset)?;
    if len == 0 {
        return Err(ParseError::MissingElement("message code"));
    }

    let mut ranges = Vec::with_capacity(len);
    for _ in 0..len {
        ranges.push(msgpack_read_value_range(&raw_payload, &mut offset)?);
    }
    if offset != raw_payload.len() {
        return Err(ParseError::Deserialize(
            "trailing data after MessagePack message array".into(),
        ));
    }

    let code = msgpack_u64(
        &raw_payload,
        range_at(&ranges, 0, "message code")?,
        "message code",
    )?;
    let data = &raw_payload;
    let message = match code {
        1 => {
            let realm = msgpack_string(data, range_at(&ranges, 1, "hello.realm")?, "hello.realm")?;
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 2, "hello.details")?,
                "hello.details",
            )?;
            WampMessage::Hello { realm, details }
        }
        2 => {
            let session_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "welcome.session_id")?,
                "welcome.session_id",
            )?;
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 2, "welcome.details")?,
                "welcome.details",
            )?;
            WampMessage::Welcome {
                session_id,
                details,
            }
        }
        3 => {
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 1, "abort.details")?,
                "abort.details",
            )?;
            let reason =
                msgpack_string(data, range_at(&ranges, 2, "abort.reason")?, "abort.reason")?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "abort.arguments",
                range_opt(&ranges, 3),
                "abort.argumentsKw",
                range_opt(&ranges, 4),
            )?;
            WampMessage::Abort {
                details,
                reason,
                payload,
            }
        }
        4 => {
            let auth_method = msgpack_string(
                data,
                range_at(&ranges, 1, "challenge.auth_method")?,
                "challenge.auth_method",
            )?;
            let extra = msgpack_required_map(
                data,
                range_at(&ranges, 2, "challenge.extra")?,
                "challenge.extra",
            )?;
            WampMessage::Challenge { auth_method, extra }
        }
        5 => {
            let signature = msgpack_string(
                data,
                range_at(&ranges, 1, "authenticate.signature")?,
                "authenticate.signature",
            )?;
            let extra = msgpack_optional_map(data, range_opt(&ranges, 2), "authenticate.extra")?;
            WampMessage::Authenticate { signature, extra }
        }
        6 => {
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 1, "goodbye.details")?,
                "goodbye.details",
            )?;
            let reason = msgpack_string(
                data,
                range_at(&ranges, 2, "goodbye.reason")?,
                "goodbye.reason",
            )?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "goodbye.arguments",
                range_opt(&ranges, 3),
                "goodbye.argumentsKw",
                range_opt(&ranges, 4),
            )?;
            WampMessage::Goodbye {
                details,
                reason,
                payload,
            }
        }
        7 => {
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 1, "heartbeat.details")?,
                "heartbeat.details",
            )?;
            let ping = msgpack_optional_u64(data, range_opt(&ranges, 2), "heartbeat.ping")?;
            let incoming = msgpack_optional_u64(data, range_opt(&ranges, 3), "heartbeat.incoming")?;
            let outgoing = msgpack_optional_u64(data, range_opt(&ranges, 4), "heartbeat.outgoing")?;
            WampMessage::Heartbeat {
                details,
                ping,
                incoming,
                outgoing,
            }
        }
        8 => {
            let request_type = msgpack_u64(
                data,
                range_at(&ranges, 1, "error.request_type")?,
                "error.request_type",
            )?;
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 2, "error.request_id")?,
                "error.request_id",
            )?;
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 3, "error.details")?,
                "error.details",
            )?;
            let error = msgpack_string(data, range_at(&ranges, 4, "error.uri")?, "error.uri")?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "error.arguments",
                range_opt(&ranges, 5),
                "error.argumentsKw",
                range_opt(&ranges, 6),
            )?;
            WampMessage::Error {
                request_type,
                request_id,
                details,
                error,
                payload,
            }
        }
        16 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "publish.request_id")?,
                "publish.request_id",
            )?;
            let options = msgpack_required_map(
                data,
                range_at(&ranges, 2, "publish.options")?,
                "publish.options",
            )?;
            let topic = msgpack_string(
                data,
                range_at(&ranges, 3, "publish.topic")?,
                "publish.topic",
            )?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "publish.arguments",
                range_opt(&ranges, 4),
                "publish.argumentsKw",
                range_opt(&ranges, 5),
            )?;
            WampMessage::Publish {
                request_id,
                options,
                topic,
                payload,
            }
        }
        17 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "published.request_id")?,
                "published.request_id",
            )?;
            let publication_id = msgpack_u64(
                data,
                range_at(&ranges, 2, "published.publication_id")?,
                "published.publication_id",
            )?;
            WampMessage::Published {
                request_id,
                publication_id,
            }
        }
        32 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "subscribe.request_id")?,
                "subscribe.request_id",
            )?;
            let options = msgpack_required_map(
                data,
                range_at(&ranges, 2, "subscribe.options")?,
                "subscribe.options",
            )?;
            let topic = msgpack_string(
                data,
                range_at(&ranges, 3, "subscribe.topic")?,
                "subscribe.topic",
            )?;
            WampMessage::Subscribe {
                request_id,
                options,
                topic,
            }
        }
        33 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "subscribed.request_id")?,
                "subscribed.request_id",
            )?;
            let subscription_id = msgpack_u64(
                data,
                range_at(&ranges, 2, "subscribed.subscription_id")?,
                "subscribed.subscription_id",
            )?;
            WampMessage::Subscribed {
                request_id,
                subscription_id,
            }
        }
        34 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "unsubscribe.request_id")?,
                "unsubscribe.request_id",
            )?;
            let subscription_id = msgpack_u64(
                data,
                range_at(&ranges, 2, "unsubscribe.subscription_id")?,
                "unsubscribe.subscription_id",
            )?;
            WampMessage::Unsubscribe {
                request_id,
                subscription_id,
            }
        }
        35 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "unsubscribed.request_id")?,
                "unsubscribed.request_id",
            )?;
            let details =
                msgpack_optional_map(data, range_opt(&ranges, 2), "unsubscribed.details")?;
            WampMessage::Unsubscribed {
                request_id,
                details,
            }
        }
        36 => {
            let subscription_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "event.subscription_id")?,
                "event.subscription_id",
            )?;
            let publication_id = msgpack_u64(
                data,
                range_at(&ranges, 2, "event.publication_id")?,
                "event.publication_id",
            )?;
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 3, "event.details")?,
                "event.details",
            )?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "event.arguments",
                range_opt(&ranges, 4),
                "event.argumentsKw",
                range_opt(&ranges, 5),
            )?;
            WampMessage::Event {
                subscription_id,
                publication_id,
                details,
                payload,
            }
        }
        48 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "call.request_id")?,
                "call.request_id",
            )?;
            let options =
                msgpack_required_map(data, range_at(&ranges, 2, "call.options")?, "call.options")?;
            let procedure = msgpack_string(
                data,
                range_at(&ranges, 3, "call.procedure")?,
                "call.procedure",
            )?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "call.arguments",
                range_opt(&ranges, 4),
                "call.argumentsKw",
                range_opt(&ranges, 5),
            )?;
            WampMessage::Call {
                request_id,
                options,
                procedure,
                payload,
            }
        }
        49 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "cancel.request_id")?,
                "cancel.request_id",
            )?;
            let options = msgpack_required_map(
                data,
                range_at(&ranges, 2, "cancel.options")?,
                "cancel.options",
            )?;
            WampMessage::Cancel {
                request_id,
                options,
            }
        }
        50 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "result.request_id")?,
                "result.request_id",
            )?;
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 2, "result.details")?,
                "result.details",
            )?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "result.arguments",
                range_opt(&ranges, 3),
                "result.argumentsKw",
                range_opt(&ranges, 4),
            )?;
            WampMessage::Result {
                request_id,
                details,
                payload,
            }
        }
        64 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "register.request_id")?,
                "register.request_id",
            )?;
            let options = msgpack_required_map(
                data,
                range_at(&ranges, 2, "register.options")?,
                "register.options",
            )?;
            let procedure = msgpack_string(
                data,
                range_at(&ranges, 3, "register.procedure")?,
                "register.procedure",
            )?;
            WampMessage::Register {
                request_id,
                options,
                procedure,
            }
        }
        65 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "registered.request_id")?,
                "registered.request_id",
            )?;
            let registration_id = msgpack_u64(
                data,
                range_at(&ranges, 2, "registered.registration_id")?,
                "registered.registration_id",
            )?;
            WampMessage::Registered {
                request_id,
                registration_id,
            }
        }
        66 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "unregister.request_id")?,
                "unregister.request_id",
            )?;
            let registration_id = msgpack_u64(
                data,
                range_at(&ranges, 2, "unregister.registration_id")?,
                "unregister.registration_id",
            )?;
            WampMessage::Unregister {
                request_id,
                registration_id,
            }
        }
        67 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "unregistered.request_id")?,
                "unregistered.request_id",
            )?;
            WampMessage::Unregistered {
                request_id,
                details: msgpack_optional_map(data, range_opt(&ranges, 2), "unregistered.details")?,
            }
        }
        68 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "invocation.request_id")?,
                "invocation.request_id",
            )?;
            let registration_id = msgpack_u64(
                data,
                range_at(&ranges, 2, "invocation.registration_id")?,
                "invocation.registration_id",
            )?;
            let details = msgpack_required_map(
                data,
                range_at(&ranges, 3, "invocation.details")?,
                "invocation.details",
            )?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "invocation.arguments",
                range_opt(&ranges, 4),
                "invocation.argumentsKw",
                range_opt(&ranges, 5),
            )?;
            WampMessage::Invocation {
                request_id,
                registration_id,
                details,
                payload,
            }
        }
        69 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "interrupt.request_id")?,
                "interrupt.request_id",
            )?;
            let options = msgpack_required_map(
                data,
                range_at(&ranges, 2, "interrupt.options")?,
                "interrupt.options",
            )?;
            WampMessage::Interrupt {
                request_id,
                options,
            }
        }
        70 => {
            let request_id = msgpack_u64(
                data,
                range_at(&ranges, 1, "yield.request_id")?,
                "yield.request_id",
            )?;
            let options = msgpack_required_map(
                data,
                range_at(&ranges, 2, "yield.options")?,
                "yield.options",
            )?;
            let payload = msgpack_payload(
                &raw_payload,
                data,
                "yield.arguments",
                range_opt(&ranges, 3),
                "yield.argumentsKw",
                range_opt(&ranges, 4),
            )?;
            WampMessage::Yield {
                request_id,
                options,
                payload,
            }
        }
        _ => {
            let mut fields = Vec::new();
            for range in ranges.iter().skip(1) {
                fields.push(msgpack_value(data, range)?);
            }
            WampMessage::Unknown { code, fields }
        }
    };

    Ok(ParsedMessage {
        message,
        raw: raw_payload,
        serializer: Serializer::MessagePack,
        encoded_metadata: None,
    })
}

fn range_at<'a>(
    ranges: &'a [Range<usize>],
    index: usize,
    label: &'static str,
) -> Result<&'a Range<usize>, ParseError> {
    ranges.get(index).ok_or(ParseError::MissingElement(label))
}

fn range_opt<'a>(ranges: &'a [Range<usize>], index: usize) -> Option<&'a Range<usize>> {
    ranges.get(index)
}

fn msgpack_read_array_len(data: &RawFrame, offset: &mut usize) -> Result<usize, ParseError> {
    let marker = read_u8(data, offset).map_err(|_| ParseError::ExpectedArray)?;
    match marker {
        0x90..=0x9f => Ok((marker & 0x0f) as usize),
        0xdc => Ok(read_u16(data, offset)? as usize),
        0xdd => {
            let len = read_u32(data, offset)?;
            Ok(u32_to_usize(len)?)
        }
        _ => Err(ParseError::ExpectedArray),
    }
}

fn msgpack_read_value_range(
    data: &RawFrame,
    offset: &mut usize,
) -> Result<Range<usize>, ParseError> {
    let start = *offset;
    msgpack_skip_value(data, offset)?;
    Ok(start..*offset)
}

fn msgpack_skip_value(data: &RawFrame, offset: &mut usize) -> Result<(), ParseError> {
    let marker = read_u8(data, offset)?;
    match marker {
        0x00..=0x7f | 0xe0..=0xff | 0xc0 | 0xc2 | 0xc3 => Ok(()),
        0xcc => skip_bytes(data, offset, 1),
        0xcd => skip_bytes(data, offset, 2),
        0xce => skip_bytes(data, offset, 4),
        0xcf => skip_bytes(data, offset, 8),
        0xd0 => skip_bytes(data, offset, 1),
        0xd1 => skip_bytes(data, offset, 2),
        0xd2 => skip_bytes(data, offset, 4),
        0xd3 => skip_bytes(data, offset, 8),
        0xca => skip_bytes(data, offset, 4),
        0xcb => skip_bytes(data, offset, 8),
        0xa0..=0xbf => skip_bytes(data, offset, (marker & 0x1f) as usize),
        0xd9 => {
            let len = read_u8(data, offset)? as usize;
            skip_bytes(data, offset, len)
        }
        0xda => {
            let len = read_u16(data, offset)? as usize;
            skip_bytes(data, offset, len)
        }
        0xdb => {
            let len = u32_to_usize(read_u32(data, offset)?)?;
            skip_bytes(data, offset, len)
        }
        0xc4 => {
            let len = read_u8(data, offset)? as usize;
            skip_bytes(data, offset, len)
        }
        0xc5 => {
            let len = read_u16(data, offset)? as usize;
            skip_bytes(data, offset, len)
        }
        0xc6 => {
            let len = u32_to_usize(read_u32(data, offset)?)?;
            skip_bytes(data, offset, len)
        }
        0x90..=0x9f => {
            let len = (marker & 0x0f) as usize;
            for _ in 0..len {
                msgpack_skip_value(data, offset)?;
            }
            Ok(())
        }
        0xdc => {
            let len = read_u16(data, offset)? as usize;
            for _ in 0..len {
                msgpack_skip_value(data, offset)?;
            }
            Ok(())
        }
        0xdd => {
            let len = u32_to_usize(read_u32(data, offset)?)?;
            for _ in 0..len {
                msgpack_skip_value(data, offset)?;
            }
            Ok(())
        }
        0x80..=0x8f => {
            let len = (marker & 0x0f) as usize;
            for _ in 0..len {
                msgpack_skip_value(data, offset)?;
                msgpack_skip_value(data, offset)?;
            }
            Ok(())
        }
        0xde => {
            let len = read_u16(data, offset)? as usize;
            for _ in 0..len {
                msgpack_skip_value(data, offset)?;
                msgpack_skip_value(data, offset)?;
            }
            Ok(())
        }
        0xdf => {
            let len = u32_to_usize(read_u32(data, offset)?)?;
            for _ in 0..len {
                msgpack_skip_value(data, offset)?;
                msgpack_skip_value(data, offset)?;
            }
            Ok(())
        }
        0xd4 => skip_ext(data, offset, 1),
        0xd5 => skip_ext(data, offset, 2),
        0xd6 => skip_ext(data, offset, 4),
        0xd7 => skip_ext(data, offset, 8),
        0xd8 => skip_ext(data, offset, 16),
        0xc7 => {
            let len = read_u8(data, offset)? as usize;
            skip_ext(data, offset, len)
        }
        0xc8 => {
            let len = read_u16(data, offset)? as usize;
            skip_ext(data, offset, len)
        }
        0xc9 => {
            let len = u32_to_usize(read_u32(data, offset)?)?;
            skip_ext(data, offset, len)
        }
        0xc1 => Err(ParseError::Deserialize(
            "encountered reserved MessagePack marker 0xc1".into(),
        )),
    }
}

fn skip_ext(data: &RawFrame, offset: &mut usize, ext_len: usize) -> Result<(), ParseError> {
    let length = ext_len.checked_add(1).ok_or_else(|| {
        ParseError::Deserialize("MessagePack extension length exceeds supported size".into())
    })?;
    skip_bytes(data, offset, length)
}

fn read_u8(data: &RawFrame, offset: &mut usize) -> Result<u8, ParseError> {
    let value = data
        .read_byte(*offset)
        .map_err(|_| ParseError::Deserialize("unexpected end of MessagePack data".into()))?;
    *offset = offset.saturating_add(1);
    Ok(value)
}

fn read_u16(data: &RawFrame, offset: &mut usize) -> Result<u16, ParseError> {
    let end = offset.saturating_add(2);
    let bytes = data.slice_or_copy(&(*offset..end))?;
    let value = u16::from_be_bytes(
        bytes
            .as_ref()
            .try_into()
            .map_err(|_| ParseError::Deserialize("unexpected end of MessagePack data".into()))?,
    );
    *offset = end;
    Ok(value)
}

fn read_u32(data: &RawFrame, offset: &mut usize) -> Result<u32, ParseError> {
    let end = offset.saturating_add(4);
    let bytes = data.slice_or_copy(&(*offset..end))?;
    let value = u32::from_be_bytes(
        bytes
            .as_ref()
            .try_into()
            .map_err(|_| ParseError::Deserialize("unexpected end of MessagePack data".into()))?,
    );
    *offset = end;
    Ok(value)
}

fn u32_to_usize(value: u32) -> Result<usize, ParseError> {
    usize::try_from(value)
        .map_err(|_| ParseError::Deserialize("MessagePack length exceeds supported size".into()))
}

fn skip_bytes(data: &RawFrame, offset: &mut usize, len: usize) -> Result<(), ParseError> {
    if data.len().saturating_sub(*offset) < len {
        return Err(ParseError::Deserialize(
            "unexpected end of MessagePack data".into(),
        ));
    }
    *offset = offset.saturating_add(len);
    Ok(())
}

fn msgpack_string(
    data: &RawFrame,
    range: &Range<usize>,
    label: &'static str,
) -> Result<String, ParseError> {
    let slice = data.slice_or_copy(range)?;
    if msgpack_is_nil(slice.as_ref()) {
        return Err(ParseError::ExpectedString(label));
    }
    let mut de = rmp_serde::Deserializer::new(Cursor::new(slice.as_ref()));
    String::deserialize(&mut de).map_err(|_| ParseError::ExpectedString(label))
}

fn msgpack_u64(
    data: &RawFrame,
    range: &Range<usize>,
    label: &'static str,
) -> Result<u64, ParseError> {
    let slice = data.slice_or_copy(range)?;
    if msgpack_is_nil(slice.as_ref()) {
        return Err(ParseError::ExpectedIdentifier(label));
    }
    let mut de = rmp_serde::Deserializer::new(Cursor::new(slice.as_ref()));
    u64::deserialize(&mut de).map_err(|_| ParseError::ExpectedIdentifier(label))
}

fn msgpack_optional_u64(
    data: &RawFrame,
    range: Option<&Range<usize>>,
    label: &'static str,
) -> Result<Option<u64>, ParseError> {
    match range {
        None => Ok(None),
        Some(range) => {
            let slice = data.slice_or_copy(range)?;
            if msgpack_is_nil(slice.as_ref()) {
                Ok(None)
            } else {
                msgpack_u64(data, range, label).map(Some)
            }
        }
    }
}

fn msgpack_required_map(
    data: &RawFrame,
    range: &Range<usize>,
    label: &'static str,
) -> Result<ValueMap, ParseError> {
    let slice = data.slice_or_copy(range)?;
    if msgpack_is_nil(slice.as_ref()) {
        return Err(ParseError::ExpectedMap(label));
    }
    msgpack_map_from_slice(slice.as_ref(), label)
}

fn msgpack_optional_map(
    data: &RawFrame,
    range: Option<&Range<usize>>,
    label: &'static str,
) -> Result<ValueMap, ParseError> {
    match range {
        None => Ok(ValueMap::new()),
        Some(range) => {
            let slice = data.slice_or_copy(range)?;
            if msgpack_is_nil(slice.as_ref()) {
                Ok(ValueMap::new())
            } else {
                msgpack_map_from_slice(slice.as_ref(), label)
            }
        }
    }
}

fn msgpack_map_from_slice(slice: &[u8], label: &'static str) -> Result<ValueMap, ParseError> {
    if !msgpack_is_map(slice) {
        return Err(ParseError::ExpectedMap(label));
    }
    let mut de = rmp_serde::Deserializer::new(Cursor::new(slice));
    let value =
        Value::deserialize(&mut de).map_err(|err| ParseError::Deserialize(err.to_string()))?;
    match value {
        Value::Map(entries) => Ok(entries.into_iter().collect()),
        _ => Err(ParseError::ExpectedMap(label)),
    }
}

fn msgpack_payload(
    raw_payload: &RawFrame,
    data: &RawFrame,
    args_label: &'static str,
    args_range: Option<&Range<usize>>,
    kwargs_label: &'static str,
    kwargs_range: Option<&Range<usize>>,
) -> Result<Payload, ParseError> {
    let args = match args_range {
        None => None,
        Some(range) => {
            let slice = data.slice_or_copy(range)?;
            if msgpack_is_nil(slice.as_ref()) {
                None
            } else if msgpack_is_array(slice.as_ref()) {
                Some(raw_payload.slice_or_copy(range)?)
            } else {
                return Err(ParseError::ExpectedList(args_label));
            }
        }
    };

    let kwargs = match kwargs_range {
        None => None,
        Some(range) => {
            let slice = data.slice_or_copy(range)?;
            if msgpack_is_nil(slice.as_ref()) {
                None
            } else if msgpack_is_map(slice.as_ref()) {
                Some(raw_payload.slice_or_copy(range)?)
            } else {
                return Err(ParseError::ExpectedMap(kwargs_label));
            }
        }
    };

    Ok(Payload {
        args,
        kwargs,
        transparent: None,
    })
}

fn msgpack_value(data: &RawFrame, range: &Range<usize>) -> Result<Value, ParseError> {
    let slice = data.slice_or_copy(range)?;
    let mut de = rmp_serde::Deserializer::new(Cursor::new(slice.as_ref()));
    Value::deserialize(&mut de).map_err(|err| ParseError::Deserialize(err.to_string()))
}

fn msgpack_is_nil(slice: &[u8]) -> bool {
    matches!(slice.first(), Some(0xc0))
}

fn msgpack_is_array(slice: &[u8]) -> bool {
    match slice.first() {
        Some(b) => (0x90..=0x9f).contains(b) || *b == 0xdc || *b == 0xdd,
        None => false,
    }
}

fn msgpack_is_map(slice: &[u8]) -> bool {
    match slice.first() {
        Some(b) => (0x80..=0x8f).contains(b) || *b == 0xde || *b == 0xdf,
        None => false,
    }
}

fn json_get<'a>(
    fields: &'a [&'a RawValue],
    index: usize,
    label: &'static str,
) -> Result<&'a RawValue, ParseError> {
    fields
        .get(index)
        .copied()
        .ok_or(ParseError::MissingElement(label))
}

fn json_string(raw: &RawValue, label: &'static str) -> Result<String, ParseError> {
    if is_json_null(raw.get()) {
        return Err(ParseError::ExpectedString(label));
    }
    serde_json::from_str(raw.get()).map_err(|err| ParseError::Deserialize(err.to_string()))
}

fn json_u64(raw: &RawValue, label: &'static str) -> Result<u64, ParseError> {
    serde_json::from_str(raw.get()).map_err(|_| ParseError::ExpectedIdentifier(label))
}

fn json_optional_u64(
    raw: Option<&RawValue>,
    label: &'static str,
) -> Result<Option<u64>, ParseError> {
    match raw {
        None => Ok(None),
        Some(raw) => {
            if is_json_null(raw.get()) {
                Ok(None)
            } else {
                json_u64(raw, label).map(Some)
            }
        }
    }
}

fn json_map(raw: &RawValue, label: &'static str) -> Result<ValueMap, ParseError> {
    if is_json_null(raw.get()) {
        return Ok(ValueMap::new());
    }
    if !matches!(first_non_ws(raw.get()), Some('{')) {
        return Err(ParseError::ExpectedMap(label));
    }
    let json_value: serde_json::Value =
        serde_json::from_str(raw.get()).map_err(|err| ParseError::Deserialize(err.to_string()))?;
    match serde_value::to_value(json_value)
        .map_err(|err| ParseError::Deserialize(err.to_string()))?
    {
        Value::Map(entries) => Ok(entries.into_iter().collect()),
        _ => Err(ParseError::ExpectedMap(label)),
    }
}

fn json_optional_map(raw: Option<&RawValue>, label: &'static str) -> Result<ValueMap, ParseError> {
    match raw {
        None => Ok(ValueMap::new()),
        Some(raw) => json_map(raw, label),
    }
}

fn json_payload(
    raw_payload: &Bytes,
    args_label: &'static str,
    args: Option<&RawValue>,
    kwargs_label: &'static str,
    kwargs: Option<&RawValue>,
) -> Result<Payload, ParseError> {
    let args_bytes = match args {
        None => None,
        Some(raw) => {
            if is_json_null(raw.get()) {
                None
            } else if matches!(first_non_ws(raw.get()), Some('[')) {
                Some(slice_raw(raw_payload, raw))
            } else {
                return Err(ParseError::ExpectedList(args_label));
            }
        }
    };

    let kwargs_bytes = match kwargs {
        None => None,
        Some(raw) => {
            if is_json_null(raw.get()) {
                None
            } else if matches!(first_non_ws(raw.get()), Some('{')) {
                Some(slice_raw(raw_payload, raw))
            } else {
                return Err(ParseError::ExpectedMap(kwargs_label));
            }
        }
    };

    Ok(Payload {
        args: args_bytes,
        kwargs: kwargs_bytes,
        transparent: None,
    })
}

fn slice_raw(raw_payload: &Bytes, raw_value: &RawValue) -> Bytes {
    raw_payload.slice_ref(raw_value.get().as_bytes())
}

fn first_non_ws(s: &str) -> Option<char> {
    s.chars().find(|c| !c.is_ascii_whitespace())
}

fn is_json_null(s: &str) -> bool {
    s.trim().eq("null")
}

struct SegmentedFrameReader {
    parts: SegmentedPartsReader,
    remaining: usize,
}

impl SegmentedFrameReader {
    fn read_cbor_value(&mut self) -> Result<(), ParseError> {
        // Native outbound segments often contain a whole encoded argument value.
        // Let serde borrow that segment instead of copying it into an IO scratch
        // buffer. A value spanning segments keeps the original reader path.
        let consumed = {
            let chunk = self
                .parts
                .segments
                .iter()
                .find(|part| !part.is_empty())
                .map(Bytes::as_ref)
                .unwrap_or(&[]);
            let mut de = serde_cbor::Deserializer::from_slice(chunk);
            IgnoredAny::deserialize(&mut de)
                .ok()
                .map(|_| de.byte_offset())
        };
        if let Some(consumed) = consumed {
            return self.advance_current_chunk(consumed);
        }
        let mut de = serde_cbor::Deserializer::from_reader(self);
        IgnoredAny::deserialize(&mut de)
            .map(|_| ())
            .map_err(|err| ParseError::Deserialize(err.to_string()))
    }

    fn advance_current_chunk(&mut self, consumed: usize) -> Result<(), ParseError> {
        let remaining = self
            .remaining
            .checked_sub(consumed)
            .ok_or_else(|| ParseError::Deserialize("CBOR value exceeds remaining frame".into()))?;
        while self.parts.segments.front().is_some_and(Bytes::is_empty) {
            self.parts.segments.pop_front();
        }
        let chunk = self
            .parts
            .segments
            .front_mut()
            .ok_or_else(|| ParseError::Deserialize("missing CBOR value segment".into()))?;
        chunk
            .get(..consumed)
            .ok_or_else(|| ParseError::Deserialize("CBOR value exceeds segment bounds".into()))?;
        chunk.advance(consumed);
        self.remaining = remaining;
        Ok(())
    }

    fn new(segments: Vec<Bytes>) -> Self {
        Self {
            remaining: segments.iter().map(Bytes::len).sum(),
            parts: SegmentedPartsReader {
                segments: segments.into(),
            },
        }
    }
}

impl Read for SegmentedFrameReader {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let count = self.remaining.min(buf.len());
        self.parts.read_exact(&mut buf[..count])?;
        self.remaining = self.remaining.saturating_sub(count);
        Ok(count)
    }
}

struct SegmentedPartsReader {
    segments: VecDeque<Bytes>,
}

impl Read for SegmentedPartsReader {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        while let Some(mut segment) = self.segments.pop_front() {
            if segment.is_empty() {
                continue;
            }
            let count = segment.len().min(buf.len());
            segment.copy_to_slice(&mut buf[..count]);
            self.segments.push_front(segment);
            return Ok(count);
        }
        Ok(0)
    }
}

fn deserialize_value(serializer: Serializer, bytes: &RawFrame) -> Result<Value, ParseError> {
    match serializer {
        Serializer::Json => {
            let raw = bytes
                .as_contiguous()
                .cloned()
                .unwrap_or_else(|| bytes.clone().into_bytes());
            let mut de = serde_json::Deserializer::from_slice(raw.as_ref());
            Value::deserialize(&mut de).map_err(|err| ParseError::Deserialize(err.to_string()))
        }
        Serializer::MessagePack => {
            let raw = bytes
                .as_contiguous()
                .cloned()
                .unwrap_or_else(|| bytes.clone().into_bytes());
            let mut de = rmp_serde::Deserializer::new(raw.as_ref());
            Value::deserialize(&mut de).map_err(|err| ParseError::Deserialize(err.to_string()))
        }
        Serializer::Cbor => match bytes {
            RawFrame::Contiguous(raw) => {
                let mut de = serde_cbor::Deserializer::from_slice(raw.as_ref());
                Value::deserialize(&mut de).map_err(|err| ParseError::Deserialize(err.to_string()))
            }
            RawFrame::Segmented { segments, .. } => {
                let mut de = serde_cbor::Deserializer::from_reader(SegmentedFrameReader::new(
                    segments.clone(),
                ));
                let value = Value::deserialize(&mut de)
                    .map_err(|err| ParseError::Deserialize(err.to_string()))?;
                de.end()
                    .map_err(|err| ParseError::Deserialize(err.to_string()))?;
                Ok(value)
            }
        },
        Serializer::Ubjson => Err(ParseError::UnsupportedSerializer(serializer)),
        Serializer::Flatbuffers => Err(ParseError::UnsupportedSerializer(serializer)),
    }
}

fn parse_hello(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let realm = expect_string(get(parts, 0, "hello.realm")?, "hello.realm")?;
    let details = expect_map(get(parts, 1, "hello.details")?, "hello.details")?;
    Ok(WampMessage::Hello { realm, details })
}

fn parse_welcome(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let session_id = value_as_u64(get(parts, 0, "welcome.session_id")?, "welcome.session_id")?;
    let details = expect_map(get(parts, 1, "welcome.details")?, "welcome.details")?;
    Ok(WampMessage::Welcome {
        session_id,
        details,
    })
}

fn parse_abort(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let details = expect_map(get(parts, 0, "abort.details")?, "abort.details")?;
    let reason = expect_string(get(parts, 1, "abort.reason")?, "abort.reason")?;
    let payload = extract_payload(
        serializer,
        "abort.arguments",
        parts.get(2),
        "abort.argumentsKw",
        parts.get(3),
    )?;
    Ok(WampMessage::Abort {
        details,
        reason,
        payload,
    })
}

fn parse_challenge(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let auth_method = expect_string(
        get(parts, 0, "challenge.auth_method")?,
        "challenge.auth_method",
    )?;
    let extra = expect_map(get(parts, 1, "challenge.extra")?, "challenge.extra")?;
    Ok(WampMessage::Challenge { auth_method, extra })
}

fn parse_authenticate(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let signature = expect_string(
        get(parts, 0, "authenticate.signature")?,
        "authenticate.signature",
    )?;
    let extra = map_or_default(parts.get(1), "authenticate.extra")?;
    Ok(WampMessage::Authenticate { signature, extra })
}

fn parse_goodbye(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let details = expect_map(get(parts, 0, "goodbye.details")?, "goodbye.details")?;
    let reason = expect_string(get(parts, 1, "goodbye.reason")?, "goodbye.reason")?;
    let payload = extract_payload(
        serializer,
        "goodbye.arguments",
        parts.get(2),
        "goodbye.argumentsKw",
        parts.get(3),
    )?;
    Ok(WampMessage::Goodbye {
        details,
        reason,
        payload,
    })
}

fn parse_heartbeat(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let details = expect_map(get(parts, 0, "heartbeat.details")?, "heartbeat.details")?;
    let ping = parts
        .get(1)
        .map(|value| value_as_u64(value, "heartbeat.ping"))
        .transpose()?;
    let incoming = parts
        .get(2)
        .map(|value| value_as_u64(value, "heartbeat.incoming"))
        .transpose()?;
    let outgoing = parts
        .get(3)
        .map(|value| value_as_u64(value, "heartbeat.outgoing"))
        .transpose()?;
    Ok(WampMessage::Heartbeat {
        details,
        ping,
        incoming,
        outgoing,
    })
}

fn parse_error(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_type = value_as_u64(get(parts, 0, "error.request_type")?, "error.request_type")?;
    let request_id = value_as_u64(get(parts, 1, "error.request_id")?, "error.request_id")?;
    let details = expect_map(get(parts, 2, "error.details")?, "error.details")?;
    let error = expect_string(get(parts, 3, "error.uri")?, "error.uri")?;
    let payload = extract_payload(
        serializer,
        "error.arguments",
        parts.get(4),
        "error.argumentsKw",
        parts.get(5),
    )?;
    Ok(WampMessage::Error {
        request_type,
        request_id,
        details,
        error,
        payload,
    })
}

fn parse_publish(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(get(parts, 0, "publish.request_id")?, "publish.request_id")?;
    let options = expect_map(get(parts, 1, "publish.options")?, "publish.options")?;
    let topic = expect_string(get(parts, 2, "publish.topic")?, "publish.topic")?;
    let payload = extract_payload(
        serializer,
        "publish.arguments",
        parts.get(3),
        "publish.argumentsKw",
        parts.get(4),
    )?;
    Ok(WampMessage::Publish {
        request_id,
        options,
        topic,
        payload,
    })
}

fn parse_published(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "published.request_id")?,
        "published.request_id",
    )?;
    let publication_id = value_as_u64(
        get(parts, 1, "published.publication_id")?,
        "published.publication_id",
    )?;
    Ok(WampMessage::Published {
        request_id,
        publication_id,
    })
}

fn parse_subscribe(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "subscribe.request_id")?,
        "subscribe.request_id",
    )?;
    let options = expect_map(get(parts, 1, "subscribe.options")?, "subscribe.options")?;
    let topic = expect_string(get(parts, 2, "subscribe.topic")?, "subscribe.topic")?;
    Ok(WampMessage::Subscribe {
        request_id,
        options,
        topic,
    })
}

fn parse_subscribed(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "subscribed.request_id")?,
        "subscribed.request_id",
    )?;
    let subscription_id = value_as_u64(
        get(parts, 1, "subscribed.subscription_id")?,
        "subscribed.subscription_id",
    )?;
    Ok(WampMessage::Subscribed {
        request_id,
        subscription_id,
    })
}

fn parse_unsubscribe(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "unsubscribe.request_id")?,
        "unsubscribe.request_id",
    )?;
    let subscription_id = value_as_u64(
        get(parts, 1, "unsubscribe.subscription_id")?,
        "unsubscribe.subscription_id",
    )?;
    Ok(WampMessage::Unsubscribe {
        request_id,
        subscription_id,
    })
}

fn parse_unsubscribed(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "unsubscribed.request_id")?,
        "unsubscribed.request_id",
    )?;
    let details = map_or_default(parts.get(1), "unsubscribed.details")?;
    Ok(WampMessage::Unsubscribed {
        request_id,
        details,
    })
}

fn parse_event(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let subscription_id = value_as_u64(
        get(parts, 0, "event.subscription_id")?,
        "event.subscription_id",
    )?;
    let publication_id = value_as_u64(
        get(parts, 1, "event.publication_id")?,
        "event.publication_id",
    )?;
    let details = expect_map(get(parts, 2, "event.details")?, "event.details")?;
    let payload = extract_payload(
        serializer,
        "event.arguments",
        parts.get(3),
        "event.argumentsKw",
        parts.get(4),
    )?;
    Ok(WampMessage::Event {
        subscription_id,
        publication_id,
        details,
        payload,
    })
}

fn parse_call(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(get(parts, 0, "call.request_id")?, "call.request_id")?;
    let options = expect_map(get(parts, 1, "call.options")?, "call.options")?;
    let procedure = expect_string(get(parts, 2, "call.procedure")?, "call.procedure")?;
    let payload = extract_payload(
        serializer,
        "call.arguments",
        parts.get(3),
        "call.argumentsKw",
        parts.get(4),
    )?;
    Ok(WampMessage::Call {
        request_id,
        options,
        procedure,
        payload,
    })
}

fn parse_cancel(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(get(parts, 0, "cancel.request_id")?, "cancel.request_id")?;
    let options = expect_map(get(parts, 1, "cancel.options")?, "cancel.options")?;
    Ok(WampMessage::Cancel {
        request_id,
        options,
    })
}

fn parse_result(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(get(parts, 0, "result.request_id")?, "result.request_id")?;
    let details = expect_map(get(parts, 1, "result.details")?, "result.details")?;
    let payload = extract_payload(
        serializer,
        "result.arguments",
        parts.get(2),
        "result.argumentsKw",
        parts.get(3),
    )?;
    Ok(WampMessage::Result {
        request_id,
        details,
        payload,
    })
}

fn parse_register(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(get(parts, 0, "register.request_id")?, "register.request_id")?;
    let options = expect_map(get(parts, 1, "register.options")?, "register.options")?;
    let procedure = expect_string(get(parts, 2, "register.procedure")?, "register.procedure")?;
    Ok(WampMessage::Register {
        request_id,
        options,
        procedure,
    })
}

fn parse_registered(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "registered.request_id")?,
        "registered.request_id",
    )?;
    let registration_id = value_as_u64(
        get(parts, 1, "registered.registration_id")?,
        "registered.registration_id",
    )?;
    Ok(WampMessage::Registered {
        request_id,
        registration_id,
    })
}

fn parse_unregister(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "unregister.request_id")?,
        "unregister.request_id",
    )?;
    let registration_id = value_as_u64(
        get(parts, 1, "unregister.registration_id")?,
        "unregister.registration_id",
    )?;
    Ok(WampMessage::Unregister {
        request_id,
        registration_id,
    })
}

fn parse_unregistered(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "unregistered.request_id")?,
        "unregistered.request_id",
    )?;
    Ok(WampMessage::Unregistered {
        request_id,
        details: map_or_default(parts.get(1), "unregistered.details")?,
    })
}

fn parse_invocation(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "invocation.request_id")?,
        "invocation.request_id",
    )?;
    let registration_id = value_as_u64(
        get(parts, 1, "invocation.registration_id")?,
        "invocation.registration_id",
    )?;
    let details = expect_map(get(parts, 2, "invocation.details")?, "invocation.details")?;
    let payload = extract_payload(
        serializer,
        "invocation.arguments",
        parts.get(3),
        "invocation.argumentsKw",
        parts.get(4),
    )?;
    Ok(WampMessage::Invocation {
        request_id,
        registration_id,
        details,
        payload,
    })
}

fn parse_interrupt(parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(
        get(parts, 0, "interrupt.request_id")?,
        "interrupt.request_id",
    )?;
    let options = expect_map(get(parts, 1, "interrupt.options")?, "interrupt.options")?;
    Ok(WampMessage::Interrupt {
        request_id,
        options,
    })
}

fn parse_yield(serializer: Serializer, parts: &[Value]) -> Result<WampMessage, ParseError> {
    let request_id = value_as_u64(get(parts, 0, "yield.request_id")?, "yield.request_id")?;
    let options = expect_map(get(parts, 1, "yield.options")?, "yield.options")?;
    let payload = extract_payload(
        serializer,
        "yield.arguments",
        parts.get(2),
        "yield.argumentsKw",
        parts.get(3),
    )?;
    Ok(WampMessage::Yield {
        request_id,
        options,
        payload,
    })
}

fn get<'a>(parts: &'a [Value], index: usize, label: &'static str) -> Result<&'a Value, ParseError> {
    parts.get(index).ok_or(ParseError::MissingElement(label))
}

fn expect_map(value: &Value, label: &'static str) -> Result<ValueMap, ParseError> {
    match value {
        Value::Map(map) => Ok(map.clone()),
        Value::Unit => Ok(ValueMap::new()),
        _ => Err(ParseError::ExpectedMap(label)),
    }
}

fn map_or_default(value: Option<&Value>, label: &'static str) -> Result<ValueMap, ParseError> {
    match value {
        Some(value) => expect_map(value, label),
        None => Ok(ValueMap::new()),
    }
}

fn value_as_u64(value: &Value, label: &'static str) -> Result<u64, ParseError> {
    match value {
        Value::U64(v) => Ok(*v),
        Value::U32(v) => Ok(*v as u64),
        Value::U16(v) => Ok(*v as u64),
        Value::U8(v) => Ok(*v as u64),
        Value::I64(v) if *v >= 0 => Ok(*v as u64),
        Value::I32(v) if *v >= 0 => Ok(*v as u64),
        Value::I16(v) if *v >= 0 => Ok(*v as u64),
        Value::I8(v) if *v >= 0 => Ok(*v as u64),
        _ => Err(ParseError::ExpectedIdentifier(label)),
    }
}

fn expect_string(value: &Value, label: &'static str) -> Result<String, ParseError> {
    match value {
        Value::String(s) => Ok(s.clone()),
        Value::Char(c) => Ok(c.to_string()),
        _ => Err(ParseError::ExpectedString(label)),
    }
}

fn extract_payload(
    serializer: Serializer,
    args_label: &'static str,
    args: Option<&Value>,
    kwargs_label: &'static str,
    kwargs: Option<&Value>,
) -> Result<Payload, ParseError> {
    let args = match args {
        Some(value) => match value {
            Value::Seq(_) => Some(serialize_value(serializer, value)?),
            Value::Unit => None,
            _ => return Err(ParseError::ExpectedList(args_label)),
        },
        None => None,
    };
    let kwargs = match kwargs {
        Some(value) => match value {
            Value::Map(_) => Some(serialize_value(serializer, value)?),
            Value::Unit => None,
            _ => return Err(ParseError::ExpectedMap(kwargs_label)),
        },
        None => None,
    };
    Ok(Payload {
        args,
        kwargs,
        transparent: None,
    })
}

fn serialize_value(serializer: Serializer, value: &Value) -> Result<Bytes, ParseError> {
    match serializer {
        Serializer::Json => serde_json::to_vec(value)
            .map(Bytes::from)
            .map_err(|err| ParseError::PayloadEncode(err.to_string())),
        Serializer::MessagePack => rmp_serde::to_vec(value)
            .map(Bytes::from)
            .map_err(|err| ParseError::PayloadEncode(err.to_string())),
        Serializer::Cbor => serde_cbor::to_vec(value)
            .map(Bytes::from)
            .map_err(|err| ParseError::PayloadEncode(err.to_string())),
        Serializer::Ubjson | Serializer::Flatbuffers => {
            Err(ParseError::UnsupportedSerializer(serializer))
        }
    }
}

#[cfg(test)]
#[path = "wamp_regression_tests.rs"]
mod regression_tests;

#[cfg(test)]
#[path = "wamp_test_support.rs"]
pub(crate) mod test_support;

#[cfg(test)]
mod tests {
    use super::test_support::{assert_condition, unexpected_message, AssertError, AssertSuccess};
    use super::*;
    use serde_json::json;

    fn to_bytes_json(value: serde_json::Value) -> Bytes {
        Bytes::from(serde_json::to_vec(&value).assert_success())
    }

    fn decode_value(serializer: Serializer, bytes: &Bytes) -> serde_json::Value {
        match serializer {
            Serializer::Json => serde_json::from_slice(bytes).assert_success(),
            Serializer::MessagePack => rmp_serde::from_slice(bytes).assert_success(),
            Serializer::Cbor => serde_cbor::from_slice(bytes).assert_success(),
            _ => panic!("unsupported serializer for decoding"),
        }
    }

    fn decode_option(serializer: Serializer, data: &Option<Bytes>) -> Option<serde_json::Value> {
        data.as_ref().map(|bytes| decode_value(serializer, bytes))
    }

    fn assert_slice_points_into(raw: &RawFrame, slice: &Bytes) {
        assert_condition!(
            raw.contains_slice(slice),
            "payload slice must point into raw frame storage"
        );
    }

    #[test]
    fn json_payload_retains_raw_slice() {
        let payload = json!([
            16,
            1,
            {"acknowledge": true},
            "com.example.topic",
            ["alpha"],
            {"beta": true}
        ]);
        let frame = to_bytes_json(payload);
        let parsed = parse_message(Serializer::Json, frame.clone()).assert_success();
        let raw = parsed
            .raw
            .as_contiguous()
            .assert_expected("json raw frame contiguous");
        assert_eq!(raw.as_ptr(), frame.as_ptr());
        assert_eq!(raw.len(), frame.len());
        match parsed.message {
            WampMessage::Publish { payload, .. } => {
                let args = payload.args.assert_expected("payload args missing");
                let kwargs = payload.kwargs.assert_expected("payload kwargs missing");
                assert_slice_points_into(&parsed.raw, &args);
                assert_slice_points_into(&parsed.raw, &kwargs);
                assert_eq!(
                    decode_option(Serializer::Json, &Some(args.clone())),
                    Some(json!(["alpha"]))
                );
                assert_eq!(
                    decode_option(Serializer::Json, &Some(kwargs.clone())),
                    Some(json!({"beta": true}))
                );
                let args_offset = args.as_ptr() as usize - raw.as_ptr() as usize;
                assert_condition!(args_offset < raw.len());
                let kwargs_offset = kwargs.as_ptr() as usize - raw.as_ptr() as usize;
                assert_condition!(kwargs_offset < raw.len());
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn msgpack_payload_retains_raw_slice() {
        use rmp_serde::encode::to_vec;

        let value = serde_json::json!([
            16,
            999,
            {"acknowledge": true},
            "com.example.topic",
            [1, 2],
            {"flag": false}
        ]);
        let bytes = Bytes::from(to_vec(&value).assert_success());
        let parsed = parse_message(Serializer::MessagePack, bytes.clone()).assert_success();
        let raw = parsed
            .raw
            .as_contiguous()
            .assert_expected("contiguous msgpack input should stay contiguous");
        assert_eq!(raw.as_ptr(), bytes.as_ptr());
        assert_eq!(raw.len(), bytes.len());
        match parsed.message {
            WampMessage::Publish { payload, .. } => {
                let args = payload.args.assert_expected("payload args missing");
                let kwargs = payload.kwargs.assert_expected("payload kwargs missing");
                assert_slice_points_into(&parsed.raw, &args);
                assert_slice_points_into(&parsed.raw, &kwargs);
                assert_eq!(
                    decode_option(Serializer::MessagePack, &Some(args.clone())),
                    Some(json!([1, 2]))
                );
                assert_eq!(
                    decode_option(Serializer::MessagePack, &Some(kwargs.clone())),
                    Some(json!({"flag": false}))
                );
                let args_offset = args.as_ptr() as usize - raw.as_ptr() as usize;
                assert_condition!(args_offset < raw.len());
                let kwargs_offset = kwargs.as_ptr() as usize - raw.as_ptr() as usize;
                assert_condition!(kwargs_offset < raw.len());
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn cbor_payload_decode_does_not_allocate_binary_storage() {
        use serde_cbor::Value as CborValue;

        const SIZE: usize = 64 * 1024;
        for binary_in_arguments in [true, false] {
            let binary = CborValue::Bytes(vec![0x5a; SIZE]);
            let (args, kwargs) = if binary_in_arguments {
                (
                    CborValue::Array(vec![binary]),
                    CborValue::Map(BTreeMap::new()),
                )
            } else {
                (
                    CborValue::Array(Vec::new()),
                    CborValue::Map(BTreeMap::from([(CborValue::Text("binary".into()), binary)])),
                )
            };
            let expected_args = args.clone();
            let expected_kwargs = kwargs.clone();
            let value = CborValue::Array(vec![
                CborValue::Integer(16),
                CborValue::Integer(999),
                CborValue::Map(BTreeMap::new()),
                CborValue::Text("com.example.topic".into()),
                args,
                kwargs,
            ]);
            let bytes = Bytes::from(serde_cbor::to_vec(&value).assert_success());
            let (parsed, largest) = super::test_allocations::largest_allocation(|| {
                parse_message(Serializer::Cbor, bytes.clone())
            });
            let parsed = parsed.assert_success();
            assert_condition!(
                largest < SIZE,
                "CBOR payload was materialized: {largest} bytes"
            );
            match parsed.message {
                WampMessage::Publish { payload, .. } => {
                    let args = payload.args.assert_success();
                    let kwargs = payload.kwargs.assert_success();
                    assert_slice_points_into(&parsed.raw, &args);
                    assert_slice_points_into(&parsed.raw, &kwargs);
                    assert_eq!(
                        serde_cbor::from_slice::<CborValue>(&args).assert_success(),
                        expected_args
                    );
                    assert_eq!(
                        serde_cbor::from_slice::<CborValue>(&kwargs).assert_success(),
                        expected_kwargs
                    );
                }
                other => unexpected_message(other),
            }
        }
    }

    #[test]
    fn cbor_borrowed_and_split_values_preserve_reader_position() {
        let mut reader = SegmentedFrameReader::new(vec![
            Bytes::new(),
            Bytes::from_static(&[0x01, 0x18]),
            Bytes::new(),
            Bytes::from_static(&[0x2a, 0x81, 0x02]),
            Bytes::new(),
        ]);
        assert_eq!(reader.remaining, 5);
        reader.read_cbor_value().assert_success();
        assert_eq!(reader.remaining, 4);
        reader.read_cbor_value().assert_success();
        assert_eq!(reader.remaining, 2);
        reader.read_cbor_value().assert_success();
        assert_eq!(reader.remaining, 0);
        let mut byte = [0];
        assert_eq!(reader.read(&mut byte).assert_success(), 0);
        assert_condition!(reader.read_cbor_value().is_err());
    }

    #[test]
    fn cbor_segment_advance_rejects_out_of_frame_and_cross_segment_counts() {
        let mut reader = SegmentedFrameReader::new(vec![
            Bytes::new(),
            Bytes::from_static(&[1]),
            Bytes::from_static(&[2, 3]),
        ]);
        assert_condition!(reader.advance_current_chunk(4).is_err());
        assert_eq!(reader.remaining, 3);
        assert_condition!(reader.advance_current_chunk(2).is_err());
        assert_eq!(reader.remaining, 3);
        let mut remaining = Vec::new();
        reader.read_to_end(&mut remaining).assert_success();
        assert_eq!(remaining, [1, 2, 3]);
        let mut empty = SegmentedFrameReader::new(vec![Bytes::new()]);
        assert_condition!(empty.advance_current_chunk(0).is_err());
        assert_eq!(empty.remaining, 0);
    }

    #[test]
    fn cbor_segmented_payload_decode_borrows_large_argument_values() {
        use serde_cbor::Value as CborValue;
        const SIZE: usize = 64 * 1024;
        let args = CborValue::Array(vec![CborValue::Bytes(vec![0x5a; SIZE])]);
        let kwargs = CborValue::Map(BTreeMap::from([(
            CborValue::Text("text".into()),
            CborValue::Text("x".repeat(SIZE)),
        )]));
        let args_encoded = serde_cbor::to_vec(&args).assert_success();
        let kwargs_encoded = serde_cbor::to_vec(&kwargs).assert_success();
        let encoded = Bytes::from(
            serde_cbor::to_vec(&CborValue::Array(vec![
                CborValue::Integer(16),
                CborValue::Integer(999),
                CborValue::Map(BTreeMap::new()),
                CborValue::Text("topic".into()),
                args.clone(),
                kwargs.clone(),
            ]))
            .assert_success(),
        );
        let args_start = encoded.len() - args_encoded.len() - kwargs_encoded.len();
        let kwargs_start = encoded.len() - kwargs_encoded.len();
        let segments = vec![
            Bytes::new(),
            encoded.slice(..args_start),
            Bytes::new(),
            encoded.slice(args_start..kwargs_start),
            Bytes::new(),
            encoded.slice(kwargs_start..),
            Bytes::new(),
        ];
        let (parsed, largest) = super::test_allocations::largest_allocation(|| {
            parse_message_segments(Serializer::Cbor, segments)
        });
        let parsed = parsed.assert_success();
        assert_condition!(largest < SIZE, "CBOR segment copied: {largest} bytes");
        match parsed.message {
            WampMessage::Publish { payload, .. } => {
                let actual_args = payload.args.assert_success();
                let actual_kwargs = payload.kwargs.assert_success();
                assert_eq!(actual_args.as_ref(), args_encoded);
                assert_eq!(actual_kwargs.as_ref(), kwargs_encoded);
                assert_eq!(actual_args.as_ptr(), encoded.slice(args_start..).as_ptr());
                assert_eq!(
                    actual_kwargs.as_ptr(),
                    encoded.slice(kwargs_start..).as_ptr()
                );
                assert_eq!(
                    serde_cbor::from_slice::<CborValue>(&actual_args).assert_success(),
                    args
                );
                assert_eq!(
                    serde_cbor::from_slice::<CborValue>(&actual_kwargs).assert_success(),
                    kwargs
                );
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn cbor_payload_retains_raw_slices_without_materializing_binary_data() {
        use serde_cbor::Value as CborValue;

        let binary = vec![0x5a; 4 * 1024 * 1024];
        let value = CborValue::Array(vec![
            CborValue::Integer(16),
            CborValue::Integer(999),
            CborValue::Map(BTreeMap::new()),
            CborValue::Text("com.example.topic".into()),
            CborValue::Array(vec![CborValue::Bytes(binary.clone())]),
            CborValue::Map(BTreeMap::from([(
                CborValue::Text("flag".into()),
                CborValue::Bool(false),
            )])),
        ]);
        let bytes = Bytes::from(serde_cbor::to_vec(&value).assert_success());
        let parsed = parse_message(Serializer::Cbor, bytes.clone()).assert_success();
        let raw = parsed
            .raw
            .as_contiguous()
            .assert_expected("contiguous CBOR input should stay contiguous");
        assert_eq!(raw.as_ptr(), bytes.as_ptr());
        assert_eq!(raw.len(), bytes.len());

        match parsed.message {
            WampMessage::Publish { payload, .. } => {
                let args = payload.args.assert_expected("payload args missing");
                let kwargs = payload.kwargs.assert_expected("payload kwargs missing");
                assert_slice_points_into(&parsed.raw, &args);
                assert_slice_points_into(&parsed.raw, &kwargs);
                assert_eq!(
                    serde_cbor::from_slice::<CborValue>(&args).assert_success(),
                    CborValue::Array(vec![CborValue::Bytes(binary)])
                );
                assert_eq!(
                    serde_cbor::from_slice::<CborValue>(&kwargs).assert_success(),
                    CborValue::Map(BTreeMap::from([(
                        CborValue::Text("flag".into()),
                        CborValue::Bool(false),
                    )]))
                );
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn cbor_payload_preserves_missing_null_and_empty_semantics() {
        let missing = Bytes::from(
            serde_cbor::to_vec(&serde_json::json!([16, 1, {}, "com.example.topic"]))
                .assert_success(),
        );
        let null = Bytes::from(
            serde_cbor::to_vec(&serde_json::json!([
                16,
                1,
                {},
                "com.example.topic",
                null,
                null
            ]))
            .assert_success(),
        );
        let empty = Bytes::from(
            serde_cbor::to_vec(&serde_json::json!([16, 1, {}, "com.example.topic", [], {}]))
                .assert_success(),
        );

        for bytes in [missing, null] {
            match parse_message(Serializer::Cbor, bytes)
                .assert_success()
                .message
            {
                WampMessage::Publish { payload, .. } => {
                    assert_condition!(payload.args.is_none());
                    assert_condition!(payload.kwargs.is_none());
                }
                other => unexpected_message(other),
            }
        }
        match parse_message(Serializer::Cbor, empty)
            .assert_success()
            .message
        {
            WampMessage::Publish { payload, .. } => {
                assert_eq!(
                    decode_option(Serializer::Cbor, &payload.args),
                    Some(json!([]))
                );
                assert_eq!(
                    decode_option(Serializer::Cbor, &payload.kwargs),
                    Some(json!({}))
                );
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn cbor_payload_rejects_wrong_argument_shapes() {
        let wrong_args = Bytes::from(
            serde_cbor::to_vec(&serde_json::json!([
                16,
                1,
                {},
                "com.example.topic",
                "not-a-list"
            ]))
            .assert_success(),
        );
        assert_condition!(matches!(
            parse_message(Serializer::Cbor, wrong_args),
            Err(ParseError::ExpectedList("publish.arguments"))
        ));

        let wrong_kwargs = Bytes::from(
            serde_cbor::to_vec(&serde_json::json!([16, 1, {}, "com.example.topic", [], []]))
                .assert_success(),
        );
        assert_condition!(matches!(
            parse_message(Serializer::Cbor, wrong_kwargs),
            Err(ParseError::ExpectedMap("publish.argumentsKw"))
        ));
    }

    #[test]
    fn cbor_range_parser_rejects_truncated_values_without_panicking() {
        let mut bytes = serde_cbor::to_vec(&serde_json::json!([
            48,
            1,
            {},
            "com.example.procedure",
            ["payload"]
        ]))
        .assert_success();
        bytes.pop();
        assert_condition!(matches!(
            parse_message(Serializer::Cbor, Bytes::from(bytes)),
            Err(ParseError::Deserialize(_))
        ));
    }

    #[test]
    fn cbor_range_parser_rejects_trailing_data_after_array() {
        let mut definite =
            serde_cbor::to_vec(&serde_json::json!([48, 1, {}, "com.example.procedure"]))
                .assert_success();
        definite.push(0x00);
        assert_condition!(matches!(
            parse_message(Serializer::Cbor, Bytes::from(definite)),
            Err(ParseError::Deserialize(_))
        ));

        let indefinite = Bytes::from_static(&[
            0x9f, 0x18, 0x30, 0x01, 0xa0, 0x75, b'c', b'o', b'm', b'.', b'e', b'x', b'a', b'm',
            b'p', b'l', b'e', b'.', b'p', b'r', b'o', b'c', b'e', b'd', b'u', b'r', b'e', 0xff,
            0x00,
        ]);
        assert_condition!(matches!(
            parse_message(Serializer::Cbor, indefinite),
            Err(ParseError::Deserialize(_))
        ));
    }

    #[test]
    fn msgpack_segmented_message_parses_without_flattening_full_frame() {
        use rmp_serde::encode::to_vec;

        let value = serde_json::json!([
            16,
            999,
            {"acknowledge": true},
            "com.example.topic",
            [1, 2],
            {"flag": false}
        ]);
        let bytes = Bytes::from(to_vec(&value).assert_success());
        let contiguous = parse_message(Serializer::MessagePack, bytes.clone()).assert_success();
        let (args_offset, kwargs_offset) = match contiguous.message {
            WampMessage::Publish { payload, .. } => {
                let raw = contiguous
                    .raw
                    .as_contiguous()
                    .assert_expected("contiguous msgpack frame expected");
                assert_eq!(raw.as_ptr(), bytes.as_ptr());
                assert_eq!(raw.len(), bytes.len());
                let args = payload.args.assert_expected("payload args missing");
                let kwargs = payload.kwargs.assert_expected("payload kwargs missing");
                (
                    args.as_ptr() as usize - raw.as_ptr() as usize,
                    kwargs.as_ptr() as usize - raw.as_ptr() as usize,
                )
            }
            other => unexpected_message(other),
        };
        let segments = vec![
            bytes.slice(0..args_offset),
            bytes.slice(args_offset..kwargs_offset),
            bytes.slice(kwargs_offset..bytes.len()),
        ];
        let parsed = parse_message_segments(Serializer::MessagePack, segments).assert_success();
        assert_condition!(matches!(parsed.raw, RawFrame::Segmented { .. }));
        match parsed.message {
            WampMessage::Publish { payload, .. } => {
                let args = payload.args.assert_expected("payload args missing");
                let kwargs = payload.kwargs.assert_expected("payload kwargs missing");
                assert_slice_points_into(&parsed.raw, &args);
                assert_slice_points_into(&parsed.raw, &kwargs);
                assert_eq!(
                    decode_option(Serializer::MessagePack, &Some(args)),
                    Some(json!([1, 2]))
                );
                assert_eq!(
                    decode_option(Serializer::MessagePack, &Some(kwargs)),
                    Some(json!({"flag": false}))
                );
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn cbor_segmented_parser_rejects_malformed_frames_at_every_split() {
        let cases: &[&[u8]] = &[
            &[],
            &[0x80],
            &[0x98],
            &[0x99, 0],
            &[0x9a, 0, 0, 0],
            &[0x9b, 0, 0, 0, 0, 0, 0, 0],
            &[0x9c],
            &[0x00],
            &[0x84, 0x18, 0x30, 1, 0xa0, 0x61],
            &[0x84, 0x18, 0x30, 1, 0xa0, 0x61, 0xff],
            &[0x84, 0x18, 0x30, 1, 0xa0, 0x61, b'p', 0],
            &[0x9f, 0x18, 0x30, 1, 0xa0, 0x61, b'p'],
            &[0x9f, 0x18, 0x30, 1, 0xa0, 0x61, b'p', 0xff, 0],
            &[0x85, 0x18, 0x30, 1, 0xa0, 0x61, b'p', 0x81],
            &[
                0x85, 0x18, 0x30, 1, 0xa0, 0x61, b'p', 0x81, 0x5a, 0xff, 0xff, 0xff, 0xff,
            ],
        ];
        for bytes in cases {
            let original = Bytes::copy_from_slice(bytes);
            assert_condition!(parse_message(Serializer::Cbor, original.clone()).is_err());
            for split in 0..=original.len() {
                assert_condition!(parse_message_segments(
                    Serializer::Cbor,
                    vec![
                        Bytes::new(),
                        original.slice(..split),
                        Bytes::new(),
                        original.slice(split..),
                        Bytes::new(),
                    ]
                )
                .is_err());
            }
        }
    }

    #[test]
    fn cbor_segmented_payload_retains_exact_encoding_and_borrowed_parts() {
        let fields = [
            0x18, 0x30, 1, 0xa0, 0x61, b'p', 0x81, 0x18, 0x17, 0xa1, 0x62, b'k', b'w', 0x18, 0x18,
        ];
        for header in [
            vec![0x86],
            vec![0x98, 6],
            vec![0x99, 0, 6],
            vec![0x9a, 0, 0, 0, 6],
            vec![0x9b, 0, 0, 0, 0, 0, 0, 0, 6],
            vec![0x9f],
        ] {
            let indefinite = header == [0x9f];
            let args_start = header.len() + 6;
            let mut encoded = header;
            encoded.extend_from_slice(&fields);
            if indefinite {
                encoded.push(0xff);
            }
            let original = Bytes::from(encoded);
            for split in 0..=original.len() {
                let parsed = parse_message_segments(
                    Serializer::Cbor,
                    vec![
                        Bytes::new(),
                        original.slice(..split),
                        Bytes::new(),
                        original.slice(split..),
                        Bytes::new(),
                    ],
                )
                .assert_success();
                assert_condition!(matches!(parsed.raw, RawFrame::Segmented { .. }));
                match parsed.message {
                    WampMessage::Call {
                        request_id,
                        procedure,
                        payload,
                        ..
                    } => {
                        assert_eq!(request_id, 1);
                        assert_eq!(procedure, "p");
                        let args = payload.args.assert_expected("missing arguments");
                        assert_eq!(args.as_ref(), &[0x81, 0x18, 0x17]);
                        assert_eq!(
                            payload.kwargs.assert_expected("missing keywords").as_ref(),
                            &[0xa1, 0x62, b'k', b'w', 0x18, 0x18]
                        );
                        if split <= args_start || split >= args_start + args.len() {
                            assert_eq!(args.as_ptr(), original.slice(args_start..).as_ptr());
                        }
                    }
                    other => unexpected_message(other),
                }
            }
        }
    }

    #[test]
    fn cbor_segmented_message_parses_without_flattening_full_frame() {
        let value = serde_json::json!([17, 999, 12345]);
        let bytes = Bytes::from(serde_cbor::to_vec(&value).assert_success());
        let split = bytes.len() / 2;
        let parsed = parse_message_segments(
            Serializer::Cbor,
            vec![bytes.slice(0..split), bytes.slice(split..bytes.len())],
        )
        .assert_success();
        assert_condition!(matches!(parsed.raw, RawFrame::Segmented { .. }));
        match parsed.message {
            WampMessage::Published {
                request_id,
                publication_id,
            } => {
                assert_eq!(request_id, 999);
                assert_eq!(publication_id, 12345);
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn parse_call_with_payload() {
        let payload = json!([
            48,
            123,
            {"timeout": 100},
            "com.example.proc",
            ["arg"],
            {"kw": 1}
        ]);
        let parsed = parse_message(Serializer::Json, to_bytes_json(payload)).assert_success();
        match parsed.message {
            WampMessage::Call {
                request_id,
                procedure,
                payload,
                ..
            } => {
                assert_eq!(request_id, 123);
                assert_eq!(procedure, "com.example.proc");
                assert_eq!(
                    decode_option(Serializer::Json, &payload.args),
                    Some(json!(["arg"]))
                );
                assert_eq!(
                    decode_option(Serializer::Json, &payload.kwargs),
                    Some(json!({"kw": 1}))
                );
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn parse_abort_with_reason() {
        let payload =
            json!([3, {"message": "not authorized"}, "wamp.error.not_authorized", ["why"]]);
        let parsed = parse_message(Serializer::Json, to_bytes_json(payload)).assert_success();
        match parsed.message {
            WampMessage::Abort {
                reason, payload, ..
            } => {
                assert_eq!(reason, "wamp.error.not_authorized");
                assert_eq!(
                    decode_option(Serializer::Json, &payload.args),
                    Some(json!(["why"]))
                );
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn parse_challenge_and_authenticate() {
        let challenge_payload = json!([4, "wampcra", {"challenge": "nonce", "salt": "pepper"}]);
        let challenge =
            parse_message(Serializer::Json, to_bytes_json(challenge_payload)).assert_success();
        match challenge.message {
            WampMessage::Challenge { auth_method, extra } => {
                assert_eq!(auth_method, "wampcra");
                assert_condition!(extra.contains_key(&Value::String("challenge".into())));
            }
            other => unexpected_message(other),
        }

        let authenticate_payload = json!([5, "signature", {"foo": "bar"}]);
        let authenticate =
            parse_message(Serializer::Json, to_bytes_json(authenticate_payload)).assert_success();
        match authenticate.message {
            WampMessage::Authenticate { signature, extra } => {
                assert_eq!(signature, "signature");
                assert_condition!(extra.contains_key(&Value::String("foo".into())));
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn parse_event_message() {
        let payload = json!([
            36,
            2024,
            7777,
            {"publisher": 1},
            ["payload"],
            {"kw": true}
        ]);
        let parsed = parse_message(Serializer::Json, to_bytes_json(payload)).assert_success();
        match parsed.message {
            WampMessage::Event {
                subscription_id,
                publication_id,
                payload,
                ..
            } => {
                assert_eq!(subscription_id, 2024);
                assert_eq!(publication_id, 7777);
                assert_eq!(
                    decode_option(Serializer::Json, &payload.args),
                    Some(json!(["payload"]))
                );
                assert_eq!(
                    decode_option(Serializer::Json, &payload.kwargs),
                    Some(json!({"kw": true}))
                );
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn parse_invocation_message() {
        let payload = json!([
            68,
            10,
            99,
            {"receive_progress": true},
            [1, 2, 3],
            {"alpha": "beta"}
        ]);
        let parsed = parse_message(Serializer::Json, to_bytes_json(payload)).assert_success();
        match parsed.message {
            WampMessage::Invocation {
                request_id,
                registration_id,
                payload,
                ..
            } => {
                assert_eq!(request_id, 10);
                assert_eq!(registration_id, 99);
                assert_eq!(
                    decode_option(Serializer::Json, &payload.args),
                    Some(json!([1, 2, 3]))
                );
                assert_eq!(
                    decode_option(Serializer::Json, &payload.kwargs),
                    Some(json!({"alpha": "beta"}))
                );
            }
            other => unexpected_message(other),
        }
    }

    #[test]
    fn unsupported_serializer() {
        let payload = Bytes::from_static(b"");
        let err = parse_message(Serializer::Ubjson, payload).assert_error();
        assert_condition!(matches!(err, ParseError::UnsupportedSerializer(_)));
    }
}
