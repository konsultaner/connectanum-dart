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
use quinn::{ClientConfig as QuinnClientConfig, Endpoint as QuinnEndpoint, TransportConfig};
use rcgen::generate_simple_self_signed;
use rustls::pki_types::CertificateDer;
use rustls::RootCertStore;
use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::runtime::Runtime as TokioRuntime;

const HTTP2_PREFACE: &[u8] = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

#[cfg(feature = "ffi-test")]
use crate::runtime::constants::HTTP_EVENT_REASON_IDLE_TIMEOUT;
use crate::runtime::constants::{
    ERR_CONNECTION_NOT_FOUND, ERR_ENDPOINT_NOT_CONFIGURED, ERR_INVALID_ARGUMENT,
    ERR_LISTENER_NOT_FOUND, ERR_UNSUPPORTED, HTTP_EVENT_REASON_BODY_TIMEOUT, PROTOCOL_HTTP,
    PROTOCOL_HTTP2, PROTOCOL_HTTP3, PROTOCOL_RAWSOCKET, PROTOCOL_WEBSOCKET, SUCCESS,
};
use crate::runtime::ffi::{
    ct_apply_router_config, ct_connection_get_http3_connection,
    ct_connection_max_rawsocket_exponent, ct_connection_poll_http_event, ct_connection_protocol,
    ct_connection_take_http2_handshake, ct_connection_take_http3_handshake,
    ct_connection_take_http_handshake, ct_connection_take_websocket_handshake, ct_get_local_port,
    ct_http2_handshake_get, ct_http2_handshake_listener_protocol, ct_http2_handshake_release,
    ct_http3_connection_poll_request, ct_http3_connection_poll_stream, ct_http3_connection_release,
    ct_http3_handshake_get, ct_http3_handshake_listener_protocol, ct_http3_handshake_release,
    ct_http_body_finish, ct_http_body_get, ct_http_body_release, ct_http_body_stream_read,
    ct_http_connection_event_get, ct_http_connection_event_release, ct_http_handshake_body_retain,
    ct_http_handshake_get, ct_http_handshake_header, ct_http_handshake_release,
    ct_http_response_send, ct_listen, ct_message_get, ct_message_release, ct_poll_connection,
    ct_poll_connection_message, ct_set_on_connection, ct_set_on_listener_started, ct_shutdown,
    ct_start_runtime, ct_websocket_handshake_extension, ct_websocket_handshake_get,
    ct_websocket_handshake_protocol, ct_websocket_handshake_release, CtHttp2HandshakeInfo,
    CtHttp3HandshakeInfo, CtHttpBodyView, CtHttpConnectionEventInfo, CtHttpHandshakeInfo,
    CtHttpHeader, CtMessageInfo, CtStringView, CtWebSocketHandshakeInfo,
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

fn wait_for_http_handshake(connection_id: i32) -> i32 {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let handle = ct_connection_take_http_handshake(connection_id);
        if handle > 0 {
            return handle;
        }
        if handle < 0 {
            panic!("take http handshake failed: {handle}");
        }
        if Instant::now() > deadline {
            panic!("timed out waiting for HTTP handshake");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
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
                    "tls_mode":"native",
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
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 24, Some(30)).await;
        drop(stream);
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let poll_result = ct_poll_connection(listener_id);
    assert!(poll_result > 0);
    assert_eq!(ct_connection_protocol(poll_result), PROTOCOL_RAWSOCKET);
    assert_eq!(
        ct_connection_max_rawsocket_exponent(poll_result),
        30,
        "raw socket exponent expected from runtime config"
    );
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
                    "tls_mode":"native",
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

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        perform_handshake(&mut stream, 16, None).await;
        let message = serde_json::to_vec(&json!([
            16,
            42,
            {},
            "com.example.topic",
            [1, 2, 3],
            {"flag": true}
        ]))
        .unwrap();
        send_json_frame(&mut stream, &message).await;
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let connection_id = ct_poll_connection(listener_id);
    assert!(connection_id > 0);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_RAWSOCKET);

    let handle = ct_poll_connection_message(connection_id);
    assert!(handle > 0);

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

    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn http_handshake_surfaced_via_ffi() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","protocols":["rawsocket","http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/health","match_kind":"prefix","methods":{"GET":{"type":"reserved_realm","append_method_suffix":true}}}]}]}"#,
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
fn http_handshake_streaming_body_round_trip() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","protocols":["rawsocket","http"],"http":{"alpn":["http/1.1"]},"http_routes":[{"path":"/stream","match_kind":"prefix","methods":{"POST":{"type":"reserved_realm","append_method_suffix":true}}}]}]}"#,
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
                    "tls_mode":"native",
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

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        stream
            .write_all(HTTP2_PREFACE)
            .await
            .expect("preface write");
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let connection_id = ct_poll_connection(listener_id);
    assert!(connection_id > 0);
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
                    "http3":{"enabled":true}
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

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let server_addr = addr.parse().unwrap();

        let mut roots = RootCertStore::empty();
        roots
            .add(CertificateDer::from(cert_der.clone()))
            .expect("add root cert");
        let mut client_config = QuinnClientConfig::with_root_certificates(Arc::new(roots)).unwrap();
        client_config.transport_config(Arc::new(TransportConfig::default()));

        let mut endpoint = QuinnEndpoint::client("[::]:0".parse().unwrap()).unwrap();
        endpoint.set_default_client_config(client_config);
        let connection = endpoint
            .connect(server_addr, "localhost")
            .expect("connect http3");
        let _connection = connection.await.expect("http3 handshake");
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let connection_id = ct_poll_connection(listener_id);
    assert!(connection_id > 0);
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
                    "http3":{"enabled":true},
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

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async move {
        let addr = format!("127.0.0.1:{}", port);
        let server_addr = addr.parse().unwrap();

        let mut roots = RootCertStore::empty();
        roots
            .add(CertificateDer::from(cert_der.clone()))
            .expect("add root cert");
        let mut client_config = QuinnClientConfig::with_root_certificates(Arc::new(roots)).unwrap();
        client_config.transport_config(Arc::new(TransportConfig::default()));

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
                    "http3":{"enabled":true}
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
                    "http3":{"enabled":true}
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

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

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
            let mut client_config =
                QuinnClientConfig::with_root_certificates(Arc::new(roots)).unwrap();
            client_config.transport_config(Arc::new(TransportConfig::default()));

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
fn http2_body_timeout_emits_connection_event() {
    let _guard = super::test_guard();
    let config_json = json!({
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[
            {
                "host":"127.0.0.1",
                "port":0,
                "tls_mode":"native",
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
            let (mut client, connection) = client::handshake(tcp).await.unwrap();
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

            let start = Instant::now();
            while start.elapsed() < Duration::from_millis(300) {
                if send_stream
                    .send_data(Bytes::copy_from_slice(&[b'x']), false)
                    .is_err()
                {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(30)).await;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        })
    });

    ready_rx.recv().expect("client ready");

    let connection_id = wait_for_connection(listener_id);
    assert_eq!(ct_connection_protocol(connection_id), PROTOCOL_HTTP2);

    let handshake_handle = wait_for_http_handshake(connection_id);
    assert_eq!(ct_http_handshake_release(handshake_handle), SUCCESS);

    let (event, _detail) = wait_for_http_event(Duration::from_secs(5));
    assert_eq!(event.connection_id, connection_id);
    assert_eq!(event.protocol, PROTOCOL_HTTP2);
    assert_eq!(event.reason, HTTP_EVENT_REASON_BODY_TIMEOUT);
    assert!(event.request_count >= 1);
    assert_eq!(event.backpressure_events, 0);
    assert_eq!(event.max_backpressure_depth, 0);
    assert_eq!(event.goaway_events, 0);

    client_handle.join().expect("client thread finished");
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[cfg(feature = "ffi-test")]
#[test]
fn http3_idle_timeout_emits_connection_event() {
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
    assert_eq!(event.goaway_events, 0);
    assert_eq!(
        retrieved_detail.as_deref(),
        Some("http/3 body idle timeout")
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
                    "tls_mode":"native",
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
            let (mut client, connection) = client::handshake(tcp).await.unwrap();
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

    let connection_id = ct_poll_connection(listener_id);
    assert!(connection_id > 0);
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
                    "tls_mode":"native",
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
            let (mut client, connection) = client::handshake(tcp).await.unwrap();
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
                    "tls_mode":"native",
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

    let connection_id = ct_poll_connection(listener_id);
    assert!(connection_id > 0);
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
    assert!(payload.len() <= (1 << 24));
    let mut header = [0u8; 4];
    if payload.len() == (1 << 24) {
        header[0] = 0x08;
    } else {
        header[0] = 0x00;
        header[1] = ((payload.len() >> 16) & 0xFF) as u8;
        header[2] = ((payload.len() >> 8) & 0xFF) as u8;
        header[3] = (payload.len() & 0xFF) as u8;
    }
    stream.write_all(&header).await.unwrap();
    if !payload.is_empty() {
        stream.write_all(payload).await.unwrap();
    }
}
