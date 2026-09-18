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
fn client_abi_rejects_null_empty_and_non_utf8_strings() {
    let _guard = test_guard();
    let host = CString::new("localhost").unwrap();
    let target = CString::new("/wamp").unwrap();
    let empty = CString::new("").unwrap();
    let invalid = CString::new(vec![0xff]).unwrap();
    for bad in [ptr::null(), empty.as_ptr(), invalid.as_ptr()] {
        assert_eq!(
            ct_client_connect_rawsocket(bad, 80, 0, 0, 1, 16, 0, 0),
            ERR_INVALID_ARGUMENT
        );
        for (host, target) in [(bad, target.as_ptr()), (host.as_ptr(), bad)] {
            assert_eq!(
                ct_client_connect_websocket(host, 80, target, 0, 0, 1, ptr::null(), 0, 0, 0),
                ERR_INVALID_ARGUMENT
            );
        }
    }
    for exponent in [i32::MIN, -1, 0] {
        assert_eq!(
            ct_client_connect_rawsocket(host.as_ptr(), 80, 0, 0, 1, exponent, 0, 0),
            ERR_INVALID_ARGUMENT
        );
    }
}

#[test]
fn http_response_abi_status_boundaries_precede_handle_consumption() {
    let _guard = test_guard();
    for streaming in [false, true] {
        for status in [
            i32::MIN,
            -1,
            0,
            99,
            100,
            101,
            200,
            598,
            599,
            600,
            601,
            i32::MAX,
        ] {
            let result = if streaming {
                ct_http_response_stream_open(i32::MAX, status, ptr::null(), 0)
            } else {
                ct_http_response_send(i32::MAX, status, ptr::null(), 0, ptr::null(), 0)
            };
            let expected = match status {
                100 | 101 | 200 | 598 | 599 => ERR_HANDSHAKE_CONSUMED,
                _ => ERR_INVALID_ARGUMENT,
            };
            assert_eq!(result, expected);
        }
    }
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

fn tls_client_policy(websocket: bool) {
    let _guard = test_guard();
    let certified = rcgen::generate_simple_self_signed(vec!["localhost".to_owned()]).unwrap();
    let config = serde_json::to_vec(&serde_json::json!({
        "schema": "connectanum.router", "version": 1,
        "endpoints": [{
            "host": "127.0.0.1", "port": 0, "tls_mode": "native",
            "handshake_timeout_ms": 5000,
            "protocols": [if websocket { "websocket" } else { "rawsocket" }],
            "sni_certificates": [{
                "hostname": "localhost",
                "certificate_chain_pem": certified.cert.pem(),
                "private_key_pem": certified.key_pair.serialize_pem()
            }]
        }]
    }))
    .unwrap();
    assert_eq!(
        ct_apply_router_config(config.as_ptr(), config.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);
    let _runtime = RuntimeGuard;
    let host = CString::new("127.0.0.1").unwrap();
    let listener = ct_listen(host.as_ptr(), 0, 128);
    assert!(listener > 0);
    let port = ct_get_local_port(listener);
    assert!(port > 0);
    for allow_insecure in [0, 1, 0, -1, 2, 0] {
        let connect = std::thread::spawn(move || {
            let host = CString::new("localhost").unwrap();
            let target = CString::new("/wamp").unwrap();
            if websocket {
                ct_client_connect_websocket(
                    host.as_ptr(),
                    port,
                    target.as_ptr(),
                    1,
                    allow_insecure,
                    1,
                    ptr::null(),
                    0,
                    0,
                    0,
                )
            } else {
                ct_client_connect_rawsocket(host.as_ptr(), port, 1, allow_insecure, 1, 16, 0, 0)
            }
        });
        let mut server = 0;
        let mut accepted = false;
        let deadline = Instant::now() + Duration::from_secs(10);
        while !connect.is_finished() {
            if server == 0 {
                server = ct_poll_connection(listener);
                assert!(server >= 0);
            }
            // Accept even on the denial path: a verification bypass must return
            // a successful connection, not hide behind an unaccepted upgrade.
            if websocket && server > 0 && !accepted {
                let handshake = ct_connection_take_websocket_handshake(server);
                if handshake > 0 {
                    let selected = b"wamp.2.json";
                    assert_eq!(
                        ct_connection_accept_websocket(
                            server,
                            handshake,
                            1,
                            selected.as_ptr().cast(),
                            selected.len() as i32
                        ),
                        SUCCESS
                    );
                    accepted = true;
                }
            }
            if Instant::now() >= deadline {
                panic!("timed out waiting for TLS client connection");
            }
            std::thread::sleep(Duration::from_millis(2));
        }
        let result = connect.join();
        assert!(result.is_ok());
        let client = result.unwrap();
        if allow_insecure == 0 {
            assert_eq!(client, ERR_IO);
            assert_eq!(server, 0);
            assert_eq!(ct_poll_connection(listener), 0);
            continue;
        }
        assert!(client > 0);
        if server == 0 {
            server = wait_positive(|| ct_poll_connection(listener));
        }
        for connection in [client, server] {
            assert_eq!(
                ct_connection_protocol(connection),
                if websocket {
                    PROTOCOL_WEBSOCKET
                } else {
                    PROTOCOL_RAWSOCKET
                }
            );
        }
        for (sender, receiver, payload) in [
            (client, server, br#"[1,"tls.realm",{}]"#.as_slice()),
            (server, client, br#"[2,41,{}]"#.as_slice()),
        ] {
            assert_eq!(
                ct_send_message(sender, payload.as_ptr(), payload.len() as i32),
                SUCCESS
            );
            let handle = ct_wait_connection_message_wide(receiver, 5000);
            if handle <= 0 {
                panic!("timed out waiting for TLS peer payload: {handle}");
            }
            let mut info = CtMessageInfo::default();
            assert_eq!(ct_message_get_wide(handle, &mut info), SUCCESS);
            assert!(!info.frame_ptr.is_null());
            assert_eq!(info.frame_len, payload.len());
            assert_eq!(
                unsafe { std::slice::from_raw_parts(info.frame_ptr, info.frame_len) },
                payload
            );
            ct_message_release_wide(handle);
        }
        let _ = ct_connection_close(client);
        let _ = ct_connection_close(server);
    }
    assert_eq!(ct_listener_close(listener), SUCCESS);
}

#[test]
fn rawsocket_client_tls_verification_is_explicit_and_recovers_after_rejection() {
    tls_client_policy(false);
}

#[test]
fn websocket_client_tls_verification_is_explicit_and_recovers_after_rejection() {
    tls_client_policy(true);
}

#[test]
fn websocket_accept_with_zero_protocol_length_omits_the_header() {
    let _guard = test_guard();
    let ignored = CString::new("ignored.protocol").unwrap();
    for protocol in [ptr::null(), ignored.as_ptr()] {
        let mut peer = peer(true);
        assert_eq!(
            ct_connection_accept_websocket(peer.connection, peer.handshake, 1, protocol, 0),
            SUCCESS
        );
        let mut response = Vec::new();
        while !response.ends_with(b"\r\n\r\n") {
            let mut byte = [0];
            peer.socket.read_exact(&mut byte).unwrap();
            response.extend_from_slice(&byte);
            assert!(response.len() < 4096);
        }
        assert_eq!(response, b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n");
        assert_eq!(
            ct_connection_accept_websocket(peer.connection, peer.handshake, 1, ptr::null(), 0),
            ERR_HANDSHAKE_CONSUMED
        );
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
        for status in [0, 99, 600, i32::MAX] {
            let result = if streaming {
                ct_http_response_stream_open(peer.handshake, status, ptr::null(), 0)
            } else {
                ct_http_response_send(peer.handshake, status, ptr::null(), 0, ptr::null(), 0)
            };
            assert_eq!(result, ERR_INVALID_ARGUMENT);
        }
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
