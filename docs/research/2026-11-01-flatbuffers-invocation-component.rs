use bytes::Bytes;
use ct_core::{
    encode_flatbuffers_message_segments, parse_message_segments, RawSocketSerializer, WampMessage,
    WampPayload,
};
use serde_value::Value;
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::collections::BTreeMap;
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
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

#[allow(dead_code, unused_imports)]
#[path = "../../native/transport/ct_core/src/wamp/flatbuffers_generated.rs"]
mod generated_source;
use generated_source::wamp::proto as gen;
fn message(
    scheme: String,
    request_id: u64,
    i: usize,
    len: usize,
    progress: Option<bool>,
    receive_progress: Option<bool>,
) -> WampMessage {
    let mut details = BTreeMap::from([
        (Value::String("ppt_scheme".into()), Value::String(scheme)),
        (
            Value::String("ppt_serializer".into()),
            Value::String("flatbuffers".into()),
        ),
    ]);
    if let Some(value) = progress {
        details.insert(Value::String("progress".into()), Value::Bool(value));
    }
    if let Some(value) = receive_progress {
        details.insert(Value::String("receive_progress".into()), Value::Bool(value));
    }
    let registration_id = 9_007_199_254_740_992 - request_id + 1;
    let body = Bytes::from(
        (0..len)
            .map(|j| (i.wrapping_mul(73) ^ j) as u8)
            .collect::<Vec<_>>(),
    );
    WampMessage::Invocation {
        request_id,
        registration_id,
        details,
        payload: WampPayload {
            transparent: Some(body),
            ..Default::default()
        },
    }
}

fn main() {
    for progress in [None, Some(false), Some(true)] {
        for receive in [None, Some(false), Some(true)] {
            for n in [4, 25, 58, 59, 60, 61, 87, 88, 89, 255, 256, 65535, 65536] {
                let input = message("s".repeat(n), 73, n, 17, progress, receive);
                let (parts, c) = measure(|| encode_flatbuffers_message_segments(&input).unwrap());
                let WampMessage::Invocation {
                    payload, details, ..
                } = &input
                else {
                    unreachable!()
                };
                assert_eq!(
                    parts[1].as_ptr(),
                    payload.transparent.as_ref().unwrap().as_ptr()
                );
                let wire = parts
                    .iter()
                    .flat_map(|p| p.iter().copied())
                    .collect::<Vec<_>>();
                let root = gen::root_as_message(&wire).unwrap();
                let invocation = root.msg_as_invocation().unwrap();
                assert_eq!(invocation.request(), 73);
                assert_eq!(invocation.registration(), 9_007_199_254_740_992 - 73 + 1);
                assert_eq!(invocation.receive_progress(), receive.unwrap_or(false));
                assert_eq!(
                    root.metadata().unwrap().bytes(),
                    serde_cbor::to_vec(details).unwrap()
                );
                let control_len = parts[0].len();
                assert_eq!(
                    parse_message_segments(RawSocketSerializer::Flatbuffers, parts)
                        .unwrap()
                        .message,
                    input
                );
                println!("{{\"progress\":{},\"receive\":{},\"scheme_len\":{n},\"calls\":{},\"requested_bytes\":{},\"control_len\":{control_len}}}",progress.map_or("null",|v|if v{"true"}else{"false"}),receive.map_or("null",|v|if v{"true"}else{"false"}),c.calls,c.requested_bytes);
            }
        }
    }
}
