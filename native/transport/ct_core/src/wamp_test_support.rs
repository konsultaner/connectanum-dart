use std::fmt::Debug;

pub(super) trait AssertSuccess {
    type Output;

    fn assert_expected(self, context: &str) -> Self::Output;

    fn assert_success(self) -> Self::Output
    where
        Self: Sized,
    {
        self.assert_expected("expected a successful result or present value")
    }
}

impl<T, E: Debug> AssertSuccess for Result<T, E> {
    type Output = T;

    fn assert_expected(self, context: &str) -> T {
        assert_eq!(
            self.as_ref().err().map(|error| format!("{error:?}")),
            None,
            "{context}"
        );
        self.unwrap()
    }
}

impl<T> AssertSuccess for Option<T> {
    type Output = T;

    fn assert_expected(self, context: &str) -> T {
        assert_eq!(self.is_some(), true, "{context}");
        self.unwrap()
    }
}

pub(super) trait AssertError {
    type Error;
    fn assert_error(self) -> Self::Error;
}

impl<T: Debug, E> AssertError for Result<T, E> {
    type Error = E;

    fn assert_error(self) -> E {
        assert_eq!(
            self.is_err(),
            true,
            "expected rejection, got {:?}",
            self.as_ref().ok()
        );
        self.unwrap_err()
    }
}

// Keep context while emitting Rust's standard assertion diagnostic, rather than
// a custom panic message that cannot establish an assertion-backed mutation kill.
macro_rules! assert_condition {
    ($condition:expr $(,)?) => {{
        let condition: bool = $condition;
        assert_eq!(condition, true, "{}", stringify!($condition));
    }};
    ($condition:expr, $($context:tt)+) => {{
        let condition: bool = $condition;
        assert_eq!(condition, true, $($context)+);
    }};
}

pub(super) use assert_condition;

pub(super) fn unexpected_message(message: super::WampMessage) -> ! {
    assert_eq!(Some(message), None, "unexpected message variant");
    unreachable!()
}

#[test]
fn result_oracles_preserve_values_and_error_identity() {
    let value = Box::new(17);
    let pointer = &*value as *const i32;
    let value = Ok::<_, &str>(value).assert_success();
    assert_eq!(&*value as *const i32, pointer);
    assert_eq!(*value, 17);
    let error = Box::new(29);
    let pointer = &*error as *const i32;
    let error = Err::<(), _>(error).assert_error();
    assert_eq!(&*error as *const i32, pointer);
    assert_eq!(*error, 29);
    assert_eq!(Some(43).assert_expected("present counter"), 43);
}

#[test]
fn false_result_expectations_fail_with_assertion_diagnostics() {
    for failure in [
        std::panic::catch_unwind(|| Err::<(), _>("expected failure").assert_success()),
        std::panic::catch_unwind(|| None::<()>.assert_expected("missing value")),
        std::panic::catch_unwind(|| {
            Ok::<_, ()>(17).assert_error();
        }),
        std::panic::catch_unwind(|| assert_condition!(false, "context")),
        std::panic::catch_unwind(|| {
            unexpected_message(super::WampMessage::Unregistered { request_id: 7 })
        }),
    ] {
        assert!(failure.is_err());
        let failure = failure.unwrap_err();
        let message = failure
            .downcast_ref::<String>()
            .map(String::as_str)
            .or_else(|| failure.downcast_ref::<&str>().copied())
            .unwrap();
        assert!(message.starts_with("assertion `left == right` failed"));
    }
}
