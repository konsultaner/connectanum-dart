use super::test_guard;
use crate::runtime::{
    ct_apply_router_config, ct_get_local_port, ct_listen, ct_poll_connection, ct_shutdown,
    ct_start_runtime, ERR_ENDPOINT_NOT_CONFIGURED, ERR_INVALID_ARGUMENT, ERR_LISTENER_NOT_FOUND,
    ERR_RUNTIME_NOT_STARTED, SUCCESS,
};
use std::ffi::CString;

#[test]
fn errors_surface_correctly() {
    let _guard = test_guard();

    assert_eq!(ct_listen(std::ptr::null(), 0, 128), ERR_INVALID_ARGUMENT);

    let config = CString::new(
        r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"native"}]}"#,
    )
    .unwrap();
    let bytes = config.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS,
    );

    assert_eq!(ct_start_runtime(), SUCCESS);
    assert_eq!(ct_listen(std::ptr::null(), 0, -1), ERR_INVALID_ARGUMENT);
    assert_eq!(
        ct_listen(CString::new("127.0.0.1").unwrap().as_ptr(), 1, 128),
        ERR_ENDPOINT_NOT_CONFIGURED,
    );
    assert_eq!(ct_get_local_port(99), ERR_LISTENER_NOT_FOUND);
    assert_eq!(ct_poll_connection(1), ERR_LISTENER_NOT_FOUND);
    assert_eq!(ct_shutdown(), SUCCESS);
}
