use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_uint};

use bytes::Bytes;
use std::ptr;

use ct_core::{
    accept_channel, apply_router_config, connection_rawsocket_max_exponent, listen, local_addr,
    poll_connection_message, send_wamp_message, shutdown, start_runtime, ConnectionId,
    Error as CoreError, ListenerId, WampMessage,
};

use crate::callbacks::{
    invoke_connection_callback, invoke_listener_callback, register_connection_callback,
    register_listener_callback,
};

use super::constants::*;
use super::state::{
    clear_channels, remove_message, store_channel, store_message, with_channel, with_message,
    StoredMessage,
};

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

#[no_mangle]
pub extern "C" fn ct_start_runtime() -> c_int {
    match start_runtime() {
        Ok(()) => SUCCESS,
        Err(err) => map_error(err),
    }
}

#[no_mangle]
pub extern "C" fn ct_shutdown() -> c_int {
    match shutdown() {
        Ok(()) => {
            clear_channels();
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

#[no_mangle]
pub extern "C" fn ct_poll_connection_message(connection_id: c_int) -> c_int {
    let connection_id = ConnectionId(connection_id as u32);
    match poll_connection_message(connection_id) {
        Ok(Some(parsed)) => {
            let (args, kwargs) = extract_payload_slices(&parsed.message);
            let info = StoredMessage {
                serializer: parsed.serializer,
                code: parsed.message.code(),
                raw: parsed.raw,
                args,
                kwargs,
            };
            store_message(info) as c_int
        }
        Ok(None) => 0,
        Err(err) => map_error(err),
    }
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
pub extern "C" fn ct_set_on_listener_started(callback: extern "C" fn(c_int, c_int)) {
    register_listener_callback(callback);
}

#[no_mangle]
pub extern "C" fn ct_set_on_connection(callback: extern "C" fn(c_int, c_int)) {
    register_connection_callback(callback);
}
