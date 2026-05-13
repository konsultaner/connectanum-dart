use std::sync::{Mutex, OnceLock};

use ct_core::{ConnectionId, ListenerId};

static LISTENER_CALLBACK: OnceLock<Mutex<Option<extern "C" fn(i32, i32)>>> = OnceLock::new();
static CONNECTION_CALLBACK: OnceLock<Mutex<Option<extern "C" fn(i32, i32)>>> = OnceLock::new();

fn listener_callback_slot() -> &'static Mutex<Option<extern "C" fn(i32, i32)>> {
    LISTENER_CALLBACK.get_or_init(|| Mutex::new(None))
}

fn connection_callback_slot() -> &'static Mutex<Option<extern "C" fn(i32, i32)>> {
    CONNECTION_CALLBACK.get_or_init(|| Mutex::new(None))
}

pub fn register_listener_callback(callback: extern "C" fn(i32, i32)) {
    *listener_callback_slot().lock().unwrap() = Some(callback);
}

pub fn register_connection_callback(callback: extern "C" fn(i32, i32)) {
    *connection_callback_slot().lock().unwrap() = Some(callback);
}

pub fn invoke_listener_callback(listener_id: ListenerId, status: i32) {
    if let Some(callback) = *listener_callback_slot().lock().unwrap() {
        callback(listener_id.0 as i32, status);
    }
}

pub fn invoke_connection_callback(listener_id: ListenerId, connection_id: ConnectionId) {
    if let Some(callback) = *connection_callback_slot().lock().unwrap() {
        callback(listener_id.0 as i32, connection_id.0 as i32);
    }
}
