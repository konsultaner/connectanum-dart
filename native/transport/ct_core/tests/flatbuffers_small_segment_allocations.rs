//! Equivalent fresh received storage must not add a heap index for <=64 pieces.
use bytes::Bytes;
use ct_core::{
    encode_flatbuffers_message_segments, parse_message, parse_message_segments,
    raw_frame_copy_metrics_snapshot, RawSocketSerializer, WampMessage, WampPayload,
};
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::collections::BTreeMap;
use std::hint::black_box;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Counts {
    calls: usize,
    requested_bytes: usize,
}
thread_local! { static COUNTS: Cell<Option<Counts>> = const { Cell::new(None) }; }
fn record(size: usize) {
    let _ = COUNTS.try_with(|state| {
        if let Some(mut value) = state.get() {
            value.calls += 1;
            value.requested_bytes += size;
            state.set(Some(value));
        }
    });
}
struct ForwardSystem;
unsafe impl GlobalAlloc for ForwardSystem {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        record(layout.size());
        unsafe { System.alloc(layout) }
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        record(layout.size());
        unsafe { System.alloc_zeroed(layout) }
    }
    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        record(size);
        unsafe { System.realloc(pointer, layout, size) }
    }
    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        unsafe { System.dealloc(pointer, layout) }
    }
}
#[global_allocator]
static ALLOCATOR: ForwardSystem = ForwardSystem;
fn measure<T>(operation: impl FnOnce() -> T) -> (T, Counts) {
    COUNTS.with(|state| {
        assert!(state.get().is_none());
        state.set(Some(Counts::default()));
    });
    let value = operation();
    let counts = COUNTS.with(|state| state.replace(None).unwrap());
    (value, counts)
}
fn fresh_frame(nonce: u64) -> (WampMessage, Bytes) {
    let expected = WampMessage::Call {
        request_id: nonce,
        procedure: "bench.rpc.echo".to_owned(),
        options: BTreeMap::new(),
        payload: WampPayload::default(),
    };
    let mut parts = encode_flatbuffers_message_segments(&expected).unwrap();
    assert_eq!(parts.len(), 1);
    (expected, parts.pop().unwrap())
}
fn decode_fresh(nonce: u64, pieces: Option<usize>) -> Counts {
    // Both representations use fresh encoder-produced storage, with the same
    // ownership state. There is no input reuse, extra Bytes clone or warmup.
    let (expected, frame) = fresh_frame(nonce);
    let mut segments = Vec::new();
    let (parsed, counts, before, after) = if let Some(pieces) = pieces {
        assert!(pieces > 0);
        segments.resize_with(pieces - 1, Bytes::new);
        segments.push(frame);
        let before = raw_frame_copy_metrics_snapshot();
        let (parsed, counts) =
            measure(|| parse_message_segments(RawSocketSerializer::Flatbuffers, segments).unwrap());
        let after = raw_frame_copy_metrics_snapshot();
        (parsed, counts, before, after)
    } else {
        let before = raw_frame_copy_metrics_snapshot();
        let (parsed, counts) =
            measure(|| parse_message(RawSocketSerializer::Flatbuffers, frame).unwrap());
        let after = raw_frame_copy_metrics_snapshot();
        (parsed, counts, before, after)
    };
    assert_eq!(parsed.message, expected);
    assert_eq!(
        after.coalescing_copy_bytes_total - before.coalescing_copy_bytes_total,
        0
    );
    assert_eq!(
        after.range_copy_bytes_total - before.range_copy_bytes_total,
        0
    );
    assert!(counts.calls > 0 && counts.requested_bytes > 0);
    counts
}
#[test]
fn contiguous_control_decodes_and_counter_observes_real_requests() {
    let ((boxed, vector), positive) =
        measure(|| (black_box(Box::new([1_u8; 19])), black_box(vec![7_u8; 37])));
    assert!(positive.calls >= 2 && positive.requested_bytes >= 56);
    drop((boxed, vector));
    let (value, zero) = measure(|| black_box(19_u64));
    assert_eq!(value, 19);
    assert_eq!(zero, Counts::default());
    decode_fresh(170_000_001, None);
}
#[test]
fn bounded_short_segments_match_the_contiguous_allocation_budget() {
    let control = decode_fresh(170_000_010, None);
    for (index, pieces) in [1, 2, 64].into_iter().enumerate() {
        let observed = decode_fresh(170_000_011 + index as u64, Some(pieces));
        eprintln!(
            "OBSERVED pieces={pieces} control={control:?} segmented={observed:?} calls_delta={} requested_bytes_delta={}",
            observed.calls as i64 - control.calls as i64,
            observed.requested_bytes as i64 - control.requested_bytes as i64
        );
        assert_eq!(
            observed, control,
            "A bounded short segment list must not allocate an avoidable heap lookup index"
        );
    }
    // The indexed side of the stride boundary still performs complete decode.
    decode_fresh(170_000_020, Some(65));
}
