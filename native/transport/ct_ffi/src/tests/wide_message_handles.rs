use super::client_connect::ClientConnect;
use super::ffi_completion::ct_connection_accept_websocket;
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
    assert!(info.frame_len > 0);
    assert!(!info.frame_ptr.is_null());
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
    let mut connect = ClientConnect::new(std::thread::spawn(move || {
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
    }));
    let deadline = Instant::now() + Duration::from_secs(5);
    let server = connect.wait_for_server(|| ct_poll_connection(listener), deadline);
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
    let client = connect.finish(Instant::now() + Duration::from_secs(5));
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
    legacy_forwarding(client, server, websocket, serializer);
    fragmented_sends(client, server, websocket, serializer);
    assert_eq!(ct_shutdown(), SUCCESS);
}

fn fragmented_sends(client: i32, server: i32, websocket: bool, serializer: i32) {
    let value =
        json!([48, 27, {}, "fragment.echo", ["caf\u{e9}", [0, 127, 128, 255]], {"flag": true}]);
    let frame = encode(serializer, &value);
    let len = frame.len() as i32;
    let receive = |expected: &[u8]| {
        let handle = incoming(server, websocket, false);
        let mut info = CtMessageInfo::default();
        assert_eq!(ct_message_get_wide(handle, &mut info), SUCCESS);
        assert_eq!(i32::from(info.serializer), serializer);
        assert_eq!(info.frame_len, expected.len());
        assert!(!info.frame_ptr.is_null());
        let actual = unsafe { std::slice::from_raw_parts(info.frame_ptr, info.frame_len) };
        assert_eq!(actual, expected);
        ct_message_release_wide(handle);
    };
    for owned in [false, true] {
        for size in [1, 3, len - 1, len, len + 1] {
            let result = if owned {
                let buffer = ct_outbound_buffer_alloc(len);
                assert!(!buffer.is_null());
                unsafe { ptr::copy_nonoverlapping(frame.as_ptr(), buffer, frame.len()) };
                ct_send_message_fragmented_owned(client, buffer, len, size)
            } else {
                let mut copied = frame.clone();
                let result = ct_send_message_fragmented(client, copied.as_ptr(), len, size);
                // The copying API must not borrow the caller's buffer after returning.
                copied.fill(0);
                result
            };
            assert_eq!(result, SUCCESS, "owned={owned} fragment={size}");
            receive(&frame);
        }
    }
    for size in [0, -1] {
        assert_eq!(
            ct_send_message_fragmented(client, frame.as_ptr(), len, size),
            ERR_INVALID_ARGUMENT
        );
        let buffer = ct_outbound_buffer_alloc(len);
        assert!(!buffer.is_null());
        unsafe { ptr::copy_nonoverlapping(frame.as_ptr(), buffer, frame.len()) };
        // Ownership transfers even when the fragment length is invalid.
        assert_eq!(
            ct_send_message_fragmented_owned(client, buffer, len, size),
            ERR_INVALID_ARGUMENT
        );
    }
    assert_eq!(
        ct_send_message_fragmented(client, ptr::null(), 1, 1),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_send_message_fragmented(client, ptr::null(), -1, 1),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_send_message_fragmented_owned(client, ptr::null_mut(), 1, 1),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_send_message_fragmented_owned(client, ptr::null_mut(), -1, 1),
        ERR_INVALID_ARGUMENT
    );
    let sentinel = encode(serializer, &json!([48, 28, {}, "fragment.after_errors"]));
    assert_eq!(
        ct_send_message_fragmented(client, sentinel.as_ptr(), sentinel.len() as i32, 2),
        SUCCESS
    );
    receive(&sentinel);
    assert_eq!(ct_wait_connection_message_wide(server, 1), 0);
}

fn legacy_forwarding(client: i32, server: i32, websocket: bool, serializer: i32) {
    let send = |value: Value| {
        let frame = encode(serializer, &value);
        assert_eq!(
            ct_send_message(client, frame.as_ptr(), frame.len() as i32),
            SUCCESS
        );
        let handle = ct_wait_connection_message(server, 5000);
        assert!(handle > 0, "legacy receive failed: {handle}");
        handle
    };
    let authid = CString::new("alice").unwrap();
    let role = CString::new("user").unwrap();
    let procedure = CString::new("legacy.echo").unwrap();
    let call = send(json!([48, 17, {}, "legacy.echo", ["payload"], {"flag": true}]));
    assert_eq!(
        ct_forward_call_invocation(
            call,
            server,
            181,
            182,
            1,
            123,
            authid.as_ptr(),
            5,
            role.as_ptr(),
            4,
            procedure.as_ptr(),
            11,
            1
        ),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([
            68, 181, 182, {"caller": 123, "caller_authid": "alice", "caller_authrole": "user",
            "procedure": "legacy.echo", "receive_progress": true}, ["payload"], {"flag": true}
        ])
    );
    assert_eq!(
        ct_forward_call_invocation_v2(
            call,
            server,
            183,
            184,
            1,
            124,
            authid.as_ptr(),
            5,
            role.as_ptr(),
            4,
            procedure.as_ptr(),
            11,
            0,
            1
        ),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([
            68, 183, 184, {"caller": 124, "caller_authid": "alice", "caller_authrole": "user",
            "procedure": "legacy.echo", "receive_progress": false, "progress": true},
            ["payload"], {"flag": true}
        ])
    );
    assert_eq!(ct_forward_result_from_call(call, server, 17), SUCCESS);
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([50, 17, {}, ["payload"], {"flag": true}])
    );
    ct_message_release(call);

    let publish = send(json!([16, 1, {}, "legacy.topic", ["event"], {"flag": true}]));
    let topic = CString::new("legacy.topic").unwrap();
    assert_eq!(
        ct_forward_publish_event(publish, server, 191, 192, 1, 125, topic.as_ptr(), 12),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([
            36, 191, 192, {"publisher": 125, "topic": "legacy.topic"}, ["event"], {"flag": true}
        ])
    );
    ct_message_release(publish);

    let yielded = send(json!([70, 181, {}, ["result"], {"flag": true}]));
    assert_eq!(
        ct_forward_result_from_yield(yielded, server, 17, 1),
        SUCCESS
    );
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([50, 17, {"progress": true}, ["result"], {"flag": true}])
    );
    ct_message_release(yielded);
    let error =
        send(json!([8, 68, 181, {}, "wamp.error.runtime_error", ["error"], {"flag": true}]));
    assert_eq!(ct_forward_error_from_error(error, server, 48, 17), SUCCESS);
    assert_eq!(
        received_value(client, websocket, serializer),
        json!([8, 48, 17, {}, "wamp.error.runtime_error", ["error"], {"flag": true}])
    );
    ct_message_release(error);
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
