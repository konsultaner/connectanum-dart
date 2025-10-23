use std::ffi::CString;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::runtime::Runtime as TokioRuntime;

use crate::runtime::constants::{
    ERR_CONNECTION_NOT_FOUND, ERR_ENDPOINT_NOT_CONFIGURED, ERR_LISTENER_NOT_FOUND, SUCCESS,
};
use crate::runtime::ffi::{
    ct_apply_router_config, ct_connection_max_rawsocket_exponent, ct_get_local_port, ct_listen,
    ct_message_get, ct_message_release, ct_poll_connection, ct_poll_connection_message,
    ct_set_on_connection, ct_set_on_listener_started, ct_shutdown, ct_start_runtime, CtMessageInfo,
};

thread_local! {
    static LISTENER_EVENTS: Arc<Mutex<Vec<(i32, i32)>>> =
        Arc::new(Mutex::new(Vec::new()));
    static CONNECTION_EVENTS: Arc<Mutex<Vec<(i32, i32)>>> =
        Arc::new(Mutex::new(Vec::new()));
}

#[test]
fn listener_callbacks_fire_and_connections_are_reported() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","max_rawsocket_size_exponent":30}]}"#,
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
    assert_eq!(ct_shutdown(), SUCCESS);

    LISTENER_EVENTS.with(|events| events.lock().unwrap().clear());
    CONNECTION_EVENTS.with(|events| events.lock().unwrap().clear());
}

#[test]
fn poll_connection_message_returns_payload() {
    let _guard = super::test_guard();
    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native","max_rawsocket_size_exponent":16}]}"#,
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
