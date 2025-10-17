use std::ffi::CString;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::runtime::Runtime as TokioRuntime;

use crate::runtime::constants::{
    ERR_CONNECTION_NOT_FOUND, ERR_ENDPOINT_NOT_CONFIGURED, ERR_LISTENER_NOT_FOUND, SUCCESS,
};
use crate::runtime::ffi::{
    ct_apply_router_config, ct_connection_max_rawsocket_exponent, ct_get_local_port, ct_listen,
    ct_poll_connection, ct_set_on_connection, ct_set_on_listener_started, ct_shutdown,
    ct_start_runtime,
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
