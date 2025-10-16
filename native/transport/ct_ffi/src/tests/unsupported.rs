use crate::runtime::{ct_start_runtime, ERR_UNSUPPORTED};

#[test]
fn runtime_not_supported() {
    assert_eq!(ct_start_runtime(), ERR_UNSUPPORTED);
}
