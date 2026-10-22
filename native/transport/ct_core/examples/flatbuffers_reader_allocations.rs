//! Diagnostic Rust allocator requests for real WAMP FlatBuffers parsing.
//! Preparation, assertions and reporting are outside the counter. This does
//! not measure timing, Dart allocation, live heap, RSS or performance parity.
use bytes::Bytes;
use ct_core::{
    encode_flatbuffers_message, parse_message, RawSocketSerializer, WampMessage, WampPayload,
};
use serde_value::Value;
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Counts {
    calls: usize,
    bytes: usize,
}
thread_local! { static COUNTS: Cell<Option<Counts>> = const { Cell::new(None) }; }
fn record(bytes: usize) {
    COUNTS.with(|slot| {
        if let Some(mut counts) = slot.get() {
            counts.calls += 1;
            counts.bytes += bytes;
            slot.set(Some(counts));
        }
    });
}
struct Counting;
// Forward every original pointer/layout to System; count only this thread.
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        record(layout.size());
        unsafe { System.alloc(layout) }
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        record(layout.size());
        unsafe { System.alloc_zeroed(layout) }
    }
    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        unsafe { System.dealloc(pointer, layout) }
    }
    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        record(size);
        unsafe { System.realloc(pointer, layout, size) }
    }
}
#[global_allocator]
static ALLOCATOR: Counting = Counting;
fn measure<T>(operation: impl FnOnce() -> T) -> (T, Counts) {
    COUNTS.with(|slot| slot.set(Some(Counts::default())));
    let value = operation();
    let counts = COUNTS.with(|slot| slot.replace(None).unwrap());
    (value, counts)
}
fn make_message(shape: &str, size: usize) -> WampMessage {
    let payload = WampPayload {
        transparent: Some(Bytes::from(vec![0x71; size])),
        ..Default::default()
    };
    match shape {
        "result" => WampMessage::Result {
            request_id: 42,
            details: BTreeMap::new(),
            payload,
        },
        "call" => WampMessage::Call {
            request_id: 42,
            options: BTreeMap::new(),
            procedure: "com.example.echo".into(),
            payload,
        },
        "error" => WampMessage::Error {
            request_type: 48,
            request_id: 42,
            details: BTreeMap::new(),
            error: "com.example.error".into(),
            payload,
        },
        _ => {
            let mut options = BTreeMap::new();
            if let Some(count) = shape.strip_prefix("publish-exclude-") {
                options.insert(
                    Value::String("exclude_authid".into()),
                    Value::Seq(
                        (0..count.parse::<usize>().unwrap())
                            .map(|n| Value::String(format!("user{n}")))
                            .collect(),
                    ),
                );
            }
            WampMessage::Publish {
                request_id: 42,
                options,
                topic: "com.example.topic".into(),
                payload,
            }
        }
    }
}
fn check_alias(message: &WampMessage, frame: &Bytes, size: usize) {
    let payload = match message {
        WampMessage::Result { payload, .. } => payload,
        WampMessage::Call {
            procedure, payload, ..
        } => {
            assert_eq!(procedure, "com.example.echo");
            payload
        }
        WampMessage::Error { error, payload, .. } => {
            assert_eq!(error, "com.example.error");
            payload
        }
        WampMessage::Publish { topic, payload, .. } => {
            assert_eq!(topic, "com.example.topic");
            payload
        }
        _ => unreachable!(),
    };
    let body = payload.transparent.as_ref().unwrap();
    assert_eq!(body.len(), size);
    if size > 0 {
        assert!(body.as_ptr() as usize >= frame.as_ptr() as usize);
        assert!(body.as_ptr() as usize + size <= frame.as_ptr() as usize + frame.len());
        assert_eq!((body[0], body[size - 1]), (0x71, 0x71));
    }
}
fn main() {
    let output = PathBuf::from(std::env::args().nth(1).unwrap());
    std::fs::create_dir(&output).unwrap();
    for shape in [
        "result",
        "call",
        "error",
        "publish",
        "publish-exclude-1",
        "publish-exclude-3",
        "publish-exclude-4",
        "publish-exclude-8",
    ] {
        for size in [0, 1024, 1024 * 1024] {
            let frame = encode_flatbuffers_message(&make_message(shape, size)).unwrap();
            let (first, cold) =
                measure(|| parse_message(RawSocketSerializer::Flatbuffers, frame.clone()).unwrap());
            check_alias(&first.message, &frame, size);
            drop(first);
            let mut observations = Vec::new();
            for _ in 0..10 {
                let (parsed, count) = measure(|| {
                    parse_message(RawSocketSerializer::Flatbuffers, frame.clone()).unwrap()
                });
                check_alias(&parsed.message, &frame, size);
                observations.push(count);
            }
            assert!(observations.iter().all(|value| *value == observations[0]));
            std::fs::write(output.join(format!("{shape}-{size}.bin")), &frame).unwrap();
            println!(
                "{}",
                serde_json::json!({"shape":shape,"body_bytes":size,"cold":{"calls":cold.calls,"bytes":cold.bytes},"observations":observations.iter().map(|v|serde_json::json!({"calls":v.calls,"bytes":v.bytes})).collect::<Vec<_>>(),"wire_bytes":frame.len(),"nonempty_payload_span_retained":size > 0,"empty_body_verified":size == 0,"scope":"native reader allocator requests only; never performance acceptance"})
            );
        }
    }
}
