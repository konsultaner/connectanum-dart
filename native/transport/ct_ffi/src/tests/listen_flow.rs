use std::ffi::CString;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::runtime::Runtime as TokioRuntime;

use super::test_guard;
use crate::runtime::{
    ct_get_local_port, ct_listen, ct_poll_connection, ct_set_on_connection,
    ct_set_on_listener_started, ct_shutdown, ct_start_runtime, ERR_LISTENER_NOT_FOUND, SUCCESS,
};

#[test]
fn listener_callbacks_fire_and_connections_are_reported() {
    let _guard = test_guard();
    assert_eq!(ct_start_runtime(), SUCCESS);

    let listener_events: Arc<Mutex<Vec<(i32, i32)>>> = Arc::new(Mutex::new(Vec::new()));
    let connection_events: Arc<Mutex<Vec<(i32, i32)>>> = Arc::new(Mutex::new(Vec::new()));

    let listener_clone = listener_events.clone();
    ct_set_on_listener_started(move |id, status| {
        listener_clone.lock().unwrap().push((id, status));
    });

    let connection_clone = connection_events.clone();
    ct_set_on_connection(move |listener_id, connection_id| {
        connection_clone
            .lock()
            .unwrap()
            .push((listener_id, connection_id));
    });

    let addr = CString::new("127.0.0.1").unwrap();
    let listener_id = ct_listen(addr.as_ptr(), 0, 128);
    assert!(listener_id > 0);

    assert_eq!(
        &listener_events.lock().unwrap()[..],
        &[(listener_id, SUCCESS)]
    );

    let port = ct_get_local_port(listener_id);
    assert!(port > 0);

    let rt = TokioRuntime::new().unwrap();
    rt.block_on(async {
        let addr = format!("127.0.0.1:{}", port);
        let stream = tokio::net::TcpStream::connect(addr).await.unwrap();
        drop(stream);
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let poll_result = ct_poll_connection(listener_id);
    assert!(poll_result > 0);
    let events = connection_events.lock().unwrap();
    assert_eq!(events.as_slice(), &[(listener_id, poll_result)]);
    drop(events);

    assert_eq!(ct_poll_connection(listener_id), 0);
    assert_eq!(ct_poll_connection(9999), ERR_LISTENER_NOT_FOUND);
    assert_eq!(ct_shutdown(), SUCCESS);
}
