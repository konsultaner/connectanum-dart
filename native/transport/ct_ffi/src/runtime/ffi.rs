use std::ffi::CStr;
use std::net::SocketAddr;
use std::os::raw::{c_char, c_int, c_uint};

use bytes::Bytes;
use std::sync::Arc;
use std::{ptr, slice, str};

#[cfg(feature = "ffi-test")]
use dashmap::DashMap;
#[cfg(feature = "ffi-test")]
use std::collections::VecDeque;
#[cfg(feature = "ffi-test")]
use std::sync::{Mutex, OnceLock};

#[cfg(feature = "ffi-test")]
use ct_core::parse_message;
use ct_core::{
    accept_channel, apply_router_config, connection_accept_websocket, connection_http3_connection,
    connection_http3_poll_request, connection_http3_poll_stream, connection_http_poll_request,
    connection_poll_http_event,
    connection_protocol, connection_rawsocket_max_exponent, connection_reject_websocket,
    connection_take_http2_handshake, connection_take_http3_handshake,
    connection_take_websocket_handshake, listen, listener_http3_port, local_addr,
    poll_connection_message, register_http3_pending, response_stream_channel, send_wamp_message,
    send_wamp_segments, shutdown, start_runtime, ConnectionId, ConnectionProtocol,
    Error as CoreError, Http3Handshake, HttpBodyHandle, HttpResponseBody, HttpResponseDispatch,
    HttpRouteResolution, ListenerId, RawSocketSerializer, WampMessage, RESPONSE_STREAM_BUFFER,
};
use http::StatusCode;

use crate::callbacks::{
    invoke_connection_callback, invoke_listener_callback, register_connection_callback,
    register_listener_callback,
};

use super::constants::*;
use super::state::{
    clear_channels, clone_message, remove_http2_handshake, remove_http3_connection,
    remove_http3_handshake, remove_http3_stream, remove_http_body, remove_http_handshake,
    remove_http_response_stream, remove_http_connection_event, remove_message,
    remove_websocket_handshake, store_channel, store_http2_handshake,
    store_http3_connection, store_http3_handshake, store_http3_stream, store_http_body,
    store_http_connection_event, store_http_request_metadata, store_http_response_stream,
    store_message, store_websocket_handshake, with_channel, with_http2_handshake,
    with_http3_handshake, with_http3_stream, with_http_body, with_http_handshake,
    with_http_response_stream, with_http_connection_event, with_message,
    with_websocket_handshake, HttpMetadata, StoredHttpHandshakePayload, StoredMessage,
};
use rmp::encode::{write_array_len, write_u64};
use serde_json::{Map as JsonMap, Number as JsonNumber, Value as JsonValue};
use serde_value::Value as SerdeValue;

#[repr(C)]
#[derive(Default)]
pub struct CtHttpHandshakeInfo {
    pub method_ptr: *const u8,
    pub method_len: usize,
    pub target_ptr: *const u8,
    pub target_len: usize,
    pub path_ptr: *const u8,
    pub path_len: usize,
    pub query_ptr: *const u8,
    pub query_len: usize,
    pub protocol_ptr: *const u8,
    pub protocol_len: usize,
    pub version: u8,
    pub headers_len: usize,
    pub body_ptr: *const u8,
    pub body_len: usize,
    pub realm_ptr: *const u8,
    pub realm_len: usize,
    pub procedure_ptr: *const u8,
    pub procedure_len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtHttpBodyView {
    pub data_ptr: *const u8,
    pub data_len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtHttp2HandshakeInfo {
    pub protocol_ptr: *const u8,
    pub protocol_len: usize,
    pub alpn_ptr: *const u8,
    pub alpn_len: usize,
    pub listener_protocols_len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtHttp3HandshakeInfo {
    pub protocol_ptr: *const u8,
    pub protocol_len: usize,
    pub alpn_ptr: *const u8,
    pub alpn_len: usize,
    pub listener_protocols_len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtHttpConnectionEventInfo {
    pub connection_id: i32,
    pub protocol: i32,
    pub reason: i32,
    pub request_count: u32,
    pub idle_timeouts: u32,
    pub body_timeouts: u32,
    pub detail_ptr: *const u8,
    pub detail_len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtHttp3StreamInfo {
    pub stream_id: u64,
}

#[repr(C)]
#[derive(Default)]
pub struct CtHttpHeader {
    pub name_ptr: *const u8,
    pub name_len: usize,
    pub value_ptr: *const u8,
    pub value_len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtStringView {
    pub ptr: *const u8,
    pub len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtWebSocketHandshakeInfo {
    pub key_ptr: *const u8,
    pub key_len: usize,
    pub protocols_len: usize,
    pub extensions_len: usize,
    pub version_ptr: *const u8,
    pub version_len: usize,
    pub http_info: CtHttpHandshakeInfo,
}

fn map_error(err: CoreError) -> c_int {
    match err {
        CoreError::RuntimeAlreadyStarted => ERR_ALREADY_STARTED,
        CoreError::RuntimeNotStarted => ERR_RUNTIME_NOT_STARTED,
        CoreError::InvalidBacklog => ERR_INVALID_ARGUMENT,
        CoreError::ListenerNotFound(_) => ERR_LISTENER_NOT_FOUND,
        CoreError::AcceptChannelAlreadyTaken(_) => ERR_CHANNEL_ALREADY_TAKEN,
        CoreError::AddressResolution(_, _) => ERR_INVALID_ARGUMENT,
        CoreError::UnsupportedPlatform => ERR_UNSUPPORTED,
        CoreError::RouterConfigInvalid(_) => ERR_ROUTER_CONFIG_INVALID,
        CoreError::EndpointNotConfigured(_, _) => ERR_ENDPOINT_NOT_CONFIGURED,
        CoreError::ConnectionNotFound(_) => ERR_CONNECTION_NOT_FOUND,
        CoreError::UnsupportedProtocol(_, _) => ERR_UNSUPPORTED_PROTOCOL,
        CoreError::HandshakeAlreadyTaken(_) => ERR_HANDSHAKE_CONSUMED,
        CoreError::ConnectionHandleUnavailable(_) => ERR_HANDLE_UNAVAILABLE,
        CoreError::Http3ResponseSend(_) => ERR_IO,
        CoreError::Io(_) => ERR_IO,
    }
}

fn extract_payload_slices(message: &WampMessage) -> (Option<Bytes>, Option<Bytes>) {
    match message {
        WampMessage::Publish { payload, .. }
        | WampMessage::Event { payload, .. }
        | WampMessage::Call { payload, .. }
        | WampMessage::Result { payload, .. }
        | WampMessage::Invocation { payload, .. }
        | WampMessage::Yield { payload, .. }
        | WampMessage::Error { payload, .. }
        | WampMessage::Abort { payload, .. }
        | WampMessage::Goodbye { payload, .. } => (payload.args.clone(), payload.kwargs.clone()),
        _ => (None, None),
    }
}

fn option_bytes_ptr(bytes: &Option<Bytes>) -> (*const u8, usize) {
    match bytes {
        Some(data) => (data.as_ptr(), data.len()),
        None => (ptr::null(), 0),
    }
}

fn http_metadata_view(metadata: &HttpMetadata) -> CtHttpHandshakeInfo {
    let total_body_len = metadata.body.len();
    let (body_ptr, inline_len) = metadata
        .body
        .inline_bytes()
        .map(|bytes| (bytes.as_ptr(), bytes.len()))
        .unwrap_or((ptr::null(), 0));
    CtHttpHandshakeInfo {
        method_ptr: metadata.method.as_ptr(),
        method_len: metadata.method.len(),
        target_ptr: metadata.target.as_ptr(),
        target_len: metadata.target.len(),
        path_ptr: metadata.path.as_ptr(),
        path_len: metadata.path.len(),
        query_ptr: metadata
            .query
            .as_ref()
            .map(|value| value.as_ptr())
            .unwrap_or(ptr::null()),
        query_len: metadata
            .query
            .as_ref()
            .map(|value| value.len())
            .unwrap_or(0),
        protocol_ptr: metadata.protocol.as_ptr(),
        protocol_len: metadata.protocol.len(),
        version: metadata.version,
        headers_len: metadata.headers.len(),
        body_ptr,
        body_len: total_body_len,
        realm_ptr: metadata
            .realm
            .as_ref()
            .map(|value| value.as_ptr())
            .unwrap_or(ptr::null()),
        realm_len: metadata
            .realm
            .as_ref()
            .map(|value| value.len())
            .unwrap_or(0),
        procedure_ptr: metadata
            .procedure
            .as_ref()
            .map(|value| value.as_ptr())
            .unwrap_or(ptr::null()),
        procedure_len: metadata
            .procedure
            .as_ref()
            .map(|value| value.len())
            .unwrap_or(0),
    }
}

fn string_view(value: &Arc<[u8]>) -> CtStringView {
    CtStringView {
        ptr: value.as_ptr(),
        len: value.len(),
    }
}

const JSON_COMMA: &[u8] = b",";
const JSON_CLOSE: &[u8] = b"]";
const EMPTY_JSON_ARRAY: &[u8] = b"[]";
const EMPTY_MSGPACK_ARRAY: &[u8] = &[0x90];

#[cfg(feature = "ffi-test")]
type TestMessageQueues = DashMap<ConnectionId, Mutex<VecDeque<u32>>>;

#[cfg(feature = "ffi-test")]
static TEST_MESSAGES: OnceLock<TestMessageQueues> = OnceLock::new();

#[cfg(feature = "ffi-test")]
fn test_messages() -> &'static TestMessageQueues {
    TEST_MESSAGES.get_or_init(DashMap::new)
}

#[cfg(feature = "ffi-test")]
fn enqueue_test_handle(connection_id: ConnectionId, handle: u32) {
    let queue = test_messages()
        .entry(connection_id)
        .or_insert_with(|| Mutex::new(VecDeque::new()));
    let mut guard = queue.lock().unwrap();
    guard.push_back(handle);
}

#[cfg(feature = "ffi-test")]
fn pop_test_handle(connection_id: ConnectionId) -> Option<u32> {
    test_messages().get(&connection_id).and_then(|entry| {
        let mut guard = entry.value().lock().unwrap();
        guard.pop_front()
    })
}

#[cfg(feature = "ffi-test")]
fn clear_test_messages() {
    if let Some(map) = TEST_MESSAGES.get() {
        let keys: Vec<ConnectionId> = map.iter().map(|entry| *entry.key()).collect();
        for key in keys {
            if let Some((_, queue_mutex)) = map.remove(&key) {
                let mut queue = queue_mutex.lock().unwrap();
                while let Some(handle) = queue.pop_front() {
                    drop(remove_message(handle));
                }
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn ct_start_runtime() -> c_int {
    match start_runtime() {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

fn read_optional_str(ptr: *const c_char, len: c_int) -> Result<Option<String>, c_int> {
    if ptr.is_null() || len <= 0 {
        return Ok(None);
    }
    let len = len as usize;
    let bytes = unsafe { slice::from_raw_parts(ptr as *const u8, len) };
    let value = str::from_utf8(bytes).map_err(|_| ERR_INVALID_ARGUMENT)?;
    Ok(Some(value.to_string()))
}

fn encode_event_segments_json(
    payload: &ct_core::WampPayload,
    subscription_id: u64,
    publication_id: u64,
    publisher: Option<u64>,
    topic: Option<&str>,
) -> Result<Vec<Bytes>, c_int> {
    let mut details = JsonMap::new();
    if let Some(publisher_id) = publisher {
        details.insert(
            "publisher".into(),
            JsonValue::Number(JsonNumber::from(publisher_id)),
        );
    }
    if let Some(topic_value) = topic {
        details.insert("topic".into(), JsonValue::String(topic_value.to_string()));
    }
    let details_value = JsonValue::Object(details);
    let details_json = serde_json::to_string(&details_value).map_err(|_| ERR_INVALID_ARGUMENT)?;
    let details_bytes = Bytes::from(details_json.clone().into_bytes());
    let has_kwargs = payload.kwargs.is_some();
    let has_args = payload.args.is_some() || has_kwargs;
    let mut segments = Vec::new();
    if has_args {
        let prefix =
            Bytes::from(format!("[36,{},{},", subscription_id, publication_id).into_bytes());
        segments.push(prefix);
        segments.push(details_bytes);
        segments.push(Bytes::from_static(JSON_COMMA));
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(EMPTY_JSON_ARRAY)
        };
        segments.push(args_bytes);
        if let Some(kwargs) = payload.kwargs.clone() {
            segments.push(Bytes::from_static(JSON_COMMA));
            segments.push(kwargs);
        }
        segments.push(Bytes::from_static(JSON_CLOSE));
    } else {
        let frame = Bytes::from(
            format!(
                "[36,{},{},{}]",
                subscription_id, publication_id, details_json
            )
            .into_bytes(),
        );
        segments.push(frame);
    }
    Ok(segments)
}

fn encode_event_segments_msgpack(
    payload: &ct_core::WampPayload,
    subscription_id: u64,
    publication_id: u64,
    publisher: Option<u64>,
    topic: Option<&str>,
) -> Result<Vec<Bytes>, c_int> {
    let mut details = JsonMap::new();
    if let Some(publisher_id) = publisher {
        details.insert(
            "publisher".into(),
            JsonValue::Number(JsonNumber::from(publisher_id)),
        );
    }
    if let Some(topic_value) = topic {
        details.insert("topic".into(), JsonValue::String(topic_value.to_string()));
    }
    let details_value = JsonValue::Object(details);
    let details_msgpack = rmp_serde::to_vec(&details_value).map_err(|_| ERR_INVALID_ARGUMENT)?;

    let has_kwargs = payload.kwargs.is_some();
    let has_args = payload.args.is_some() || has_kwargs;
    let mut element_count = 4; // code, subscription_id, publication_id, details
    if has_args {
        element_count += 1;
    }
    if has_kwargs {
        element_count += 1;
    }

    let mut prefix = Vec::new();
    write_array_len(&mut prefix, element_count as u32).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, 36).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, subscription_id).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, publication_id).map_err(|_| ERR_INVALID_ARGUMENT)?;
    prefix.extend_from_slice(&details_msgpack);

    let mut segments = Vec::new();
    segments.push(Bytes::from(prefix));
    if has_args {
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(EMPTY_MSGPACK_ARRAY)
        };
        segments.push(args_bytes);
    }
    if let Some(kwargs) = payload.kwargs.clone() {
        segments.push(kwargs);
    }
    Ok(segments)
}

fn encode_event_segments(
    message: &StoredMessage,
    subscription_id: u64,
    publication_id: u64,
    publisher: Option<u64>,
    topic: Option<&str>,
) -> Result<Vec<Bytes>, c_int> {
    let payload = match &message.message {
        WampMessage::Publish { payload, .. } => payload,
        _ => return Err(ERR_INVALID_ARGUMENT),
    };
    match message.serializer {
        RawSocketSerializer::Json => {
            encode_event_segments_json(payload, subscription_id, publication_id, publisher, topic)
        }
        RawSocketSerializer::MessagePack => encode_event_segments_msgpack(
            payload,
            subscription_id,
            publication_id,
            publisher,
            topic,
        ),
        _ => Err(ERR_UNSUPPORTED),
    }
}

fn encode_invocation_segments_json(
    payload: &ct_core::WampPayload,
    invocation_id: u64,
    registration_id: u64,
    caller: Option<u64>,
    procedure: Option<&str>,
    receive_progress: Option<bool>,
) -> Result<Vec<Bytes>, c_int> {
    let mut details = JsonMap::new();
    if let Some(caller_id) = caller {
        details.insert(
            "caller".into(),
            JsonValue::Number(JsonNumber::from(caller_id)),
        );
    }
    if let Some(proc_name) = procedure {
        details.insert("procedure".into(), JsonValue::String(proc_name.to_string()));
    }
    if let Some(progress) = receive_progress {
        details.insert("receive_progress".into(), JsonValue::Bool(progress));
    }
    let details_value = JsonValue::Object(details);
    let details_json = serde_json::to_string(&details_value).map_err(|_| ERR_INVALID_ARGUMENT)?;
    let details_bytes = Bytes::from(details_json.clone().into_bytes());
    let has_kwargs = payload.kwargs.is_some();
    let has_args = payload.args.is_some() || has_kwargs;
    let mut segments = Vec::new();
    if has_args {
        let prefix =
            Bytes::from(format!("[68,{},{},", invocation_id, registration_id).into_bytes());
        segments.push(prefix);
        segments.push(details_bytes);
        segments.push(Bytes::from_static(JSON_COMMA));
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(EMPTY_JSON_ARRAY)
        };
        segments.push(args_bytes);
        if let Some(kwargs) = payload.kwargs.clone() {
            segments.push(Bytes::from_static(JSON_COMMA));
            segments.push(kwargs);
        }
        segments.push(Bytes::from_static(JSON_CLOSE));
    } else {
        let frame = Bytes::from(
            format!(
                "[68,{},{},{}]",
                invocation_id, registration_id, details_json
            )
            .into_bytes(),
        );
        segments.push(frame);
    }
    Ok(segments)
}

fn encode_invocation_segments_msgpack(
    payload: &ct_core::WampPayload,
    invocation_id: u64,
    registration_id: u64,
    caller: Option<u64>,
    procedure: Option<&str>,
    receive_progress: Option<bool>,
) -> Result<Vec<Bytes>, c_int> {
    let mut details = JsonMap::new();
    if let Some(caller_id) = caller {
        details.insert(
            "caller".into(),
            JsonValue::Number(JsonNumber::from(caller_id)),
        );
    }
    if let Some(proc_name) = procedure {
        details.insert("procedure".into(), JsonValue::String(proc_name.to_string()));
    }
    if let Some(progress) = receive_progress {
        details.insert("receive_progress".into(), JsonValue::Bool(progress));
    }
    let details_value = JsonValue::Object(details);
    let details_msgpack = rmp_serde::to_vec(&details_value).map_err(|_| ERR_INVALID_ARGUMENT)?;

    let has_kwargs = payload.kwargs.is_some();
    let has_args = payload.args.is_some() || has_kwargs;
    let mut element_count = 4; // code, invocation_id, registration_id, details
    if has_args {
        element_count += 1;
    }
    if has_kwargs {
        element_count += 1;
    }

    let mut prefix = Vec::new();
    write_array_len(&mut prefix, element_count as u32).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, 68).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, invocation_id).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, registration_id).map_err(|_| ERR_INVALID_ARGUMENT)?;
    prefix.extend_from_slice(&details_msgpack);

    let mut segments = Vec::new();
    segments.push(Bytes::from(prefix));
    if has_args {
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(EMPTY_MSGPACK_ARRAY)
        };
        segments.push(args_bytes);
    }
    if let Some(kwargs) = payload.kwargs.clone() {
        segments.push(kwargs);
    }
    Ok(segments)
}

fn encode_invocation_segments(
    message: &StoredMessage,
    invocation_id: u64,
    registration_id: u64,
    caller: Option<u64>,
    procedure: Option<&str>,
    receive_progress: Option<bool>,
) -> Result<Vec<Bytes>, c_int> {
    let payload = match &message.message {
        WampMessage::Call { payload, .. } => payload,
        _ => return Err(ERR_INVALID_ARGUMENT),
    };
    match message.serializer {
        RawSocketSerializer::Json => encode_invocation_segments_json(
            payload,
            invocation_id,
            registration_id,
            caller,
            procedure,
            receive_progress,
        ),
        RawSocketSerializer::MessagePack => encode_invocation_segments_msgpack(
            payload,
            invocation_id,
            registration_id,
            caller,
            procedure,
            receive_progress,
        ),
        _ => Err(ERR_UNSUPPORTED),
    }
}

fn build_result_segments_json(
    payload: &ct_core::WampPayload,
    request_id: u64,
    details_bytes: Bytes,
) -> Vec<Bytes> {
    let has_kwargs = payload.kwargs.is_some();
    let has_args = payload.args.is_some() || has_kwargs;
    let mut segments = Vec::new();
    segments.push(Bytes::from(format!("[50,{},", request_id).into_bytes()));
    segments.push(details_bytes);
    if has_args {
        segments.push(Bytes::from_static(JSON_COMMA));
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(EMPTY_JSON_ARRAY)
        };
        segments.push(args_bytes);
        if let Some(kwargs) = payload.kwargs.clone() {
            segments.push(Bytes::from_static(JSON_COMMA));
            segments.push(kwargs);
        }
    }
    segments.push(Bytes::from_static(JSON_CLOSE));
    segments
}

fn build_result_segments_msgpack(
    payload: &ct_core::WampPayload,
    request_id: u64,
    details_msgpack: Vec<u8>,
) -> Result<Vec<Bytes>, c_int> {
    let has_kwargs = payload.kwargs.is_some();
    let has_args = payload.args.is_some() || has_kwargs;
    let mut element_count = 3; // code, request_id, details
    if has_args {
        element_count += 1;
    }
    if has_kwargs {
        element_count += 1;
    }

    let mut prefix = Vec::new();
    write_array_len(&mut prefix, element_count as u32).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, 50).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, request_id).map_err(|_| ERR_INVALID_ARGUMENT)?;
    let mut segments = Vec::new();
    segments.push(Bytes::from(prefix));
    segments.push(Bytes::from(details_msgpack));
    if has_args {
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(EMPTY_MSGPACK_ARRAY)
        };
        segments.push(args_bytes);
    }
    if let Some(kwargs) = payload.kwargs.clone() {
        segments.push(kwargs);
    }
    Ok(segments)
}

fn encode_result_segments(
    message: &StoredMessage,
    request_id: u64,
    progress: bool,
) -> Result<Vec<Bytes>, c_int> {
    match &message.message {
        WampMessage::Yield {
            options, payload, ..
        } => match message.serializer {
            RawSocketSerializer::Json => {
                let mut details_map = options.clone();
                if progress {
                    details_map.insert(
                        SerdeValue::String("progress".into()),
                        SerdeValue::Bool(true),
                    );
                }
                let details_json =
                    serde_json::to_vec(&details_map).map_err(|_| ERR_INVALID_ARGUMENT)?;
                Ok(build_result_segments_json(
                    payload,
                    request_id,
                    Bytes::from(details_json),
                ))
            }
            RawSocketSerializer::MessagePack => {
                let mut details_map = options.clone();
                if progress {
                    details_map.insert(
                        SerdeValue::String("progress".into()),
                        SerdeValue::Bool(true),
                    );
                }
                let details_msgpack =
                    rmp_serde::to_vec(&details_map).map_err(|_| ERR_INVALID_ARGUMENT)?;
                build_result_segments_msgpack(payload, request_id, details_msgpack)
            }
            _ => Err(ERR_UNSUPPORTED),
        },
        _ => Err(ERR_INVALID_ARGUMENT),
    }
}

fn build_error_segments_json(
    payload: &ct_core::WampPayload,
    request_type: u64,
    request_id: u64,
    details_bytes: Bytes,
    error_bytes: Bytes,
) -> Vec<Bytes> {
    let has_kwargs = payload.kwargs.is_some();
    let has_args = payload.args.is_some() || has_kwargs;
    let mut segments = Vec::new();
    segments.push(Bytes::from(
        format!("[8,{},{},", request_type, request_id).into_bytes(),
    ));
    segments.push(details_bytes);
    segments.push(Bytes::from_static(JSON_COMMA));
    segments.push(error_bytes);
    if has_args {
        segments.push(Bytes::from_static(JSON_COMMA));
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(EMPTY_JSON_ARRAY)
        };
        segments.push(args_bytes);
        if let Some(kwargs) = payload.kwargs.clone() {
            segments.push(Bytes::from_static(JSON_COMMA));
            segments.push(kwargs);
        }
    }
    segments.push(Bytes::from_static(JSON_CLOSE));
    segments
}

fn build_error_segments_msgpack(
    payload: &ct_core::WampPayload,
    request_type: u64,
    request_id: u64,
    details_msgpack: Vec<u8>,
    error_msgpack: Vec<u8>,
) -> Result<Vec<Bytes>, c_int> {
    let has_kwargs = payload.kwargs.is_some();
    let has_args = payload.args.is_some() || has_kwargs;
    let mut element_count = 5; // code, request_type, request_id, details, error
    if has_args {
        element_count += 1;
    }
    if has_kwargs {
        element_count += 1;
    }

    let mut prefix = Vec::new();
    write_array_len(&mut prefix, element_count as u32).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, 8).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, request_type).map_err(|_| ERR_INVALID_ARGUMENT)?;
    write_u64(&mut prefix, request_id).map_err(|_| ERR_INVALID_ARGUMENT)?;
    prefix.extend_from_slice(&details_msgpack);
    prefix.extend_from_slice(&error_msgpack);

    let mut segments = Vec::new();
    segments.push(Bytes::from(prefix));
    if has_args {
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(EMPTY_MSGPACK_ARRAY)
        };
        segments.push(args_bytes);
    }
    if let Some(kwargs) = payload.kwargs.clone() {
        segments.push(kwargs);
    }
    Ok(segments)
}

fn encode_error_segments(
    message: &StoredMessage,
    request_type: u64,
    request_id: u64,
) -> Result<Vec<Bytes>, c_int> {
    match &message.message {
        WampMessage::Error {
            details,
            error,
            payload,
            ..
        } => match message.serializer {
            RawSocketSerializer::Json => {
                let details_json = serde_json::to_vec(details).map_err(|_| ERR_INVALID_ARGUMENT)?;
                let error_json = serde_json::to_string(error).map_err(|_| ERR_INVALID_ARGUMENT)?;
                Ok(build_error_segments_json(
                    payload,
                    request_type,
                    request_id,
                    Bytes::from(details_json),
                    Bytes::from(error_json.into_bytes()),
                ))
            }
            RawSocketSerializer::MessagePack => {
                let details_msgpack =
                    rmp_serde::to_vec(details).map_err(|_| ERR_INVALID_ARGUMENT)?;
                let error_msgpack = rmp_serde::to_vec(error).map_err(|_| ERR_INVALID_ARGUMENT)?;
                build_error_segments_msgpack(
                    payload,
                    request_type,
                    request_id,
                    details_msgpack,
                    error_msgpack,
                )
            }
            _ => Err(ERR_UNSUPPORTED),
        },
        _ => Err(ERR_INVALID_ARGUMENT),
    }
}

#[no_mangle]
pub extern "C" fn ct_shutdown() -> c_int {
    match shutdown() {
        Ok(()) => {
            clear_channels();
            #[cfg(feature = "ffi-test")]
            {
                clear_test_messages();
            }
            SUCCESS
        }
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_apply_router_config(data: *const u8, len: c_int) -> c_int {
    if data.is_null() || len < 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len as usize) };
    match apply_router_config(bytes) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_listen(addr: *const c_char, port: c_uint, backlog: c_int) -> c_int {
    if addr.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let c_str = unsafe { CStr::from_ptr(addr) };
    let addr_str = match c_str.to_str() {
        Ok(value) => value,
        Err(_) => return ERR_INVALID_ARGUMENT,
    };

    match listen(addr_str, port as u16, backlog) {
        Ok(listener_id) => match accept_channel(listener_id) {
            Ok(receiver) => {
                store_channel(listener_id, receiver);
                invoke_listener_callback(listener_id, SUCCESS);
                listener_id.0 as c_int
            }
            Err(err) => map_error(err),
        },
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_get_local_port(listener_id: c_int) -> c_int {
    let listener_id = ListenerId(listener_id as u32);
    match local_addr(listener_id) {
        Ok(addr) => addr.port() as c_int,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_listener_http3_port(listener_id: c_int) -> c_int {
    let listener_id = ListenerId(listener_id as u32);
    match listener_http3_port(listener_id) {
        Ok(Some(port)) => port as c_int,
        Ok(None) => 0,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_poll_connection(listener_id: c_int) -> c_int {
    let listener_id = ListenerId(listener_id as u32);
    match with_channel(listener_id, |receiver| receiver.try_recv()) {
        Some(Ok(connection_id)) => {
            invoke_connection_callback(listener_id, connection_id);
            connection_id.0 as c_int
        }
        Some(Err(_)) => 0,
        None => match local_addr(listener_id) {
            Ok(_) => 0,
            Err(err) => map_error(err),
        },
    }
}

#[no_mangle]
pub extern "C" fn ct_connection_max_rawsocket_exponent(connection_id: c_int) -> c_int {
    let connection_id = ConnectionId(connection_id as u32);
    match connection_rawsocket_max_exponent(connection_id) {
        Ok(exponent) => exponent as c_int,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_connection_protocol(connection_id: c_int) -> c_int {
    let connection_id = ConnectionId(connection_id as u32);
    match connection_protocol(connection_id) {
        Ok(ConnectionProtocol::RawSocket) => PROTOCOL_RAWSOCKET,
        Ok(ConnectionProtocol::WebSocket) => PROTOCOL_WEBSOCKET,
        Ok(ConnectionProtocol::Http) => PROTOCOL_HTTP,
        Ok(ConnectionProtocol::Http2) => PROTOCOL_HTTP2,
        Ok(ConnectionProtocol::Http3) => PROTOCOL_HTTP3,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_connection_take_http_handshake(connection_id: c_int) -> c_int {
    if connection_id <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_http_poll_request(connection_id) {
        Ok(Some((summary, response))) => {
            let metadata = HttpMetadata::from_summary(&summary);
            store_http_request_metadata(metadata, response) as c_int
        }
        Ok(None) => 0,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_connection_take_http2_handshake(connection_id: c_int) -> c_int {
    if connection_id <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_take_http2_handshake(connection_id) {
        Ok(handshake) => store_http2_handshake(handshake) as c_int,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_http2_handshake_get(handle: c_int, info: *mut CtHttp2HandshakeInfo) -> c_int {
    if handle <= 0 || info.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http2_handshake(handle as u32, |stored| {
        let metadata = &stored.metadata;
        let info_ref = unsafe { info.as_mut().unwrap() };
        info_ref.protocol_ptr = metadata.protocol.as_ptr();
        info_ref.protocol_len = metadata.protocol.len();
        if let Some(alpn) = &metadata.alpn {
            info_ref.alpn_ptr = alpn.as_ptr();
            info_ref.alpn_len = alpn.len();
        } else {
            info_ref.alpn_ptr = ptr::null();
            info_ref.alpn_len = 0;
        }
        info_ref.listener_protocols_len = metadata.listener_protocols.len();
    }) {
        Some(()) => SUCCESS,
        None => ERR_HANDSHAKE_CONSUMED,
    }
}

#[no_mangle]
pub extern "C" fn ct_http2_handshake_listener_protocol(
    handle: c_int,
    index: usize,
    view: *mut CtStringView,
) -> c_int {
    if handle <= 0 || view.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http2_handshake(handle as u32, |stored| {
        stored.metadata.listener_protocol(index).map(|bytes| {
            let view_ref = unsafe { view.as_mut().unwrap() };
            view_ref.ptr = bytes.as_ptr();
            view_ref.len = bytes.len();
        })
    }) {
        Some(Some(())) => SUCCESS,
        Some(None) => ERR_INVALID_ARGUMENT,
        None => ERR_HANDSHAKE_CONSUMED,
    }
}

#[no_mangle]
pub extern "C" fn ct_http2_handshake_release(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    remove_http2_handshake(handle as u32);
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_connection_take_http3_handshake(connection_id: c_int) -> c_int {
    if connection_id <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_take_http3_handshake(connection_id) {
        Ok(handshake) => store_http3_handshake(handshake) as c_int,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_http3_handshake_get(handle: c_int, info: *mut CtHttp3HandshakeInfo) -> c_int {
    if handle <= 0 || info.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http3_handshake(handle as u32, |stored| {
        let metadata = &stored.metadata;
        let info_ref = unsafe { info.as_mut().unwrap() };
        info_ref.protocol_ptr = metadata.protocol.as_ptr();
        info_ref.protocol_len = metadata.protocol.len();
        if let Some(alpn) = &metadata.alpn {
            info_ref.alpn_ptr = alpn.as_ptr();
            info_ref.alpn_len = alpn.len();
        } else {
            info_ref.alpn_ptr = ptr::null();
            info_ref.alpn_len = 0;
        }
        info_ref.listener_protocols_len = metadata.listener_protocols.len();
    }) {
        Some(()) => SUCCESS,
        None => ERR_HANDSHAKE_CONSUMED,
    }
}

#[no_mangle]
pub extern "C" fn ct_http3_handshake_listener_protocol(
    handle: c_int,
    index: usize,
    view: *mut CtStringView,
) -> c_int {
    if handle <= 0 || view.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http3_handshake(handle as u32, |stored| {
        stored.metadata.listener_protocol(index).map(|bytes| {
            let view_ref = unsafe { view.as_mut().unwrap() };
            view_ref.ptr = bytes.as_ptr();
            view_ref.len = bytes.len();
        })
    }) {
        Some(Some(())) => SUCCESS,
        Some(None) => ERR_INVALID_ARGUMENT,
        None => ERR_HANDSHAKE_CONSUMED,
    }
}

#[no_mangle]
pub extern "C" fn ct_http3_handshake_release(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    remove_http3_handshake(handle as u32);
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_connection_get_http3_connection(connection_id: c_int) -> c_int {
    if connection_id <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_http3_connection(connection_id) {
        Ok(connection) => store_http3_connection(connection) as c_int,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_http3_connection_release(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    remove_http3_connection(handle as u32);
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_http3_connection_poll_stream(connection_id: c_int) -> c_int {
    if connection_id <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_http3_poll_stream(connection_id) {
        Ok(Some(stream)) => store_http3_stream(stream) as c_int,
        Ok(None) => 0,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_http3_connection_poll_request(connection_id: c_int) -> c_int {
    if connection_id <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_http3_poll_request(connection_id) {
        Ok(Some((summary, response_handle))) => {
            let metadata = HttpMetadata::from_summary(&summary);
            store_http_request_metadata(metadata, response_handle) as c_int
        }
        Ok(None) => 0,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_http3_stream_get(handle: c_int, info: *mut CtHttp3StreamInfo) -> c_int {
    if handle <= 0 || info.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http3_stream(handle as u32, |stored| stored.stream_id) {
        Some(stream_id) => {
            unsafe {
                info.write(CtHttp3StreamInfo { stream_id });
            }
            SUCCESS
        }
        None => ERR_INVALID_ARGUMENT,
    }
}

#[no_mangle]
pub extern "C" fn ct_http3_stream_release(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    remove_http3_stream(handle as u32);
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_connection_poll_http_event(connection_id: c_int) -> c_int {
    if connection_id <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_poll_http_event(connection_id) {
        Ok(Some(event)) => store_http_connection_event(event) as c_int,
        Ok(None) => 0,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_http_connection_event_get(
    handle: c_int,
    info: *mut CtHttpConnectionEventInfo,
) -> c_int {
    if handle <= 0 || info.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http_connection_event(handle as u32, |stored| {
        let info_ref = unsafe { info.as_mut().unwrap() };
        info_ref.connection_id = stored.connection_id.0 as i32;
        info_ref.protocol = match stored.protocol {
            ConnectionProtocol::RawSocket => PROTOCOL_RAWSOCKET,
            ConnectionProtocol::WebSocket => PROTOCOL_WEBSOCKET,
            ConnectionProtocol::Http => PROTOCOL_HTTP,
            ConnectionProtocol::Http2 => PROTOCOL_HTTP2,
            ConnectionProtocol::Http3 => PROTOCOL_HTTP3,
        };
        info_ref.reason = match stored.reason {
            HttpConnectionCloseReason::Graceful => HTTP_EVENT_REASON_GRACEFUL,
            HttpConnectionCloseReason::GoAway => HTTP_EVENT_REASON_GOAWAY,
            HttpConnectionCloseReason::IdleTimeout => HTTP_EVENT_REASON_IDLE_TIMEOUT,
            HttpConnectionCloseReason::BodyTimeout => HTTP_EVENT_REASON_BODY_TIMEOUT,
            HttpConnectionCloseReason::ProtocolError => HTTP_EVENT_REASON_PROTOCOL_ERROR,
            HttpConnectionCloseReason::Internal => HTTP_EVENT_REASON_INTERNAL,
        };
        info_ref.request_count = stored.request_count;
        info_ref.idle_timeouts = stored.idle_timeouts;
        info_ref.body_timeouts = stored.body_timeouts;
        if let Some(detail) = &stored.detail {
            info_ref.detail_ptr = detail.as_ptr();
            info_ref.detail_len = detail.len();
        } else {
            info_ref.detail_ptr = ptr::null();
            info_ref.detail_len = 0;
        }
    }) {
        Some(()) => SUCCESS,
        None => ERR_HANDLE_UNAVAILABLE,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_connection_event_release(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    remove_http_connection_event(handle as u32);
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_http_response_send(
    handshake_handle: c_int,
    status: c_int,
    headers: *const CtHttpHeader,
    headers_len: usize,
    body_ptr: *const u8,
    body_len: usize,
) -> c_int {
    if handshake_handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    if status < 100 || status > 599 {
        return ERR_INVALID_ARGUMENT;
    }
    if headers.is_null() && headers_len > 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let mut header_vec: Vec<(String, String)> = Vec::with_capacity(headers_len);
    for index in 0..headers_len {
        let header = unsafe { headers.add(index).as_ref() };
        let Some(header) = header else {
            return ERR_INVALID_ARGUMENT;
        };
        let name_slice = unsafe { std::slice::from_raw_parts(header.name_ptr, header.name_len) };
        let value_slice = unsafe { std::slice::from_raw_parts(header.value_ptr, header.value_len) };
        let name = match std::str::from_utf8(name_slice) {
            Ok(value) => value.to_string(),
            Err(_) => return ERR_INVALID_ARGUMENT,
        };
        let value = match std::str::from_utf8(value_slice) {
            Ok(value) => value.to_string(),
            Err(_) => return ERR_INVALID_ARGUMENT,
        };
        header_vec.push((name, value));
    }
    let body_vec = if body_ptr.is_null() || body_len == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(body_ptr, body_len) }.to_vec()
    };

    let Some(stored) = remove_http_handshake(handshake_handle as u32) else {
        return ERR_HANDSHAKE_CONSUMED;
    };
    let Some(payload) = stored.take_payload() else {
        return ERR_HANDSHAKE_CONSUMED;
    };
    let dispatch = HttpResponseDispatch {
        status,
        headers: header_vec,
        body: HttpResponseBody::Buffered(body_vec),
    };
    match payload {
        StoredHttpHandshakePayload::Response(handle) => match handle.respond(dispatch) {
            Ok(()) => SUCCESS,
            Err(err) => map_error(err),
        },
    }
}
#[no_mangle]
pub extern "C" fn ct_http_response_stream_open(
    handshake_handle: c_int,
    status: c_int,
    headers: *const CtHttpHeader,
    headers_len: usize,
) -> c_int {
    if handshake_handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    if status < 100 || status > 599 {
        return ERR_INVALID_ARGUMENT;
    }
    if headers.is_null() && headers_len > 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let mut header_vec: Vec<(String, String)> = Vec::with_capacity(headers_len);
    for index in 0..headers_len {
        let header = unsafe { headers.add(index).as_ref() };
        let Some(header) = header else {
            return ERR_INVALID_ARGUMENT;
        };
        let name_slice = unsafe { std::slice::from_raw_parts(header.name_ptr, header.name_len) };
        let value_slice = unsafe { std::slice::from_raw_parts(header.value_ptr, header.value_len) };
        let name = match std::str::from_utf8(name_slice) {
            Ok(value) => value.to_string(),
            Err(_) => return ERR_INVALID_ARGUMENT,
        };
        let value = match std::str::from_utf8(value_slice) {
            Ok(value) => value.to_string(),
            Err(_) => return ERR_INVALID_ARGUMENT,
        };
        header_vec.push((name, value));
    }
    let Some(stored) = remove_http_handshake(handshake_handle as u32) else {
        return ERR_HANDSHAKE_CONSUMED;
    };
    let Some(payload) = stored.take_payload() else {
        return ERR_HANDSHAKE_CONSUMED;
    };
    let (writer, reader) = response_stream_channel(RESPONSE_STREAM_BUFFER);
    let dispatch = HttpResponseDispatch {
        status,
        headers: header_vec,
        body: HttpResponseBody::Streaming(reader),
    };
    match payload {
        StoredHttpHandshakePayload::Response(handle) => match handle.respond(dispatch) {
            Ok(()) => store_http_response_stream(writer) as c_int,
            Err(err) => map_error(err),
        },
    }
}

#[no_mangle]
pub extern "C" fn ct_http_response_stream_write(
    stream_handle: c_int,
    chunk_ptr: *const u8,
    chunk_len: usize,
) -> c_int {
    if stream_handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    if chunk_len > 0 && chunk_ptr.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    if chunk_len == 0 {
        return SUCCESS;
    }
    match with_http_response_stream(stream_handle as u32, |stream| {
        let slice = unsafe { slice::from_raw_parts(chunk_ptr, chunk_len) };
        stream.write_chunk(Bytes::copy_from_slice(slice))
    }) {
        Some(Ok(())) => SUCCESS,
        Some(Err(_)) => ERR_STREAM_CLOSED,
        None => ERR_HANDLE_UNAVAILABLE,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_response_stream_finish(stream_handle: c_int) -> c_int {
    if stream_handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    match remove_http_response_stream(stream_handle as u32) {
        Some(stream) => match stream.finish() {
            Ok(()) => SUCCESS,
            Err(_err) => ERR_STREAM_CLOSED,
        },
        None => ERR_HANDLE_UNAVAILABLE,
    }
}


#[no_mangle]
pub extern "C" fn ct_connection_take_websocket_handshake(connection_id: c_int) -> c_int {
    if connection_id <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_take_websocket_handshake(connection_id) {
        Ok(handshake) => store_websocket_handshake(handshake) as c_int,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_connection_accept_websocket(
    connection_id: c_int,
    handshake_handle: c_int,
    serializer_id: c_int,
    protocol_ptr: *const c_char,
    protocol_len: c_int,
) -> c_int {
    if connection_id <= 0 || handshake_handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let serializer = match serializer_from_id(serializer_id) {
        Ok(value) => value,
        Err(err) => return err,
    };
    let protocol = if protocol_len > 0 {
        if protocol_ptr.is_null() {
            return ERR_INVALID_ARGUMENT;
        }
        let bytes =
            unsafe { std::slice::from_raw_parts(protocol_ptr as *const u8, protocol_len as usize) };
        match std::str::from_utf8(bytes) {
            Ok(value) => Some(value.to_string()),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
    } else {
        None
    };
    let handshake = match remove_websocket_handshake(handshake_handle as u32) {
        Some(stored) => match stored.take() {
            Some(value) => value,
            None => return ERR_HANDSHAKE_CONSUMED,
        },
        None => return ERR_HANDSHAKE_CONSUMED,
    };
    match connection_accept_websocket(
        ConnectionId(connection_id as u32),
        handshake,
        serializer,
        protocol.as_deref(),
    ) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_connection_reject_websocket(
    connection_id: c_int,
    handshake_handle: c_int,
    status: c_int,
    reason_ptr: *const c_char,
    reason_len: c_int,
) -> c_int {
    if connection_id <= 0 || handshake_handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let status_code = match StatusCode::from_u16(status as u16) {
        Ok(code) => code,
        Err(_) => return ERR_INVALID_ARGUMENT,
    };
    let reason = if reason_len > 0 {
        if reason_ptr.is_null() {
            return ERR_INVALID_ARGUMENT;
        }
        let bytes =
            unsafe { std::slice::from_raw_parts(reason_ptr as *const u8, reason_len as usize) };
        match std::str::from_utf8(bytes) {
            Ok(value) => Some(value.to_string()),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
    } else {
        None
    };
    let handshake = match remove_websocket_handshake(handshake_handle as u32) {
        Some(stored) => match stored.take() {
            Some(value) => value,
            None => return ERR_HANDSHAKE_CONSUMED,
        },
        None => return ERR_HANDSHAKE_CONSUMED,
    };
    match connection_reject_websocket(
        ConnectionId(connection_id as u32),
        handshake,
        status_code,
        reason.as_deref(),
    ) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[repr(C)]
#[derive(Default)]
pub struct CtMessageInfo {
    pub serializer: u8,
    pub message_code: u64,
    pub frame_ptr: *const u8,
    pub frame_len: usize,
    pub args_ptr: *const u8,
    pub args_len: usize,
    pub kwargs_ptr: *const u8,
    pub kwargs_len: usize,
}

fn serializer_id(serializer: ct_core::RawSocketSerializer) -> u8 {
    match serializer {
        ct_core::RawSocketSerializer::Json => 1,
        ct_core::RawSocketSerializer::MessagePack => 2,
        ct_core::RawSocketSerializer::Cbor => 3,
        ct_core::RawSocketSerializer::Ubjson => 4,
        ct_core::RawSocketSerializer::Flatbuffers => 5,
    }
}

fn serializer_from_id(value: c_int) -> Result<RawSocketSerializer, c_int> {
    match value {
        1 => Ok(RawSocketSerializer::Json),
        2 => Ok(RawSocketSerializer::MessagePack),
        3 => Ok(RawSocketSerializer::Cbor),
        4 => Ok(RawSocketSerializer::Ubjson),
        5 => Ok(RawSocketSerializer::Flatbuffers),
        _ => Err(ERR_INVALID_ARGUMENT),
    }
}

#[no_mangle]
pub extern "C" fn ct_poll_connection_message(connection_id: c_int) -> c_int {
    let connection_id = ConnectionId(connection_id as u32);
    #[cfg(feature = "ffi-test")]
    if let Some(handle) = pop_test_handle(connection_id) {
        return handle as c_int;
    }
    match poll_connection_message(connection_id) {
        Ok(Some(parsed)) => {
            let ct_core::ParsedMessage {
                message,
                raw,
                serializer,
            } = parsed;
            let (args, kwargs) = extract_payload_slices(&message);
            let info = StoredMessage {
                serializer,
                code: message.code(),
                raw,
                message,
                args,
                kwargs,
            };
            store_message(info) as c_int
        }
        Ok(None) => 0,
        Err(err) => map_error(err),
    }
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_message_enqueue(
    connection_id: c_int,
    serializer_id: c_int,
    frame_ptr: *const u8,
    frame_len: c_int,
) -> c_int {
    if frame_len <= 0 || frame_ptr.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let serializer = match serializer_from_id(serializer_id) {
        Ok(value) => value,
        Err(code) => return code,
    };
    let bytes = unsafe { slice::from_raw_parts(frame_ptr, frame_len as usize) };
    let payload = Bytes::copy_from_slice(bytes);
    match parse_message(serializer, payload) {
        Ok(ct_core::ParsedMessage {
            message,
            raw,
            serializer: _,
        }) => {
            let (args, kwargs) = extract_payload_slices(&message);
            let handle = store_message(StoredMessage {
                serializer,
                code: message.code(),
                raw,
                message,
                args,
                kwargs,
            });
            enqueue_test_handle(ConnectionId(connection_id as u32), handle);
            handle as c_int
        }
        Err(_) => ERR_INVALID_ARGUMENT,
    }
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_register_http3_connection(
    listener_id: c_int,
    connection_id: c_int,
    protocol_ptr: *const c_char,
    alpn_ptr: *const c_char,
    protocols_ptr: *const c_char,
) -> c_int {
    if listener_id <= 0 || connection_id <= 0 || protocol_ptr.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let protocol = match unsafe { CStr::from_ptr(protocol_ptr) }.to_str() {
        Ok(value) => value.to_string(),
        Err(_) => return ERR_INVALID_ARGUMENT,
    };
    let alpn = if alpn_ptr.is_null() {
        None
    } else {
        match unsafe { CStr::from_ptr(alpn_ptr) }.to_str() {
            Ok(value) if value.is_empty() => None,
            Ok(value) => Some(value.to_string()),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
    };
    let listener_protocols = if protocols_ptr.is_null() {
        Vec::<String>::new()
    } else {
        match unsafe { CStr::from_ptr(protocols_ptr) }.to_str() {
            Ok(value) => value
                .split(',')
                .map(|token| token.trim())
                .filter(|token| !token.is_empty())
                .map(|token| token.to_string())
                .collect::<Vec<String>>(),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
    };
    let handshake = Http3Handshake {
        protocol,
        alpn,
        listener_protocols,
    };
    let listener_id = ListenerId(listener_id as u32);
    let connection_id = ConnectionId(connection_id as u32);
    let peer_addr = SocketAddr::from(([127, 0, 0, 1], 0));
    match register_http3_pending(listener_id, connection_id, handshake, peer_addr) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_register_http3_request(
    listener_id: c_int,
    connection_id: c_int,
    method_ptr: *const c_char,
    target_ptr: *const c_char,
    protocol_ptr: *const c_char,
    headers_ptr: *const CtHttpHeader,
    headers_len: usize,
    body_ptr: *const u8,
    body_len: usize,
    realm_ptr: *const c_char,
    procedure_ptr: *const c_char,
) -> c_int {
    if listener_id <= 0 || connection_id <= 0 || method_ptr.is_null() || target_ptr.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let method = match unsafe { CStr::from_ptr(method_ptr) }.to_str() {
        Ok(value) => value.to_string(),
        Err(_) => return ERR_INVALID_ARGUMENT,
    };
    let target = match unsafe { CStr::from_ptr(target_ptr) }.to_str() {
        Ok(value) => value.to_string(),
        Err(_) => return ERR_INVALID_ARGUMENT,
    };
    let protocol = if protocol_ptr.is_null() {
        "http/3".to_string()
    } else {
        match unsafe { CStr::from_ptr(protocol_ptr) }.to_str() {
            Ok(value) => value.to_string(),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
    };
    let (path, query) = match target.split_once('?') {
        Some((p, rest)) => (p.to_string(), Some(rest.to_string())),
        None => (target.clone(), None),
    };
    let headers = if headers_len == 0 || headers_ptr.is_null() {
        Vec::new()
    } else {
        let mut list = Vec::with_capacity(headers_len);
        for index in 0..headers_len {
            let header = unsafe { headers_ptr.add(index).as_ref() };
            let Some(header) = header else {
                return ERR_INVALID_ARGUMENT;
            };
            let name = unsafe { std::slice::from_raw_parts(header.name_ptr, header.name_len) };
            let value = unsafe { std::slice::from_raw_parts(header.value_ptr, header.value_len) };
            let name = match std::str::from_utf8(name) {
                Ok(value) => value.to_string(),
                Err(_) => return ERR_INVALID_ARGUMENT,
            };
            let value = match std::str::from_utf8(value) {
                Ok(value) => value.to_string(),
                Err(_) => return ERR_INVALID_ARGUMENT,
            };
            list.push((name, value));
        }
        list
    };
    let body_handle = if body_len == 0 || body_ptr.is_null() {
        HttpBodyHandle::empty()
    } else {
        let bytes = unsafe { std::slice::from_raw_parts(body_ptr, body_len) }.to_vec();
        HttpBodyHandle::from_bytes(bytes)
    };
    let realm = if realm_ptr.is_null() {
        None
    } else {
        match unsafe { CStr::from_ptr(realm_ptr) }.to_str() {
            Ok(value) if value.is_empty() => None,
            Ok(value) => Some(value.to_string()),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
    };
    let procedure = if procedure_ptr.is_null() {
        None
    } else {
        match unsafe { CStr::from_ptr(procedure_ptr) }.to_str() {
            Ok(value) if value.is_empty() => None,
            Ok(value) => Some(value.to_string()),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
    };
    let route = match (realm.clone(), procedure.clone()) {
        (Some(realm), Some(procedure)) => Some(HttpRouteResolution {
            realm,
            procedure,
            method: method.clone(),
            protocol: protocol.clone(),
            path: path.clone(),
            query: query.clone(),
        }),
        _ => None,
    };
    let summary = ct_core::HttpRequestSummary::new(
        method,
        target,
        path,
        query,
        protocol,
        3,
        headers,
        body_handle,
        realm,
        procedure,
        route,
    );
    let connection_id = ConnectionId(connection_id as u32);
    match ct_core::register_http_request(connection_id, summary) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_clear_messages() -> c_int {
    clear_test_messages();
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_send_message(
    connection_id: c_int,
    payload_ptr: *const u8,
    payload_len: c_int,
) -> c_int {
    if payload_len < 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    let payload = if payload_len == 0 {
        Bytes::new()
    } else {
        if payload_ptr.is_null() {
            return ERR_INVALID_ARGUMENT;
        }
        let slice = unsafe { std::slice::from_raw_parts(payload_ptr, payload_len as usize) };
        Bytes::copy_from_slice(slice)
    };
    match send_wamp_message(connection_id, payload) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_message_get(handle: c_int, out_info: *mut CtMessageInfo) -> c_int {
    if out_info.is_null() || handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let handle_u32 = handle as u32;
    match with_message(handle_u32, |msg| {
        let (args_ptr, args_len) = option_bytes_ptr(&msg.args);
        let (kwargs_ptr, kwargs_len) = option_bytes_ptr(&msg.kwargs);
        CtMessageInfo {
            serializer: serializer_id(msg.serializer),
            message_code: msg.code,
            frame_ptr: msg.raw.as_ptr(),
            frame_len: msg.raw.len(),
            args_ptr,
            args_len,
            kwargs_ptr,
            kwargs_len,
        }
    }) {
        Some(info) => {
            unsafe {
                out_info.write(info);
            }
            SUCCESS
        }
        None => ERR_INVALID_ARGUMENT,
    }
}

#[no_mangle]
pub extern "C" fn ct_message_release(handle: c_int) {
    if handle <= 0 {
        return;
    }
    let handle_u32 = handle as u32;
    remove_message(handle_u32);
}

#[no_mangle]
pub extern "C" fn ct_message_retain(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let handle_u32 = handle as u32;
    match clone_message(handle_u32) {
        Some(new_handle) => new_handle as c_int,
        None => ERR_INVALID_ARGUMENT,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_handshake_get(
    handle: c_int,
    out_info: *mut CtHttpHandshakeInfo,
) -> c_int {
    if handle <= 0 || out_info.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http_handshake(handle as u32, |stored| http_metadata_view(&stored.metadata)) {
        Some(info) => {
            unsafe {
                out_info.write(info);
            }
            SUCCESS
        }
        None => ERR_INVALID_ARGUMENT,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_handshake_header(
    handle: c_int,
    index: usize,
    out_header: *mut CtHttpHeader,
) -> c_int {
    if handle <= 0 || out_header.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http_handshake(handle as u32, |stored| {
        stored
            .metadata
            .headers
            .get(index)
            .map(|(name, value)| CtHttpHeader {
                name_ptr: name.as_ptr(),
                name_len: name.len(),
                value_ptr: value.as_ptr(),
                value_len: value.len(),
            })
    }) {
        Some(Some(header)) => {
            unsafe {
                out_header.write(header);
            }
            SUCCESS
        }
        Some(None) => ERR_INVALID_ARGUMENT,
        None => ERR_INVALID_ARGUMENT,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_handshake_release(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    remove_http_handshake(handle as u32);
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_http_handshake_body_retain(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http_handshake(handle as u32, |stored| stored.metadata.body.clone()) {
        Some(body) => store_http_body(body) as c_int,
        None => ERR_HANDSHAKE_CONSUMED,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_body_get(handle: c_int, view: *mut CtHttpBodyView) -> c_int {
    if handle <= 0 || view.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http_body(handle as u32, |body| body.slice(0, body.len())) {
        Some(Some(slice)) => {
            unsafe {
                view.write(CtHttpBodyView {
                    data_ptr: slice.ptr,
                    data_len: slice.len,
                });
            }
            SUCCESS
        }
        Some(None) => ERR_UNSUPPORTED,
        None => ERR_HANDSHAKE_CONSUMED,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_body_read(
    handle: c_int,
    offset: usize,
    len: usize,
    view: *mut CtHttpBodyView,
) -> c_int {
    if handle <= 0 || view.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http_body(handle as u32, |body| {
        if offset > body.len() {
            None
        } else {
            let request_len = len.min(body.len().saturating_sub(offset));
            body.slice(offset, request_len)
        }
    }) {
        Some(Some(slice)) => {
            unsafe {
                view.write(CtHttpBodyView {
                    data_ptr: slice.ptr,
                    data_len: slice.len,
                });
            }
            SUCCESS
        }
        Some(None) => ERR_INVALID_ARGUMENT,
        None => ERR_HANDSHAKE_CONSUMED,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_body_release(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    if let Some(body) = remove_http_body(handle as u32) {
        body.request_finish();
    }
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_http_body_stream_read(
    handle: c_int,
    len: usize,
    view: *mut CtHttpBodyView,
) -> c_int {
    if handle <= 0 || view.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    if len == 0 {
        unsafe {
            view.write(CtHttpBodyView {
                data_ptr: ptr::null(),
                data_len: 0,
            });
        }
        return SUCCESS;
    }
    match with_http_body(handle as u32, |body| body.stream_read(len)) {
        Some(Ok(Some(slice))) => {
            unsafe {
                view.write(CtHttpBodyView {
                    data_ptr: slice.ptr,
                    data_len: slice.len,
                });
            }
            SUCCESS
        }
        Some(Ok(None)) => {
            unsafe {
                view.write(CtHttpBodyView {
                    data_ptr: ptr::null(),
                    data_len: 0,
            ñ0áÉßÀ‡…}ÎğÊ:*†µ¥0áreüˆËƒ4^BùÁ'gåQ*u";yç±­`©ş9™ƒ$µµkfA•ÆÜŞ=pk!5°Ù„N¾)Åœºvå29IQ‚Ç°«CÂ·ôIñéGeGxcê¸$t–œµÀéB1¡’ZÕ=Ey½=íøåq¹êjşş½ğ4÷Œ£½÷ÃºuNìíl.|’?N£%ºfRP3ó‘GoÆ¦÷Ã}š¬g´uN‡ë[ÂyÌ¹ügš£Œœ©åÔH¾‚¢tÌÎaˆ¾@’èÏx7lèÌÏy{|úÅkjA˜Ø_r†ôçªéÓc$24AĞHÆãTºú¬”êå³îû*ğÄÊÑ[´*„ö­dØÎâóäâí’ß¢¤–Ò"Dp`ï66ÿ—Ğğ…]nH#Å"ŸË´ù©ÂÙ;<*~Ï¥(5FËŒªêG<åˆn]^şMÎÕût0Ê0U†aNJDgše.|8Ì°Ë¯ªê¢(2³Ñ™ıŞDÔ~`ñÆÀ[ó"önçîılÙnƒôRhQşä.i0ON$2Rum“Â¦FXâßP+ËŒéœ}¿+I7S4GÀišìi1„´' ù¦%„=—æ	Wuº^—3qÇÉ… ø’L›ú¥TåC§Y7²ÜUpÑŒádÒe+”4>ŞŒ½Ú¬…‚x®š®fE„`¼T!«öèJODêş~pšÉ4:•äŞÒ/ÔªZÊ}—T-*‘‡LE_Ù0,…¿çÊ×Uô2¤Q’e?Ç›Ã8ÏİÀÌâ¹åL”LšÙ»ù‰xn®×` Áğ¥)éhïw>n¢µAH}B|©9
‡Ê|yG|»:8ŞÔ¦&Òh®¶‡›Ìa¬4û`àç· ö&ôÃ·l;¹9C–àÃnˆÌÎñ¿ĞD3‘KØbàMÀØmK‡YúIÉÔ¨4Ò5\›	àO…Äš©ú˜Ï™ïòñÉ29¤ƒ‡ß;…*Ñ}ªÌ]‘V¹Ãß¯4wò5Ë~³Å ÜÓOéw‚ôÜÀ\Ùğk)#S÷.zQëpa'®ºò“ v.†ÛU/A:÷¸Ukt8S¬jí(-5ö`¶	öıĞîb5y‘tÁĞ:zrŸfº%”æKP0:ª`ºñ“D”VŠ˜¢`Í$Ç¾Yá‘XøUf•ºOêj9ëÅ¹s
¼ÂX…Ú1è°$´.éZôˆeÑ=Ú8ZÕƒ¾ô5?ü6mç,€û„U¥ôñâ´òô¸×­Œ\µ'í[2†:UMbe *Ù±Ry;£fÃ{s¯ŸºÀ¨ã NZµE„„š!Ò3æªu`>ÛÁŒøov”d+3¥^O¡.©KŒKVÄí¦Œóòœ¿ˆø7ÏB4¹ÊéS?ÀŠ ÈR¼LZçî°ÆÇšõÜı,İP¯ı=6Î³C«zòÏº»ëÎF	»Ã ®SÑ”KbIönEëÕH`ø-3B‰šDÃÛya7vtˆQb`ê#z_ÄØ•‡GÑş‚Ÿ™ËYÚ¡Àhı€¡[İ²³s¨Û6h:†¯¦[eÓ§›H1F	PĞŞ[ÄFl}Şöyb]ß}€7’PÆ×£F ,ƒG6‹bBÎnèî¥bƒxÍr:
fçñZÈyõôm…wjœ%ÅmNRõ{L&Àô—
–‡æŠ*
† I*ìØ{ğ“¼™<Z TãÜ‘7¨Ps*®ßfò7²°	6UÒDúø‘ÛÒ&ª²òZêÈùSµğ CFÄ¥Õ‚†®e”;Ã¶‰Êv¯LlŸêõÔ3JÏTºXo³ï`Dä<‘9'Qit
z´âSBş‰X÷« §?})Ö®)÷ÊÉPnuR R‰¹i¿I<Ä@²˜- *¤>èF+F‘€­Ò®4ü-J§Ê~¤5
Q¡:•—…,7¹q×TXˆ*n†zÇdNĞÄj4HQÔåfùñ, „zYğ0PDÅŞçş’yYbII¥;‰Ü7¿oí‚õ›yòÆ•ÈÉ*«=‹Ho@*m«‹Ÿ¾>Q¤F¼	p—=×ùu‚h¦}°‡_4tušT¸~«05Œ\Ñíï‡ ÚKÀ¨f6íï¼ïÌ“³¯Ë‰²›‡ŞmjZÖ	f}gÕÇ/ä·ı‰ÿo‘Ì‹O

bÕÚ^¬”u†‚ù4Ÿ•‹:R5İ`ı'd³ÑNnŒ‚¯+ç‡šäÏÊ£¿Ï‰_V+ê²â/#ab¬n3¨Cä:®¸p‡4ç,S†ŒÂQ_¡úğö?õ$‘Ò¨D‚ÆmJ=/–WÅÀ™ğš,.÷½­ö/Æ/ùÅ¸«—Òº(›–ƒñPvnÁcÙÙN›¦ÎpŠuÁ ¸İÿ?ı¤ÈUŸàpÇ™gÜã`Ê{Î£-Ã4/©!Økìÿ%è-pjÈ;WnÍÕ«ŒŞŠ\?bá<y¶¿ÙüjÉ¯İ95xkãş/ñÇü€ YÛï<&â:›fšmã¿}¸M"•ÑÜÂj¶D3‰Y†4ªà0m^CC[!_Æ‰€Ì^^¬pwrs¢qÎZv/5ólÃx‹Èq$N€Q€T7Hx~µ…˜ ìŠ"ÑD¹HóÇ
IÚùh2\ˆä $ˆ JÎ¬ï—3aï*9NPI¨ô¯˜Ë~bİ@”’Âáàp{ZÜƒ]Ñh«öóQ'¿÷:Eš.Àxš]Ä‰“uÖ¬ãiâZàkJ¦éÆõ
}ô]GBä¢¢Ès{z#ó·&º²D3üâĞ?—0óç$èpp¡½£t€àxØ–Óï’ĞÇµ4PDjàìAáÌT{¨q|­áS4™U•òÿ–ü«Û$ñq¤.}ûòÉMµO‹¡Ä
R/Ë¿~Ò:ğÉÀ‹®'¥””‰æŒË‰Š;Ê¹¿ ¦¶½a3&øÆù†è†ygŠjgYâ-\øFc«¦VîÊƒûóÔ´½HÇ.ü.Ş8êVLQ>Õ~dO4.?»U-¥'è9Ô¤k©†W­a³¦Øç¼ó25¼’Âìy‰]K÷aEŞ7zçğo‹T…¨=M™³ØşÕş*sï›¦Ì
1±ùw‰ŒV¼àŒ{İDŒC™s¹Jûq}mºQÙà¶JÃ†»Aözıì3cd°nÆ-p•Ó‹ÿ»X}
,òpÎß[Ø–nçgO÷ú¸`M¨áÃš¦(bªy5ÅÎ]ıá_Õ|<æ;¬s&;ş|'îÂÍŠ#Õº/T÷/§ÛÖ”*;}°Óbd×*úÚ‰¯_~(âhY¤Æ:İi¥7nêƒŒ:Sz}{;ñ3m	İF4¶è(«2rut•İ
	İ{¤ óMlßˆ"/¬ş"P““gßà;”ÔQ/æ®OßYøÜ}3ø±Ó1Âƒ4‘)H·^Â™ƒ¿14D‹ÚÈWY¦ÎİdÅ}¼ğ7n¾ÕÙ$6:ÄmîÁÕ+ ‰Àññ Ú®¹í¬¹}ê9‰;¨c16c×mòÛ‡Û¿	£é”ºÈab<9f“'é˜°P·÷˜V»€Wè´˜œöÉ¨ô,H+·áÕÆ Û=£.Š¿VrŒ˜²¬… (ªBè6h›a€sµÁ/‘I~ú5|Ø–~Nµm;Ñ8Õ‘Pâ•‹R‘ |(-s¥æ`+ğMhgRN"Fé+	êÜHYŠEÄÿ{Ê½û7‚¥dŒï§©©¸x.Ö¢(ü4Ï<›Çá+¹dOXÚĞ	ˆZmSFoóD²¨ƒŞ€*ti„‹”sŸŸäë‚„*=EºA”„ç®yÆFôÍ¸‚ë¥şÅàÅùS,ì²¶Šek³üWèg¥ÿ¶/â³·éÊMÙnw}ìëp{ñmå
yáÀa ¤~ìğúèş†ÅaÓâ97ê”J”á0‚bàáwÌÙğQ<&ÄF¥\„¼}ËS?ÕXVæÜ(,h.ºX¬
Ï8$'şxƒ›ñDìİpçİË-æ âH|jÜ™Êáî(eGY¥si¯6€öùñ‡«pG½p`8«>{í}-TÎÿIe4áĞ	Ü~ê3ÆH
ß».î=æ Zl>‰üÈÉ!²`ò:’ ÉoÌ‰ŸŒë4öR¶Çèt(==]êà)Ì’MQ•óÿ­ıpÔš‰a¡PÖü1/È¨KÔÖ6Cï—óõ]6Ôx35¸Ï3§
C@;–r|¼Âú©’Aáï2#éúc5î>º±‘¦[lÏ—/Åı’.ÔS)XmäËÉ9ÿÍ#İ£‹ª…Pélx/³§´QLqeø°ìá¥nèg[²ÜÉv{ ¼ËG­8†ŠGÀ©A¶üÁ¿/‹o
Êõ?¬?0ãbŒÁŞ¶ªhR?*z§ö^¡œPÑ¹ Ä¤Ô.Ê9¦4XY²M@`»|¦@ÊôZòÁğş\¯ã}Èd_ÖØ×ösûËJš+ÛSeµÛÃ©±ÓI€^£ñ_~âÑèá^ :LÀ‹Ñ;N$3ÒWSån£)J4³°p=›×‹n¾&IÒ*(¾
¡ÜèúöªÿQ¤^6ƒt ²`·Tœğ2»V,
~LD«pÊ{˜Ãål+X‰{Û5¹zPx€ÍCİnÖ{›\y7ÅC,øÎ‹t`T¨8•‹.a¢Òt¼FÛßk q¸tY0
l™ur–`XwjYb‰èı¾åÚ€ )îxzá= çrÅ7ÌO–zô¢İÊİ	¬ˆY*@¬T	
Ê‚^Gu
Õ[2N;M`Åsó2:æ§Zkó‰õóYÚ?Nú+ê?'êA¾K Ù²¼’Øi­Ü¾k±Ï—Ô!à`B=æLˆŞ!Öè"%<ƒæß´EP„Qıç¢ãõ'
]=0k~Ÿê¤Oõç;,g"UÖ¶mŒ­2O]éØ)ı˜A`D}’~# 4ø¶	´ÀÅ_¸Ö›ú²y)Bß``4‘>hü[Xéß&Ô#W&¹2
+ıJeˆãÚ0(V««d<uÚÖÖA*Ş–ßØº¼BŞÜÕsşÓO¤Ùô½fÑEu
~{ë>w%ş¨âK[[újk"~6=j`ZıhlÈÔäôÿ¬ëÿ^¹KÔÏ‚[X4ÓC?ÇNxé!•åUpL^F>ï+$1VŞy:ØìÊéØ“~ãø[ªÄéu˜òÑBßZ»–ºæF[°³,ˆS"òùÕÔÇ•¨Íf¯Â!9$`ò§1wÒ‹OƒmØY›ÜY#÷”‡ó‘ŞXªFæõr×pçEMkÔâPü,±o‹?K”‹‡êï¼tò²´ç9ƒû¶„ğ&ßh}ª_…`³|¿ X~­é’K¾\¾’Ğï"#@0ÇkŒgˆ%™O‘ğÁ`NAŸË2Üûp¤rÈ»*·û}K½zaG6ÿ£L$¼
ºÁğ&8§Yi˜¼'ß},\‡BY©µK³¨máÇ¼ùM1íLı)~‘^;
ÊVGg½.{_#@ƒd_Ï!—›Gà÷™ìQ»ÔîfØï$Íg*¦#¡MjíX
HŞ)}¯¢E5›·ê`)¸H¼¿³¾sGï	æ({ƒ®“›¿^_&Vh6½²µ –ŒãDhDe§ˆ—½²™à ê¨$#Gû+2uC<&#-iœ—}öÄ…¾K¡\vßŠeÎæÏÔEò³Ñ%À|7yÖ…ÚüOöÕƒæuU1KÆ€­NÏ• MJ_÷m#à`4x;>Ş|Óîs™´Ó—¼…=šÀHü¥p¶Öra- [c°eU¾PóÍÌITñRD®í	TCÖà9·Õë~ „„_Í"½',4q«?7pkgÉ¨i!\vp-¶8Ğ±•¡Ø’\0#¨iÜDŸ]®‹{Ååº4şJ_d#:¦°út§PçÃA0Y~Uùf’õyÎÚByzOı1Éb×@¨$ÀRõ° d5|©±¾”dĞ]ÅOQ½¤ªò^
¢Z	¶‹Ëõv ZŸE4ÿKC Hä|İß«ç)0h\¦Wj.a>"Tác>•®´ûÙ=œ9ïMUÔæCyË×
O1W»P.¾E¼[ÚŠNÈN„íœ«ğĞìÓ4j {u…\;©révO‰ÿ 0»U$Åj\
ûyÁ"0Òo=©Å×Ç°[†*¬9ÚÖıÍ0§<Xùk[»ù˜‹ÿ¿ËiŒÚ¡²ÛHÇ³ª]~ Qc´ceô³*šQá4ReE·ˆÃ…I”µâ‹ÿ¹ÇBøa=!ÛÍrÑ¡CÃÍıøG¯Véb›#»¸+İÆ}ı°xøµ×¤rÀ…Íø‰Ùåaé‚ã3+…ÎÃH•^Ø2ç*İ©.ËŸOıÖ!nYÃÌ!¼âì6¨Z!ÄÆûïŸL[$—òª)øˆĞ	
…dsÈ -âëRónXZá6›å± 'tÈš4%ZšÄ,ğ%!aq;°>›{†ÕL/áˆÖÛiN‹X2Ä–-¯û»ïvD^o}ÚqL$:Â+æWóÍ8"5àf×¹Ü*mâK3Ğåá¡P½füqˆó—£Kûj}iX¾–§l ‰ŒŸA(n´›ÇÁ2Ò{]L•Òî/D“ä¸¼;ÎŠ/—gé£>‚—’')mçXİ\y{;éLúÈù”–#iå÷Îùî…ƒçº–?ìgR|…ßñWDF75Š†Jn Ua¼<ÀzVòë\eDèO/x6şv2üNê‡hSdÃ^ƒÂ1ÄîÜ–aEmí
1İ‡¬/`¸líw®°ç£Œwˆ&xu½5ª ˆ fÚÂ ¯;çóâº”(ğOX|Bå3;Ò´r¿¯úºˆ{alº\*„	Õª®³ğ> kÆ: å³Hße4¥{ ~6è­7Ñ£+chph•È‰–tm„À^“½&§…c¯LËCÿµ“@vÈUûLŞÒû˜|½Š~Ïq„KveS•Ï} ÂöšqoÍí~6óK2Æ Ìëp¶?¦ìÂPØl¥Ï$ .Ò6¬îÄ_ËÊø|fm‰ƒkÈTĞ÷—ó"#&‰Iš_fÎ¯Éu€ËÏ]%hñŠTÓÿùj¯4¨XS#Ì»á{W§ßË±[Á`áùıæÒ—ŞÇÕJ.eA¶^°çUç Céq&+0İ
‰	–@•”SÃXíŞ[­ã2¨Ï3© S‘Ûbañ›…Õö5¤¹ãoÅ3:í=(¿Áéd¥]BJÍ~9ù‹š`…öj›[bæ¨‰8Æ?ª\ôâp.aRÃöØ'ÜÅÈGYE @ZàÆŞK«[^/Ñ0p©Š—JÔİÛU¨’a—C‚	Já'Éh¼àéÂ‘˜ù“-€$6ôıõÌr„~¦¤@fvÌN,âÔòP®ÿeW¤àŒqX95Jz,qÍáš g+ÏX|Î j÷MrÎ"MÚq5(QÚM|eNÅÛò7Êk
Ìé} bı>™¤%Í’J¥ãÓ Hö’ÓğÖ=š)XF’º0>8E[B»Èµrhû/PM½‚2}@LÆö­ ÛÌ·ş¶#†âJû?ª/F <Œñï	áßB€¯j×ºİ
ìóÅLá÷|$‰ø`—h3Ç6×7«Ú³ïæäIÔÔ—¶ô_Ú£SoîáêŒv†ûØ"8×ò¸£¸U?–²
_üj¡¶÷æPˆğœ¹ÓFÖÉ•™‹Y·SX›Æ@9x„‰~JüÆH$Ò¦”¨±Fÿ	Z%˜L´¢¿G\ŸëüÃÜ‚„B-,ŸÛìh£²ãˆfÍà›˜'{q{i¥xké[;(JÎŞ‡s¶WEâ !²@
éÙxPb/<áMÂ¦^µÚÊ[
 Ûú|ª^k¶³"TI"Àqñ¾é{LÒ”û]Cm…•b È	)pÉi¦sd”Qg°VzZ”Wgj¼$ÅA›³9äø•åû:veöJóHÛ¶lÓğDÙ®¯AÄ­ø\ey­‹-”Ÿjˆ1êXÇÜ™¥€nZüæ`;üO,Z»Lmİ¯R×³6_	¨_Ÿ
kVœ&X]‰1&€ ŠàbdÇ*ÖSÜ»EÌkÏ|DÌŒ -$ÏÄ.èçq	aH‹P¨´Û”ûÀÅæ¸Å/p/nÓªoâ~W“\âÌŒ6±m™X©Œ‹›Š,yÔ€¦1‚ïÕ\€°õ˜eîĞJÿ)ùs<âşmÉÍÀ±€‰a[h¸ÁÀÎª…æÔ#Q‚kNÂË‹Ğsù ÷vA‰”0¾ÎÔ$Ç)Š|YIz}G*ÜQ´¹F¦o¨W•² õ“Ä´q]>ÅËzÄ]’1ÏMå‘ÚEZ«PÇ/5ßĞş2R1JR±‘ú¢’tîdçA~dïÀ~|k332`zÙİ^«£ªx¥Ûï-,lÈ2XÅ]nÇµÖZ;g<$Éd	{Á“¾|ğÎ–ì¼:ÙX"gğ)RT'yø äc+æİ ×
}#‹XG“‹ÏhZÄsìÊ³+-³A°	¾dÓªÑÑû‰ó‹%D
ÿ™?×‹ÜTòœt«Í¦óĞ¼ğó¦úêÙ¼Ig°·É‡—Â¾ŞßŞşı:ƒU‰wB¡„ŠAÌk»#*+É&X6ÿf5 ×Ô¿Ç‘Ë:ÚyG4eÌÄ]¾Å=	#I)î4BÊ…õ6êYŒtG¬WU 5­”ô—zHÏ6Á:?x÷	·ËJü¿ÜñA†ûJŸ	öşÀæWbÿ‘GQh_	?Ú{¥Áå¥
ğ7ûİòí&‘(·ù ‰ØU3üÓ®4#Ô!®åËM)ìİrv×SÒ” &en« _+É)ÖÁ§Ü
	ıE[õ
=*{Í³ğ:Ğmèi¤¨á0Éñç/®_“—8u³®UšDbY á‘uñ,`¾¼(”ÚS/©©(»˜\YN)‚Î‡À¤›
:põ4{ÕŸ™W^ñ]uíÄ‰¤×ïè'ß4ÂÍÀ«ùÖ²+ó’{Îe’8dñ{WâÖºZ@w'÷¢!§0»‰-×z»^@
ô¦BÏ
>áÏ–µ–….pÛ—eJ¹æ‹±AÈ W¹¿q†ÈìA!…Ã,àsjü¸ÅŸ¯eB¯#íâtéõ×?»ÇPìr#¯N‚Ó®©'ê3A†Uˆ^‰¶Â¥æi)8K35³vâ H°xš÷. †VŞ^7¥Ä¨øsÇœä1\½¬t½$g#¦Ë)U`O¡P›çš=IE0îò\J¦|bU‹GÅopVå¿ß'ÈVæIí¨)E¯™–»lè}Ğ\½ -ïÇ‰­ãÙbÛ¼Hf/›¦¶*‰0íÚ