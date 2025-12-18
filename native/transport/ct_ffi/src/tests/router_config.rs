use std::ffi::CString;

use crate::runtime::constants::{ERR_ROUTER_CONFIG_INVALID, SUCCESS};
use crate::runtime::ffi::{ct_apply_router_config, ct_shutdown, ct_start_runtime};

#[test]
fn apply_valid_router_config() {
    let _guard = super::test_guard();
    assert_eq!(ct_start_runtime(), SUCCESS);
    let json = CString::new(r#"{"schema":"connectanum.router","version":1,"endpoints":[{"host":"127.0.0.1","port":0,"tls_mode":"disabled","max_rawsocket_size_exponent":16,"protocols":["rawsocket"]}]}"#).unwrap();
    let bytes = json.as_bytes();
    assert_eq!(
        ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32),
        SUCCESS
    );
    assert_eq!(ct_shutdown(), SUCCESS);
}

#[test]
fn apply_invalid_router_config() {
    let _guard = super::test_guard();
    let bytes = b"invalid-json";
    let code = ct_apply_router_config(bytes.as_ptr(), bytes.len() as i32);
    assert_eq!(code, ERR_ROUTER_CONFIG_INVALID);
}
