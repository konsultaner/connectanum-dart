use std::ffi::CString;
use std::io::{Read, Write};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use crate::runtime::constants::{
    ERR_CONNECTION_NOT_FOUND, ERR_INVALID_ARGUMENT, PROTOCOL_MQTT, SUCCESS,
};
use crate::runtime::ffi::{
    ct_apply_router_config, ct_connection_close, ct_connection_mqtt_version,
    ct_connection_protocol, ct_get_local_port, ct_listen, ct_poll_connection, ct_poll_mqtt_chunk,
    ct_send_mqtt_chunk, ct_set_mqtt_wakeup, ct_shutdown, ct_start_runtime,
};

const CONNECT: &[u8] = b"\x10\x0d\x00\x04MQTT\x05\x02\x00\x3c\x00\x00\x00";
const CONNACK: &[u8] = b"\x20\x03\x00\x00\x00";
static WAKE_COUNT: AtomicUsize = AtomicUsize::new(0);

extern "C" fn mqtt_wake(connection_id: i32) {
    assert!(connection_id > 0);
    WAKE_COUNT.fetch_add(1, Ordering::SeqCst);
}

#[test]
fn mqtt_native_byte_channel_preserves_connect_and_response() {
    let _guard = super::test_guard();
    let config = br#"{
        "schema":"connectanum.router",
        "version":1,
        "endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled",
                      "protocols":["mqtt"]}]
    }"#;
    assert_eq!(
        ct_apply_router_config(config.as_ptr(), config.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_start_runtime(), SUCCESS);
    let host = CString::new("127.0.0.1").unwrap();
    let listener = ct_listen(host.as_ptr(), 0, 128);
    assert!(listener > 0);
    let port = ct_get_local_port(listener);
    assert!(port > 0);

    let mut client = std::net::TcpStream::connect(("127.0.0.1", port as u16)).unwrap();
    client
        .set_read_timeout(Some(Duration::from_secs(2)))
        .unwrap();
    client.write_all(CONNECT).unwrap();

    let deadline = Instant::now() + Duration::from_secs(2);
    let connection = loop {
        let id = ct_poll_connection(listener);
        if id > 0 {
            break id;
        }
        assert!(
            Instant::now() < deadline,
            "MQTT connection was not accepted"
        );
        std::thread::sleep(Duration::from_millis(2));
    };
    assert_eq!(ct_connection_protocol(connection), PROTOCOL_MQTT);
    assert_eq!(ct_connection_mqtt_version(connection), 5);

    let mut received = Vec::new();
    let mut buffer = [0u8; 16 * 1024];
    while received.len() < CONNECT.len() {
        let count = ct_poll_mqtt_chunk(connection, buffer.as_mut_ptr(), buffer.len() as i32);
        assert!(count >= 0, "poll failed: {count}");
        if count > 0 {
            received.extend_from_slice(&buffer[..count as usize]);
        }
        assert!(Instant::now() < deadline, "CONNECT bytes were lost");
        if count == 0 {
            std::thread::sleep(Duration::from_millis(2));
        }
    }
    assert_eq!(received, CONNECT);
    assert_eq!(
        ct_poll_mqtt_chunk(connection, buffer.as_mut_ptr(), buffer.len() as i32),
        0
    );
    assert_eq!(
        ct_send_mqtt_chunk(connection, CONNACK.as_ptr(), CONNACK.len() as i32),
        SUCCESS
    );
    let mut response = [0u8; 5];
    client.read_exact(&mut response).unwrap();
    assert_eq!(response, CONNACK);

    WAKE_COUNT.store(0, Ordering::SeqCst);
    assert_eq!(ct_set_mqtt_wakeup(connection, Some(mqtt_wake)), SUCCESS);
    client.write_all(&[0xc0, 0x00]).unwrap();
    while WAKE_COUNT.load(Ordering::SeqCst) == 0 {
        assert!(Instant::now() < deadline, "MQTT read did not wake Dart");
        std::thread::sleep(Duration::from_millis(2));
    }
    assert_eq!(
        ct_poll_mqtt_chunk(connection, buffer.as_mut_ptr(), buffer.len() as i32),
        2
    );
    assert_eq!(&buffer[..2], &[0xc0, 0x00]);
    assert_eq!(ct_set_mqtt_wakeup(connection, None), SUCCESS);
    assert_eq!(ct_set_mqtt_wakeup(0, None), ERR_INVALID_ARGUMENT);

    assert_eq!(
        ct_poll_mqtt_chunk(connection, std::ptr::null_mut(), 0),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(
        ct_send_mqtt_chunk(connection, std::ptr::null(), 0),
        ERR_INVALID_ARGUMENT
    );
    assert_eq!(ct_connection_close(connection), SUCCESS);
    assert_eq!(
        ct_connection_mqtt_version(connection),
        ERR_CONNECTION_NOT_FOUND
    );
    assert_eq!(ct_shutdown(), SUCCESS);
}
