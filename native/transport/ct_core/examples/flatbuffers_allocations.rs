//! Diagnostic allocator requests for real segmented WAMP encoding. Input
//! preparation and reporting are outside the counter. This is not a timing,
//! Dart allocation, retained-memory, or copy-accounting acceptance benchmark.
use bytes::Bytes;
use ct_core::{encode_flatbuffers_message_segments, WampMessage, WampPayload as Payload};
use serde::Serialize;
use serde_value::Value;
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
struct Counts {
    calls: usize,
    requested_bytes: usize,
}
thread_local! {
    static COUNTS: Cell<Option<Counts>> = const { Cell::new(None) };
}
fn record(size: usize) {
    COUNTS.with(|cell| {
        if let Some(mut counts) = cell.get() {
            counts.calls += 1;
            counts.requested_bytes += size;
            cell.set(Some(counts));
        }
    });
}
struct Counting;
// Forward each allocation's original layout and pointer to the system allocator.
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
    COUNTS.with(|cell| cell.set(Some(Counts::default())));
    let value = operation();
    let counts = COUNTS.with(|cell| cell.replace(None).unwrap());
    (value, counts)
}

fn payload(shape: &str, length: usize) -> Payload {
    let body = vec![0x71; length];
    match shape {
        "opaque" => Payload {
            transparent: Some(Bytes::from(body)),
            ..Payload::default()
        },
        "args" | "args_kwargs" => Payload {
            args: Some(Bytes::from(
                serde_cbor::to_vec(&Value::Seq(vec![Value::Bytes(body)])).unwrap(),
            )),
            kwargs: (shape == "args_kwargs").then(|| Bytes::from_static(&[0xa1, 0x61, b'k', 0x01])),
            transparent: None,
        },
        "control" => Payload::default(),
        _ => unreachable!(),
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let output = PathBuf::from(
        std::env::args()
            .nth(1)
            .expect("pass a new output directory"),
    );
    std::fs::create_dir(&output)?;
    for shape in ["control", "opaque", "args", "args_kwargs"] {
        for length in [0, 1024, 1024 * 1024] {
            if shape == "control" && length != 0 {
                continue;
            }
            let payload = payload(shape, length);
            let aliases: Vec<_> = [&payload.args, &payload.kwargs, &payload.transparent]
                .into_iter()
                .flatten()
                .map(|bytes| (bytes.as_ptr(), bytes.len()))
                .collect();
            let message = WampMessage::Result {
                request_id: 42,
                details: BTreeMap::new(),
                payload,
            };
            let mut observations = Vec::new();
            for _ in 0..10 {
                let (segments, counts) =
                    measure(|| encode_flatbuffers_message_segments(&message).unwrap());
                assert_eq!(
                    segments.len(),
                    if aliases.len() == 1 {
                        2
                    } else {
                        1 + 2 * aliases.len()
                    }
                );
                for (pointer, size) in &aliases {
                    assert_eq!(
                        segments
                            .iter()
                            .filter(|s| s.as_ptr() == *pointer && s.len() == *size)
                            .count(),
                        1
                    );
                }
                observations.push(counts);
            }
            assert!(observations.iter().all(|value| *value == observations[0]));
            let segments = encode_flatbuffers_message_segments(&message)?;
            drop(message);
            let wire: Vec<_> = segments.iter().flat_map(|s| s.iter().copied()).collect();
            std::fs::write(output.join(format!("{shape}-{length}.bin")), &wire)?;
            println!(
                "{}",
                serde_json::json!({
                    "scope": "native_encoder_allocator_requests_only_never_parity_acceptance",
                    "shape": shape, "body_bytes": length, "observations": observations,
                    "wire_bytes": wire.len(), "borrowed_vectors": aliases.len(),
                })
            );
        }
    }
    Ok(())
}
