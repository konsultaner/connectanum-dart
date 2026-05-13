use super::test_guard;
use crate::runtime::{ct_shutdown, ct_start_runtime, ERR_ALREADY_STARTED, SUCCESS};

#[test]
fn start_and_shutdown() {
    let _guard = test_guard();
    assert_eq!(ct_start_runtime(), SUCCESS);
    assert_eq!(ct_start_runtime(), ERR_ALREADY_STARTED);
    assert_eq!(ct_shutdown(), SUCCESS);
}
