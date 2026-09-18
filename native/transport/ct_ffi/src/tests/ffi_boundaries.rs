use super::test_guard;
use crate::runtime::*;
use std::ffi::CString;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::ptr;
use std::time::{Duration, Instant};

fn response(streaming: bool, handle: i32, headers: *const CtHttpHeader, len: usize) -> i32 {
    if streaming {
        ct_http_response_stream_open(handle, 200, headers, len)
    } else {
        ct_http_response_send(handle, 200, headers, len, ptr::null(), 0)
    }
}

fn header(name: &[u8], value: &[u8]) -> CtHttpHeader {
    CtHttpHeader {
        name_ptr: name.as_ptr(),
        name_len: name.len(),
        value_ptr: value.as_ptr(),
        value_len: value.len(),
    }
}

fn websocket_client(port: i32, headers: *const CtHttpHeader, len: usize) -> i32 {
    let host = CString::new("127.0.0.1").unwrap();
    let target = CString::new("/wamp").unwrap();
    ct_client_connect_websocket(
        host.as_ptr(),
        port,
        target.as_ptr(),
        0,
        0,
        1,
        headers,
        len,
        0,
        0,
    )
}

#[test]
fn client_abi_rejects_ports_that_would_wrap_to_another_endpoint() {
    let _guard = test_guard();
    let host = CString::new("127.0.0.1").unwrap();
    for port in [65_536, 65_537, i32::MAX, 0, -1, i32::MIN] {
        assert_eq!(
            websocket_client(port, ptr::null(), 0),
            ERR_INVALID_ARGUMENT,
            "port={port}"
        );
        assert_eq!(
            ct_client_connect_rawsocket(host.as_ptr(), port, 0, 0, 1, 16, 0, 0),
            ERR_INVALID_ARGUMENT,
            "port={port}"
        );
    }
    for port in [1, 65_535] {
        assert_eq!(
            websocket_client(port, ptr::null(), 0),
            ERR_RUNTIME_NOT_STARTED
        );
        assert_eq!(
            ct_client_connect_rawsocket(host.as_ptr(), port, 0, 0, 1, 16, 0, 0),
            ERR_RUNTIME_NOT_STARTED
        );
    }
}

#[test]
fn client_abi_checks_header_ranges_and_accepts_empty_values() {
    let _guard = test_guard();
    assert_eq!(websocket_client(80, ptr::null(), 1), ERR_INVALID_ARGUMENT);
    let item = header(b"x-test", b"value");
    assert_eq!(
        websocket_client(80, &item, usize::MAX),
        ERR_INVALID_ARGUMENT
    );
    let misaligned = (&item as *const CtHttpHeader)
        .cast::<u8>()
        .wrapping_add(1)
        .cast();
    assert_eq!(websocket_client(80, misaligned, 1), ERR_INVALID_ARGUMENT);
    for field in ["name", "value"] {
        let mut item = header(b"x-test", b"value");
        if field == "name" {
            item.name_ptr = ptr::null();
        } else {
            item.value_ptr = ptr::null();
        }
        assert_eq!(websocket_client(80, &item, 1), ERR_INVALID_ARGUMENT);
        let mut item = header(b"x-test", b"value");
        if field == "name" {
            item.name_len = usize::MAX;
        } else {
            item.value_len = usize::MAX;
        }
        assert_eq!(websocket_client(80, &item, 1), ERR_INVALID_ARGUMENT);
    }
    for item in [header(b"\xff", b"valid"), header(b"x-test", b"\xff")] {
        assert_eq!(websocket_client(80, &item, 1), ERR_INVALID_ARGUMENT);
    }
    let mut empty = header(b"x-test", b"");
    empty.value_ptr = ptr::null();
    assert_eq!(websocket_client(80, &empty, 1), ERR_RUNTIME_NOT_STARTED);
    assert_eq!(websocket_client(80, &item, 1), ERR_RUNTIME_NOT_STARTED);
}

#[test]
fn http_response_abi_rejects_null_header_fields() {
    let _guard = test_guard();
    for streaming in [false, true] {
        for field in ["name", "value"] {
            let mut item = header(b"x-test", b"value");
            if field == "name" {
                item.name_ptr = ptr::null();
            } else {
                item.value_ptr = ptr::null();
            }
            assert_eq!(
                response(streaming, 1, &item, 1),
                ERR_INVALID_ARGUMENT,
                "streaming={streaming}, field={field}"
            );
        }
    }
}

#[test]
fn http_response_abi_rejects_unrepresentable_or_misaligned_slices() {
    let _guard = test_guard();
    for streaming in [false, true] {
        let item = header(b"x-test", b"value");
        assert_eq!(
            response(streaming, 1, &item, usize::MAX),
            ERR_INVALID_ARGUMENT
        );
        let misaligned = (&item as *const CtHttpHeader)
            .cast::<u8>()
            .wrapping_add(1)
            .cast();
        assert_eq!(response(streaming, 1, misaligned, 1), ERR_INVALID_ARGUMENT);
        for field in ["name", "value"] {
            let mut item = header(b"x-test", b"value");
            if field == "name" {
                item.name_len = usize::MAX;
            } else {
                item.value_len = usize::MAX;
            }
            assert_eq!(response(streaming, 1, &item, 1), ERR_INVALID_ARGUMENT);
        }
        let mut item = header(b"x-test", b"value");
        item.value_ptr = usize::MAX as *const u8;
        item.value_len = 1;
        assert_eq!(response(streaming, 1, &item, 1), ERR_INVALID_ARGUMENT);
    }
}

#[test]
fn http_response_abi_checks_body_pointer_and_length() {
    let _guard = test_guard();
    assert_eq!(
        ct_http_response_send(1, 200, ptr::null(), 0, ptr::null(), 1),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_http_response_send(1, 200, ptr::null(), 0, b"x".as_ptr(), usize::MAX),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_http_response_send(1, 200, ptr::null(), 0, ptr::null(), 0),
        ERR_HANDSHAKE_CONSUMED
    );
}

#[test]
fn http_stream_rejects_invalid_chunk_without_consuming_writer() {
    let _guard = test_guard();
    let mut peer = peer(false);
    let stream = ct_http_response_stream_open(peer.handshake, 200, ptr::null(), 0);
    assert!(stream > 0);
    assert_eq!(
        ct_http_response_stream_write(stream, ptr::null(), 1),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_http_response_stream_write(stream, b"x".as_ptr(), usize::MAX),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_http_response_stream_write(stream, ptr::null(), 0),
        SUCCESS
    );
    assert_eq!(
        ct_http_response_stream_write(stream, b"payload".as_ptr(), 7),
        SUCCESS
    );
    assert_eq!(ct_http_response_stream_finish(stream), SUCCESS);
    let mut received = Vec::new();
    peer.socket.read_to_end(&mut received).unwrap();
    assert!(received.ends_with(b"\r\n\r\n7\r\npayload\r\n0\r\n\r\n"));
}

#[test]
fn http_response_abi_empty_and_utf8_headers_preserve_lookup_errors() {
    let _guard = test_guard();
    for streaming in [false, true] {
        assert_eq!(response(streaming, 0, ptr::null(), 0), ERR_INVALID_ARGUMENT);
        assert_eq!(response(streaming, 1, ptr::null(), 1), ERR_INVALID_ARGUMENT);
        assert_eq!(
            response(streaming, 1, ptr::null(), 0),
            ERR_HANDSHAKE_CONSUMED
        );
        for item in [header(b"\xff", b"valid"), header(b"x-test", b"\xff")] {
            assert_eq!(response(streaming, 1, &item, 1), ERR_INVALID_ARGUMENT);
        }
        let mut empty = header(b"x-test", b"");
        empty.value_ptr = ptr::null();
        assert_eq!(response(streaming, 1, &empty, 1), ERR_HANDSHAKE_CONSUMED);
        assert_eq!(
            response(streaming, 1, &header(b"x-test", b"Gr\xc3\xbc\xc3\x9fe"), 1),
            ERR_HANDSHAKE_CONSUMED
        );
    }
}

#[test]
fn websocket_abi_rejects_out_of_range_status_without_narrowing() {
    let _guard = test_guard();
    for status in [
        65_939,
        -65_133,
        i32::MIN,
        i32::MAX,
        -1,
        0,
        99,
        600,
        999,
        1_000,
    ] {
        assert_eq!(
            ct_connection_reject_websocket(1, 1, status, ptr::null(), 0),
            ERR_INVALID_ARGUMENT,
            "status={status}"
        );
    }
    for status in [100, 403, 599] {
        assert_eq!(
            ct_connection_reject_websocket(1, 1, status, ptr::null(), 0),
            ERR_HANDSHAKE_CONSUMED
        );
    }
}

#[test]
fn websocket_abi_rejects_negative_optional_string_lengths() {
    let _guard = test_guard();
    for len in [-1, i32::MIN] {
        assert_eq!(
            ct_connection_accept_websocket(1, 1, 1, ptr::null(), len),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(
            ct_connection_reject_websocket(1, 1, 403, ptr::null(), len),
            ERR_INVALID_ARGUMENT
        );
    }
    assert_eq!(
        ct_connection_accept_websocket(1, 1, 1, ptr::null(), 0),
        ERR_HANDSHAKE_CONSUMED
    );
    for (connection, handle) in [(0, 1), (-1, 1), (1, 0), (1, -1)] {
        assert_eq!(
            ct_connection_accept_websocket(connection, handle, 1, ptr::null(), 0),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(
            ct_connection_reject_websocket(connection, handle, 403, ptr::null(), 0),
            ERR_INVALID_ARGUMENT
        );
    }
}

struct Peer {
    socket: TcpStream,
    connection: i32,
    handshake: i32,
    _runtime: RuntimeGuard,
}

struct RuntimeGuard;

impl Drop for RuntimeGuard {
    fn drop(&mut self) {
        let _ = ct_shutdown();
    }
}

fn wait_positive(mut poll: impl FnMut() -> i32) -> i32 {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let value = poll();
        if value > 0 {
            return value;
        }
        assert!(
            Instant::now() < deadline,
            "native poll did not become ready: {value}"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
}

fn peer(websocket: bool) -> Peer {
    let config = if websocket {
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["websocket"]}]}"#
    } else {
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/probe","match_kind":"exact","methods":{"GET":{"type":"reserved_realm","append_method_suffix":true}}}]}]}"#
    };
    assert_eq!(
        ct_apply_router_config(config.as_ptr(), config.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);
    let runtime = RuntimeGuard;
    let host = CString::new("127.0.0.1").unwrap();
    let listener = ct_listen(host.as_ptr(), 0, 128);
    assert!(listener > 0);
    let port = ct_get_local_port(listener);
    assert!(port > 0);
    let mut socket = TcpStream::connect(("127.0.0.1", port as u16)).unwrap();
    socket
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    socket
        .set_write_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    socket.write_all(if websocket {
        b"GET /wamp HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: wamp.2.json\r\n\r\n"
    } else {
        b"GET /probe HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    }).unwrap();
    let connection = wait_positive(|| ct_poll_connection(listener));
    let handshake = wait_positive(|| {
        if websocket {
            ct_connection_take_websocket_handshake(connection)
        } else {
            ct_connection_take_http_handshake(connection)
        }
    });
    Peer {
        socket,
        connection,
        handshake,
        _runtime: runtime,
    }
}

#[test]
fn websocket_accept_rejects_wrapping_protocol_range() {
    let _guard = test_guard();
    assert_eq!(
        ct_connection_accept_websocket(1, 1, 1, usize::MAX as *const _, 1),
        ERR_INVALID_ARGUMENT
    );
}

#[test]
fn websocket_reject_rejects_wrapping_reason_range() {
    let _guard = test_guard();
    assert_eq!(
        ct_connection_reject_websocket(1, 1, 403, usize::MAX as *const _, 1),
        ERR_INVALID_ARGUMENT
    );
}

#[test]
fn websocket_rejection_keeps_handshake_on_invalid_input_and_closes_peer_on_success() {
    let _guard = test_guard();
    for reason in [None, Some(b"access denied: \xc3\xa4".as_slice())] {
        let mut peer = peer(true);
        for status in [65_939, -65_133, 600] {
            assert_eq!(
                ct_connection_reject_websocket(
                    peer.connection,
                    peer.handshake,
                    status,
                    ptr::null(),
                    0
                ),
                ERR_INVALID_ARGUMENT
            );
        }
        for (data, len) in [
            (ptr::null(), 1),
            (ptr::null(), -1),
            (b"\xff".as_ptr().cast(), 1),
        ] {
            assert_eq!(
                ct_connection_reject_websocket(peer.connection, peer.handshake, 403, data, len),
                ERR_INVALID_ARGUMENT
            );
        }
        assert_eq!(
            ct_connection_accept_websocket(peer.connection, peer.handshake, 1, ptr::null(), -1),
            ERR_INVALID_ARGUMENT
        );
        let mut info = CtWebSocketHandshakeInfo::default();
        assert_eq!(
            ct_websocket_handshake_get(peer.handshake, &mut info),
            SUCCESS
        );
        let (data, len) = reason.map_or((ptr::null(), 0), |bytes| {
            (bytes.as_ptr().cast(), bytes.len() as i32)
        });
        assert_eq!(
            ct_connection_reject_websocket(peer.connection, peer.handshake, 403, data, len),
            SUCCESS
        );
        let mut received = Vec::new();
        peer.socket.read_to_end(&mut received).unwrap();
        let body = reason.unwrap_or(b"websocket upgrade rejected");
        let mut expected = format!(
            "HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: {}\r\n\r\n",
            body.len()
        )
        .into_bytes();
        expected.extend_from_slice(body);
        assert_eq!(received, expected);
        assert_eq!(
            ct_connection_reject_websocket(peer.connection, peer.handshake, 403, ptr::null(), 0),
            ERR_HANDSHAKE_CONSUMED
        );
        assert_eq!(
            ct_connection_protocol(peer.connection),
            ERR_CONNECTION_NOT_FOUND
        );
    }
}

#[test]
fn http_responses_keep_handshake_after_invalid_buffers_then_deliver_exact_payload() {
    let _guard = test_guard();
    for streaming in [false, true] {
        let mut peer = peer(false);
        let mut bad = header(b"x-test", b"value");
        bad.value_ptr = ptr::null();
        assert_eq!(
            response(streaming, peer.handshake, &bad, 1),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(
            response(streaming, peer.handshake, &header(b"x-test", b"\xff"), 1),
            ERR_INVALID_ARGUMENT
        );
        assert_eq!(
            ct_http_response_send(peer.handshake, 200, ptr::null(), 0, ptr::null(), 8),
            ERR_INVALID_ARGUMENT
        );
        let mut info = CtHttpHandshakeInfo::default();
        assert_eq!(ct_http_handshake_get(peer.handshake, &mut info), SUCCESS);
        let mut empty = header(b"x-empty", b"");
        empty.value_ptr = ptr::null();
        if streaming {
            let stream = ct_http_response_stream_open(peer.handshake, 200, &empty, 1);
            assert!(stream > 0);
            assert_eq!(
                ct_http_response_stream_write(stream, b"payload".as_ptr(), 7),
                SUCCESS
            );
            assert_eq!(ct_http_response_stream_finish(stream), SUCCESS);
        } else {
            assert_eq!(
                ct_http_response_send(peer.handshake, 200, &empty, 1, b"payload".as_ptr(), 7),
                SUCCESS
            );
        }
        let mut received = Vec::new();
        peer.socket.read_to_end(&mut received).unwrap();
        let split = received
            .windows(4)
            .position(|bytes| bytes == b"\r\n\r\n")
            .unwrap()
            + 4;
        let headers = std::str::from_utf8(&received[..split])
            .unwrap()
            .to_ascii_lowercase();
        assert!(headers.starts_with("http/1.1 200 "), "{headers}");
        assert!(headers.contains("\r\nx-empty:"), "{headers}");
        assert_eq!(
            &received[split..],
            if streaming {
                b"7\r\npayload\r\n0\r\n\r\n".as_slice()
            } else {
                b"payload".as_slice()
            }
        );
        assert_eq!(
            response(streaming, peer.handshake, ptr::null(), 0),
            ERR_HANDSHAKE_CONSUMED
        );
    }
}
