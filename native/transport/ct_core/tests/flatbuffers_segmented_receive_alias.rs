//! A contained application allocation must survive fragmented WAMP receive without whole-frame coalescing.
use bytes::Bytes;
use ct_core::{
    encode_flatbuffers_message_segments, parse_message, parse_message_segments,
    raw_frame_copy_metrics_snapshot, RawSocketSerializer, WampMessage, WampPayload,
};
use serde_value::Value;
use std::collections::BTreeMap;
use std::sync::Mutex;

// The public copy counters are process-wide, including in integration tests.
// Recover poisoning because the pre-fix alias assertion intentionally fails.
static COPY_METRICS: Mutex<()> = Mutex::new(());
fn pattern(index: usize, seed: u64) -> u8 {
    ((index as u64).wrapping_mul(131) ^ seed.rotate_left((index % 61) as u32)) as u8
}
fn fresh_call(seed: u64) -> WampMessage {
    WampMessage::Call {
        request_id: seed,
        procedure: "bench.rpc.echo".to_owned(),
        options: BTreeMap::from([
            (
                Value::String("ppt_scheme".into()),
                Value::String("x_connectanum_bench_typed".into()),
            ),
            (
                Value::String("ppt_serializer".into()),
                Value::String("flatbuffers".into()),
            ),
        ]),
        payload: WampPayload {
            transparent: Some(Bytes::from(
                (0..10240).map(|i| pattern(i, seed)).collect::<Vec<_>>(),
            )),
            ..WampPayload::default()
        },
    }
}
fn opaque(message: &WampMessage) -> &Bytes {
    let WampMessage::Call { payload, .. } = message else {
        panic!("CALL")
    };
    payload.transparent.as_ref().unwrap()
}
#[test]
fn segmented_flatbuffers_receive_retains_the_contained_application_segment() {
    let _guard = COPY_METRICS
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let seed = 77_000_001;
    let message = fresh_call(seed);
    let original = opaque(&message).as_ptr();
    let segments = encode_flatbuffers_message_segments(&message).unwrap();
    assert!(segments.len() > 1);
    assert_eq!(
        segments
            .iter()
            .filter(|s| s.as_ptr() == original && s.len() == 10240)
            .count(),
        1
    );
    let before = raw_frame_copy_metrics_snapshot();
    let parsed = parse_message_segments(RawSocketSerializer::Flatbuffers, segments).unwrap();
    let after = raw_frame_copy_metrics_snapshot();
    assert_eq!(parsed.message, message);
    eprintln!(
        "segmented receive coalesced_bytes={} range_copy_bytes={}",
        after.coalescing_copy_bytes_total - before.coalescing_copy_bytes_total,
        after.range_copy_bytes_total - before.range_copy_bytes_total
    );
    assert_eq!(
        opaque(&parsed.message).as_ptr(),
        original,
        "segmented FlatBuffers receive still coalesces a contained application vector"
    );
    assert!(parsed.raw.as_contiguous().is_none());
    assert_eq!(
        after.coalescing_copy_bytes_total - before.coalescing_copy_bytes_total,
        0,
        "no complete-frame copy"
    );
    assert_eq!(
        after.range_copy_bytes_total - before.range_copy_bytes_total,
        0,
        "the entire application field is inside one real input segment"
    );
    drop(message);
    assert!(opaque(&parsed.message)
        .iter()
        .enumerate()
        .all(|(i, b)| *b == pattern(i, seed)));
}
#[test]
fn contiguous_flatbuffers_receive_still_borrows_the_wire_allocation() {
    let _guard = COPY_METRICS
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let seed = 77_000_002;
    let message = fresh_call(seed);
    let parts = encode_flatbuffers_message_segments(&message).unwrap();
    let wire = Bytes::from(
        parts
            .iter()
            .flat_map(|b| b.iter().copied())
            .collect::<Vec<_>>(),
    );
    drop(parts);
    let base = wire.as_ptr() as usize;
    let end = base + wire.len();
    let before = raw_frame_copy_metrics_snapshot();
    let parsed = parse_message(RawSocketSerializer::Flatbuffers, wire).unwrap();
    let after = raw_frame_copy_metrics_snapshot();
    assert_eq!(parsed.message, message);
    let body = opaque(&parsed.message);
    assert!((body.as_ptr() as usize) >= base && (body.as_ptr() as usize) + body.len() <= end);
    assert!(parsed.raw.as_contiguous().is_some());
    assert_eq!(
        after.coalescing_copy_bytes_total - before.coalescing_copy_bytes_total,
        0
    );
    assert_eq!(
        after.range_copy_bytes_total - before.range_copy_bytes_total,
        0
    );
    drop(message);
    assert!(opaque(&parsed.message)
        .iter()
        .enumerate()
        .all(|(i, b)| *b == pattern(i, seed)));
}
