use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_uint};

use bytes::Bytes;
use std::{ptr, slice, str};

#[cfg(feature = "ffi-test")]
use dashmap::DashMap;
#[cfg(feature = "ffi-test")]
use std::collections::VecDeque;
#[cfg(feature = "ffi-test")]
use std::sync::{Mutex, OnceLock};

use ct_core::{
    accept_channel, apply_router_config, connection_rawsocket_max_exponent, listen, local_addr,
    poll_connection_message, send_wamp_message, send_wamp_segments, shutdown, start_runtime,
    ConnectionId, Error as CoreError, ListenerId, RawSocketSerializer, WampMessage,
};
#[cfg(feature = "ffi-test")]
use ct_core::parse_message;

use crate::callbacks::{
    invoke_connection_callback, invoke_listener_callback, register_connection_callback,
    register_listener_callback,
};

use super::constants::*;
use super::state::{
    clear_channels, clone_message, remove_message, store_channel, store_message, with_channel,
    with_message, StoredMessage,
};
use rmp::encode::{write_array_len, write_u64};
use serde_json::{Map as JsonMap, Number as JsonNumber, Value as JsonValue};
use serde_value::Value as SerdeValue;

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

#[cfg(feature = "ffi-test")]
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
