use crate::runtime::*;
use serde_json::{json, Value};
use std::ffi::CString;
use std::ptr;
use std::time::{Duration, Instant};

fn encode(serializer: i32, value: &Value) -> Vec<u8> {
    match serializer {
        1 => serde_json::to_vec(value).unwrap(),
        2 => rmp_serde::to_vec(value).unwrap(),
        3 => serde_cbor::to_vec(value).unwrap(),
        _ => unreachable!(),
    }
}

fn incoming(connection: i32, websocket: bool, poll: bool) -> i64 {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let handle = if !poll {
            ct_wait_connection_message_wide(connection, 5000)
        } else if websocket {
            ct_poll_websocket_message_wide(connection)
        } else {
            ct_poll_connection_message_wide(connection)
        };
        if handle > 0 {
            assert!(
                handle > u32::MAX as i64,
                "wide transport returned narrow ID"
            );
            return handle;
        }
        assert_eq!(handle, 0, "receive failed");
        assert!(Instant::now() < deadline, "wide receive timed out");
        std::thread::sleep(Duration::from_millis(1));
    }
}

fn received_value(connection: i32, websocket: bool, serializer: i32) -> Value {
    let handle = incoming(connection, websocket, true);
    let mut info = CtMessageInfo::default();
    assert_eq!(ct_message_get_wide(handle, &mut info), SUCCESS);
    assert_eq!(i32::from(info.serializer), serializer);
    let frame = unsafe { std::slice::from_raw_parts(info.frame_ptr, info.frame_len) };
    let value = match serializer {
        1 => serde_json::from_slice(frame).unwrap(),
        2 => rmp_serde::from_slice(frame).unwrap(),
        3 => serde_cbor::from_slice(frame).unwrap(),
        _ => unreachable!(),
    };
    ct_message_release_wide(handle);
    value
}

fn round_trip(websocket: bool, serializer: i32) {
    let _guard = super::test_guard();
    let config = serde_json::to_vec(&json!({
        "schema": "connectanum.router", "version": 1,
        "endpoints": [{"host": "127.0.0.1", "port": 0, "tls_mode": "disabled",
            "protocols": [if websocket { "websocket" } else { "rawsocket" }]}]
    }))
    .unwrap();
    assert_eq!(
        ct_apply_router_config(config.as_ptr(), config.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);
    let host = CString::new("127.0.0.1").unwrap();
    let listener = ct_listen(host.as_ptr(), 0, 128);
    assert!(listener > 0);
    let port = ct_get_local_port(listener);
    let connect = std::thread::spawn(move || {
        let host = CString::new("127.0.0.1").unwrap();
        if websocket {
            let path = CString::new("/ws").unwrap();
            ct_client_connect_websocket(
                host.as_ptr(),
                port,
                path.as_ptr(),
                0,
                0,
                serializer,
                ptr::null(),
                0,
                0,
                0,
            )
        } else {
            ct_client_connect_rawsocket(host.as_ptr(), port, 0, 0, serializer, 16, 0, 0)
        }
    });
    let deadline = Instant::now() + Duration::from_secs(5);
    let server = loop {
        let id = ct_poll_connection(listener);
        if id > 0 {
            break id;
        }
        assert_eq!(id, 0);
        assert!(Instant::now() < deadline);
        std::thread::sleep(Duration::from_millis(1));
    };
    if websocket {
        let handshake = ct_connection_take_websocket_handshake(server);
        assert!(handshake > 0);
        let protocol = CString::new(match serializer {
            1 => "wamp.2.json",
            2 => "wamp.2.msgpack",
            3 => "wamp.2.cbor",
            _ => unreachable!(),
        })
        .unwrap();
        assert_eq!(
            ct_connection_accept_websocket(
                server,
                handshake,
                serializer,
                protocol.as_ptr(),
                protocol.as_bytes().len() as i32
            ),
            SUCCESS
        );
    }
    let client = connect.join().unwrap();
    assert!(client > 0);
    if !websocket {
        assert_eq!(
            ct_poll_websocket_message_wide(client),
            i64::from(ERR_UNSUPPORTED)
        );
    }
    assert_eq!(ct_wait_connection_message_wide(client, 1), 0);
    let send = |value: Value| {
        let frame = encode(serializer, &value);
        assert_eq!(
            ct_send_message(client, frame.as_ptr(), frame.len() as i32),
            SUCCESS
        );
        incoming(server, websocket, false)
    };
    let call = send(json!([48, 7, {}, "wide.echo", ["payload"], {"flag": true}]));
    assert_eq!(
        ct_forward_call_invocation_wide(
            call,
            server,
            81,
            82,
            0,
            0,
            ptr::null(),
            0,
            ptr::null(),
            0,
            ptr::null(),
            0,
            -1
        ),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([68, 81, 82, {}, ["payload"], {"flag": true}])
    );
    assert_eq!(
        ct_forward_call_invocation_v2_wide(
            call,
            server,
            83,
            84,
            0,
            0,
            ptr::null(),
            0,
            ptr::null(),
            0,
            ptr::null(),
            0,
            1,
            1
        ),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([68, 83, 84, {"receive_progress": true, "progress": true}, ["payload"], {"flag": true}])
    );
    assert_eq!(ct_forward_result_from_call_wide(call, server, 7), SUCCESS);
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([50, 7, {}, ["payload"], {"flag": true}])
    );
    ct_message_release_wide(call);

    let publish = send(json!([16, 1, {}, "wide.topic", ["event"], {"flag": true}]));
    assert_eq!(
        ct_forward_publish_event_wide(publish, server, 91, 92, 0, 0, ptr::null(), 0),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([36, 91, 92, {}, ["event"], {"flag": true}])
    );
    ct_message_release_wide(publish);

    let yielded = send(json!([70, 81, {}, ["result"], {"flag": true}]));
    assert_eq!(
        ct_forward_result_from_yield_wide(yielded, server, 7, 1),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([50, 7, {"progress": true}, ["result"], {"flag": true}])
    );
    ct_message_release_wide(yielded);

    let error = send(json!([8, 68, 81, {}, "wamp.error.runtime_error", ["error"], {"flag": true}]));
    assert_eq!(
        ct_forward_error_from_error_wide(error, server, 48, 7),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([8, 48, 7, {}, "wamp.error.runtime_error", ["error"], {"flag": true}])
    );
    ct_message_release_wide(error);
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn wide_rawsocket_json() {
    round_trip(false, 1);
}
#[test]
fn wide_rawsocket_messagepack() {
    round_trip(false, 2);
}
#[test]
fn wide_rawsocket_cbor() {
    round_trip(false, 3);
}
#[test]
fn wide_websocket_json() {
    round_trip(true, 1);
}
#[test]
fn wide_websocket_messagepack() {
    round_trip(true, 2);
}
#[test]
fn wide_websocket_cbor() {
    round_trip(true, 3);
}
