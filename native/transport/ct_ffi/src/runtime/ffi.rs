use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_uint};

use ct_core::{
    accept_channel, apply_router_config, connection_rawsocket_max_exponent, listen, local_addr,
    shutdown, start_runtime, ConnectionId, Error as CoreError, ListenerId,
};

use crate::callbacks::{
    invoke_connection_callback, invoke_listener_callback, register_connection_callback,
    register_listener_callback,
};

use super::constants::*;
use super::state::{clear_channels, store_channel, with_channel};

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

#[no_mangle]
pub extern "C" fn ct_set_on_listener_started(callback: extern "C" fn(c_int, c_int)) {
    register_listener_callback(callback);
}

#[no_mangle]
pub extern "C" fn ct_set_on_connection(callback: extern "C" fn(c_int, c_int)) {
    register_connection_callback(callback);
}
