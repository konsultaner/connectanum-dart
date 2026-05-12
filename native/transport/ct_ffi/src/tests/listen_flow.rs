use std::ffi::CString;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use bytes::{Buf, Bytes};
use ct_core::{HttpBodyHandle, StreamingBodyState};
use futures_util::future;
use h2::client;
use h3::client as h3_client;
use h3_quinn::Connection as H3QuinnConnection;
use http::Request;
use http02::{Request as Http2TestRequest, StatusCode as Http2StatusCode};
use quinn::{
    crypto::rustls::QuicClientConfig as QuinnRustlsClientConfig, ClientConfig as QuinnClientConfig,
    Endpoint as QuinnEndpoint, TransportConfig,
};
use rcgen::generate_simple_self_signed;
use rustls::client::WebPkiServerVerifier;
use rustls::pki_types::CertificateDer;
use rustls::{ClientConfig as RustlsClientConfig, RootCertStore};
use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::runtime::Runtime as TokioRuntime;

const HTTP2_TEST_MAX_CONCURRENT_STREAMS: u32 = 1024;
const HTTP2_TEST_INITIAL_STREAM_WINDOW: u32 = 8 * 1024 * 1024;
const HTTP2_TEST_INITIAL_CONNECTION_WINDOW: u32 = 64 * 1024 * 1024;
const HTTP2_TEST_MAX_FRAME_SIZE: u32 = 1 * 1024 * 1024;
const HTTP2_TEST_MAX_HEADER_LIST_SIZE: u32 = 16 * 1024 * 1024;
const HTTP2_TEST_MAX_CONCURRENT_RESET_STREAMS: usize = 256;
const HTTP2_TEST_MAX_SEND_BUFFER_SIZE: usize = 8 * 1024 * 1024;
const MESSAGE_FLAG_DIRECT_BIND: u32 = 1 << 0;
const MESSAGE_FLAG_DETAIL_NUMBER_A_PRESENT: u32 = 1 << 1;
const MESSAGE_FLAG_DETAIL_NUMBER_B_PRESENT: u32 = 1 << 2;
const MESSAGE_FLAG_DETAIL_BOOL_A_TRUE: u32 = 1 << 3;
const MESSAGE_FLAG_METADATA_BIND: u32 = 1 << 4;

#[cfg(feature = "ffi-test")]
use crate::runtime::constants::HTTP_EVENT_REASON_GOAWAY;
use crate::runtime::constants::{
    ERR_CONNECTION_NOT_FOUND, ERR_ENDPOINT_NOT_CONFIGURED, ERR_INVALID_ARGUMENT,
    ERR_LISTENER_NOT_FOUND, ERR_UNSUPPORTED, HTTP_EVENT_REASON_BODY_TIMEOUT,
    HTTP_EVENT_REASON_IDLE_TIMEOUT, PROTOCOL_HTTP, PROTOCOL_HTTP2, PROTOCOL_HTTP3,
    PROTOCOL_RAWSOCKET, PROTOCOL_WEBSOCKET, SUCCESS,
};
use crate::runtime::ffi::{
    ct_apply_router_config, ct_client_connect_rawsocket, ct_client_connect_websocket,
    ct_connection_accept_websocket, ct_connection_close, ct_connection_get_http3_connection,
    ct_connection_max_rawsocket_exponent, ct_connection_poll_http_event, ct_connection_protocol,
    ct_connection_take_http2_handshake, ct_connection_take_http3_handshake,
    ct_connection_take_http_handshake, ct_connection_take_websocket_handshake,
    ct_connection_websocket_protocol, ct_get_local_port, ct_http2_handshake_get,
    ct_http2_handshake_listener_protocol, ct_http2_handshake_release,
    ct_http3_connection_poll_request, ct_http3_connection_poll_stream, ct_http3_connection_release,
    ct_http3_handshake_get, ct_http3_handshake_listener_protocol, ct_http3_handshake_release,
    ct_http_body_finish, ct_http_body_get, ct_http_body_release, ct_http_body_stream_read,
    ct_http_connection_event_get, ct_http_connection_event_release, ct_http_handshake_body_retain,
    ct_http_handshake_get, ct_http_handshake_header, ct_http_handshake_release,
    ct_http_response_send, ct_http_response_stream_finish, ct_http_response_stream_open,
    ct_http_response_stream_write, ct_listen, ct_listener_close, ct_listener_http3_port,
    ct_message_get, ct_message_peek, ct_message_release, ct_poll_connection,
    ct_poll_connection_message, ct_send_message, ct_set_on_connection, ct_set_on_listener_started,
    ct_shutdown, ct_start_runtime, ct_wait_connection_message, ct_websocket_handshake_extension,
    ct_websocket_handshake_get, ct_websocket_handshake_protocol, ct_websocket_handshake_release,
    CtHttp2HandshakeInfo, CtHttp3HandshakeInfo, CtHttpBodyView, CtHttpConnectionEventInfo,
    CtHttpHandshakeInfo, CtHttpHeader, CtMessageInfo, CtStringView, CtWebSocketHandshakeInfo,
};
use crate::runtime::store_http_body;

#[cfg(feature = "ffi-test")]
use crate::runtime::ffi::{
    ct_test_push_http_connection_event, ct_test_register_http3_connection,
    ct_test_register_http3_request,
};

thread_local! {
    static LISTENER_EVENTS: Arc<Mutex<Vec<(i32, i32)>>> =
        Arc::new(Mutex::new(Vec::new()));
    static CONNECTION_EVENTS: Arc<Mutex<Vec<(i32, i32)>>> =
        Arc::new(Mutex::new(Vec::new()));
}

fn wait_for_connection(listener_id: i32) -> i32 {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let id = ct_poll_connection(listener_id);
        if id > 0 {
            return id;
        }
        if id < 0 {
            panic!("poll connection failed: {id}");
        }
        if Instant::now() > deadline {
            panic!("timed out waiting for connection");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn require_http3_port(listener_id: i32) -> i32 {
    let port = ct_listener_http3_port(listener_id);
    assert!(port > 0, "HTTP/3 listener did not start: {port}");
    port
}

fn wait_for_message_handle(connection_id: i32) -> i32 {
    let handle = ct_wait_connection_message(connection_id, 5_000);
    if handle <= 0 {
        panic!("timed out waiting for message on connection {connection_id}: {handle}");
    }
    handle
}

fn poll_for_message_handle(connection_id: i32) -> i32 {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let handle = ct_poll_connection_message(connection_id);
        if handle > 0 {
            return handle;
        }
        if handle < 0 {
            panic!("poll message failed for connection {connection_id}: {handle}");
        }
        if Instant::now() > deadline {
            panic!("timed out polling for message on connection {connection_id}");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn wait_for_http_handshake(connection_id: i32) -> i32 {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let handle = ct_connection_take_http_handshake(connection_id);
        if handle > 0 {
            return handle;
        }
        if handle < 0 {
            // Transient errors (connection not found/reset) can occur if the peer
            // closes early; keep polling until timeout.
            std::thread::sleep(Duration::from_millis(10));
            continue;
        }
        if Instant::now() > deadline {
            panic!("timed out waiting for HTTP handshake");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn wait_for_http_handshakes(connection_id: i32, expected: usize, timeout: Duration) -> Vec<i32> {
    let deadline = Instant::now() + timeout;
    let mut handles = Vec::with_capacity(expected);
    while handles.len() < expected {
        let handle = ct_connection_take_http_handshake(connection_id);
        if handle > 0 {
            handles.push(handle);
            continue;
        }
        if handle < 0 {
            std::thread::sleep(Duration::from_millis(10));
            continue;
        }
        if Instant::now() > deadline {
            panic!(
                "timed out waiting for {} HTTP handshakes on connection {}",
                expected, connection_id
            );
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    handles
}

fn http2_test_client_builder() -> client::Builder {
    let mut builder = client::Builder::new();
    builder
        .max_concurrent_streams(HTTP2_TEST_MAX_CONCURRENT_STREAMS)
        .initial_window_size(HTTP2_TEST_INITIAL_STREAM_WINDOW)
        .initial_connection_window_size(HTTP2_TEST_INITIAL_CONNECTION_WINDOW)
        .max_frame_size(HTTP2_TEST_MAX_FRAME_SIZE)
        .max_header_list_size(HTTP2_TEST_MAX_HEADER_LIST_SIZE)
        .max_concurrent_reset_streams(HTTP2_TEST_MAX_CONCURRENT_RESET_STREAMS)
        .max_send_buffer_size(HTTP2_TEST_MAX_SEND_BUFFER_SIZE);
    builder
}

fn wait_for_http_event(timeout: Duration) -> (CtHttpConnectionEventInfo, Option<String>) {
    let deadline = Instant::now() + timeout;
    loop {
        let handle = ct_connection_poll_http_event();
        if handle > 0 {
            let mut info = CtHttpConnectionEventInfo::default();
            let result =
                ct_http_connection_event_get(handle, &mut info as *mut CtHttpConnectionEventInfo);
            assert_eq!(result, SUCCESS);
            let detail = if info.detail_ptr.is_null() || info.detail_len == 0 {
                None
            } else {
                let slice = unsafe { std::slice::from_raw_parts(info.detail_ptr, info.detail_len) };
                Some(String::from_utf8_lossy(slice).to_string())
            };
            assert_eq!(ct_http_connection_event_release(handle), SUCCESS);
            return (info, detail);
        }
        if handle < 0 {
            panic!("poll http event failed: {handle}");
        }
        if Instant::now() > deadline {
            panic!("timed out waiting for HTTP connection event");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

async fn read_http_response_head(stream: &mut tokio::net::TcpStream) -> (String, Vec<u8>) {
    let mut buffer = Vec::new();
    loop {
        let mut chunk = [0u8; 1024];
        let read = tokio::time::timeout(Duration::from_secs(5), stream.read(&mut chunk))
            .await
            .expect("read response head timeout")
            .expect("read response head failed");
        assert!(read > 0, "connection closed before response head");
        buffer.extend_from_slice(&chunk[..read]);
        if let Some(index) = buffer.windows(4).position(|window| window == b"\r\n\r\n") {
            let head = String::from_utf8_lossy(&buffer[..index + 4]).to_string();
            let rest = buffer[index + 4..].to_vec();
            return (head, rest);
        }
    }
}

async fn read_exact_prefetched(
    stream: &mut tokio::net::TcpStream,
    prefetched: &mut Vec<u8>,
    len: usize,
) -> Vec<u8> {
    let mut output = Vec::with_capacity(len);
    while output.len() < len {
        if !prefetched.is_empty() {
            let take = (len - output.len()).min(prefetched.len());
            output.extend_from_slice(&prefetched[..take]);
            prefetched.drain(..take);
            continue;
        }
        let mut chunk = vec![0u8; len - output.len()];
        tokio::time::timeout(Duration::from_secs(5), stream.read_exact(&mut chunk))
            .await
            .expect("read exact timeout")
            .expect("read exact failed");
        output.extend_from_slice(&chunk);
    }
    output
}

async fn read_line_prefetched(
    stream: &mut tokio::net::TcpStream,
    prefetched: &mut Vec<u8>,
) -> Vec<u8> {
    let mut output = Vec::new();
    loop {
        if let Some(index) = prefetched.windows(2).position(|window| window == b"\r\n") {
            output.extend_from_slice(&prefetched[..index]);
            prefetched.drain(..index + 2);
            return output;
        }
        if !prefetched.is_empty() {
            output.extend_from_slice(prefetched);
            prefetched.clear();
        }
        let mut chunk = [0u8; 1024];
        let read = tokio::time::timeout(Duration::from_secs(5), stream.read(&mut chunk))
            .await
            .expect("read line timeout")
            .expect("read line failed");
        assert!(read > 0, "connection closed before line terminator");
        prefetched.extend_from_slice(&chunk[..read]);
    }
}

async fn read_chunked_response_body(
    stream: &mut tokio::net::TcpStream,
    prefetched: &mut Vec<u8>,
) -> Vec<u8> {
    let mut decoded = Vec::new();
    loop {
        let line = read_line_prefetched(stream, prefetched).await;
        let len_str = std::str::from_utf8(&line).expect("chunk size utf8");
        let chunk_len = usize::from_str_radix(len_str.trim(), 16).expect("chunk size hex");
        if chunk_len == 0 {
            let trailer = read_exact_prefetched(stream, prefetched, 2).await;
            assert_eq!(trailer, b"\r\n");
            break;
        }
        let chunk = read_exact_prefetched(stream, prefetched, chunk_len).await;
        decoded.extend_from_slice(&chunk);
        let suffix = read_exact_prefetched(stream, prefetched, 2).await;
        assert_eq!(suffix, b"\r\n");
    }
    decoded
}

fn build_http3_client_config(roots: Arc<RootCertStore>) -> QuinnClientConfig {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let verifier = WebPkiServerVerifier::builder_with_provider(roots, provider.clone())
        .build()
        .expect("webpki verifier");
    let mut inner = RustlsClientConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])
        .expect("tls13 supported")
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth();
    inner.enable_early_data = true;
    inner.alpn_protocols = vec![b"h3".to_vec(), b"h3-29".to_vec()];
    let quic_suite = rustls::crypto::ring::cipher_suite::TLS13_AES_128_GCM_SHA256
        .tls13()
        .and_then(|suite| suite.quic_suite())
        .expect("quic suite");
    let quic = QuinnRustlsClientConfig::with_initial(Arc::new(inner), quic_suite)
        .expect("build quic client config");
    let mut config = QuinnClientConfig::new(Arc::new(quic));
    config.transport_config(Arc::new(TransportConfig::default()));
    config
}

#[test]
fn listener_callbacks_fire_and_connections_are_reported() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "max_rawsocket_size_exponent":30
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    extern "C" fn on_listener_started(id: i32, status: i32) {
        LISTENER_EVENTS.with(|events| {
            events.lock().unwrap().push((id, status));
        });
    }

    extern "C" fn on_connection(listener_id: i32, connection_id: i32) {
        CONNECTION_EVENTS.with(|events| {
            events.lock().unwrap().push((listener_id, connection_id));
        });
    }

    ct_set_on_listener_started(on_listener_started);
    ct_set_on_connection(on_connection);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let other = CString::new("0.0.0.0").unwrap();
    assert_eq!(
        ct_listen(other.as_ptr(), 0, 128),
        ERR_ENDPOINT_NOT_CONFIGURED
    );

    LISTENER_EVENTS.with(|events| {
        assert_eq!(events.lock().unwrap().as_slice(), &[(listener_id, SUCCESS)]);
    });

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    let poll_result = rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 24, Some(30)).await;

        let poll_result = loop {
            let polled = ct_poll_connection(listener_id);
            if polled > 0 {
                break polled;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        };

        assert_eq!(ct_connection_protocol(poll_result), PROTOCOL_RAWSOCKET);
        assert_eq!(
            ct_connection_max_rawsocket_exponent(poll_result),
            30,
            "raw socket exponent expected from runtime config"
        );

        drop(stream);
        tokio::time::sleep(Duration::from_millis(50)).await;
        poll_result
    });

    assert!(poll_result > 0);
    CONNECTION_EVENTS.with(|events| {
        assert_eq!(
            events.lock().unwrap().as_slice(),
            &[(listener_id, poll_result)]
        );
    });

    assert_eq!(ct_poll_connection(listener_id), 0);
    assert_eq!(ct_poll_connection(9999), ERR_LISTENER_NOT_FOUND);
    assert_eq!(
        ct_connection_max_rawsocket_exponent(9999),
        ERR_CONNECTION_NOT_FOUND
    );
    assert_eq!(ct_connection_protocol(9999), ERR_CONNECTION_NOT_FOUND);
    assert_eq!(ct_shutdown(), SUCCESS);

    LISTENER_EVENTS.with(|events| events.lock().unwrap().clear());
    CONNECTION_EVENTS.with(|events| events.lock().unwrap().clear());
}

#[test]
fn listener_close_removes_listener_from_queries() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled"}]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);
    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    assert_eq!(ct_listener_close(listener_id), SUCCESS);
    assert_eq!(ct_get_local_port(listener_id), ERR_LISTENER_NOT_FOUND);
    assert_eq!(ct_listener_close(listener_id), ERR_LISTENER_NOT_FOUND);
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn poll_connection_message_returns_payload() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http"],
                    "http":{
                        "alpn":["http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/health",
                            "match_kind":"prefix",
                            "methods":{
                                "GET":{"type":"reserved_realm","append_method_suffix":true}
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let message = serde_json::to_vec(&json!([
        16,
        42,
        {},
        "com.example.topic",
        [1, 2, 3],
        {"flag": true}
    ]))
    .unwrap();
    let (release_client_tx, release_client_rx) = tokio::sync::oneshot::channel();
    let sender = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            perform_handshake(&mut stream, 16, None).await;
            send_json_frame(&mut stream, &message).await;
            let _ = tokio::time::timeout(Duration::from_secs(5), release_client_rx).await;
        });
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_RAWSOCKET);

    let handle = poll_for_message_handle(connection_id);

    let mut info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(handle, &mut info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(info.serializer, 1, "JSON serializer expected");
    assert_eq!(info.message_code, 16, "Publish message expected");
    assert!(info.args_len > 0);
    assert!(!info.args_ptr.is_null());
    assert!(info.kwargs_len > 0);
    assert!(!info.kwargs_ptr.is_null());
    unsafe {
        let frame = std::slice::from_raw_parts(info.frame_ptr, info.frame_len);
        let args = std::slice::from_raw_parts(info.args_ptr, info.args_len);
        let kwargs = std::slice::from_raw_parts(info.kwargs_ptr, info.kwargs_len);
        let frame_value: serde_json::Value = serde_json::from_slice(frame).unwrap();
        assert_eq!(frame_value[4], json!([1, 2, 3]));
        assert_eq!(frame_value[5], json!({"flag": true}));
        let args_value: serde_json::Value = serde_json::from_slice(args).unwrap();
        assert_eq!(args_value, json!([1, 2, 3]));
        let kwargs_value: serde_json::Value = serde_json::from_slice(kwargs).unwrap();
        assert_eq!(kwargs_value, json!({"flag": true}));
    }

    ct_message_release(handle);
    // Releasing twice should be a no-op.
    ct_message_release(handle);

    let _ = release_client_tx.send(());
    sender.join().expect("rawsocket sender thread");

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn ct_message_get_exports_direct_bind_metadata_for_hot_messages() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket"]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let messages = vec![
        serde_json::to_vec(&json!([
            2,
            5150,
            {
                "realm": "bench.realm",
                "authid": "bench-user",
                "authrole": "bench-role",
                "authmethod": "ticket",
                "authprovider": "native"
            }
        ]))
        .unwrap(),
        serde_json::to_vec(&json!([
            3,
            {"message": "denied"},
            "wamp.error.authorization_failed"
        ]))
        .unwrap(),
        serde_json::to_vec(&json!([
            4,
            "ticket",
            {
                "challenge": "abc123",
                "channel_binding": "tls-unique",
                "iterations": 4096
            }
        ]))
        .unwrap(),
        serde_json::to_vec(&json!([17, 43, 99])).unwrap(),
        serde_json::to_vec(&json!([
            36,
            7,
            99,
            {
                "publisher": 55,
                "trustlevel": 9,
                "topic": "bench.topic",
                "ppt_scheme": "wamp",
                "ppt_serializer": "cbor",
                "ppt_cipher": "aes",
                "ppt_keyid": "kid-1"
            },
            [1],
            {"flag": true}
        ]))
        .unwrap(),
        serde_json::to_vec(&json!([
            50,
            123,
            {
                "progress": true,
                "ppt_scheme": "wamp",
                "ppt_serializer": "msgpack",
                "ppt_cipher": "aes",
                "ppt_keyid": "kid-2"
            },
            [1],
            {"flag": true}
        ]))
        .unwrap(),
        serde_json::to_vec(&json!([
            68,
            77,
            12,
            {
                "caller": 5,
                "procedure": "bench.rpc.echo",
                "receive_progress": true,
                "ppt_scheme": "wamp",
                "ppt_serializer": "cbor",
                "ppt_cipher": "aes",
                "ppt_keyid": "kid-3"
            },
            [1],
            {"flag": true}
        ]))
        .unwrap(),
        serde_json::to_vec(&json!([
            8,
            48,
            777,
            {"message": "boom"},
            "wamp.error.runtime_error",
            [1],
            {"flag": true}
        ]))
        .unwrap(),
        serde_json::to_vec(&json!([
            6,
            {"message": "bye"},
            "wamp.error.system_shutdown"
        ]))
        .unwrap(),
        serde_json::to_vec(&json!([
            36,
            8,
            100,
            {
                "topic": "bench.topic",
                "_custom": true
            }
        ]))
        .unwrap(),
    ];
    let sender = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            perform_handshake(&mut stream, 16, None).await;
            for message in messages {
                send_json_frame(&mut stream, &message).await;
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
            tokio::time::sleep(Duration::from_millis(250)).await;
        });
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_RAWSOCKET);

    let welcome_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(welcome_handle > 0);
    let mut welcome_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(welcome_handle, &mut welcome_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(welcome_info.message_code, 2);
    assert_eq!(welcome_info.primary_id, 5150);
    assert_eq!(
        welcome_info.flags & MESSAGE_FLAG_DIRECT_BIND,
        MESSAGE_FLAG_DIRECT_BIND
    );
    unsafe {
        let realm =
            std::slice::from_raw_parts(welcome_info.string_a_ptr, welcome_info.string_a_len);
        let authid =
            std::slice::from_raw_parts(welcome_info.string_b_ptr, welcome_info.string_b_len);
        let authrole =
            std::slice::from_raw_parts(welcome_info.string_c_ptr, welcome_info.string_c_len);
        let authmethod =
            std::slice::from_raw_parts(welcome_info.string_d_ptr, welcome_info.string_d_len);
        let authprovider =
            std::slice::from_raw_parts(welcome_info.string_e_ptr, welcome_info.string_e_len);
        assert_eq!(std::str::from_utf8(realm).unwrap(), "bench.realm");
        assert_eq!(std::str::from_utf8(authid).unwrap(), "bench-user");
        assert_eq!(std::str::from_utf8(authrole).unwrap(), "bench-role");
        assert_eq!(std::str::from_utf8(authmethod).unwrap(), "ticket");
        assert_eq!(std::str::from_utf8(authprovider).unwrap(), "native");
    }
    ct_message_release(welcome_handle);

    let abort_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(abort_handle > 0);
    let mut abort_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(abort_handle, &mut abort_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(abort_info.message_code, 3);
    assert_eq!(
        abort_info.flags & MESSAGE_FLAG_DIRECT_BIND,
        MESSAGE_FLAG_DIRECT_BIND
    );
    assert_eq!(
        abort_info.flags & MESSAGE_FLAG_METADATA_BIND,
        MESSAGE_FLAG_METADATA_BIND
    );
    unsafe {
        let reason = std::slice::from_raw_parts(abort_info.string_a_ptr, abort_info.string_a_len);
        let message = std::slice::from_raw_parts(abort_info.string_b_ptr, abort_info.string_b_len);
        assert_eq!(
            std::str::from_utf8(reason).unwrap(),
            "wamp.error.authorization_failed"
        );
        assert_eq!(std::str::from_utf8(message).unwrap(), "denied");
    }
    ct_message_release(abort_handle);

    let challenge_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(challenge_handle > 0);
    let mut challenge_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_peek(challenge_handle, &mut challenge_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(challenge_info.message_code, 4);
    assert_eq!(challenge_info.flags & MESSAGE_FLAG_DIRECT_BIND, 0);
    assert_eq!(
        challenge_info.flags & MESSAGE_FLAG_METADATA_BIND,
        MESSAGE_FLAG_METADATA_BIND
    );
    assert_eq!(challenge_info.frame_len, 0);
    assert!(challenge_info.details_len > 0);
    unsafe {
        let auth_method =
            std::slice::from_raw_parts(challenge_info.string_a_ptr, challenge_info.string_a_len);
        let details =
            std::slice::from_raw_parts(challenge_info.details_ptr, challenge_info.details_len);
        assert_eq!(std::str::from_utf8(auth_method).unwrap(), "ticket");
        let extra: serde_json::Value = serde_json::from_slice(details).unwrap();
        assert_eq!(
            extra,
            json!({
                "challenge": "abc123",
                "channel_binding": "tls-unique",
                "iterations": 4096
            })
        );
    }
    ct_message_release(challenge_handle);

    let ack_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(ack_handle > 0);
    let mut ack_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(ack_handle, &mut ack_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(ack_info.message_code, 17);
    assert_eq!(ack_info.primary_id, 43);
    assert_eq!(ack_info.secondary_id, 99);
    assert_eq!(
        ack_info.flags & MESSAGE_FLAG_DIRECT_BIND,
        MESSAGE_FLAG_DIRECT_BIND
    );
    assert_eq!(
        ack_info.flags & MESSAGE_FLAG_METADATA_BIND,
        MESSAGE_FLAG_METADATA_BIND
    );
    ct_message_release(ack_handle);

    let event_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(event_handle > 0);
    let mut event_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(event_handle, &mut event_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(event_info.message_code, 36);
    assert_eq!(event_info.primary_id, 7);
    assert_eq!(event_info.secondary_id, 99);
    assert_eq!(event_info.detail_number_a, 55);
    assert_eq!(event_info.detail_number_b, 9);
    assert_eq!(
        event_info.flags,
        MESSAGE_FLAG_DIRECT_BIND
            | MESSAGE_FLAG_METADATA_BIND
            | MESSAGE_FLAG_DETAIL_NUMBER_A_PRESENT
            | MESSAGE_FLAG_DETAIL_NUMBER_B_PRESENT
    );
    unsafe {
        let topic = std::slice::from_raw_parts(event_info.string_a_ptr, event_info.string_a_len);
        let ppt_serializer =
            std::slice::from_raw_parts(event_info.string_c_ptr, event_info.string_c_len);
        assert_eq!(std::str::from_utf8(topic).unwrap(), "bench.topic");
        assert_eq!(std::str::from_utf8(ppt_serializer).unwrap(), "cbor");
    }
    ct_message_release(event_handle);

    let result_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(result_handle > 0);
    let mut result_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(result_handle, &mut result_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(result_info.message_code, 50);
    assert_eq!(result_info.primary_id, 123);
    assert_eq!(
        result_info.flags,
        MESSAGE_FLAG_DIRECT_BIND | MESSAGE_FLAG_METADATA_BIND | MESSAGE_FLAG_DETAIL_BOOL_A_TRUE
    );
    unsafe {
        let ppt_scheme =
            std::slice::from_raw_parts(result_info.string_a_ptr, result_info.string_a_len);
        assert_eq!(std::str::from_utf8(ppt_scheme).unwrap(), "wamp");
    }
    ct_message_release(result_handle);

    let invocation_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(invocation_handle > 0);
    let mut invocation_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(
            invocation_handle,
            &mut invocation_info as *mut CtMessageInfo
        ),
        SUCCESS
    );
    assert_eq!(invocation_info.message_code, 68);
    assert_eq!(invocation_info.primary_id, 77);
    assert_eq!(invocation_info.secondary_id, 12);
    assert_eq!(invocation_info.detail_number_a, 5);
    assert_eq!(
        invocation_info.flags,
        MESSAGE_FLAG_DIRECT_BIND
            | MESSAGE_FLAG_METADATA_BIND
            | MESSAGE_FLAG_DETAIL_NUMBER_A_PRESENT
            | MESSAGE_FLAG_DETAIL_BOOL_A_TRUE
    );
    unsafe {
        let procedure =
            std::slice::from_raw_parts(invocation_info.string_a_ptr, invocation_info.string_a_len);
        assert_eq!(std::str::from_utf8(procedure).unwrap(), "bench.rpc.echo");
    }
    ct_message_release(invocation_handle);

    let error_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(error_handle > 0);
    let mut error_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(error_handle, &mut error_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(error_info.message_code, 8);
    assert_eq!(error_info.primary_id, 48);
    assert_eq!(error_info.secondary_id, 777);
    assert_eq!(
        error_info.flags & MESSAGE_FLAG_DIRECT_BIND,
        MESSAGE_FLAG_DIRECT_BIND
    );
    assert_eq!(
        error_info.flags & MESSAGE_FLAG_METADATA_BIND,
        MESSAGE_FLAG_METADATA_BIND
    );
    assert!(error_info.args_len > 0);
    assert!(error_info.kwargs_len > 0);
    unsafe {
        let error = std::slice::from_raw_parts(error_info.string_a_ptr, error_info.string_a_len);
        let message = std::slice::from_raw_parts(error_info.string_b_ptr, error_info.string_b_len);
        let args = std::slice::from_raw_parts(error_info.args_ptr, error_info.args_len);
        let kwargs = std::slice::from_raw_parts(error_info.kwargs_ptr, error_info.kwargs_len);
        assert_eq!(
            std::str::from_utf8(error).unwrap(),
            "wamp.error.runtime_error"
        );
        assert_eq!(std::str::from_utf8(message).unwrap(), "boom");
        let args_value: serde_json::Value = serde_json::from_slice(args).unwrap();
        assert_eq!(args_value, json!([1]));
        let kwargs_value: serde_json::Value = serde_json::from_slice(kwargs).unwrap();
        assert_eq!(kwargs_value, json!({"flag": true}));
    }
    ct_message_release(error_handle);

    let goodbye_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(goodbye_handle > 0);
    let mut goodbye_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(goodbye_handle, &mut goodbye_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(goodbye_info.message_code, 6);
    assert_eq!(
        goodbye_info.flags & MESSAGE_FLAG_DIRECT_BIND,
        MESSAGE_FLAG_DIRECT_BIND
    );
    assert_eq!(
        goodbye_info.flags & MESSAGE_FLAG_METADATA_BIND,
        MESSAGE_FLAG_METADATA_BIND
    );
    unsafe {
        let reason =
            std::slice::from_raw_parts(goodbye_info.string_a_ptr, goodbye_info.string_a_len);
        let message =
            std::slice::from_raw_parts(goodbye_info.string_b_ptr, goodbye_info.string_b_len);
        assert_eq!(
            std::str::from_utf8(reason).unwrap(),
            "wamp.error.system_shutdown"
        );
        assert_eq!(std::str::from_utf8(message).unwrap(), "bye");
    }
    ct_message_release(goodbye_handle);

    let custom_event_handle = ct_wait_connection_message(connection_id, 5_000);
    assert!(custom_event_handle > 0);
    let mut custom_event_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_peek(
            custom_event_handle,
            &mut custom_event_info as *mut CtMessageInfo
        ),
        SUCCESS
    );
    assert_eq!(custom_event_info.message_code, 36);
    assert_eq!(
        custom_event_info.flags & MESSAGE_FLAG_DIRECT_BIND,
        MESSAGE_FLAG_DIRECT_BIND
    );
    assert_eq!(
        custom_event_info.flags & MESSAGE_FLAG_METADATA_BIND,
        MESSAGE_FLAG_METADATA_BIND
    );
    assert_eq!(custom_event_info.frame_len, 0);
    assert!(custom_event_info.details_len > 0);
    unsafe {
        let details = std::slice::from_raw_parts(
            custom_event_info.details_ptr,
            custom_event_info.details_len,
        );
        let decoded: serde_json::Value = serde_json::from_slice(details).unwrap();
        assert_eq!(
            decoded,
            json!({
                "topic": "bench.topic",
                "_custom": true
            })
        );
    }
    ct_message_release(custom_event_handle);

    sender.join().unwrap();
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn wait_connection_message_times_out_without_payload() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket"]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);
    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    let wait_result = rt.block_on(async move {
        let addr = format!("127.0.0.1:{port}");
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 16, None).await;

        let connection_id = wait_for_connection(listener_id);
        assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_RAWSOCKET);
        ct_wait_connection_message(connection_id, 10)
    });
    assert_eq!(wait_result, 0);

    assert_eq!(ct_listener_close(listener_id), SUCCESS);
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn client_connect_rawsocket_round_trips_over_ffi() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","max_rawsocket_size_exponent":30}]}"#,
    )
    .unwrap();
    assert_eq!(
        ct_apply_router_config(config.as_bytes().as_ptr(), config.as_bytes().len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let host = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(host.as_ptr(), 0, 128);
    assert!(listener_id > 0);
    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let client_connection_id = ct_client_connect_rawsocket(host.as_ptr(), port, 0, 0, 1, 30, 0, 0);
    assert!(client_connection_id > 0);
    let server_connection_id = wait_for_connection(listener_id);
    assert_eq!(
        ct_connection_protocol(client_connection_id),
        PROTOCOL_RAWSOCKET
    );
    assert_eq!(
        ct_connection_protocol(server_connection_id),
        PROTOCOL_RAWSOCKET
    );
    assert_eq!(
        ct_connection_max_rawsocket_exponent(client_connection_id),
        30
    );

    let hello = serde_json::to_vec(&json!([1, "realm", {}])).unwrap();
    assert_eq!(
        ct_send_message(client_connection_id, hello.as_ptr(), hello.len() as i32,),
        SUCCESS
    );
    let server_handle = wait_for_message_handle(server_connection_id);
    let mut server_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(server_handle, &mut server_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(server_info.message_code, 1, "HELLO expected");
    ct_message_release(server_handle);

    let welcome = serde_json::to_vec(&json!([2, 9001, {}])).unwrap();
    assert_eq!(
        ct_send_message(server_connection_id, welcome.as_ptr(), welcome.len() as i32,),
        SUCCESS
    );
    let client_handle = wait_for_message_handle(client_connection_id);
    let mut client_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(client_handle, &mut client_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(client_info.message_code, 2, "WELCOME expected");
    ct_message_release(client_handle);

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn client_connect_websocket_round_trips_over_ffi() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["websocket"]}]}"#,
    )
    .unwrap();
    assert_eq!(
        ct_apply_router_config(config.as_bytes().as_ptr(), config.as_bytes().len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let host = CString::new("127.0.0.1").unwrap();
    let target = CString::new("/wamp").unwrap();
    let listener_id = ct_listen(host.as_ptr(), 0, 128);
    assert!(listener_id > 0);
    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let host_ptr = host.clone();
    let target_ptr = target.clone();
    let header_name = b"X-Test".to_vec();
    let header_value = b"ffi".to_vec();
    let connect = std::thread::spawn(move || {
        let header = CtHttpHeader {
            name_ptr: header_name.as_ptr(),
            name_len: header_name.len(),
            value_ptr: header_value.as_ptr(),
            value_len: header_value.len(),
        };
        ct_client_connect_websocket(
            host_ptr.as_ptr(),
            port,
            target_ptr.as_ptr(),
            0,
            0,
            1,
            &header as *const CtHttpHeader,
            1,
            0,
            0,
        )
    });

    let server_connection_id = wait_for_connection(listener_id);
    assert_eq!(
        ct_connection_protocol(server_connection_id),
        PROTOCOL_WEBSOCKET
    );
    let handshake_handle = ct_connection_take_websocket_handshake(server_connection_id);
    assert!(handshake_handle > 0);

    let mut handshake = CtWebSocketHandshakeInfo::default();
    assert_eq!(
        ct_websocket_handshake_get(
            handshake_handle,
            &mut handshake as *mut CtWebSocketHandshakeInfo
        ),
        SUCCESS
    );
    assert_eq!(handshake.protocols_len, 1);
    let mut protocol = CtStringView::default();
    assert_eq!(
        ct_websocket_handshake_protocol(handshake_handle, 0, &mut protocol as *mut CtStringView),
        SUCCESS
    );
    unsafe {
        let protocol = std::slice::from_raw_parts(protocol.ptr, protocol.len);
        assert_eq!(std::str::from_utf8(protocol).unwrap(), "wamp.2.json");
    }

    let selected = CString::new("wamp.2.json").unwrap();
    assert_eq!(
        ct_connection_accept_websocket(
            server_connection_id,
            handshake_handle,
            1,
            selected.as_ptr(),
            selected.as_bytes().len() as i32,
        ),
        SUCCESS
    );
    let client_connection_id = connect.join().unwrap();
    assert!(client_connection_id > 0);
    assert_eq!(
        ct_connection_protocol(client_connection_id),
        PROTOCOL_WEBSOCKET
    );

    let hello = serde_json::to_vec(&json!([1, "realm", {}])).unwrap();
    assert_eq!(
        ct_send_message(client_connection_id, hello.as_ptr(), hello.len() as i32,),
        SUCCESS
    );
    let server_handle = wait_for_message_handle(server_connection_id);
    let mut server_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(server_handle, &mut server_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(server_info.message_code, 1, "HELLO expected");
    ct_message_release(server_handle);

    let welcome = serde_json::to_vec(&json!([2, 5150, {}])).unwrap();
    assert_eq!(
        ct_send_message(server_connection_id, welcome.as_ptr(), welcome.len() as i32,),
        SUCCESS
    );
    let client_handle = wait_for_message_handle(client_connection_id);
    let mut client_info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(client_handle, &mut client_info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(client_info.message_code, 2, "WELCOME expected");
    ct_message_release(client_handle);

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http_handshake_surfaced_via_ffi() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["rawsocket","http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/health","match_kind":"prefix","methods":{"GET":{"type":"reserved_realm","append_method_suffix":true}}}]}]}"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        stream
            .write_all(b"GET /health?check=true HTTP/1.1\r\nHost: localhost\r\nX-Test: ffi\r\n\r\n")
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let connection_id = ct_poll_connection(listener_id);
    assert!(connection_id > 0);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP);

    let handle = loop {
        let handle = ct_connection_take_http_handshake(connection_id);
        if handle > 0 {
            break handle;
        }
        std::thread::sleep(Duration::from_millis(10));
    };

    // No additional requests should be pending yet.
    assert_eq!(ct_connection_take_http_handshake(connection_id), 0);

    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );

    unsafe {
        let method =
            std::str::from_utf8(std::slice::from_raw_parts(info.method_ptr, info.method_len))
                .expect("method utf8");
        assert_eq!(method, "GET");

        let target =
            std::str::from_utf8(std::slice::from_raw_parts(info.target_ptr, info.target_len))
                .expect("target utf8");
        assert_eq!(target, "/health?check=true");

        let path = std::str::from_utf8(std::slice::from_raw_parts(info.path_ptr, info.path_len))
            .expect("path utf8");
        assert_eq!(path, "/health");

        assert!(!info.query_ptr.is_null());
        let query = std::str::from_utf8(std::slice::from_raw_parts(info.query_ptr, info.query_len))
            .expect("query utf8");
        assert_eq!(query, "check=true");

        let protocol = std::str::from_utf8(std::slice::from_raw_parts(
            info.protocol_ptr,
            info.protocol_len,
        ))
        .expect("protocol utf8");
        assert_eq!(protocol, "http/1.1");

        assert!(!info.realm_ptr.is_null());
        let realm = std::str::from_utf8(std::slice::from_raw_parts(info.realm_ptr, info.realm_len))
            .expect("realm utf8");
        assert_eq!(realm, "router.http");

        assert!(!info.procedure_ptr.is_null());
        let procedure = std::str::from_utf8(std::slice::from_raw_parts(
            info.procedure_ptr,
            info.procedure_len,
        ))
        .expect("procedure utf8");
        assert_eq!(procedure, "health.get");

        assert_eq!(info.version, 1);
        assert_eq!(info.headers_len, 2);

        let body = std::slice::from_raw_parts(info.body_ptr, info.body_len);
        assert!(body.is_empty());
    }

    let mut header = CtHttpHeader::default();
    assert_eq!(
        ct_http_handshake_header(handle, 0, &mut header as *mut CtHttpHeader),
        SUCCESS
    );
    unsafe {
        let name =
            std::str::from_utf8(std::slice::from_raw_parts(header.name_ptr, header.name_len))
                .unwrap();
        let value = std::str::from_utf8(std::slice::from_raw_parts(
            header.value_ptr,
            header.value_len,
        ))
        .unwrap();
        assert_eq!(name.to_lowercase(), "host");
        assert_eq!(value, "localhost");
    }

    assert_eq!(
        ct_http_handshake_header(handle, 1, &mut header as *mut CtHttpHeader),
        SUCCESS
    );
    unsafe {
        let name =
            std::str::from_utf8(std::slice::from_raw_parts(header.name_ptr, header.name_len))
                .unwrap();
        let value = std::str::from_utf8(std::slice::from_raw_parts(
            header.value_ptr,
            header.value_len,
        ))
        .unwrap();
        assert_eq!(name.to_lowercase(), "x-test");
        assert_eq!(value, "ffi");
    }

    assert_eq!(
        ct_http_handshake_header(handle, 10, &mut header as *mut CtHttpHeader),
        ERR_INVALID_ARGUMENT
    );

    let body_handle = ct_http_handshake_body_retain(handle);
    assert!(
        body_handle > 0,
        "HTTP body handle should be available for retained requests"
    );
    let mut body_view = CtHttpBodyView::default();
    assert_eq!(
        ct_http_body_get(body_handle, &mut body_view as *mut CtHttpBodyView),
        SUCCESS
    );
    assert_eq!(body_view.data_len, 0);
    assert_eq!(ct_http_body_release(body_handle), SUCCESS);

    assert_eq!(ct_http_handshake_release(handle), SUCCESS);
    assert_eq!(
        ct_http_handshake_release(handle),
        SUCCESS,
        "idempotent release"
    );

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http_handshake_rejects_bad_requests_with_status_only_responses() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","max_http_content_length":8,"protocols":["rawsocket","http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/health","match_kind":"prefix","methods":{"GET":{"type":"reserved_realm","append_method_suffix":true}}}]}]}"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    let cases = [
        (
            "bad-content-length",
            "POST /health HTTP/1.1\r\nHost: localhost\r\nContent-Length: nope\r\n\r\n",
            "HTTP/1.1 400 Bad Request",
        ),
        (
            "payload-too-large",
            "POST /health HTTP/1.1\r\nHost: localhost\r\nContent-Length: 16\r\n\r\n0123456789abcdef",
            "HTTP/1.1 413 Payload Too Large",
        ),
        (
            "chunked-not-implemented",
            "POST /health HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n",
            "HTTP/1.1 501 Not Implemented",
        ),
    ];

    for (name, request, expected_status) in cases {
        let response = rt.block_on(async {
            let addr = format!("127.0.0.1:{}", port);
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            stream.write_all(request.as_bytes()).await.unwrap();
            stream.shutdown().await.unwrap();
            let mut response = Vec::new();
            stream.read_to_end(&mut response).await.unwrap();
            response
        });
        let response_text = String::from_utf8_lossy(&response);
        assert!(
            response_text.starts_with(expected_status),
            "{name} unexpected response: {response_text}",
        );
        assert!(
            response_text.contains("Content-Length: 0"),
            "{name} missing zero-length body: {response_text}",
        );
        assert!(
            response_text.ends_with("\r\n\r\n"),
            "{name} expected status-only response: {response_text:?}",
        );
    }

    std::thread::sleep(Duration::from_millis(50));
    assert_eq!(ct_poll_connection(listener_id), 0);
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http_transport_auth_rejects_bearerless_http1_route() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["rawsocket","http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/secure","match_kind":"exact","transport_auth":{"require_bearer":true},"methods":{"GET":{"type":"reserved_realm","append_method_suffix":true}}}]}]}"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    let response = rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        stream
            .write_all(b"GET /secure HTTP/1.1\r\nHost: localhost\r\n\r\n")
            .await
            .unwrap();
        stream.shutdown().await.unwrap();
        let mut response = Vec::new();
        stream.read_to_end(&mut response).await.unwrap();
        response
    });
    let response_text = String::from_utf8_lossy(&response);
    assert!(
        response_text.starts_with("HTTP/1.1 401 Unauthorized"),
        "unexpected response: {}",
        response_text
    );
    assert!(
        response_text.contains("WWW-Authenticate: Bearer"),
        "unexpected response: {}",
        response_text
    );

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http_transport_auth_allows_bearerless_cors_preflight_when_configured() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["rawsocket","http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/secure","match_kind":"exact","transport_auth":{"require_bearer":true,"allow_unauthenticated_cors_preflight":true},"methods":{"OPTIONS":{"type":"reserved_realm","append_method_suffix":true}}}]}]}"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            stream
                .write_all(
                    b"OPTIONS /secure HTTP/1.1\r\nHost: localhost\r\nOrigin: https://consumer.example\r\nAccess-Control-Request-Method: POST\r\nConnection: close\r\n\r\n",
                )
                .await
                .unwrap();
            let mut response = Vec::new();
            stream.read_to_end(&mut response).await.unwrap();
            response
        })
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP);
    let handle = wait_for_http_handshake(connection_id);

    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let method =
            std::str::from_utf8(std::slice::from_raw_parts(info.method_ptr, info.method_len))
                .expect("method utf8");
        assert_eq!(method, "OPTIONS");
        let path = std::str::from_utf8(std::slice::from_raw_parts(info.path_ptr, info.path_len))
            .expect("path utf8");
        assert_eq!(path, "/secure");
    }

    assert_eq!(
        ct_http_response_send(handle, 204, std::ptr::null(), 0, std::ptr::null(), 0),
        SUCCESS
    );
    assert_eq!(ct_http_handshake_release(handle), SUCCESS);

    let response = client_handle.join().expect("client result");
    let response_text = String::from_utf8_lossy(&response);
    assert!(
        response_text.starts_with("HTTP/1.1 204"),
        "unexpected response: {}",
        response_text
    );

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http_handshake_streaming_body_round_trip() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","protocols":["rawsocket","http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/stream","match_kind":"prefix","methods":{"POST":{"type":"reserved_realm","append_method_suffix":true}}}]}]}"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let payload_len = 70_000;
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            let request = format!(
                "POST /stream HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Length: {}\r\n\r\n",
                payload_len
            );
            stream.write_all(request.as_bytes()).await.unwrap();
            let payload = vec![b'x'; payload_len];
            let initial = 32 * 1024;
            stream.write_all(&payload[..initial.min(payload.len())])
                .await
                .unwrap();
            stream.flush().await.unwrap();
            tokio::time::sleep(Duration::from_millis(50)).await;
            if initial < payload.len() {
                stream.write_all(&payload[initial..]).await.unwrap();
                stream.flush().await.unwrap();
            }
            let mut response = Vec::new();
            stream.read_to_end(&mut response).await.unwrap();
            response
        })
    });

    let connection_id = loop {
        let id = ct_poll_connection(listener_id);
        if id > 0 {
            break id;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP);

    let handle = loop {
        let handle = ct_connection_take_http_handshake(connection_id);
        if handle > 0 {
            break handle;
        }
        std::thread::sleep(Duration::from_millis(10));
    };

    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    assert_eq!(info.body_len, payload_len);

    let body_handle = ct_http_handshake_body_retain(handle);
    assert!(body_handle > 0, "streaming body handle expected");

    let mut view = CtHttpBodyView::default();
    assert_eq!(
        ct_http_body_get(body_handle, &mut view as *mut CtHttpBodyView),
        ERR_UNSUPPORTED
    );

    let mut collected = Vec::new();
    loop {
        assert_eq!(
            ct_http_body_stream_read(body_handle, 8192, &mut view as *mut CtHttpBodyView),
            SUCCESS
        );
        if view.data_len == 0 {
            break;
        }
        unsafe {
            let slice = std::slice::from_raw_parts(view.data_ptr, view.data_len);
            collected.extend_from_slice(slice);
        }
    }
    assert_eq!(collected.len(), payload_len);
    assert!(collected.iter().all(|byte| *byte == b'x'));

    assert_eq!(ct_http_body_finish(body_handle), SUCCESS);
    assert_eq!(ct_http_body_release(body_handle), SUCCESS);

    let body = b"stream-ok";
    assert_eq!(
        ct_http_response_send(handle, 204, std::ptr::null(), 0, body.as_ptr(), body.len(),),
        SUCCESS
    );
    assert_eq!(ct_http_handshake_release(handle), SUCCESS);

    let response_bytes = client_handle.join().expect("client result");
    let response_text = String::from_utf8_lossy(&response_bytes);
    assert!(
        response_text.starts_with("HTTP/1.1 204"),
        "unexpected response: {}",
        response_text
    );

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http_response_streaming_round_trip() {
    fn decode_chunked_body(body: &[u8]) -> Vec<u8> {
        let mut cursor = 0usize;
        let mut decoded = Vec::new();
        while cursor < body.len() {
            let line_end = body[cursor..]
                .windows(2)
                .position(|window| window == b"\r\n")
                .map(|pos| cursor + pos)
                .expect("chunk size line");
            let len_str = std::str::from_utf8(&body[cursor..line_end]).expect("chunk size utf8");
            let chunk_len = usize::from_str_radix(len_str.trim(), 16).expect("chunk size hex");
            cursor = line_end + 2;
            if chunk_len == 0 {
                break;
            }
            let end = cursor
                .checked_add(chunk_len)
                .expect("chunk length overflow");
            assert!(
                end + 2 <= body.len(),
                "chunk overruns body buffer (len={}, remaining={})",
                chunk_len,
                body.len() - cursor
            );
            decoded.extend_from_slice(&body[cursor..end]);
            cursor = end + 2;
        }
        decoded
    }

    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http"],
                    "http":{
                        "alpn":["http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/h1stream",
                            "match_kind":"prefix",
                            "methods":{
                                "GET":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let (client_tx, client_rx) = std::sync::mpsc::channel();
    let chunk = vec![b'q'; 16 * 1024];
    let chunk_count = 4;
    let trailer = b"h1-stream-finished";
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            let request = b"GET /h1stream HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
            stream.write_all(request).await.unwrap();
            stream.flush().await.unwrap();
            client_tx.send(()).unwrap();
            let mut response = Vec::new();
            stream.read_to_end(&mut response).await.unwrap();
            response
        })
    });

    client_rx.recv().unwrap();

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP);

    let handle = wait_for_http_handshake(connection_id);
    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let method =
            std::str::from_utf8(std::slice::from_raw_parts(info.method_ptr, info.method_len))
                .expect("method utf8");
        assert_eq!(method, "GET");
        let path = std::str::from_utf8(std::slice::from_raw_parts(info.path_ptr, info.path_len))
            .expect("path utf8");
        assert_eq!(path, "/h1stream");
    }

    let header_name = CString::new("content-type").unwrap();
    let header_value = CString::new("application/octet-stream").unwrap();
    let headers = [CtHttpHeader {
        name_ptr: header_name.as_ptr() as *const u8,
        name_len: header_name.as_bytes().len(),
        value_ptr: header_value.as_ptr() as *const u8,
        value_len: header_value.as_bytes().len(),
    }];

    let stream_handle = ct_http_response_stream_open(handle, 206, headers.as_ptr(), headers.len());
    assert!(stream_handle > 0);

    for _ in 0..chunk_count {
        assert_eq!(
            ct_http_response_stream_write(stream_handle, chunk.as_ptr(), chunk.len()),
            SUCCESS
        );
    }
    assert_eq!(
        ct_http_response_stream_write(stream_handle, trailer.as_ptr(), trailer.len()),
        SUCCESS
    );
    assert_eq!(ct_http_response_stream_finish(stream_handle), SUCCESS);
    assert_eq!(ct_http_handshake_release(handle), SUCCESS);

    let response_bytes = client_handle.join().unwrap();
    let header_split = response_bytes
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .expect("header terminator");
    let header_bytes = &response_bytes[..header_split];
    let header_text = String::from_utf8_lossy(header_bytes);
    assert!(
        header_text.starts_with("HTTP/1.1 206"),
        "unexpected status line: {}",
        header_text
    );
    assert!(
        header_text
            .to_ascii_lowercase()
            .contains("transfer-encoding: chunked"),
        "missing chunked header: {}",
        header_text
    );
    let body_bytes = &response_bytes[header_split + 4..];
    let decoded = decode_chunked_body(body_bytes);
    let expected_len = chunk.len() * chunk_count + trailer.len();
    assert_eq!(decoded.len(), expected_len);
    assert!(decoded[..chunk.len()].iter().all(|byte| *byte == b'q'));
    assert!(decoded.ends_with(trailer));

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http1_keep_alive_pipeline_preserves_prefetched_requests() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http"],
                    "http":{
                        "alpn":["http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/first",
                            "match_kind":"prefix",
                            "methods":{
                                "POST":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        },
                        {
                            "path":"/second",
                            "match_kind":"prefix",
                            "methods":{
                                "GET":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            stream
                .write_all(
                    b"POST /first HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\nContent-Length: 4\r\n\r\nbodyGET /second HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
                )
                .await
                .unwrap();
            stream.flush().await.unwrap();
            let mut response = Vec::new();
            stream.read_to_end(&mut response).await.unwrap();
            response
        })
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP);

    let first_handle = wait_for_http_handshake(connection_id);
    let mut first_info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(first_handle, &mut first_info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let method = std::str::from_utf8(std::slice::from_raw_parts(
            first_info.method_ptr,
            first_info.method_len,
        ))
        .expect("first method utf8");
        let path = std::str::from_utf8(std::slice::from_raw_parts(
            first_info.path_ptr,
            first_info.path_len,
        ))
        .expect("first path utf8");
        assert_eq!(method, "POST");
        assert_eq!(path, "/first");
    }
    assert_eq!(first_info.body_len, 4);

    let body_handle = ct_http_handshake_body_retain(first_handle);
    assert!(body_handle > 0);
    let mut body_view = CtHttpBodyView::default();
    assert_eq!(
        ct_http_body_get(body_handle, &mut body_view as *mut CtHttpBodyView),
        SUCCESS
    );
    unsafe {
        let bytes = std::slice::from_raw_parts(body_view.data_ptr, body_view.data_len);
        assert_eq!(bytes, b"body");
    }
    assert_eq!(ct_http_body_release(body_handle), SUCCESS);

    let first_body = b"first-response";
    assert_eq!(
        ct_http_response_send(
            first_handle,
            201,
            std::ptr::null(),
            0,
            first_body.as_ptr(),
            first_body.len(),
        ),
        SUCCESS
    );
    assert_eq!(ct_http_handshake_release(first_handle), SUCCESS);

    let second_handle = wait_for_http_handshake(connection_id);
    let mut second_info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(second_handle, &mut second_info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let method = std::str::from_utf8(std::slice::from_raw_parts(
            second_info.method_ptr,
            second_info.method_len,
        ))
        .expect("second method utf8");
        let path = std::str::from_utf8(std::slice::from_raw_parts(
            second_info.path_ptr,
            second_info.path_len,
        ))
        .expect("second path utf8");
        assert_eq!(method, "GET");
        assert_eq!(path, "/second");
    }
    assert_eq!(second_info.body_len, 0);

    let second_body = b"second-response";
    assert_eq!(
        ct_http_response_send(
            second_handle,
            202,
            std::ptr::null(),
            0,
            second_body.as_ptr(),
            second_body.len(),
        ),
        SUCCESS
    );
    assert_eq!(ct_http_handshake_release(second_handle), SUCCESS);

    let response_bytes = client_handle.join().unwrap();
    let response_text = String::from_utf8_lossy(&response_bytes);
    let first_status = response_text
        .find("HTTP/1.1 201")
        .expect("first response status");
    let second_status = response_text
        .find("HTTP/1.1 202")
        .expect("second response status");
    assert!(
        first_status < second_status,
        "responses out of order: {response_text}"
    );
    assert!(
        response_text.contains("first-response"),
        "missing first body: {response_text}"
    );
    assert!(
        response_text.contains("second-response"),
        "missing second body: {response_text}"
    );

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http1_streaming_request_and_streaming_response_keep_alive_round_trip() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http"],
                    "http":{
                        "alpn":["http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/stream",
                            "match_kind":"prefix",
                            "methods":{
                                "POST":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let payload_len = 70_000usize;
    let response_chunk = vec![b'r'; 32 * 1024];
    let response_trailer = b"stream-finished";
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            let first_request = format!(
                "POST /stream HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\nContent-Length: {}\r\n\r\n",
                payload_len
            );
            stream.write_all(first_request.as_bytes()).await.unwrap();
            stream.write_all(&vec![b'x'; payload_len]).await.unwrap();
            stream.flush().await.unwrap();

            let (first_head, mut first_prefetched) = read_http_response_head(&mut stream).await;
            assert!(
                first_head.starts_with("HTTP/1.1 207"),
                "unexpected first response: {first_head}"
            );
            assert!(
                first_head
                    .to_ascii_lowercase()
                    .contains("transfer-encoding: chunked"),
                "missing chunked header: {first_head}"
            );
            let first_body = read_chunked_response_body(&mut stream, &mut first_prefetched).await;

            let second_request =
                b"POST /stream HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Length: 0\r\n\r\n";
            stream.write_all(second_request).await.unwrap();
            stream.flush().await.unwrap();

            let (second_head, second_prefetched) = read_http_response_head(&mut stream).await;
            assert!(
                second_head.starts_with("HTTP/1.1 204"),
                "unexpected second response: {second_head}"
            );
            assert!(second_prefetched.is_empty());
            let mut tail = Vec::new();
            stream.read_to_end(&mut tail).await.unwrap();
            (first_body, second_head)
        })
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP);

    let first_handle = wait_for_http_handshake(connection_id);
    let mut first_info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(first_handle, &mut first_info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    assert_eq!(first_info.body_len, payload_len);

    let body_handle = ct_http_handshake_body_retain(first_handle);
    assert!(body_handle > 0);
    let mut collected = Vec::new();
    loop {
        let mut view = CtHttpBodyView::default();
        assert_eq!(
            ct_http_body_stream_read(body_handle, 8192, &mut view as *mut CtHttpBodyView),
            SUCCESS
        );
        if view.data_len == 0 {
            break;
        }
        unsafe {
            let slice = std::slice::from_raw_parts(view.data_ptr, view.data_len);
            collected.extend_from_slice(slice);
        }
    }
    assert_eq!(collected.len(), payload_len);
    assert!(collected.iter().all(|byte| *byte == b'x'));
    assert_eq!(ct_http_body_finish(body_handle), SUCCESS);
    assert_eq!(ct_http_body_release(body_handle), SUCCESS);

    let header_name = CString::new("content-type").unwrap();
    let header_value = CString::new("application/octet-stream").unwrap();
    let headers = [CtHttpHeader {
        name_ptr: header_name.as_ptr() as *const u8,
        name_len: header_name.as_bytes().len(),
        value_ptr: header_value.as_ptr() as *const u8,
        value_len: header_value.as_bytes().len(),
    }];
    let stream_handle =
        ct_http_response_stream_open(first_handle, 207, headers.as_ptr(), headers.len());
    assert!(stream_handle > 0);
    for _ in 0..4 {
        assert_eq!(
            ct_http_response_stream_write(
                stream_handle,
                response_chunk.as_ptr(),
                response_chunk.len()
            ),
            SUCCESS
        );
    }
    assert_eq!(
        ct_http_response_stream_write(
            stream_handle,
            response_trailer.as_ptr(),
            response_trailer.len(),
        ),
        SUCCESS
    );
    assert_eq!(ct_http_response_stream_finish(stream_handle), SUCCESS);
    assert_eq!(ct_http_handshake_release(first_handle), SUCCESS);

    let second_handle = wait_for_http_handshake(connection_id);
    let mut second_info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(second_handle, &mut second_info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    assert_eq!(second_info.body_len, 0);
    assert_eq!(
        ct_http_response_send(second_handle, 204, std::ptr::null(), 0, std::ptr::null(), 0),
        SUCCESS
    );
    assert_eq!(ct_http_handshake_release(second_handle), SUCCESS);

    let (first_body, second_head) = client_handle.join().unwrap();
    let expected_len = response_chunk.len() * 4 + response_trailer.len();
    assert_eq!(first_body.len(), expected_len);
    assert!(first_body[..response_chunk.len()]
        .iter()
        .all(|byte| *byte == b'r'));
    assert!(first_body.ends_with(response_trailer));
    assert!(second_head.contains("Content-Length: 0"));

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http_body_streaming_can_be_read_via_ffi() {
    let state = StreamingBodyState::new(6);
    state.enqueue_vec(vec![1, 2, 3]);
    state.enqueue_vec(vec![4, 5, 6]);
    state.mark_finished();
    let handle = HttpBodyHandle::streaming(state.clone());
    let body_id = store_http_body(handle);

    let mut view = CtHttpBodyView::default();
    assert_eq!(
        ct_http_body_stream_read(body_id as i32, 3, &mut view as *mut CtHttpBodyView),
        SUCCESS
    );
    unsafe {
        assert_eq!(
            std::slice::from_raw_parts(view.data_ptr, view.data_len),
            &[1, 2, 3]
        );
    }

    assert_eq!(
        ct_http_body_stream_read(body_id as i32, 3, &mut view as *mut CtHttpBodyView),
        SUCCESS
    );
    unsafe {
        assert_eq!(
            std::slice::from_raw_parts(view.data_ptr, view.data_len),
            &[4, 5, 6]
        );
    }

    assert_eq!(
        ct_http_body_stream_read(body_id as i32, 3, &mut view as *mut CtHttpBodyView),
        SUCCESS
    );
    assert_eq!(view.data_len, 0);

    assert_eq!(ct_http_body_finish(body_id as i32), SUCCESS);
    assert!(state.finish_requested());
    assert_eq!(ct_http_body_release(body_id as i32), SUCCESS);
}

#[test]
fn http2_handshake_surfaced_via_ffi() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http"],
                    "http":{
                        "alpn":["h2","http/1.1"]
                    }
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let (client_tx, client_rx) = std::sync::mpsc::channel();
    let (client_done_tx, client_done_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(&addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (_client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            client_tx.send(()).unwrap();
            tokio::spawn(async move {
                let _ = connection.await;
            });
            client_done_rx.recv().unwrap();
        })
    });

    client_rx.recv().unwrap();

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP2);

    let handle = ct_connection_take_http2_handshake(connection_id);
    assert!(handle > 0);

    let mut info = CtHttp2HandshakeInfo::default();
    assert_eq!(
        ct_http2_handshake_get(handle, &mut info as *mut CtHttp2HandshakeInfo),
        SUCCESS
    );
    unsafe {
        let protocol = std::str::from_utf8(std::slice::from_raw_parts(
            info.protocol_ptr,
            info.protocol_len,
        ))
        .unwrap();
        assert_eq!(protocol, "http/2");
        if info.alpn_len > 0 {
            let alpn =
                std::str::from_utf8(std::slice::from_raw_parts(info.alpn_ptr, info.alpn_len))
                    .unwrap();
            assert_eq!(alpn, "h2");
        } else {
            panic!("expected negotiated ALPN token");
        }
    }
    assert_eq!(info.listener_protocols_len, 3);

    let mut view = CtStringView::default();
    assert_eq!(
        ct_http2_handshake_listener_protocol(handle, 0, &mut view as *mut CtStringView),
        SUCCESS
    );
    unsafe {
        let value = std::str::from_utf8(std::slice::from_raw_parts(view.ptr, view.len)).unwrap();
        assert_eq!(value, "rawsocket");
    }
    assert_eq!(
        ct_http2_handshake_listener_protocol(handle, 1, &mut view as *mut CtStringView),
        SUCCESS
    );
    unsafe {
        let value = std::str::from_utf8(std::slice::from_raw_parts(view.ptr, view.len)).unwrap();
        assert_eq!(value, "http");
    }
    assert_eq!(
        ct_http2_handshake_listener_protocol(handle, 2, &mut view as *mut CtStringView),
        SUCCESS
    );
    unsafe {
        let value = std::str::from_utf8(std::slice::from_raw_parts(view.ptr, view.len)).unwrap();
        assert_eq!(value, "http2");
    }
    assert_eq!(
        ct_http2_handshake_listener_protocol(
            handle,
            info.listener_protocols_len,
            &mut view as *mut CtStringView
        ),
        ERR_INVALID_ARGUMENT
    );

    assert_eq!(ct_http2_handshake_release(handle), SUCCESS);
    client_done_tx.send(()).unwrap();
    client_handle.join().unwrap();
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http3_handshake_surfaced_via_ffi() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();
    let cert_der = certified.cert.der().to_vec();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["http/1.1","h2","h3"],
                    "http3":{"enabled":true,"port":0}
                },
                "http_routes":[
                    {
                        "path":"/metrics",
                        "methods":{
                            "POST":{
                                "type":"translation",
                                "realm":"realm.metrics",
                                "procedure":"connectanum.metrics.openmetrics"
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = require_http3_port(listener_id);

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let server_addr = addr.parse().unwrap();

        let mut roots = RootCertStore::empty();
        roots
            .add(CertificateDer::from(cert_der.clone()))
            .expect("add root cert");
        let client_config = build_http3_client_config(Arc::new(roots));

        let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
        endpoint.set_default_client_config(client_config);
        let connection = endpoint
            .connect(server_addr, "localhost")
            .expect("connect http3");
        let _connection = connection.await.expect("http3 handshake");
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP3);

    let handle = ct_connection_take_http3_handshake(connection_id);
    assert!(handle > 0);

    let mut info = CtHttp3HandshakeInfo::default();
    assert_eq!(
        ct_http3_handshake_get(handle, &mut info as *mut CtHttp3HandshakeInfo),
        SUCCESS
    );
    unsafe {
        let protocol = std::str::from_utf8(std::slice::from_raw_parts(
            info.protocol_ptr,
            info.protocol_len,
        ))
        .unwrap();
        assert_eq!(protocol, "http/3");
        if info.alpn_len > 0 {
            let alpn =
                std::str::from_utf8(std::slice::from_raw_parts(info.alpn_ptr, info.alpn_len))
                    .unwrap();
            assert_eq!(alpn, "h3");
        }
    }
    assert_eq!(info.listener_protocols_len, 4);

    let mut view = CtStringView::default();
    for index in 0..info.listener_protocols_len {
        assert_eq!(
            ct_http3_handshake_listener_protocol(handle, index, &mut view as *mut CtStringView),
            SUCCESS
        );
        unsafe {
            let value =
                std::str::from_utf8(std::slice::from_raw_parts(view.ptr, view.len)).unwrap();
            assert!(!value.is_empty());
        }
    }
    assert_eq!(
        ct_http3_handshake_listener_protocol(
            handle,
            info.listener_protocols_len,
            &mut view as *mut CtStringView,
        ),
        ERR_INVALID_ARGUMENT
    );

    let connection_handle = ct_connection_get_http3_connection(connection_id);
    assert!(connection_handle > 0);
    assert_eq!(ct_http3_connection_release(connection_handle), SUCCESS);

    assert_eq!(ct_http3_handshake_release(handle), SUCCESS);
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http3_multiple_connections_handshake() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();
    let cert_der = certified.cert.der().to_vec();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["h3","h2","http/1.1"],
                    "http3":{"enabled":true,"port":0}
                }
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = require_http3_port(listener_id);

    let connection_count = 5usize;
    let rt = TokioRuntime::new().unwrap();
    let client_connections = rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let server_addr = addr.parse().unwrap();

        let mut roots = RootCertStore::empty();
        roots
            .add(CertificateDer::from(cert_der.clone()))
            .expect("add root cert");
        let client_config = build_http3_client_config(Arc::new(roots));

        let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
        endpoint.set_default_client_config(client_config);
        let mut conns = Vec::with_capacity(connection_count);
        for _ in 0..connection_count {
            let connection = endpoint
                .connect(server_addr, "localhost")
                .expect("connect http3");
            let conn = connection.await.expect("http3 handshake");
            conns.push(conn);
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
        conns
    });

    for _ in 0..connection_count {
        let connection_id = ct_poll_connection(listener_id);
        assert!(connection_id > 0);
        assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP3);
        let handle = ct_connection_take_http3_handshake(connection_id);
        assert!(handle > 0);
        assert_eq!(ct_http3_handshake_release(handle), SUCCESS);
    }

    drop(client_connections);
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http3_stream_poll_returns_handle() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();
    let cert_der = certified.cert.der().to_vec();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["http/1.1","h2","h3"],
                    "http3":{"enabled":true,"port":0},
                    "routes":[
                        {
                            "match":{"path":"/metrics"},
                            "default":{
                                "type":"translation",
                                "realm":"realm.metrics",
                                "procedure":"connectanum.metrics.openmetrics"
                            }
                        }
                    ]
                }
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = require_http3_port(listener_id);

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let server_addr = addr.parse().unwrap();

        let mut roots = RootCertStore::empty();
        roots
            .add(CertificateDer::from(cert_der.clone()))
            .expect("add root cert");
        let client_config = build_http3_client_config(Arc::new(roots));

        let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
        endpoint.set_default_client_config(client_config);
        let connecting = endpoint
            .connect(server_addr, "localhost")
            .expect("connect http3");
        let connection = connecting.await.expect("http3 handshake");

        let (mut driver, mut sender) = h3_client::builder()
            .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
            .await
            .expect("build h3 client");
        tokio::spawn(async move {
            let _ = future::poll_fn(|cx| driver.poll_close(cx)).await;
        });

        let request = Request::post("https://localhost/metrics")
            .header("content-length", "0")
            .body(())
            .unwrap();
        let mut stream = sender
            .send_request(request)
            .await
            .expect("send http3 request");
        stream
            .send_data(Bytes::new())
            .await
            .expect("send empty body");
        stream.finish().await.expect("finish stream");
        tokio::time::sleep(Duration::from_millis(200)).await;
    });

    let connection_id = ct_poll_connection(listener_id);
    assert!(connection_id > 0);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP3);

    let connection_handle = ct_connection_get_http3_connection(connection_id);
    assert!(connection_handle > 0);
    assert_eq!(ct_http3_connection_release(connection_handle), SUCCESS);

    // Streams are no longer surfaced directly; poll should return 0.
    let stream_handle = ct_http3_connection_poll_stream(connection_id);
    assert_eq!(stream_handle, 0);

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[cfg(feature = "ffi-test")]
#[test]
fn http3_request_poll_returns_metadata() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["http/1.1","h2","h3"],
                    "http3":{"enabled":true,"port":0}
                },
                "http_routes":[
                    {
                        "path":"/metrics",
                        "methods":{
                            "POST":{
                                "type":"translation",
                                "realm":"realm.metrics",
                                "procedure":"connectanum.metrics.openmetrics"
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let connection_id = 1234;
    let protocol = CString::new("http/3").unwrap();
    let alpn = CString::new("h3").unwrap();
    let protocols = CString::new("rawsocket,http,http2,http3").unwrap();
    assert_eq!(
        ct_test_register_http3_connection(
            listener_id,
            connection_id,
            protocol.as_ptr(),
            alpn.as_ptr(),
            protocols.as_ptr(),
        ),
        SUCCESS
    );

    let method = CString::new("GET").unwrap();
    let target = CString::new("/metrics").unwrap();
    let header_name = CString::new("accept").unwrap();
    let header_value = CString::new("text/plain").unwrap();
    let ct_header = CtHttpHeader {
        name_ptr: header_name.as_ptr() as *const u8,
        name_len: header_name.as_bytes().len(),
        value_ptr: header_value.as_ptr() as *const u8,
        value_len: header_value.as_bytes().len(),
    };
    let realm = CString::new("realm.metrics").unwrap();
    let procedure = CString::new("connectanum.metrics.openmetrics").unwrap();
    assert_eq!(
        ct_test_register_http3_request(
            listener_id,
            connection_id,
            method.as_ptr(),
            target.as_ptr(),
            protocol.as_ptr(),
            &ct_header as *const CtHttpHeader,
            1,
            std::ptr::null(),
            0,
            realm.as_ptr(),
            procedure.as_ptr(),
        ),
        SUCCESS
    );

    let handle = ct_http3_connection_poll_request(connection_id);
    assert!(handle > 0);

    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let method_slice = std::slice::from_raw_parts(info.method_ptr, info.method_len);
        assert_eq!(std::str::from_utf8(method_slice).unwrap(), "GET");
        let path_slice = std::slice::from_raw_parts(info.path_ptr, info.path_len);
        assert_eq!(std::str::from_utf8(path_slice).unwrap(), "/metrics");
        let protocol_slice = std::slice::from_raw_parts(info.protocol_ptr, info.protocol_len);
        assert_eq!(std::str::from_utf8(protocol_slice).unwrap(), "http/3");
        let realm_slice = std::slice::from_raw_parts(info.realm_ptr, info.realm_len);
        assert_eq!(std::str::from_utf8(realm_slice).unwrap(), "realm.metrics");
    }
    assert_eq!(ct_http_handshake_release(handle), SUCCESS);
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http3_request_round_trip_over_network() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();
    let cert_der = certified.cert.der().to_vec();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["http/1.1","h2","h3"],
                    "http3":{"enabled":true,"port":0}
                },
                "http_routes":[
                    {
                        "path":"/metrics",
                        "methods":{
                            "POST":{
                                "type":"translation",
                                "realm":"realm.metrics",
                                "procedure":"connectanum.metrics.openmetrics"
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = require_http3_port(listener_id);

    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let server_addr = addr.parse().unwrap();

            let mut roots = RootCertStore::empty();
            roots
                .add(CertificateDer::from(cert_der.clone()))
                .expect("add root cert");
            let client_config = build_http3_client_config(Arc::new(roots));

            let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
            endpoint.set_default_client_config(client_config);
            let connecting = endpoint
                .connect(server_addr, "localhost")
                .expect("connect http3");
            let connection = connecting.await.expect("http3 handshake");

            let (mut driver, mut send_request) = h3_client::builder()
                .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
                .await
                .expect("build h3 client");
            tokio::spawn(async move {
                let _ = future::poll_fn(|cx| driver.poll_close(cx)).await;
            });

            let request = Request::post("https://localhost/metrics").body(()).unwrap();
            ready_tx.send(()).unwrap();
            let mut stream = send_request
                .send_request(request)
                .await
                .expect("send request");
            stream.finish().await.expect("finish request");
            let response = stream.recv_response().await.expect("recv response");
            let mut body = Vec::new();
            while let Some(chunk) = stream.recv_data().await.expect("recv body chunk") {
                let data = chunk.chunk();
                body.extend_from_slice(data);
            }
            (response.status().as_u16(), body)
        })
    });

    ready_rx.recv().expect("client ready");

    let connection_id = {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let id = ct_poll_connection(listener_id);
            if id > 0 {
                break id;
            }
            if Instant::now() > deadline {
                panic!("timed out waiting for HTTP/3 connection");
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    };
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP3);

    let request_handle = {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let handle = ct_http3_connection_poll_request(connection_id);
            if handle > 0 {
                break handle;
            }
            if Instant::now() > deadline {
                panic!("timed out waiting for HTTP/3 request");
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    };
    assert!(request_handle > 0);

    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(request_handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let path = std::slice::from_raw_parts(info.path_ptr, info.path_len);
        assert_eq!(std::str::from_utf8(path).unwrap(), "/metrics");
        let protocol = std::slice::from_raw_parts(info.protocol_ptr, info.protocol_len);
        assert_eq!(std::str::from_utf8(protocol).unwrap(), "http/3");
    }

    let body = b"{\"status\":\"ok\"}";
    assert_eq!(
        ct_http_response_send(
            request_handle,
            201,
            std::ptr::null(),
            0,
            body.as_ptr(),
            body.len(),
        ),
        SUCCESS
    );

    let (status, response_body) = client_handle.join().expect("client result");
    assert_eq!(status, 201);
    assert_eq!(response_body, body);

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http3_transport_auth_rejects_bearerless_route() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();
    let cert_der = certified.cert.der().to_vec();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["http/1.1","h2","h3"],
                    "http3":{"enabled":true,"port":0}
                },
                "http_routes":[
                    {
                        "path":"/secure",
                        "match_kind":"exact",
                        "transport_auth":{"require_bearer":true},
                        "methods":{
                            "GET":{
                                "type":"reserved_realm",
                                "append_method_suffix":true
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = require_http3_port(listener_id);

    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let server_addr = addr.parse().unwrap();

            let mut roots = RootCertStore::empty();
            roots
                .add(CertificateDer::from(cert_der.clone()))
                .expect("add root cert");
            let client_config = build_http3_client_config(Arc::new(roots));

            let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
            endpoint.set_default_client_config(client_config);
            let connecting = endpoint
                .connect(server_addr, "localhost")
                .expect("connect http3");
            let connection = connecting.await.expect("http3 handshake");

            let (mut driver, mut send_request) = h3_client::builder()
                .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
                .await
                .expect("build h3 client");
            tokio::spawn(async move {
                let _ = future::poll_fn(|cx| driver.poll_close(cx)).await;
            });

            let request = Request::get("https://localhost/secure").body(()).unwrap();
            let mut stream = send_request
                .send_request(request)
                .await
                .expect("send request");
            stream.finish().await.expect("finish request");
            let response = stream.recv_response().await.expect("recv response");
            let header = response
                .headers()
                .get("www-authenticate")
                .and_then(|value| value.to_str().ok())
                .map(|value| value.to_string());
            (response.status().as_u16(), header)
        })
    });

    let (status, auth_header) = client_handle.join().expect("client result");
    assert_eq!(status, 401);
    assert_eq!(auth_header.as_deref(), Some("Bearer"));

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http3_response_streaming_round_trip() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();
    let cert_der = certified.cert.der().to_vec();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["http/1.1","h2","h3"],
                    "http3":{"enabled":true,"port":0}
                },
                "http_routes":[
                    {
                        "path":"/h3stream",
                        "match_kind":"prefix",
                        "methods":{
                            "GET":{
                                "type":"reserved_realm",
                                "append_method_suffix":true
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = require_http3_port(listener_id);

    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let chunk = vec![b'r'; 24 * 1024];
    let chunk_count = 3;
    let trailer = b"h3-stream-finished";
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let server_addr = addr.parse().unwrap();

            let mut roots = RootCertStore::empty();
            roots
                .add(CertificateDer::from(cert_der.clone()))
                .expect("add root cert");
            let client_config = build_http3_client_config(Arc::new(roots));

            let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
            endpoint.set_default_client_config(client_config);
            let connecting = endpoint
                .connect(server_addr, "localhost")
                .expect("connect http3");
            let connection = connecting.await.expect("http3 handshake");

            let (mut driver, mut send_request) = h3_client::builder()
                .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
                .await
                .expect("build h3 client");
            tokio::spawn(async move {
                let _ = future::poll_fn(|cx| driver.poll_close(cx)).await;
            });

            let request = Request::get("https://localhost/h3stream").body(()).unwrap();
            ready_tx.send(()).unwrap();
            let mut stream = send_request
                .send_request(request)
                .await
                .expect("send request");
            stream.finish().await.expect("finish sending request body");
            let response = stream.recv_response().await.expect("recv response");
            let mut body = Vec::new();
            while let Some(chunk) = stream.recv_data().await.expect("recv data") {
                let data = chunk.chunk();
                body.extend_from_slice(data);
            }
            (response.status().as_u16(), body)
        })
    });

    ready_rx.recv().expect("client ready");

    let connection_id = {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let id = ct_poll_connection(listener_id);
            if id > 0 {
                break id;
            }
            if Instant::now() > deadline {
                panic!("timed out waiting for HTTP/3 connection");
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    };
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP3);

    let request_handle = {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let handle = ct_http3_connection_poll_request(connection_id);
            if handle > 0 {
                break handle;
            }
            if Instant::now() > deadline {
                panic!("timed out waiting for HTTP/3 request");
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    };
    assert!(request_handle > 0);

    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(request_handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let path = std::slice::from_raw_parts(info.path_ptr, info.path_len);
        assert_eq!(std::str::from_utf8(path).unwrap(), "/h3stream");
        let protocol = std::slice::from_raw_parts(info.protocol_ptr, info.protocol_len);
        assert_eq!(std::str::from_utf8(protocol).unwrap(), "http/3");
    }

    let header_name = CString::new("content-type").unwrap();
    let header_value = CString::new("application/octet-stream").unwrap();
    let headers = [CtHttpHeader {
        name_ptr: header_name.as_ptr() as *const u8,
        name_len: header_name.as_bytes().len(),
        value_ptr: header_value.as_ptr() as *const u8,
        value_len: header_value.as_bytes().len(),
    }];

    let stream_handle =
        ct_http_response_stream_open(request_handle, 206, headers.as_ptr(), headers.len());
    assert!(stream_handle > 0);

    for _ in 0..chunk_count {
        assert_eq!(
            ct_http_response_stream_write(stream_handle, chunk.as_ptr(), chunk.len()),
            SUCCESS
        );
    }
    assert_eq!(
        ct_http_response_stream_write(stream_handle, trailer.as_ptr(), trailer.len()),
        SUCCESS
    );
    assert_eq!(ct_http_response_stream_finish(stream_handle), SUCCESS);
    assert_eq!(ct_http_handshake_release(request_handle), SUCCESS);

    let (status, response_body) = client_handle.join().expect("client result");
    assert_eq!(status, 206);
    let expected_len = chunk.len() * chunk_count + trailer.len();
    assert_eq!(response_body.len(), expected_len);
    assert!(response_body[..chunk.len()]
        .iter()
        .all(|byte| *byte == b'r'));
    assert!(response_body.ends_with(trailer));

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http2_body_timeout_emits_connection_event() {
    let _guard = super::test_guard();
    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"disabled",
                "idle_timeout_ms":250,
                "protocols":["rawsocket","http","http2"],
                "http":{
                    "alpn":["h2"]
                },
                "http_routes":[
                    {
                        "path":"/metrics",
                        "methods":{
                            "POST":{
                                "type":"translation",
                                "realm":"realm.metrics",
                                "procedure":"connectanum.metrics.openmetrics"
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config = CString::new(config_json.to_string()).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);
    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (mut client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            tokio::spawn(async move {
                let _ = connection.await;
            });

            let request = Http2TestRequest::builder()
                .method("POST")
                .uri("https://localhost/metrics")
                .header("content-length", "1024")
                .body(())
                .unwrap();
            let (_response, mut send_stream) = client.send_request(request, false).unwrap();
            ready_tx.send(()).unwrap();

            // Keep the body flowing often enough that the stream stays below the
            // configured idle timeout, then hold it open long enough to cross
            // the derived total-body timeout under full-suite load.
            let start = Instant::now();
            while start.elapsed() < Duration::from_millis(1200) {
                if send_stream
                    .send_data(Bytes::copy_from_slice(&[b'x']), false)
                    .is_err()
                {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        })
    });

    ready_rx.recv().expect("client ready");

    let (event, _detail) = wait_for_http_event(Duration::from_secs(5));
    assert!(event.connection_id > 0);
    assert_eq!(event.protocol, PROTOCOL_HTTP2);
    assert_eq!(event.reason, HTTP_EVENT_REASON_BODY_TIMEOUT);
    assert!(event.request_count >= 1);
    assert_eq!(event.backpressure_events, 0);
    assert_eq!(event.max_backpressure_depth, 0);
    assert_eq!(event.goaway_events, 1);

    client_handle.join().expect("client thread finished");
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http2_idle_timeout_emits_connection_event() {
    let _guard = super::test_guard();
    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"disabled",
                "idle_timeout_ms":50,
                "protocols":["rawsocket","http","http2"],
                "http":{
                    "alpn":["h2"]
                },
                "http_routes":[
                    {
                        "path":"/metrics",
                        "methods":{
                            "POST":{
                                "type":"translation",
                                "realm":"realm.metrics",
                                "procedure":"connectanum.metrics.openmetrics"
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config = CString::new(config_json.to_string()).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);
    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (mut client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            tokio::spawn(async move {
                let _ = connection.await;
            });

            let request = Http2TestRequest::builder()
                .method("POST")
                .uri("https://localhost/metrics")
                .header("content-length", "1024")
                .body(())
                .unwrap();
            let (_response, _send_stream) = client.send_request(request, false).unwrap();
            ready_tx.send(()).unwrap();

            // Hold the QUIC connection open long enough for the server to
            // surface the accepted connection and observe the configured idle
            // timeout even under full-suite load.
            tokio::time::sleep(Duration::from_secs(1)).await;
        })
    });

    ready_rx.recv().expect("client ready");

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP2);

    let handshake_handle = wait_for_http_handshake(connection_id);
    assert_eq!(ct_http_handshake_release(handshake_handle), SUCCESS);

    let (event, detail) = wait_for_http_event(Duration::from_secs(5));
    assert_eq!(event.connection_id, connection_id);
    assert_eq!(event.protocol, PROTOCOL_HTTP2);
    assert_eq!(event.reason, HTTP_EVENT_REASON_IDLE_TIMEOUT);
    assert_eq!(event.idle_timeouts, 1);
    assert_eq!(event.body_timeouts, 0);
    assert!(event.request_count >= 1);
    assert_eq!(event.backpressure_events, 0);
    assert_eq!(event.max_backpressure_depth, 0);
    assert_eq!(event.goaway_events, 1);
    assert_eq!(detail.as_deref(), Some("http/2 body idle timeout"));

    client_handle.join().expect("client thread finished");
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http3_body_timeout_emits_connection_event() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();
    let cert_der = certified.cert.der().to_vec();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "idle_timeout_ms":250,
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["http/1.1","h2","h3"],
                    "http3":{"enabled":true,"port":0}
                },
                "http_routes":[
                    {
                        "path":"/metrics",
                        "methods":{
                            "POST":{
                                "type":"translation",
                                "realm":"realm.metrics",
                                "procedure":"connectanum.metrics.openmetrics"
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = require_http3_port(listener_id);

    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let server_addr = addr.parse().unwrap();

            let mut roots = RootCertStore::empty();
            roots
                .add(CertificateDer::from(cert_der.clone()))
                .expect("add root cert");
            let client_config = build_http3_client_config(Arc::new(roots));

            let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
            endpoint.set_default_client_config(client_config);
            let connecting = endpoint
                .connect(server_addr, "localhost")
                .expect("connect http3");
            let connection = connecting.await.expect("http3 handshake");

            let (mut driver, mut sender) = h3_client::builder()
                .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
                .await
                .expect("build h3 client");
            tokio::spawn(async move {
                let _ = future::poll_fn(|cx| driver.poll_close(cx)).await;
            });

            let request = Request::post("https://localhost/metrics")
                .header("content-length", "1024")
                .body(())
                .unwrap();
            let mut stream = sender
                .send_request(request)
                .await
                .expect("send http3 request");
            ready_tx.send(()).unwrap();

            // Keep the body flowing often enough that the stream stays below the
            // configured idle timeout, then hold it open long enough to cross
            // the derived total-body timeout under full-suite load.
            let start = Instant::now();
            while start.elapsed() < Duration::from_millis(1200) {
                if stream
                    .send_data(Bytes::copy_from_slice(&[b'x']))
                    .await
                    .is_err()
                {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            let _ = stream.finish().await;
            tokio::time::sleep(Duration::from_millis(100)).await;
        })
    });

    ready_rx.recv().expect("client ready");

    let (event, detail) = wait_for_http_event(Duration::from_secs(5));
    assert!(event.connection_id > 0);
    assert_eq!(event.protocol, PROTOCOL_HTTP3);
    assert_eq!(event.reason, HTTP_EVENT_REASON_BODY_TIMEOUT);
    assert_eq!(event.idle_timeouts, 0);
    assert_eq!(event.body_timeouts, 1);
    assert!(event.request_count >= 1);
    assert_eq!(event.backpressure_events, 0);
    assert_eq!(event.max_backpressure_depth, 0);
    assert_eq!(event.goaway_events, 1);
    assert_eq!(detail.as_deref(), Some("http/3 body total timeout"));

    client_handle.join().expect("client thread finished");
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http3_idle_timeout_emits_connection_event() {
    let _guard = super::test_guard();
    let certified =
        generate_simple_self_signed(vec!["localhost".into(), "127.0.0.1".into()]).unwrap();
    let cert_pem = certified.cert.pem();
    let key_pem = certified.key_pair.serialize_pem();
    let cert_der = certified.cert.der().to_vec();

    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
                "idle_timeout_ms":50,
                "protocols":["rawsocket","http","http2","http3"],
                "sni_certificates":[
                    {
                        "hostname":"localhost",
                        "certificate_chain_pem":cert_pem,
                        "private_key_pem":key_pem
                    }
                ],
                "http":{
                    "alpn":["http/1.1","h2","h3"],
                    "http3":{"enabled":true,"port":0}
                },
                "http_routes":[
                    {
                        "path":"/metrics",
                        "methods":{
                            "POST":{
                                "type":"translation",
                                "realm":"realm.metrics",
                                "procedure":"connectanum.metrics.openmetrics"
                            }
                        }
                    }
                ]
            }
        ]
    });
    let config_string = config_json.to_string();
    let config = CString::new(config_string).unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = require_http3_port(listener_id);

    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let server_addr = addr.parse().unwrap();

            let mut roots = RootCertStore::empty();
            roots
                .add(CertificateDer::from(cert_der.clone()))
                .expect("add root cert");
            let client_config = build_http3_client_config(Arc::new(roots));

            let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
            endpoint.set_default_client_config(client_config);
            let connecting = endpoint
                .connect(server_addr, "localhost")
                .expect("connect http3");
            let connection = connecting.await.expect("http3 handshake");

            let (mut driver, mut sender) = h3_client::builder()
                .build::<_, _, Bytes>(H3QuinnConnection::new(connection))
                .await
                .expect("build h3 client");
            tokio::spawn(async move {
                let _ = future::poll_fn(|cx| driver.poll_close(cx)).await;
            });

            let request = Request::post("https://localhost/metrics")
                .header("content-length", "1024")
                .body(())
                .unwrap();
            let _stream = sender
                .send_request(request)
                .await
                .expect("send http3 request");
            ready_tx.send(()).unwrap();

            tokio::time::sleep(Duration::from_millis(200)).await;
        })
    });

    ready_rx.recv().expect("client ready");

    let (event, detail) = wait_for_http_event(Duration::from_secs(5));
    assert!(event.connection_id > 0);
    assert_eq!(event.protocol, PROTOCOL_HTTP3);
    assert_eq!(event.reason, HTTP_EVENT_REASON_IDLE_TIMEOUT);
    assert_eq!(event.idle_timeouts, 1);
    assert_eq!(event.body_timeouts, 0);
    assert!(event.request_count >= 1);
    assert_eq!(event.backpressure_events, 0);
    assert_eq!(event.max_backpressure_depth, 0);
    assert_eq!(event.goaway_events, 1);
    assert_eq!(detail.as_deref(), Some("http/3 body idle timeout"));

    client_handle.join().expect("client thread finished");
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[cfg(feature = "ffi-test")]
#[test]
fn http2_goaway_event_includes_detail() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"native",
                    "protocols":["rawsocket","http","http2","http3"],
                    "http":{"alpn":["http/1.1","h2","h3"],"http3":{"enabled":true}},
                    "http_routes":[]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let detail = CString::new("remote http/2 GOAWAY: too_many_streams").unwrap();
    let detail_bytes = detail.as_bytes();
    let connection_id = 5151;
    assert_eq!(
        ct_test_push_http_connection_event(
            connection_id,
            1,
            PROTOCOL_HTTP2,
            HTTP_EVENT_REASON_GOAWAY,
            2,
            0,
            0,
            0,
            0,
            1,
            detail.as_ptr(),
            detail_bytes.len() as i32,
        ),
        SUCCESS
    );

    let (event, retrieved_detail) = wait_for_http_event(Duration::from_secs(5));
    assert_eq!(event.connection_id, connection_id);
    assert_eq!(event.protocol, PROTOCOL_HTTP2);
    assert_eq!(event.reason, HTTP_EVENT_REASON_GOAWAY);
    assert_eq!(event.goaway_events, 1);
    assert_eq!(event.request_count, 2);
    assert_eq!(
        retrieved_detail.as_deref(),
        Some("remote http/2 GOAWAY: too_many_streams")
    );

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[cfg(feature = "ffi-test")]
#[test]
fn http3_idle_timeout_event_push_includes_detail() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"native",
                    "protocols":["rawsocket","http","http2","http3"],
                    "http":{"alpn":["http/1.1","h2","h3"],"http3":{"enabled":true}},
                    "http_routes":[]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let detail = CString::new("http/3 body idle timeout").unwrap();
    let detail_bytes = detail.as_bytes();
    let connection_id = 4242;
    assert_eq!(
        ct_test_push_http_connection_event(
            connection_id,
            1,
            PROTOCOL_HTTP3,
            HTTP_EVENT_REASON_IDLE_TIMEOUT,
            1,
            1,
            0,
            0,
            0,
            0,
            detail.as_ptr(),
            detail_bytes.len() as i32,
        ),
        SUCCESS
    );

    let (event, retrieved_detail) = wait_for_http_event(Duration::from_secs(5));
    assert_eq!(event.connection_id, connection_id);
    assert_eq!(event.protocol, PROTOCOL_HTTP3);
    assert_eq!(event.reason, HTTP_EVENT_REASON_IDLE_TIMEOUT);
    assert_eq!(event.idle_timeouts, 1);
    assert_eq!(event.backpressure_events, 0);
    assert_eq!(event.max_backpressure_depth, 0);
    assert_eq!(event.goaway_events, 1);
    assert_eq!(
        retrieved_detail.as_deref(),
        Some("http/3 body idle timeout")
    );

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[cfg(feature = "ffi-test")]
#[test]
fn http3_goaway_event_includes_detail() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"native",
                    "protocols":["rawsocket","http","http2","http3"],
                    "http":{"alpn":["http/1.1","h2","h3"],"http3":{"enabled":true}},
                    "http_routes":[]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let detail = CString::new("remote http/3 GOAWAY: idle").unwrap();
    let detail_bytes = detail.as_bytes();
    let connection_id = 5252;
    assert_eq!(
        ct_test_push_http_connection_event(
            connection_id,
            1,
            PROTOCOL_HTTP3,
            HTTP_EVENT_REASON_GOAWAY,
            1,
            0,
            0,
            0,
            0,
            1,
            detail.as_ptr(),
            detail_bytes.len() as i32,
        ),
        SUCCESS
    );

    let (event, retrieved_detail) = wait_for_http_event(Duration::from_secs(5));
    assert_eq!(event.connection_id, connection_id);
    assert_eq!(event.protocol, PROTOCOL_HTTP3);
    assert_eq!(event.reason, HTTP_EVENT_REASON_GOAWAY);
    assert_eq!(event.goaway_events, 1);
    assert_eq!(
        retrieved_detail.as_deref(),
        Some("remote http/3 GOAWAY: idle")
    );

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http2_request_round_trip_over_network() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http","http2"],
                    "http":{
                        "alpn":["h2","http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/h2",
                            "match_kind":"prefix",
                            "methods":{
                                "POST":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let (client_tx, client_rx) = std::sync::mpsc::channel();
    let body_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(&addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (mut client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            tokio::spawn(async move {
                if let Err(err) = connection.await {
                    panic!("h2 connection error: {}", err);
                }
            });
            let request = Http2TestRequest::builder()
                .method("POST")
                .uri("/h2")
                .header("content-length", "4")
                .body(())
                .unwrap();
            let (response, mut send_stream) = client.send_request(request, false).unwrap();
            send_stream
                .send_data(Bytes::from_static(b"ping"), true)
                .unwrap();
            client_tx.send(()).unwrap();
            let response = response.await.unwrap();
            assert_eq!(response.status(), Http2StatusCode::OK);
            let mut body = response.into_body();
            let mut collected = Vec::new();
            while let Some(chunk) = body.data().await {
                let chunk = chunk.unwrap();
                collected.extend_from_slice(&chunk);
            }
            collected
        })
    });

    client_rx.recv().unwrap();

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP2);

    let deadline = Instant::now() + Duration::from_secs(5);
    let handle = loop {
        let handle = ct_connection_take_http_handshake(connection_id);
        if handle > 0 {
            break handle;
        }
        assert!(
            Instant::now() < deadline,
            "timed out waiting for HTTP/2 handshake"
        );
        std::thread::sleep(Duration::from_millis(10));
    };

    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let method =
            std::str::from_utf8(std::slice::from_raw_parts(info.method_ptr, info.method_len))
                .expect("method utf8");
        assert_eq!(method, "POST");
        let path = std::str::from_utf8(std::slice::from_raw_parts(info.path_ptr, info.path_len))
            .expect("path utf8");
        assert_eq!(path, "/h2");
        let protocol = std::str::from_utf8(std::slice::from_raw_parts(
            info.protocol_ptr,
            info.protocol_len,
        ))
        .expect("protocol utf8");
        assert_eq!(protocol, "http/2");
    }

    let body = b"pong";
    assert_eq!(
        ct_http_response_send(handle, 200, std::ptr::null(), 0, body.as_ptr(), body.len(),),
        SUCCESS,
    );
    assert_eq!(ct_http_handshake_release(handle), SUCCESS);

    let response_body = body_handle.join().unwrap();
    assert_eq!(response_body, b"pong");

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http2_transport_auth_rejects_bearerless_route() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http","http2"],
                    "http":{
                        "alpn":["h2","http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/secure",
                            "match_kind":"exact",
                            "transport_auth":{"require_bearer":true},
                            "methods":{
                                "GET":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(&addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (mut client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            tokio::spawn(async move {
                if let Err(err) = connection.await {
                    panic!("h2 connection error: {}", err);
                }
            });
            let request = Http2TestRequest::builder()
                .method("GET")
                .uri("/secure")
                .body(())
                .unwrap();
            let (response, _) = client.send_request(request, true).unwrap();
            let response = response.await.unwrap();
            let header = response
                .headers()
                .get("www-authenticate")
                .and_then(|value| value.to_str().ok())
                .map(|value| value.to_string());
            (response.status().as_u16(), header)
        })
    });

    let (status, auth_header) = client_handle.join().expect("client result");
    assert_eq!(status, 401);
    assert_eq!(auth_header.as_deref(), Some("Bearer"));

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http2_large_headers_survive_continuation_frames() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http","http2"],
                    "http":{
                        "alpn":["h2","http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/h2headers",
                            "match_kind":"prefix",
                            "methods":{
                                "GET":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let large_header_value = "a".repeat(96 * 1024);
    let expected_len = large_header_value.len();
    let (client_tx, client_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(&addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (mut client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            tokio::spawn(async move {
                if let Err(err) = connection.await {
                    panic!("h2 connection error: {}", err);
                }
            });
            let request = Http2TestRequest::builder()
                .method("GET")
                .uri("/h2headers?fragmented=true")
                .header("x-long", large_header_value)
                .body(())
                .unwrap();
            let (response, _send_stream) = client.send_request(request, true).unwrap();
            client_tx.send(()).unwrap();
            let response = response.await.unwrap();
            assert_eq!(response.status(), Http2StatusCode::OK);
            let mut body = response.into_body();
            let mut collected = Vec::new();
            while let Some(chunk) = body.data().await {
                let chunk = chunk.unwrap();
                body.flow_control()
                    .release_capacity(chunk.len())
                    .expect("release capacity");
                collected.extend_from_slice(&chunk);
            }
            collected
        })
    });

    client_rx.recv().unwrap();

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP2);

    let handle = wait_for_http_handshake(connection_id);
    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let target =
            std::str::from_utf8(std::slice::from_raw_parts(info.target_ptr, info.target_len))
                .expect("target utf8");
        assert_eq!(target, "/h2headers?fragmented=true");
    }

    let mut found_large_header = false;
    for index in 0..info.headers_len {
        let mut header = CtHttpHeader::default();
        assert_eq!(
            ct_http_handshake_header(handle, index, &mut header as *mut CtHttpHeader),
            SUCCESS
        );
        unsafe {
            let name =
                std::str::from_utf8(std::slice::from_raw_parts(header.name_ptr, header.name_len))
                    .expect("header name utf8");
            let value = std::str::from_utf8(std::slice::from_raw_parts(
                header.value_ptr,
                header.value_len,
            ))
            .expect("header value utf8");
            if name.eq_ignore_ascii_case("x-long") {
                assert_eq!(value.len(), expected_len);
                assert!(value.as_bytes().iter().all(|byte| *byte == b'a'));
                found_large_header = true;
                break;
            }
        }
    }
    assert!(
        found_large_header,
        "expected fragmented header to be surfaced"
    );

    let response_body = b"h2-continuation-ok";
    assert_eq!(
        ct_http_response_send(
            handle,
            200,
            std::ptr::null(),
            0,
            response_body.as_ptr(),
            response_body.len(),
        ),
        SUCCESS
    );
    assert_eq!(ct_http_handshake_release(handle), SUCCESS);

    let body = client_handle.join().unwrap();
    assert_eq!(body, response_body);

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http2_accepts_multiple_streams_before_first_response_finishes() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http","http2"],
                    "http":{
                        "alpn":["h2","http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/h2multi",
                            "match_kind":"prefix",
                            "methods":{
                                "GET":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let (client_tx, client_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(&addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            tokio::spawn(async move {
                if let Err(err) = connection.await {
                    panic!("h2 connection error: {}", err);
                }
            });

            let mut client_one = client;
            let mut client_two = client_one.clone();
            let first = async move {
                let request = Http2TestRequest::builder()
                    .method("GET")
                    .uri("/h2multi?stream=1")
                    .body(())
                    .unwrap();
                let (response, _send_stream) = client_one.send_request(request, true).unwrap();
                let response = response.await.unwrap();
                assert_eq!(response.status(), Http2StatusCode::OK);
                let mut body = response.into_body();
                let mut collected = Vec::new();
                while let Some(chunk) = body.data().await {
                    let chunk = chunk.unwrap();
                    body.flow_control()
                        .release_capacity(chunk.len())
                        .expect("release capacity");
                    collected.extend_from_slice(&chunk);
                }
                collected
            };
            let second = async move {
                let request = Http2TestRequest::builder()
                    .method("GET")
                    .uri("/h2multi?stream=2")
                    .body(())
                    .unwrap();
                let (response, _send_stream) = client_two.send_request(request, true).unwrap();
                let response = response.await.unwrap();
                assert_eq!(response.status(), Http2StatusCode::OK);
                let mut body = response.into_body();
                let mut collected = Vec::new();
                while let Some(chunk) = body.data().await {
                    let chunk = chunk.unwrap();
                    body.flow_control()
                        .release_capacity(chunk.len())
                        .expect("release capacity");
                    collected.extend_from_slice(&chunk);
                }
                collected
            };

            client_tx.send(()).unwrap();
            tokio::join!(first, second)
        })
    });

    client_rx.recv().unwrap();

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP2);

    let handles = wait_for_http_handshakes(connection_id, 2, Duration::from_secs(5));
    let mut seen_targets = Vec::with_capacity(handles.len());
    for handle in handles {
        let mut info = CtHttpHandshakeInfo::default();
        assert_eq!(
            ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
            SUCCESS
        );
        let target = unsafe {
            std::str::from_utf8(std::slice::from_raw_parts(info.target_ptr, info.target_len))
                .expect("target utf8")
                .to_string()
        };
        let response_body = match target.as_str() {
            "/h2multi?stream=1" => b"stream-one".as_slice(),
            "/h2multi?stream=2" => b"stream-two".as_slice(),
            other => panic!("unexpected target {other}"),
        };
        assert_eq!(
            ct_http_response_send(
                handle,
                200,
                std::ptr::null(),
                0,
                response_body.as_ptr(),
                response_body.len(),
            ),
            SUCCESS
        );
        assert_eq!(ct_http_handshake_release(handle), SUCCESS);
        seen_targets.push(target);
    }
    seen_targets.sort();
    assert_eq!(
        seen_targets,
        vec![
            "/h2multi?stream=1".to_string(),
            "/h2multi?stream=2".to_string(),
        ]
    );

    let (first_body, second_body) = client_handle.join().unwrap();
    assert_eq!(first_body, b"stream-one");
    assert_eq!(second_body, b"stream-two");

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http2_streaming_body_round_trip() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http","http2"],
                    "http":{
                        "alpn":["h2","http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/h2stream",
                            "match_kind":"prefix",
                            "methods":{
                                "POST":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let payload_len = 70_000;
    let (client_tx, client_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(&addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (mut client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            tokio::spawn(async move {
                if let Err(err) = connection.await {
                    panic!("h2 connection error: {}", err);
                }
            });
            let request = Http2TestRequest::builder()
                .method("POST")
                .uri("/h2stream")
                .header("content-length", payload_len.to_string())
                .body(())
                .unwrap();
            let (response, mut send_stream) = client.send_request(request, false).unwrap();
            let payload = vec![b'y'; payload_len];
            let first = 32 * 1024;
            send_stream
                .send_data(
                    Bytes::copy_from_slice(&payload[..first.min(payload.len())]),
                    false,
                )
                .unwrap();
            send_stream.reserve_capacity(payload_len - first.min(payload_len));
            client_tx.send(()).unwrap();
            tokio::time::sleep(Duration::from_millis(50)).await;
            if first < payload_len {
                send_stream
                    .send_data(Bytes::copy_from_slice(&payload[first..]), true)
                    .unwrap();
            } else {
                send_stream.send_data(Bytes::new(), true).unwrap();
            }
            let response = response.await.unwrap();
            assert_eq!(response.status(), Http2StatusCode::ACCEPTED);
            let mut body = response.into_body();
            let mut collected = Vec::new();
            while let Some(chunk) = body.data().await {
                let chunk = chunk.unwrap();
                collected.extend_from_slice(&chunk);
            }
            collected
        })
    });

    client_rx.recv().unwrap();

    let connection_id = loop {
        let connection_id = ct_poll_connection(listener_id);
        if connection_id > 0 {
            break connection_id;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP2);

    let deadline = Instant::now() + Duration::from_secs(5);
    let handle = loop {
        let handle = ct_connection_take_http_handshake(connection_id);
        if handle > 0 {
            break handle;
        }
        assert!(
            Instant::now() < deadline,
            "timed out waiting for HTTP/2 streaming request"
        );
        std::thread::sleep(Duration::from_millis(10));
    };

    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let protocol = std::str::from_utf8(std::slice::from_raw_parts(
            info.protocol_ptr,
            info.protocol_len,
        ))
        .expect("protocol utf8");
        assert_eq!(protocol, "http/2");
        let path = std::str::from_utf8(std::slice::from_raw_parts(info.path_ptr, info.path_len))
            .expect("path utf8");
        assert_eq!(path, "/h2stream");
        assert_eq!(info.body_len, payload_len);
    }

    let body_handle = ct_http_handshake_body_retain(handle);
    assert!(body_handle > 0);

    let mut view = CtHttpBodyView::default();
    assert_eq!(
        ct_http_body_get(body_handle, &mut view as *mut CtHttpBodyView),
        ERR_UNSUPPORTED
    );

    let mut collected = Vec::new();
    loop {
        assert_eq!(
            ct_http_body_stream_read(body_handle, 16 * 1024, &mut view as *mut CtHttpBodyView),
            SUCCESS
        );
        if view.data_len == 0 {
            break;
        }
        unsafe {
            let slice = std::slice::from_raw_parts(view.data_ptr, view.data_len);
            collected.extend_from_slice(slice);
        }
    }
    assert_eq!(collected.len(), payload_len);
    assert!(collected.iter().all(|byte| *byte == b'y'));

    assert_eq!(ct_http_body_finish(body_handle), SUCCESS);
    assert_eq!(ct_http_body_release(body_handle), SUCCESS);

    let response_body = b"h2-stream-ok";
    assert_eq!(
        ct_http_response_send(
            handle,
            202,
            std::ptr::null(),
            0,
            response_body.as_ptr(),
            response_body.len(),
        ),
        SUCCESS
    );
    assert_eq!(ct_http_handshake_release(handle), SUCCESS);

    let body = client_handle.join().unwrap();
    assert_eq!(body, response_body);

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http2_response_streaming_round_trip() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","http","http2"],
                    "http":{
                        "alpn":["h2","http/1.1"]
                    },
                    "http_routes":[
                        {
                            "path":"/h2stream",
                            "match_kind":"prefix",
                            "methods":{
                                "GET":{
                                    "type":"reserved_realm",
                                    "append_method_suffix":true
                                }
                            }
                        }
                    ]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let (client_tx, client_rx) = std::sync::mpsc::channel();
    let client_handle = std::thread::spawn(move || {
        let rt = TokioRuntime::new().unwrap();
        rt.block_on(async move {
            let addr = format!("127.0.0.1:{}", port);
            let tcp = tokio::net::TcpStream::connect(&addr).await.unwrap();
            let builder = http2_test_client_builder();
            let (mut client, connection) = builder.handshake::<_, Bytes>(tcp).await.unwrap();
            tokio::spawn(async move {
                if let Err(err) = connection.await {
                    panic!("h2 connection error: {}", err);
                }
            });
            let request = Http2TestRequest::builder()
                .method("GET")
                .uri("/h2stream")
                .body(())
                .unwrap();
            let (response, _send_stream) = client.send_request(request, true).unwrap();
            client_tx.send(()).unwrap();
            let response = response.await.unwrap();
            assert_eq!(response.status(), Http2StatusCode::PARTIAL_CONTENT);
            let mut body = response.into_body();
            let mut collected = Vec::new();
            while let Some(chunk) = body.data().await {
                let chunk = chunk.unwrap();
                body.flow_control()
                    .release_capacity(chunk.len())
                    .expect("release capacity");
                collected.extend_from_slice(&chunk);
            }
            collected
        })
    });

    client_rx.recv().unwrap();

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP2);

    let handle = wait_for_http_handshake(connection_id);
    let mut info = CtHttpHandshakeInfo::default();
    assert_eq!(
        ct_http_handshake_get(handle, &mut info as *mut CtHttpHandshakeInfo),
        SUCCESS
    );
    unsafe {
        let method =
            std::str::from_utf8(std::slice::from_raw_parts(info.method_ptr, info.method_len))
                .expect("method utf8");
        assert_eq!(method, "GET");
        let path = std::str::from_utf8(std::slice::from_raw_parts(info.path_ptr, info.path_len))
            .expect("path utf8");
        assert_eq!(path, "/h2stream");
        let protocol = std::str::from_utf8(std::slice::from_raw_parts(
            info.protocol_ptr,
            info.protocol_len,
        ))
        .expect("protocol utf8");
        assert_eq!(protocol, "http/2");
    }

    let header_name = CString::new("content-type").unwrap();
    let header_value = CString::new("application/octet-stream").unwrap();
    let headers = [CtHttpHeader {
        name_ptr: header_name.as_ptr() as *const u8,
        name_len: header_name.as_bytes().len(),
        value_ptr: header_value.as_ptr() as *const u8,
        value_len: header_value.as_bytes().len(),
    }];

    let stream_handle = ct_http_response_stream_open(handle, 206, headers.as_ptr(), headers.len());
    assert!(stream_handle > 0);

    let chunk = vec![b'z'; 16 * 1024];
    let chunk_count = 5;
    for _ in 0..chunk_count {
        assert_eq!(
            ct_http_response_stream_write(stream_handle, chunk.as_ptr(), chunk.len()),
            SUCCESS
        );
    }
    let trailer = b"h2-stream-finished";
    assert_eq!(
        ct_http_response_stream_write(stream_handle, trailer.as_ptr(), trailer.len()),
        SUCCESS
    );
    assert_eq!(ct_http_response_stream_finish(stream_handle), SUCCESS);
    assert_eq!(ct_http_handshake_release(handle), SUCCESS);

    let response_body = client_handle.join().unwrap();
    let expected_len = chunk.len() * chunk_count + trailer.len();
    assert_eq!(response_body.len(), expected_len);
    assert!(response_body
        .iter()
        .take(chunk.len())
        .all(|byte| *byte == b'z'));
    assert!(response_body.ends_with(trailer));

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn websocket_handshake_surfaced_via_ffi() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","websocket","http"],
                    "http":{
                        "alpn":["http/1.1"]
                    }
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        stream
            .write_all(
                b"GET /ws/chat HTTP/1.1\r\n\
Host: localhost\r\n\
Upgrade: websocket\r\n\
Connection: Upgrade\r\n\
Sec-WebSocket-Key: SGVsbG9OZkZJ\r\n\
Sec-WebSocket-Version: 13\r\n\
Sec-WebSocket-Protocol: wamp.2.json, wamp.2.cbor\r\n\
Sec-WebSocket-Extensions: permessage-deflate\r\n\r\n",
            )
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_WEBSOCKET);

    let handle = ct_connection_take_websocket_handshake(connection_id);
    assert!(handle > 0);

    let mut info = CtWebSocketHandshakeInfo::default();
    assert_eq!(
        ct_websocket_handshake_get(handle, &mut info as *mut CtWebSocketHandshakeInfo),
        SUCCESS
    );

    unsafe {
        let key =
            std::str::from_utf8(std::slice::from_raw_parts(info.key_ptr, info.key_len)).unwrap();
        assert_eq!(key, "SGVsbG9OZkZJ");

        let method = std::str::from_utf8(std::slice::from_raw_parts(
            info.http_info.method_ptr,
            info.http_info.method_len,
        ))
        .unwrap();
        assert_eq!(method, "GET");

        let target = std::str::from_utf8(std::slice::from_raw_parts(
            info.http_info.target_ptr,
            info.http_info.target_len,
        ))
        .unwrap();
        assert_eq!(target, "/ws/chat");
    }
    assert_eq!(info.protocols_len, 2);
    assert_eq!(info.extensions_len, 1);

    let mut view = CtStringView::default();
    assert_eq!(
        ct_websocket_handshake_protocol(handle, 0, &mut view as *mut CtStringView),
        SUCCESS
    );
    unsafe {
        let value = std::str::from_utf8(std::slice::from_raw_parts(view.ptr, view.len)).unwrap();
        assert_eq!(value, "wamp.2.json");
    }

    assert_eq!(
        ct_websocket_handshake_extension(handle, 0, &mut view as *mut CtStringView),
        SUCCESS
    );
    unsafe {
        let value = std::str::from_utf8(std::slice::from_raw_parts(view.ptr, view.len)).unwrap();
        assert_eq!(value, "permessage-deflate");
    }

    assert_eq!(
        ct_websocket_handshake_protocol(handle, 5, &mut view as *mut CtStringView),
        ERR_INVALID_ARGUMENT
    );

    assert_eq!(ct_websocket_handshake_release(handle), SUCCESS);
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn websocket_wamp_round_trip() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket","websocket","http"],
                    "websocket_path":"/ws",
                    "http":{
                        "alpn":["http/1.1"]
                    }
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    let mut stream = rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        send_websocket_handshake(&mut stream, "/ws").await;
        stream
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_WEBSOCKET);

    let handshake_handle = ct_connection_take_websocket_handshake(connection_id);
    assert!(handshake_handle > 0);
    let protocol = CString::new("wamp.2.json").unwrap();
    assert_eq!(
        ct_connection_accept_websocket(
            connection_id,
            handshake_handle,
            1,
            protocol.as_ptr(),
            protocol.as_bytes().len() as i32
        ),
        SUCCESS
    );

    let mut protocol_len: i32 = 0;
    assert_eq!(
        ct_connection_websocket_protocol(connection_id, std::ptr::null_mut(), &mut protocol_len),
        SUCCESS
    );
    assert_eq!(protocol_len, "wamp.2.json".len() as i32);

    let mut buffer = vec![0u8; protocol_len as usize];
    let mut buffer_len = protocol_len;
    assert_eq!(
        ct_connection_websocket_protocol(connection_id, buffer.as_mut_ptr(), &mut buffer_len),
        SUCCESS
    );
    assert_eq!(buffer_len, protocol_len);
    let negotiated =
        std::str::from_utf8(&buffer[..buffer_len as usize]).expect("utf8 websocket protocol");
    assert_eq!(negotiated, "wamp.2.json");

    rt.block_on(async {
        let response = read_http_response_until_body(&mut stream).await;
        assert!(
            response.starts_with("HTTP/1.1 101"),
            "handshake response: {}",
            response
        );
        assert!(
            response
                .to_ascii_lowercase()
                .contains("sec-websocket-protocol: wamp.2.json"),
            "handshake response missing subprotocol: {}",
            response
        );
    });

    let hello = serde_json::to_vec(&json!([
        1,
        "realm:default",
        {
            "roles": {
                "publisher": {},
                "subscriber": {}
            }
        }
    ]))
    .unwrap();
    rt.block_on(async {
        send_client_websocket_frame(&mut stream, 0x1, &hello).await;
    });

    let message_handle = {
        let mut attempts = 0;
        loop {
            let handle = ct_poll_connection_message(connection_id);
            if handle > 0 {
                break handle;
            }
            attempts += 1;
            assert!(attempts < 100, "timed out waiting for websocket message");
            std::thread::sleep(Duration::from_millis(10));
        }
    };

    let mut info = CtMessageInfo::default();
    assert_eq!(
        ct_message_get(message_handle, &mut info as *mut CtMessageInfo),
        SUCCESS
    );
    assert_eq!(info.serializer, 1, "JSON serializer expected");
    assert_eq!(info.message_code, 1, "HELLO message expected");
    unsafe {
        let frame = std::slice::from_raw_parts(info.frame_ptr, info.frame_len);
        let parsed: serde_json::Value = serde_json::from_slice(frame).unwrap();
        assert_eq!(parsed[0], json!(1));
        assert_eq!(parsed[1], json!("realm:default"));
    }
    ct_message_release(message_handle);

    let welcome = serde_json::to_vec(&json!([2, 1, {}, {}])).unwrap();
    assert_eq!(
        ct_send_message(connection_id, welcome.as_ptr(), welcome.len() as i32),
        SUCCESS
    );

    let received = rt.block_on(async { read_server_websocket_frame(&mut stream).await });
    assert!(received.fin);
    assert_eq!(received.opcode, 0x1);
    let parsed: serde_json::Value = serde_json::from_slice(&received.payload).unwrap();
    assert_eq!(parsed[0], json!(2));
    assert_eq!(parsed[1], json!(1));

    // Client-to-server WebSocket frames must be masked. Unmasked payloads are
    // rejected with a protocol-error close frame.
    let unmasked_hello = serde_json::to_vec(&json!([
        1,
        "realm:unmasked",
        {
            "roles": {
                "publisher": {},
                "subscriber": {}
            }
        }
    ]))
    .unwrap();
    rt.block_on(async {
        send_unmasked_websocket_frame(&mut stream, 0x1, &unmasked_hello).await;
    });
    let close = rt.block_on(async { read_server_websocket_frame(&mut stream).await });
    assert!(close.fin);
    assert_eq!(close.opcode, 0x8, "expected protocol-error close frame");
    assert_eq!(decode_websocket_close_code(&close.payload), Some(1002));

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn websocket_ping_pong_and_empty_close_round_trip() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["websocket","http"],
                    "websocket_path":"/ws",
                    "http":{
                        "alpn":["http/1.1"]
                    }
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    let mut stream = rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        send_websocket_handshake(&mut stream, "/ws").await;
        stream
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_WEBSOCKET);

    let handshake_handle = ct_connection_take_websocket_handshake(connection_id);
    assert!(handshake_handle > 0);
    let protocol = CString::new("wamp.2.json").unwrap();
    assert_eq!(
        ct_connection_accept_websocket(
            connection_id,
            handshake_handle,
            1,
            protocol.as_ptr(),
            protocol.as_bytes().len() as i32
        ),
        SUCCESS
    );

    rt.block_on(async {
        let response = read_http_response_until_body(&mut stream).await;
        assert!(
            response.starts_with("HTTP/1.1 101"),
            "handshake response: {}",
            response
        );
    });

    rt.block_on(async {
        send_client_websocket_frame(&mut stream, 0x9, b"ping-check").await;
    });
    let pong = rt.block_on(async { read_server_websocket_frame(&mut stream).await });
    assert!(pong.fin);
    assert_eq!(pong.opcode, 0xA);
    assert_eq!(pong.payload, b"ping-check");

    rt.block_on(async {
        send_client_websocket_frame(&mut stream, 0x8, &[]).await;
    });
    let close = rt.block_on(async { read_server_websocket_frame(&mut stream).await });
    assert!(close.fin);
    assert_eq!(close.opcode, 0x8);
    assert!(close.payload.is_empty(), "expected empty close echo");

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn websocket_heartbeat_sends_ping_and_accepts_pong() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "heartbeat_interval_ms":50,
                    "heartbeat_timeout_ms":200,
                    "protocols":["websocket","http"],
                    "websocket_path":"/ws",
                    "http":{
                        "alpn":["http/1.1"]
                    }
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    let mut stream = rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        send_websocket_handshake(&mut stream, "/ws").await;
        stream
    });

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_WEBSOCKET);
    let handshake_handle = ct_connection_take_websocket_handshake(connection_id);
    assert!(handshake_handle > 0);
    let protocol = CString::new("wamp.2.json").unwrap();
    assert_eq!(
        ct_connection_accept_websocket(
            connection_id,
            handshake_handle,
            1,
            protocol.as_ptr(),
            protocol.as_bytes().len() as i32
        ),
        SUCCESS
    );

    rt.block_on(async {
        let response = read_http_response_until_body(&mut stream).await;
        assert!(
            response.starts_with("HTTP/1.1 101"),
            "handshake response: {}",
            response
        );

        let ping = read_server_websocket_frame(&mut stream).await;
        assert!(ping.fin);
        assert_eq!(ping.opcode, 0x9, "expected server heartbeat ping");
        assert_eq!(ping.payload.len(), 8, "expected 8-byte heartbeat ping");

        send_client_websocket_frame(&mut stream, 0xA, &ping.payload).await;
        tokio::time::sleep(Duration::from_millis(25)).await;
    });

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn rawsocket_heartbeat_sends_ping_and_accepts_pong() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "heartbeat_interval_ms":50,
                    "heartbeat_timeout_ms":200,
                    "protocols":["rawsocket"]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 16, None).await;

        let (frame_type, payload) = read_rawsocket_frame(&mut stream).await;
        assert_eq!(frame_type, 1, "expected server PING frame");
        assert_eq!(payload.len(), 8, "expected 8-byte ping payload");

        send_rawsocket_frame(&mut stream, 2, &payload).await;
        tokio::time::sleep(Duration::from_millis(25)).await;
    });

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn connection_close_removes_connection_entry() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{
            "schema":"connectanum.router",
            "version":1,
            "endpoints":[
                {
                    "host":"127.0.0.1",
                    "port":0,
                    "tls_mode":"disabled",
                    "protocols":["rawsocket"]
                }
            ]
        }"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    let (hold_tx, hold_rx) = tokio::sync::oneshot::channel::<()>();
    rt.spawn(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 16, None).await;
        let _ = hold_rx.await;
    });

    let deadline = Instant::now() + Duration::from_secs(1);
    let connection_id = loop {
        let connection_id = ct_poll_connection(listener_id);
        if connection_id > 0 {
            break connection_id;
        }
        if Instant::now() > deadline {
            panic!("timed out waiting for connection id");
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_RAWSOCKET);
    assert_eq!(ct_connection_close(connection_id), SUCCESS);
    assert_eq!(
        ct_connection_protocol(connection_id),
        ERR_CONNECTION_NOT_FOUND
    );
    let _ = hold_tx.send(());
    assert_eq!(ct_shutdown(), SUCCESS);
}

async fn perform_handshake(
    stream: &mut tokio::net::TcpStream,
    exponent: u32,
    upgrade: Option<u32>,
) {
    let clamped = exponent.clamp(9, 24);
    let handshake_byte = ((clamped - 9) as u8) << 4 | 0x01;
    stream
        .write_all(&[0x7F, handshake_byte, 0, 0])
        .await
        .unwrap();
    let mut buffer = [0u8; 4];
    stream.read_exact(&mut buffer).await.unwrap();
    assert_eq!(buffer[0], 0x7F);
    if let Some(upgrade_exponent) = upgrade {
        let nibble = (upgrade_exponent.saturating_sub(25)).min(15) as u8;
        stream.write_all(&[0x3F, nibble]).await.unwrap();
        let mut upgrade_response = [0u8; 2];
        stream.read_exact(&mut upgrade_response).await.unwrap();
        assert_eq!(upgrade_response[0], 0x3F);
    }
}

async fn send_json_frame(stream: &mut tokio::net::TcpStream, payload: &[u8]) {
    send_rawsocket_frame(stream, 0, payload).await;
}

async fn send_rawsocket_frame(stream: &mut tokio::net::TcpStream, frame_type: u8, payload: &[u8]) {
    assert!(frame_type <= 0x07);
    assert!(payload.len() <= (1 << 24));
    let mut header = [0u8; 4];
    if payload.len() == (1 << 24) {
        header[0] = 0x08 | (frame_type & 0x07);
    } else {
        header[0] = frame_type & 0x07;
        header[1] = ((payload.len() >> 16) & 0xFF) as u8;
        header[2] = ((payload.len() >> 8) & 0xFF) as u8;
        header[3] = (payload.len() & 0xFF) as u8;
    }
    stream.write_all(&header).await.unwrap();
    if !payload.is_empty() {
        stream.write_all(payload).await.unwrap();
    }
}

async fn read_rawsocket_frame(stream: &mut tokio::net::TcpStream) -> (u8, Vec<u8>) {
    let mut header = [0u8; 4];
    stream.read_exact(&mut header).await.unwrap();
    let frame_type = header[0] & 0x07;
    let length_hi = (header[0] >> 3) & 0x01;
    let mut length = ((header[1] as u32) << 16) | ((header[2] as u32) << 8) | header[3] as u32;
    if length_hi == 1 {
        length = 1 << 24;
    }
    let mut payload = vec![0u8; length as usize];
    if length > 0 {
        stream.read_exact(&mut payload).await.unwrap();
    }
    (frame_type, payload)
}

async fn send_websocket_handshake(stream: &mut tokio::net::TcpStream, path: &str) {
    let request = format!(
        "GET {} HTTP/1.1\r\n\
Host: localhost\r\n\
Upgrade: websocket\r\n\
Connection: Upgrade\r\n\
Sec-WebSocket-Key: SGVsbG9XU1Rlc3Q=\r\n\
Sec-WebSocket-Version: 13\r\n\
Sec-WebSocket-Protocol: wamp.2.json\r\n\r\n",
        path
    );
    stream.write_all(request.as_bytes()).await.unwrap();
}

async fn read_http_response_until_body(stream: &mut tokio::net::TcpStream) -> String {
    let mut buffer = Vec::new();
    let mut chunk = [0u8; 1];
    while !buffer.ends_with(b"\r\n\r\n") {
        let read = stream.read(&mut chunk).await.unwrap();
        if read == 0 {
            break;
        }
        buffer.push(chunk[0]);
    }
    String::from_utf8_lossy(&buffer).to_string()
}

async fn send_client_websocket_frame(
    stream: &mut tokio::net::TcpStream,
    opcode: u8,
    payload: &[u8],
) {
    let mask = [0x12u8, 0x34, 0x56, 0x78];
    let mut header = Vec::with_capacity(6);
    header.push(0x80 | (opcode & 0x0F));
    if payload.len() < 126 {
        header.push(0x80 | (payload.len() as u8));
    } else if payload.len() <= u16::MAX as usize {
        header.push(0x80 | 126);
        header.extend_from_slice(&(payload.len() as u16).to_be_bytes());
    } else {
        header.push(0x80 | 127);
        header.extend_from_slice(&(payload.len() as u64).to_be_bytes());
    }
    header.extend_from_slice(&mask);
    stream.write_all(&header).await.unwrap();
    if !payload.is_empty() {
        let masked: Vec<u8> = payload
            .iter()
            .enumerate()
            .map(|(idx, byte)| byte ^ mask[idx % 4])
            .collect();
        stream.write_all(&masked).await.unwrap();
    }
}

async fn send_unmasked_websocket_frame(
    stream: &mut tokio::net::TcpStream,
    opcode: u8,
    payload: &[u8],
) {
    let mut header = Vec::with_capacity(2);
    header.push(0x80 | (opcode & 0x0F));
    if payload.len() < 126 {
        header.push(payload.len() as u8);
    } else if payload.len() <= u16::MAX as usize {
        header.push(126);
        header.extend_from_slice(&(payload.len() as u16).to_be_bytes());
    } else {
        header.push(127);
        header.extend_from_slice(&(payload.len() as u64).to_be_bytes());
    }
    stream.write_all(&header).await.unwrap();
    if !payload.is_empty() {
        stream.write_all(payload).await.unwrap();
    }
}

async fn read_server_websocket_frame(stream: &mut tokio::net::TcpStream) -> TestWebSocketFrame {
    let mut header = [0u8; 2];
    stream.read_exact(&mut header).await.unwrap();
    let opcode = header[0] & 0x0F;
    assert_eq!(header[1] & 0x80, 0, "server frames must be unmasked");
    let fin = header[0] & 0x80 != 0;

    let mut len = (header[1] & 0x7F) as u64;
    if len == 126 {
        let mut extended = [0u8; 2];
        stream.read_exact(&mut extended).await.unwrap();
        len = u16::from_be_bytes(extended) as u64;
    } else if len == 127 {
        let mut extended = [0u8; 8];
        stream.read_exact(&mut extended).await.unwrap();
        len = u64::from_be_bytes(extended);
    }

    let mut payload = vec![0u8; len as usize];
    if len > 0 {
        stream.read_exact(&mut payload).await.unwrap();
    }
    TestWebSocketFrame {
        fin,
        opcode,
        payload,
    }
}

fn decode_websocket_close_code(payload: &[u8]) -> Option<u16> {
    if payload.len() < 2 {
        return None;
    }
    Some(u16::from_be_bytes([payload[0], payload[1]]))
}

struct TestWebSocketFrame {
    fin: bool,
    opcode: u8,
    payload: Vec<u8>,
}
