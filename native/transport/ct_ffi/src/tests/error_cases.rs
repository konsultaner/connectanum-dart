use super::test_guard;
use crate::runtime::{
    ct_get_local_port, ct_listen, ct_poll_connection, ct_shutdown, ct_start_runtime,
    ERR_INVALID_ARGUMENT, ERR_LISTENER_NOT_FOUND, SUCCESS,
};

#[test]
fn errors_surface_correctly() {
    let _guard = test_guard();
    assert_eq!(ct_start_runtime(), SUCCESS);
    assert_eq!(ct_listen(std::ptr::null(), 0, -1), ERR_INVALID_ARGUMENT);
    assert_eq!(ct_get_local_port(99), ERR_LISTENER_NOT_FOUND);
    assert_eq!(ct_poll_connection(1), ERR_LISTENER_NOT_FOUND);
    assert_eq!(ct_shutdown(), SUCCESS);
}
