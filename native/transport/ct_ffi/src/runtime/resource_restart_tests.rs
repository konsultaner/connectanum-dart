use crate::runtime::state::{get_file, store_http_connection_event};
use crate::runtime::*;
use crate::tests::test_guard;
use ct_core::{ConnectionId, ConnectionProtocol, HttpConnectionCloseReason, HttpConnectionEvent};
use std::ffi::CString;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::ptr;
use std::time::{SystemTime, UNIX_EPOCH};

struct RunningRuntime;

impl RunningRuntime {
    fn new() -> Self {
        assert_eq!(ct_start_runtime(), SUCCESS);
        assert_eq!(ct_shutdown(), SUCCESS);
        assert_eq!(ct_start_runtime(), SUCCESS);
        Self
    }

    fn restart(&self) {
        assert_eq!(ct_shutdown(), SUCCESS);
        assert_eq!(ct_start_runtime(), SUCCESS);
    }
}

impl Drop for RunningRuntime {
    fn drop(&mut self) {
        let _ = ct_shutdown();
    }
}

struct FixtureFile(PathBuf);

impl FixtureFile {
    fn new(bytes: &[u8]) -> Self {
        let path = std::env::temp_dir().join(format!(
            "connectanum-resource-restart-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        file.write_all(bytes).unwrap();
        Self(path)
    }

    fn open(&self) -> i32 {
        let path = CString::new(self.0.to_str().unwrap()).unwrap();
        let size = std::fs::metadata(&self.0).unwrap().len();
        let handle = ct_file_open(path.as_ptr(), path.as_bytes().len() as i32, size);
        assert!(handle > 0);
        handle
    }
}

impl Drop for FixtureFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

fn add_key(keyring: i32, byte: u8) -> i32 {
    let key_id = b"restart-key";
    let key = [byte; 32];
    ct_e2ee_keyring_add_key(
        keyring,
        key_id.as_ptr().cast(),
        key_id.len() as i32,
        key.as_ptr(),
        key.len() as i32,
        1,
    )
}

fn event(connection: u32) -> u32 {
    store_http_connection_event(HttpConnectionEvent {
        connection_id: ConnectionId(connection),
        protocol: ConnectionProtocol::Http3,
        reason: HttpConnectionCloseReason::Graceful,
        request_count: 1,
        idle_timeouts: 0,
        body_timeouts: 0,
        backpressure_events: 0,
        max_backpressure_depth: 0,
        goaway_events: 0,
        detail: None,
    })
    .unwrap()
}

#[test]
fn resource_restart_file_lookup_cannot_alias_replacement() {
    let _guard = test_guard();
    let runtime = RunningRuntime::new();
    let old_file = FixtureFile::new(b"old file");
    let stale = old_file.open();
    runtime.restart();
    let new_file = FixtureFile::new(b"replacement file");
    let current = new_file.open();

    assert!(
        get_file(stale as u32).is_none(),
        "stale file resolved after restart"
    );
    let file = get_file(current as u32).expect("replacement file remains owned");
    let mut bytes = Vec::new();
    (&*file).read_to_end(&mut bytes).unwrap();
    assert_eq!(bytes, b"replacement file");
    assert_eq!(ct_file_release(current), SUCCESS);
}

#[test]
fn resource_restart_file_release_preserves_replacement() {
    let _guard = test_guard();
    let runtime = RunningRuntime::new();
    let old_file = FixtureFile::new(b"old file");
    let stale = old_file.open();
    runtime.restart();
    let new_file = FixtureFile::new(b"replacement file");
    let current = new_file.open();

    let result = ct_file_release(stale);
    assert!(
        get_file(current as u32).is_some(),
        "stale release removed replacement"
    );
    assert_eq!(result, ERR_HANDLE_UNAVAILABLE);
    assert_eq!(ct_file_release(current), SUCCESS);
}

#[test]
fn resource_restart_keyring_mutation_rejects_stale_handle() {
    let _guard = test_guard();
    let runtime = RunningRuntime::new();
    let stale = ct_e2ee_keyring_new();
    assert!(stale > 0);
    assert_eq!(add_key(stale, 11), SUCCESS);
    runtime.restart();
    let current = ct_e2ee_keyring_new();
    assert!(current > 0);
    assert_eq!(add_key(current, 22), SUCCESS);

    assert_eq!(add_key(stale, 33), ERR_HANDLE_UNAVAILABLE);
    let session = ct_e2ee_session_new(current, ptr::null(), 0);
    assert!(session > 0);
    assert_eq!(ct_e2ee_session_release(session), SUCCESS);
    assert_eq!(ct_e2ee_keyring_release(current), SUCCESS);
}

#[test]
fn resource_restart_keyring_release_preserves_replacement() {
    let _guard = test_guard();
    let runtime = RunningRuntime::new();
    let stale = ct_e2ee_keyring_new();
    assert!(stale > 0);
    runtime.restart();
    let current = ct_e2ee_keyring_new();
    assert!(current > 0);

    let result = ct_e2ee_keyring_release(stale);
    let session = ct_e2ee_session_new(current, ptr::null(), 0);
    assert!(session > 0, "stale release removed replacement keyring");
    assert_eq!(result, ERR_HANDLE_UNAVAILABLE);
    assert_eq!(ct_e2ee_session_release(session), SUCCESS);
    assert_eq!(ct_e2ee_keyring_release(current), SUCCESS);
}

#[test]
fn resource_restart_event_lookup_cannot_alias_replacement() {
    let _guard = test_guard();
    let runtime = RunningRuntime::new();
    let stale = event(71) as i32;
    runtime.restart();
    let current = event(72) as i32;
    let mut info = CtHttpConnectionEventInfo::default();

    assert_eq!(
        ct_http_connection_event_get(stale, &mut info),
        ERR_HANDLE_UNAVAILABLE
    );
    assert_eq!(ct_http_connection_event_get(current, &mut info), SUCCESS);
    assert_eq!(info.connection_id, 72);
    assert_eq!(ct_http_connection_event_release(current), SUCCESS);
}

#[test]
fn resource_restart_event_release_preserves_replacement() {
    let _guard = test_guard();
    let runtime = RunningRuntime::new();
    let stale = event(71) as i32;
    runtime.restart();
    let current = event(72) as i32;

    ct_http_connection_event_release(stale);
    let mut info = CtHttpConnectionEventInfo::default();
    assert_eq!(ct_http_connection_event_get(current, &mut info), SUCCESS);
    assert_eq!(info.connection_id, 72);
    assert_eq!(ct_http_connection_event_release(current), SUCCESS);
}
