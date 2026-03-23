use std::ffi::CStr;
#[cfg(feature = "ffi-test")]
use std::io::Cursor;
use std::os::raw::{c_char, c_int, c_uint};

#[allow(unused_imports)]
use bytes::Buf;
use bytes::Bytes;
use std::sync::{Arc, Mutex, OnceLock};
use std::{ptr, slice, str};

#[cfg(feature = "ffi-test")]
use std::net::SocketAddr;

#[cfg(feature = "ffi-test")]
use dashmap::DashMap;
#[cfg(feature = "ffi-test")]
use futures_util::future;
#[cfg(feature = "ffi-test")]
use std::collections::VecDeque;
#[cfg(feature = "ffi-test")]
use tokio::runtime::Runtime as TokioRuntime;

use ct_core::http_metrics_snapshot_with_breakdown;
#[cfg(feature = "ffi-test")]
use ct_core::parse_message;
use ct_core::{
    accept_channel, apply_router_config, close_connection, close_listener,
    connection_accept_websocket, connection_http3_connection, connection_http3_poll_request,
    connection_http3_poll_stream, connection_http_poll_request, connection_poll_http_event,
    connection_protocol, connection_rawsocket_max_exponent, connection_reject_websocket,
    connection_take_http2_handshake, connection_take_http3_handshake,
    connection_take_websocket_handshake, connection_websocket_protocol, listen,
    listener_http3_port, local_addr, poll_connection_message, reload_tls, response_stream_channel,
    send_wamp_message, send_wamp_segments, shutdown, start_runtime, ConnectionId,
    ConnectionProtocol, Error as CoreError, HttpConnectionCloseReason,
    HttpMetricsBreakdownSnapshot, HttpMetricsSnapshot, HttpResponseBody, HttpResponseDispatch,
    ListenerId, RawSocketSerializer, WampMessage, RESPONSE_STREAM_BUFFER,
};
#[cfg(feature = "ffi-test")]
use ct_core::{
    push_http_connection_event, register_http3_pending, Http3Handshake, HttpBodyHandle,
    HttpConnectionEvent, HttpRouteResolution,
};
#[cfg(feature = "ffi-test")]
use h3::client as h3_client;
#[cfg(feature = "ffi-test")]
use h3_quinn::Connection as H3QuinnConnection;
use http::StatusCode;
#[cfg(feature = "ffi-test")]
use quinn::{
    crypto::rustls::QuicClientConfig as QuinnRustlsClientConfig, ClientConfig as QuinnClientConfig,
    Endpoint as QuinnEndpoint, TransportConfig,
};
#[cfg(feature = "ffi-test")]
use rustls::client::WebPkiServerVerifier;
#[cfg(feature = "ffi-test")]
use rustls::pki_types::CertificateDer;
#[cfg(feature = "ffi-test")]
use rustls::{ClientConfig as RustlsClientConfig, RootCertStore};
#[cfg(feature = "ffi-test")]
use rustls_pemfile::certs as read_pem_certs;

use crate::callbacks::{
    invoke_connection_callback, invoke_listener_callback, register_connection_callback,
    register_listener_callback,
};

use super::constants::*;
use super::state::{
    clear_channels, clone_message, remove_http2_handshake, remove_http3_connection,
    remove_http3_handshake, remove_http3_stream, remove_http_body, remove_http_connection_event,
    remove_http_handshake, remove_http_response_stream, remove_message, remove_websocket_handshake,
    store_channel, store_http2_handshake, store_http3_connection, store_http3_handshake,
    store_http3_stream, store_http_body, store_http_connection_event, store_http_request_metadata,
    store_http_response_stream, store_message, store_websocket_handshake, with_channel,
    with_http2_handshake, with_http3_handshake, with_http3_stream, with_http_body,
    with_http_connection_event, with_http_handshake, with_http_response_stream, with_message,
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

#[cfg(feature = "ffi-test")]
#[repr(C)]
pub struct CtByteBuffer {
    pub ptr: *mut u8,
    pub len: usize,
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
    pub backpressure_events: u32,
    pub max_backpressure_depth: u32,
    pub goaway_events: u32,
    pub detail_ptr: *const u8,
    pub detail_len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtRouterMetricsInfo {
    pub total_events: u64,
    pub graceful_events: u64,
    pub goaway_events: u64,
    pub idle_timeout_events: u64,
    pub body_timeout_events: u64,
    pub protocol_error_events: u64,
    pub internal_error_events: u64,
    pub backpressure_events: u64,
    pub max_backpressure_depth: u32,
    pub breakdown_ptr: *const CtRouterMetricsBreakdownInfo,
    pub breakdown_len: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct CtRouterMetricsBreakdownInfo {
    pub listener_id: u32,
    pub protocol: c_int,
    pub total_events: u64,
    pub graceful_events: u64,
    pub goaway_events: u64,
    pub idle_timeout_events: u64,
    pub body_timeout_events: u64,
    pub protocol_error_events: u64,
    pub internal_error_events: u64,
    pub backpressure_events: u64,
    pub max_backpressure_depth: u32,
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
        CoreError::SendQueueFull(_) => ERR_SEND_QUEUE_FULL,
        CoreError::InvalidRuntimeThreadCount(_) => ERR_INVALID_ARGUMENT,
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
    let (body_ptr, _inline_len) = metadata
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

static ROUTER_METRICS_BREAKDOWN: OnceLock<Mutex<Option<Box<[CtRouterMetricsBreakdownInfo]>>>> =
    OnceLock::new();

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

fn write_cbor_array_len(buf: &mut Vec<u8>, len: usize) {
    if len <= 23 {
        buf.push(0x80 | len as u8);
    } else if len <= u8::MAX as usize {
        buf.push(0x98);
        buf.push(len as u8);
    } else if len <= u16::MAX as usize {
        buf.push(0x99);
        buf.extend_from_slice(&(len as u16).to_be_bytes());
    } else if len <= u32::MAX as usize {
        buf.push(0x9a);
        buf.extend_from_slice(&(len as u32).to_be_bytes());
    } else {
        buf.push(0x9b);
        buf.extend_from_slice(&(len as u64).to_be_bytes());
    }
}

fn encode_event_segments_cbor(
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
    let details_cbor = serde_cbor::to_vec(&details_value).map_err(|_| ERR_INVALID_ARGUMENT)?;

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
    write_cbor_array_len(&mut prefix, element_count);
    prefix.extend_from_slice(&serde_cbor::to_vec(&36u64).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix.extend_from_slice(
        &serde_cbor::to_vec(&subscription_id).map_err(|_| ERR_INVALID_ARGUMENT)?,
    );
    prefix
        .extend_from_slice(&serde_cbor::to_vec(&publication_id).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix.extend_from_slice(&details_cbor);

    let mut segments = Vec::new();
    segments.push(Bytes::from(prefix));
    if has_args {
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(&[0x80])
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
        RawSocketSerializer::Cbor => {
            encode_event_segments_cbor(payload, subscription_id, publication_id, publisher, topic)
        }
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

fn encode_invocation_segments_cbor(
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
    let details_cbor = serde_cbor::to_vec(&details_value).map_err(|_| ERR_INVALID_ARGUMENT)?;

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
    write_cbor_array_len(&mut prefix, element_count);
    prefix.extend_from_slice(&serde_cbor::to_vec(&68u64).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix
        .extend_from_slice(&serde_cbor::to_vec(&invocation_id).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix.extend_from_slice(
        &serde_cbor::to_vec(&registration_id).map_err(|_| ERR_INVALID_ARGUMENT)?,
    );
    prefix.extend_from_slice(&details_cbor);

    let mut segments = Vec::new();
    segments.push(Bytes::from(prefix));
    if has_args {
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(&[0x80])
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
        RawSocketSerializer::Cbor => encode_invocation_segments_cbor(
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

fn build_result_segments_cbor(
    payload: &ct_core::WampPayload,
    request_id: u64,
    details_cbor: Vec<u8>,
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
    write_cbor_array_len(&mut prefix, element_count);
    prefix.extend_from_slice(&serde_cbor::to_vec(&50u64).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix.extend_from_slice(&serde_cbor::to_vec(&request_id).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix.extend_from_slice(&details_cbor);

    let mut segments = Vec::new();
    segments.push(Bytes::from(prefix));
    if has_args {
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(&[0x80])
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
            RawSocketSerializer::Cbor => {
                let mut details_map = options.clone();
                if progress {
                    details_map.insert(
                        SerdeValue::String("progress".into()),
                        SerdeValue::Bool(true),
                    );
                }
                let details_cbor =
                    serde_cbor::to_vec(&details_map).map_err(|_| ERR_INVALID_ARGUMENT)?;
                build_result_segments_cbor(payload, request_id, details_cbor)
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

fn build_error_segments_cbor(
    payload: &ct_core::WampPayload,
    request_type: u64,
    request_id: u64,
    details_cbor: Vec<u8>,
    error_cbor: Vec<u8>,
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
    write_cbor_array_len(&mut prefix, element_count);
    prefix.extend_from_slice(&serde_cbor::to_vec(&8u64).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix.extend_from_slice(&serde_cbor::to_vec(&request_type).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix.extend_from_slice(&serde_cbor::to_vec(&request_id).map_err(|_| ERR_INVALID_ARGUMENT)?);
    prefix.extend_from_slice(&details_cbor);
    prefix.extend_from_slice(&error_cbor);

    let mut segments = Vec::new();
    segments.push(Bytes::from(prefix));
    if has_args {
        let args_bytes = if let Some(args) = payload.args.clone() {
            args
        } else {
            Bytes::from_static(&[0x80])
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
            RawSocketSerializer::Cbor => {
                let details_cbor = serde_cbor::to_vec(details).map_err(|_| ERR_INVALID_ARGUMENT)?;
                let error_cbor = serde_cbor::to_vec(error).map_err(|_| ERR_INVALID_ARGUMENT)?;
                build_error_segments_cbor(
                    payload,
                    request_type,
                    request_id,
                    details_cbor,
                    error_cbor,
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
pub extern "C" fn ct_reload_tls() -> c_int {
    match reload_tls() {
        Ok(count) => count as c_int,
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
pub extern "C" fn ct_listener_close(listener_id: c_int) -> c_int {
    let listener_id = ListenerId(listener_id as u32);
    match close_listener(listener_id) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_poll_connection(listener_id: c_int) -> c_int {
    let listener_id = ListenerId(listener_id as u32);
    loop {
        match with_channel(listener_id, |receiver| receiver.try_recv()) {
            Some(Ok(connection_id)) => match connection_protocol(connection_id) {
                Ok(_) => {
                    invoke_connection_callback(listener_id, connection_id);
                    return connection_id.0 as c_int;
                }
                Err(CoreError::ConnectionNotFound(_)) => continue,
                Err(err) => return map_error(err),
            },
            Some(Err(_)) => return 0,
            None => {
                return match local_addr(listener_id) {
                    Ok(_) => 0,
                    Err(err) => map_error(err),
                }
            }
        }
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
        Ok(protocol) => {
            #[cfg(feature = "ffi-test")]
            eprintln!(
                "ct_connection_protocol({:?}) -> {:?}",
                connection_id, protocol
            );
            match protocol {
                ConnectionProtocol::RawSocket => PROTOCOL_RAWSOCKET,
                ConnectionProtocol::WebSocket => PROTOCOL_WEBSOCKET,
                ConnectionProtocol::Http => PROTOCOL_HTTP,
                ConnectionProtocol::Http2 => PROTOCOL_HTTP2,
                ConnectionProtocol::Http3 => PROTOCOL_HTTP3,
            }
        }
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_connection_close(connection_id: c_int) -> c_int {
    let connection_id = ConnectionId(connection_id as u32);
    match close_connection(connection_id) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_connection_websocket_protocol(
    connection_id: c_int,
    buffer: *mut u8,
    len: *mut c_int,
) -> c_int {
    if len.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let capacity = unsafe { *len };
    if capacity < 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let connection_id = ConnectionId(connection_id as u32);
    match connection_websocket_protocol(connection_id) {
        Ok(Some(protocol)) => {
            let required = protocol.as_bytes().len() as c_int;
            unsafe {
                *len = required;
            }
            if buffer.is_null() {
                return SUCCESS;
            }
            if capacity < required {
                return ERR_INVALID_ARGUMENT;
            }
            unsafe {
                ptr::copy_nonoverlapping(protocol.as_ptr(), buffer, required as usize);
            }
            SUCCESS
        }
        Ok(None) => {
            unsafe {
                *len = 0;
            }
            SUCCESS
        }
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
            let metadata = HttpMetadata::from_summary(summary);
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
        Ok(handshake) => {
            #[cfg(feature = "ffi-test")]
            eprintln!(
                "ct_connection_take_http3_handshake {:?} -> stored handle",
                connection_id
            );
            store_http3_handshake(handshake) as c_int
        }
        Err(err) => {
            #[cfg(feature = "ffi-test")]
            eprintln!(
                "ct_connection_take_http3_handshake {:?} failed: {:?}",
                connection_id, err
            );
            map_error(err)
        }
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
            let metadata = HttpMetadata::from_summary(summary);
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
pub extern "C" fn ct_connection_poll_http_event() -> c_int {
    match connection_poll_http_event() {
        Some(event) => store_http_connection_event(event) as c_int,
        None => 0,
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
        info_ref.backpressure_events = stored.backpressure_events;
        info_ref.max_backpressure_depth = stored.max_backpressure_depth;
        info_ref.goaway_events = stored.goaway_events;
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
pub extern "C" fn ct_router_metrics_snapshot(info: *mut CtRouterMetricsInfo) -> c_int {
    if info.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    let (snapshot, breakdown): (HttpMetricsSnapshot, Vec<HttpMetricsBreakdownSnapshot>) =
        http_metrics_snapshot_with_breakdown();
    let info_ref = unsafe { info.as_mut().unwrap() };
    info_ref.total_events = snapshot.total_events;
    info_ref.graceful_events = snapshot.graceful_events;
    info_ref.goaway_events = snapshot.goaway_events;
    info_ref.idle_timeout_events = snapshot.idle_timeout_events;
    info_ref.body_timeout_events = snapshot.body_timeout_events;
    info_ref.protocol_error_events = snapshot.protocol_error_events;
    info_ref.internal_error_events = snapshot.internal_error_events;
    info_ref.backpressure_events = snapshot.backpressure_events;
    info_ref.max_backpressure_depth = snapshot.max_backpressure_depth;
    if breakdown.is_empty() {
        info_ref.breakdown_ptr = ptr::null();
        info_ref.breakdown_len = 0;
        if let Some(cache) = ROUTER_METRICS_BREAKDOWN.get() {
            let mut guard = cache.lock().unwrap();
            *guard = None;
        }
    } else {
        let boxed: Box<[CtRouterMetricsBreakdownInfo]> = breakdown
            .into_iter()
            .map(|entry| CtRouterMetricsBreakdownInfo {
                listener_id: entry.listener_id.0,
                protocol: match entry.protocol {
                    ConnectionProtocol::RawSocket => PROTOCOL_RAWSOCKET,
                    ConnectionProtocol::WebSocket => PROTOCOL_WEBSOCKET,
                    ConnectionProtocol::Http => PROTOCOL_HTTP,
                    ConnectionProtocol::Http2 => PROTOCOL_HTTP2,
                    ConnectionProtocol::Http3 => PROTOCOL_HTTP3,
                },
                total_events: entry.snapshot.total_events,
                graceful_events: entry.snapshot.graceful_events,
                goaway_events: entry.snapshot.goaway_events,
                idle_timeout_events: entry.snapshot.idle_timeout_events,
                body_timeout_events: entry.snapshot.body_timeout_events,
                protocol_error_events: entry.snapshot.protocol_error_events,
                internal_error_events: entry.snapshot.internal_error_events,
                backpressure_events: entry.snapshot.backpressure_events,
                max_backpressure_depth: entry.snapshot.max_backpressure_depth,
            })
            .collect::<Vec<_>>()
            .into_boxed_slice();
        let cache = ROUTER_METRICS_BREAKDOWN.get_or_init(|| Mutex::new(None));
        let mut guard = cache.lock().unwrap();
        *guard = Some(boxed);
        if let Some(slice) = guard.as_ref() {
            info_ref.breakdown_ptr = slice.as_ptr();
            info_ref.breakdown_len = slice.len();
        } else {
            info_ref.breakdown_ptr = ptr::null();
            info_ref.breakdown_len = 0;
        }
    }
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

/// Alias that only succeeds for WebSocket connections; returns ERR_UNSUPPORTED otherwise.
#[no_mangle]
pub extern "C" fn ct_poll_websocket_message(connection_id: c_int) -> c_int {
    let connection_id = ConnectionId(connection_id as u32);
    match connection_protocol(connection_id) {
        Ok(ConnectionProtocol::WebSocket) => ct_poll_connection_message(connection_id.0 as c_int),
        Ok(_) => ERR_UNSUPPORTED,
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
            list.push((
                std::sync::Arc::<[u8]>::from(name.into_bytes()),
                std::sync::Arc::<[u8]>::from(value.into_bytes()),
            ));
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
pub extern "C" fn ct_test_byte_buffer_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        Vec::from_raw_parts(ptr, len, len);
    }
}

#[cfg(feature = "ffi-test")]
fn build_http3_client_config_from_roots(
    roots: Arc<RootCertStore>,
) -> Result<QuinnClientConfig, c_int> {
    let provider = rustls::crypto::ring::default_provider();
    let verifier = WebPkiServerVerifier::builder_with_provider(roots, Arc::new(provider.clone()))
        .build()
        .map_err(|_| ERR_INVALID_ARGUMENT)?;
    let mut inner = RustlsClientConfig::builder_with_provider(Arc::new(provider))
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(|_| ERR_INVALID_ARGUMENT)?
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth();
    inner.enable_early_data = true;
    inner.alpn_protocols = vec![b"h3".to_vec(), b"h3-29".to_vec()];
    let quic_suite = rustls::crypto::ring::cipher_suite::TLS13_AES_128_GCM_SHA256
        .tls13()
        .and_then(|suite| suite.quic_suite())
        .ok_or(ERR_INVALID_ARGUMENT)?;
    let quic = QuinnRustlsClientConfig::with_initial(Arc::new(inner), quic_suite)
        .map_err(|_| ERR_INVALID_ARGUMENT)?;
    let mut config = QuinnClientConfig::new(Arc::new(quic));
    config.transport_config(Arc::new(TransportConfig::default()));
    Ok(config)
}

#[cfg(feature = "ffi-test")]
fn build_http3_client_config_from_pem(pem: &str) -> Result<QuinnClientConfig, c_int> {
    let mut reader = Cursor::new(pem.as_bytes());
    let mut certs = Vec::new();
    for cert in read_pem_certs(&mut reader) {
        let cert = cert.map_err(|_| ERR_INVALID_ARGUMENT)?;
        certs.push(cert);
    }
    if certs.is_empty() {
        return Err(ERR_INVALID_ARGUMENT);
    }
    let mut roots = RootCertStore::empty();
    for der in certs {
        roots
            .add(CertificateDer::from(der))
            .map_err(|_| ERR_INVALID_ARGUMENT)?;
    }
    build_http3_client_config_from_roots(Arc::new(roots))
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_http3_stream_request(
    host_ptr: *const c_char,
    port: c_int,
    path_ptr: *const c_char,
    method_ptr: *const c_char,
    headers_ptr: *const CtHttpHeader,
    headers_len: usize,
    body_ptr: *const u8,
    body_len: usize,
    cert_pem_ptr: *const c_char,
    status_out: *mut c_int,
    response_ptr_out: *mut *mut u8,
    response_len_out: *mut usize,
) -> c_int {
    if host_ptr.is_null() || path_ptr.is_null() || method_ptr.is_null() || port <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let host = match unsafe { CStr::from_ptr(host_ptr) }.to_str() {
        Ok(value) => value.to_string(),
        Err(_) => return ERR_INVALID_ARGUMENT,
    };
    let path = match unsafe { CStr::from_ptr(path_ptr) }.to_str() {
        Ok(value) => value.to_string(),
        Err(_) => return ERR_INVALID_ARGUMENT,
    };
    let method = match unsafe { CStr::from_ptr(method_ptr) }.to_str() {
        Ok(value) => value.to_string(),
        Err(_) => return ERR_INVALID_ARGUMENT,
    };
    let cert_pem = if cert_pem_ptr.is_null() {
        return ERR_INVALID_ARGUMENT;
    } else {
        match unsafe { CStr::from_ptr(cert_pem_ptr) }.to_str() {
            Ok(value) => value.to_string(),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
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
    let body = if body_len == 0 || body_ptr.is_null() {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(body_ptr, body_len) }
    };
    let client_config = match build_http3_client_config_from_pem(&cert_pem) {
        Ok(config) => config,
        Err(code) => return code,
    };
    let runtime = match TokioRuntime::new() {
        Ok(rt) => rt,
        Err(_) => return ERR_INTERNAL,
    };
    let result = runtime.block_on(async {
        let addr = format!("{host}:{port}");
        let server_addr = addr.parse().map_err(|_| ERR_INVALID_ARGUMENT)?;
        let mut endpoint =
            QuinnEndpoint::client("[::]:0".parse().map_err(|_| ERR_INVALID_ARGUMENT)?)
                .map_err(|_| ERR_INTERNAL)?;
        endpoint.set_default_client_config(client_config);
        let connecting = endpoint.connect(server_addr, &host).map_err(|err| {
            eprintln!("ffi-test http3 connect failed: {err}");
            ERR_INTERNAL
        })?;
        let connection = connecting.await.map_err(|err| {
            eprintln!("ffi-test http3 handshake failed: {err}");
            ERR_INTERNAL
        })?;
        let (mut driver, mut send_request) = h3_client::builder()
            .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
            .await
            .map_err(|err| {
                eprintln!("ffi-test http3 builder failed: {err}");
                ERR_INTERNAL
            })?;
        tokio::spawn(async move {
            future::poll_fn(|cx| driver.poll_close(cx)).await;
        });
        let uri = format!("https://{host}:{port}{path}");
        let http_method = method
            .parse::<http::Method>()
            .map_err(|_| ERR_INVALID_ARGUMENT)?;
        let mut builder = http::Request::builder().method(http_method).uri(uri);
        for (name, value) in &headers {
            builder = builder.header(name.as_str(), value.as_str());
        }
        let request = builder.body(()).map_err(|_| ERR_INVALID_ARGUMENT)?;
        let mut stream = send_request.send_request(request).await.map_err(|err| {
            eprintln!("ffi-test http3 send_request failed: {err}");
            ERR_INTERNAL
        })?;
        if body.is_empty() {
            stream.finish().await.map_err(|err| {
                eprintln!("ffi-test http3 finish failed: {err}");
                ERR_INTERNAL
            })?;
        } else {
            let mut offset = 0usize;
            while offset < body.len() {
                let end = usize::min(offset + 16 * 1024, body.len());
                let chunk = Bytes::copy_from_slice(&body[offset..end]);
                stream.send_data(chunk).await.map_err(|err| {
                    eprintln!("ffi-test http3 send_data failed: {err}");
                    ERR_INTERNAL
                })?;
                offset = end;
            }
            stream.finish().await.map_err(|err| {
                eprintln!("ffi-test http3 finish failed: {err}");
                ERR_INTERNAL
            })?;
        }
        let response = stream.recv_response().await.map_err(|err| {
            eprintln!("ffi-test http3 recv_response failed: {err}");
            ERR_INTERNAL
        })?;
        let mut response_body = Vec::new();
        while let Some(chunk) = stream.recv_data().await.map_err(|err| {
            eprintln!("ffi-test http3 recv_data failed: {err}");
            ERR_INTERNAL
        })? {
            response_body.extend_from_slice(chunk.chunk());
        }
        Ok::<(c_int, Vec<u8>), c_int>((response.status().as_u16() as c_int, response_body))
    });
    let (status, response_body) = match result {
        Ok(value) => value,
        Err(code) => return code,
    };
    let (ptr, len) = if response_body.is_empty() {
        (ptr::null_mut(), 0usize)
    } else {
        let len = response_body.len();
        let boxed = response_body.into_boxed_slice();
        (Box::into_raw(boxed) as *mut u8, len)
    };
    unsafe {
        if !status_out.is_null() {
            *status_out = status;
        }
        if !response_ptr_out.is_null() {
            *response_ptr_out = ptr;
        }
        if !response_len_out.is_null() {
            *response_len_out = len;
        }
    }
    SUCCESS
}

#[cfg(feature = "ffi-test")]
#[no_mangle]
pub extern "C" fn ct_test_push_http_connection_event(
    connection_id: c_int,
    listener_id: c_int,
    protocol: c_int,
    reason: c_int,
    request_count: u32,
    idle_timeouts: u32,
    body_timeouts: u32,
    backpressure_events: u32,
    max_backpressure_depth: u32,
    goaway_events: u32,
    detail_ptr: *const c_char,
    detail_len: c_int,
) -> c_int {
    if connection_id <= 0 || listener_id <= 0 || detail_len < 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let protocol = match protocol {
        PROTOCOL_RAWSOCKET => ConnectionProtocol::RawSocket,
        PROTOCOL_WEBSOCKET => ConnectionProtocol::WebSocket,
        PROTOCOL_HTTP => ConnectionProtocol::Http,
        PROTOCOL_HTTP2 => ConnectionProtocol::Http2,
        PROTOCOL_HTTP3 => ConnectionProtocol::Http3,
        _ => return ERR_INVALID_ARGUMENT,
    };
    let reason = match reason {
        HTTP_EVENT_REASON_GRACEFUL => HttpConnectionCloseReason::Graceful,
        HTTP_EVENT_REASON_GOAWAY => HttpConnectionCloseReason::GoAway,
        HTTP_EVENT_REASON_IDLE_TIMEOUT => HttpConnectionCloseReason::IdleTimeout,
        HTTP_EVENT_REASON_BODY_TIMEOUT => HttpConnectionCloseReason::BodyTimeout,
        HTTP_EVENT_REASON_PROTOCOL_ERROR => HttpConnectionCloseReason::ProtocolError,
        HTTP_EVENT_REASON_INTERNAL => HttpConnectionCloseReason::Internal,
        _ => return ERR_INVALID_ARGUMENT,
    };
    let detail = if detail_ptr.is_null() || detail_len == 0 {
        None
    } else {
        let bytes =
            unsafe { std::slice::from_raw_parts(detail_ptr as *const u8, detail_len as usize) };
        match String::from_utf8(bytes.to_vec()) {
            Ok(value) => Some(value),
            Err(_) => return ERR_INVALID_ARGUMENT,
        }
    };
    let event = HttpConnectionEvent {
        connection_id: ConnectionId(connection_id as u32),
        protocol,
        reason,
        request_count,
        idle_timeouts,
        body_timeouts,
        backpressure_events,
        max_backpressure_depth,
        goaway_events,
        detail,
    };
    push_http_connection_event(ListenerId(listener_id as u32), event);
    SUCCESS
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
                });
            }
            SUCCESS
        }
        Some(Err(err)) => {
            eprintln!("http body stream read failed: {:?}", err);
            ERR_IO
        }
        None => ERR_HANDLE_UNAVAILABLE,
    }
}

#[no_mangle]
pub extern "C" fn ct_http_body_finish(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    match with_http_body(handle as u32, |body| {
        body.request_finish();
    }) {
        Some(()) => SUCCESS,
        None => ERR_HANDLE_UNAVAILABLE,
    }
}

#[no_mangle]
pub extern "C" fn ct_websocket_handshake_get(
    handle: c_int,
    out_info: *mut CtWebSocketHandshakeInfo,
) -> c_int {
    if handle <= 0 || out_info.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_websocket_handshake(handle as u32, |stored| CtWebSocketHandshakeInfo {
        key_ptr: stored.key.as_ptr(),
        key_len: stored.key.len(),
        protocols_len: stored.protocols.len(),
        extensions_len: stored.extensions.len(),
        version_ptr: stored
            .version
            .as_ref()
            .map(|value| value.as_ptr())
            .unwrap_or(ptr::null()),
        version_len: stored
            .version
            .as_ref()
            .map(|value| value.len())
            .unwrap_or(0),
        http_info: http_metadata_view(&stored.metadata),
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
pub extern "C" fn ct_websocket_handshake_protocol(
    handle: c_int,
    index: usize,
    out_view: *mut CtStringView,
) -> c_int {
    if handle <= 0 || out_view.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_websocket_handshake(handle as u32, |stored| {
        stored.protocols.get(index).map(|value| string_view(value))
    }) {
        Some(Some(view)) => {
            unsafe {
                out_view.write(view);
            }
            SUCCESS
        }
        Some(None) => ERR_INVALID_ARGUMENT,
        None => ERR_INVALID_ARGUMENT,
    }
}

#[no_mangle]
pub extern "C" fn ct_websocket_handshake_extension(
    handle: c_int,
    index: usize,
    out_view: *mut CtStringView,
) -> c_int {
    if handle <= 0 || out_view.is_null() {
        return ERR_INVALID_ARGUMENT;
    }
    match with_websocket_handshake(handle as u32, |stored| {
        stored.extensions.get(index).map(|value| string_view(value))
    }) {
        Some(Some(view)) => {
            unsafe {
                out_view.write(view);
            }
            SUCCESS
        }
        Some(None) => ERR_INVALID_ARGUMENT,
        None => ERR_INVALID_ARGUMENT,
    }
}

#[no_mangle]
pub extern "C" fn ct_websocket_handshake_release(handle: c_int) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    remove_websocket_handshake(handle as u32);
    SUCCESS
}

#[no_mangle]
pub extern "C" fn ct_forward_publish_event(
    handle: c_int,
    connection_id: c_int,
    subscription_id: u64,
    publication_id: u64,
    publisher_present: c_int,
    publisher_session: u64,
    topic_ptr: *const c_char,
    topic_len: c_int,
) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let topic = match read_optional_str(topic_ptr, topic_len) {
        Ok(topic) => topic,
        Err(code) => return code,
    };
    let publisher = if publisher_present != 0 {
        Some(publisher_session)
    } else {
        None
    };
    let handle_u32 = handle as u32;
    let segments = match with_message(handle_u32, |msg| {
        encode_event_segments(
            msg,
            subscription_id,
            publication_id,
            publisher,
            topic.as_deref(),
        )
    }) {
        Some(Ok(parts)) => parts,
        Some(Err(code)) => return code,
        None => return ERR_INVALID_ARGUMENT,
    };
    let connection_id = ConnectionId(connection_id as u32);
    match send_wamp_segments(connection_id, segments) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_forward_call_invocation(
    handle: c_int,
    connection_id: c_int,
    invocation_id: u64,
    registration_id: u64,
    caller_present: c_int,
    caller_session: u64,
    procedure_ptr: *const c_char,
    procedure_len: c_int,
    receive_progress_flag: c_int,
) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let procedure = match read_optional_str(procedure_ptr, procedure_len) {
        Ok(proc) => proc,
        Err(code) => return code,
    };
    let caller = if caller_present != 0 {
        Some(caller_session)
    } else {
        None
    };
    let receive_progress = match receive_progress_flag {
        -1 => None,
        0 => Some(false),
        _ => Some(true),
    };
    let handle_u32 = handle as u32;
    let segments = match with_message(handle_u32, |msg| {
        encode_invocation_segments(
            msg,
            invocation_id,
            registration_id,
            caller,
            procedure.as_deref(),
            receive_progress,
        )
    }) {
        Some(Ok(parts)) => parts,
        Some(Err(code)) => return code,
        None => return ERR_INVALID_ARGUMENT,
    };
    let connection_id = ConnectionId(connection_id as u32);
    match send_wamp_segments(connection_id, segments) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_forward_result_from_yield(
    handle: c_int,
    connection_id: c_int,
    request_id: u64,
    progress_flag: c_int,
) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let handle_u32 = handle as u32;
    let progress = progress_flag != 0;
    let segments = match with_message(handle_u32, |msg| {
        encode_result_segments(msg, request_id, progress)
    }) {
        Some(Ok(parts)) => parts,
        Some(Err(code)) => return code,
        None => return ERR_INVALID_ARGUMENT,
    };
    let connection_id = ConnectionId(connection_id as u32);
    match send_wamp_segments(connection_id, segments) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_forward_error_from_error(
    handle: c_int,
    connection_id: c_int,
    request_type: u64,
    request_id: u64,
) -> c_int {
    if handle <= 0 {
        return ERR_INVALID_ARGUMENT;
    }
    let handle_u32 = handle as u32;
    let segments = match with_message(handle_u32, |msg| {
        encode_error_segments(msg, request_type, request_id)
    }) {
        Some(Ok(parts)) => parts,
        Some(Err(code)) => return code,
        None => return ERR_INVALID_ARGUMENT,
    };
    let connection_id = ConnectionId(connection_id as u32);
    match send_wamp_segments(connection_id, segments) {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_set_on_listener_started(callback: extern "C" fn(c_int, c_int)) {
    register_listener_callback(callback);
}

#[no_mangle]
pub extern "C" fn ct_set_on_connection(callback: extern "C" fn(c_int, c_int)) {
    register_connection_callback(callback);
}

#[cfg(test)]
mod tests {
    use super::*;
    use bytes::Bytes;
    use ct_core::{WampMessage, WampPayload};
    use serde_json::json;
    use std::collections::BTreeMap;

    fn concat_segments(segments: Vec<Bytes>) -> Vec<u8> {
        let total_len: usize = segments.iter().map(Bytes::len).sum();
        let mut bytes = Vec::with_capacity(total_len);
        for segment in segments {
            bytes.extend_from_slice(&segment);
        }
        bytes
    }

    #[test]
    fn cbor_event_and_invocation_segments_preserve_payload_slices() {
        let args = Bytes::from(serde_cbor::to_vec(&vec!["payload"]).unwrap());
        let kwargs = Bytes::from(serde_cbor::to_vec(&json!({"flag": true})).unwrap());

        let publish = StoredMessage {
            serializer: RawSocketSerializer::Cbor,
            code: 16,
            raw: Bytes::new(),
            message: WampMessage::Publish {
                request_id: 1,
                options: BTreeMap::new(),
                topic: "bench.topic".into(),
                payload: WampPayload {
                    args: Some(args.clone()),
                    kwargs: Some(kwargs.clone()),
                },
            },
            args: Some(args.clone()),
            kwargs: Some(kwargs.clone()),
        };
        let event = concat_segments(
            encode_event_segments(&publish, 77, 88, Some(9), Some("bench.topic")).unwrap(),
        );
        let decoded_event: serde_json::Value = serde_cbor::from_slice(&event).unwrap();
        assert_eq!(
            decoded_event,
            json!([36, 77, 88, {"publisher": 9, "topic": "bench.topic"}, ["payload"], {"flag": true}])
        );

        let call = StoredMessage {
            serializer: RawSocketSerializer::Cbor,
            code: 48,
            raw: Bytes::new(),
            message: WampMessage::Call {
                request_id: 2,
                options: BTreeMap::new(),
                procedure: "bench.rpc.echo".into(),
                payload: WampPayload {
                    args: Some(args.clone()),
                    kwargs: Some(kwargs.clone()),
                },
            },
            args: Some(args),
            kwargs: Some(kwargs),
        };
        let invocation = concat_segments(
            encode_invocation_segments(&call, 99, 101, Some(7), Some("bench.rpc.echo"), Some(true))
                .unwrap(),
        );
        let decoded_invocation: serde_json::Value = serde_cbor::from_slice(&invocation).unwrap();
        assert_eq!(
            decoded_invocation,
            json!([
                68,
                99,
                101,
                {"caller": 7, "procedure": "bench.rpc.echo", "receive_progress": true},
                ["payload"],
                {"flag": true}
            ])
        );
    }

    #[test]
    fn cbor_result_and_error_segments_preserve_payload_slices() {
        let args = Bytes::from(serde_cbor::to_vec(&vec!["payload"]).unwrap());
        let kwargs = Bytes::from(serde_cbor::to_vec(&json!({"flag": true})).unwrap());

        let mut yield_options = BTreeMap::new();
        yield_options.insert(
            SerdeValue::String("progress".into()),
            SerdeValue::Bool(false),
        );
        let yield_message = StoredMessage {
            serializer: RawSocketSerializer::Cbor,
            code: 70,
            raw: Bytes::new(),
            message: WampMessage::Yield {
                request_id: 3,
                options: yield_options,
                payload: WampPayload {
                    args: Some(args.clone()),
                    kwargs: Some(kwargs.clone()),
                },
            },
            args: Some(args.clone()),
            kwargs: Some(kwargs.clone()),
        };
        let result = concat_segments(encode_result_segments(&yield_message, 123, true).unwrap());
        let decoded_result: serde_json::Value = serde_cbor::from_slice(&result).unwrap();
        assert_eq!(
            decoded_result,
            json!([50, 123, {"progress": true}, ["payload"], {"flag": true}])
        );

        let error_message = StoredMessage {
            serializer: RawSocketSerializer::Cbor,
            code: 8,
            raw: Bytes::new(),
            message: WampMessage::Error {
                request_type: 68,
                request_id: 123,
                details: BTreeMap::new(),
                error: "wamp.error.runtime_error".into(),
                payload: WampPayload {
                    args: Some(args.clone()),
                    kwargs: Some(kwargs.clone()),
                },
            },
            args: Some(args),
            kwargs: Some(kwargs),
        };
        let error = concat_segments(encode_error_segments(&error_message, 68, 123).unwrap());
        let decoded_error: serde_json::Value = serde_cbor::from_slice(&error).unwrap();
        assert_eq!(
            decoded_error,
            json!([
                8,
                68,
                123,
                {},
                "wamp.error.runtime_error",
                ["payload"],
                {"flag": true}
            ])
        );
    }
}
