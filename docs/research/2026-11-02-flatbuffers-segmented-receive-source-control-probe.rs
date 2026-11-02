//! Read-only two-source diagnostic. The before arm explicitly EXPECTS the known
//! copy defect; it is not an accepted zero-copy baseline. Counts are requested
//! allocation sizes and observed frame-copy bytes, never RSS or transport timing.
const BEFORE_COPYING_DECODER: bool = cfg!(before_copying_decoder);
use bytes::Bytes;
use ct_core::{
    encode_flatbuffers_message_segments, parse_message, parse_message_segments, ParsedMessage,
    RawSocketSerializer, WampRawFrame as RawFrame, WampMessage, WampPayload as Payload, raw_frame_copy_metrics_snapshot,
};
use serde_value::Value;
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::collections::BTreeMap;
use std::hint::black_box;
use std::path::PathBuf;
#[derive(Clone, Copy, Default, Debug)]
struct Counts {
    calls: usize,
    requested_bytes: usize,
}
thread_local! { static COUNTS: Cell<Option<Counts>> = const { Cell::new(None) }; }
fn record(size: usize) {
    let _ = COUNTS.try_with(|cell| {
        if let Some(mut c) = cell.get() {
            c.calls += 1;
            c.requested_bytes += size;
            cell.set(Some(c));
        }
    });
}
struct Counting;
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        record(l.size());
        unsafe { System.alloc(l) }
    }
    unsafe fn alloc_zeroed(&self, l: Layout) -> *mut u8 {
        record(l.size());
        unsafe { System.alloc_zeroed(l) }
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        unsafe { System.dealloc(p, l) }
    }
    unsafe fn realloc(&self, p: *mut u8, l: Layout, n: usize) -> *mut u8 {
        record(n);
        unsafe { System.realloc(p, l, n) }
    }
}
#[global_allocator]
static ALLOCATOR: Counting = Counting;
fn measure<T>(f: impl FnOnce() -> T) -> (T, Counts) {
    COUNTS.with(|c| {
        assert!(c.get().is_none());
        c.set(Some(Counts::default()));
    });
    let value = f();
    let counts = COUNTS.with(|c| c.replace(None).unwrap());
    (value, counts)
}
fn pattern(i: usize, nonce: u64) -> u8 {
    if i < 8 {
        return nonce.to_le_bytes()[i];
    }
    let mut x = nonce.wrapping_add((i as u64).wrapping_mul(0x9e3779b97f4a7c15));
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
    (x ^ (x >> 31)) as u8
}
fn cases() -> Vec<(&'static str, &'static str, &'static str, usize)> {
    let mut result = Vec::new();
    for variant in ["Call", "Invocation", "Result", "Publish", "Event"] {
        for shape in ["control", "opaque", "args", "args_kwargs"] {
            for size in [0, 10 * 1024, 1024 * 1024] {
                if shape == "control" && size != 0 {
                    continue;
                }
                result.push((variant, "plain", shape, size));
            }
        }
        for size in [0, 10 * 1024, 1024 * 1024] {
            result.push((variant, "ppt", "opaque", size));
        }
        if matches!(variant, "Call" | "Invocation" | "Result") {
            for size in [0, 10 * 1024, 1024 * 1024] {
                result.push((variant, "ppt_progressive", "opaque", size));
            }
        }
    }
    result
}
fn prepare(variant: &str, meta: &str, shape: &str, size: usize, nonce: u64) -> WampMessage {
    // All body, ordinary-container, URI and metadata preparation is fresh and outside measure().
    let body: Vec<u8> = (0..size).map(|i| pattern(i, nonce)).collect();
    let mut payload = Payload::default();
    match shape {
        "control" => {}
        "opaque" => payload.transparent = Some(Bytes::from(body)),
        "args" | "args_kwargs" => {
            payload.args = Some(Bytes::from(
                serde_cbor::to_vec(&Value::Seq(vec![Value::Bytes(body)])).unwrap(),
            ));
            if shape == "args_kwargs" {
                let map = BTreeMap::from([(
                    Value::String("k".to_owned()),
                    Value::Bytes(nonce.to_le_bytes().to_vec()),
                )]);
                payload.kwargs = Some(Bytes::from(serde_cbor::to_vec(&Value::Map(map)).unwrap()));
            }
        }
        _ => unreachable!(),
    }
    let mut dictionary = BTreeMap::new();
    if meta != "plain" {
        dictionary.insert(
            Value::String("ppt_scheme".into()),
            Value::String("wamp".into()),
        );
        dictionary.insert(
            Value::String("ppt_serializer".into()),
            Value::String("flatbuffers".into()),
        );
        if meta == "ppt_progressive" {
            dictionary.insert(
                Value::String(
                    if variant == "Result" {
                        "progress"
                    } else {
                        "receive_progress"
                    }
                    .into(),
                ),
                Value::Bool(true),
            );
        }
    }
    match variant {
        "Call" => WampMessage::Call {
            request_id: nonce + 42,
            procedure: "com.example.probe".to_owned(),
            options: dictionary,
            payload,
        },
        "Invocation" => WampMessage::Invocation {
            request_id: nonce + 42,
            registration_id: nonce + 101,
            details: dictionary,
            payload,
        },
        "Result" => WampMessage::Result {
            request_id: nonce + 42,
            details: dictionary,
            payload,
        },
        "Publish" => WampMessage::Publish {
            request_id: nonce + 42,
            topic: "com.example.probe".to_owned(),
            options: dictionary,
            payload,
        },
        "Event" => WampMessage::Event {
            subscription_id: nonce + 42,
            publication_id: nonce + 101,
            details: dictionary,
            payload,
        },
        _ => unreachable!(),
    }
}
fn payload(message: &WampMessage) -> &Payload {
    match message {
        WampMessage::Call { payload, .. }
        | WampMessage::Invocation { payload, .. }
        | WampMessage::Result { payload, .. }
        | WampMessage::Publish { payload, .. }
        | WampMessage::Event { payload, .. } => payload,
        _ => unreachable!(),
    }
}
fn verify_decoded(
    message: &WampMessage,
    parsed: &ParsedMessage,
    ranges: &[(usize, usize)],
    shape: &str,
    size: usize,
    nonce: u64,
    mode: &str,
) {
    assert!(COUNTS.with(|c| c.get().is_none()));
    assert_eq!(
        &parsed.message, message,
        "Full decoded schema/metadata/message mismatch"
    );
    // Prove the original storage is still owned after decoder return and again
    // after producer release, without cloning/promoting input Bytes beforehand.
    match (&parsed.raw, !BEFORE_COPYING_DECODER && mode == "segmented") {
        (RawFrame::Segmented { segments, len }, true) => {
            assert_eq!(segments.len(), ranges.len());
            assert_eq!(*len, ranges.iter().map(|(_, len)| *len).sum::<usize>());
            for (segment, (base, len)) in segments.iter().zip(ranges) {
                assert_eq!(segment.as_ptr() as usize, *base);
                assert_eq!(segment.len(), *len);
            }
        }
        (RawFrame::Contiguous(bytes), false) => {
            assert_eq!(bytes.len(), ranges.iter().map(|(_, len)| *len).sum::<usize>());
            if ranges.len() == 1 { assert_eq!(bytes.as_ptr() as usize, ranges[0].0); }
        }
        _ => panic!("Unexpected received-storage owner/representation"),
    }
    for part in [
        &payload(&parsed.message).args,
        &payload(&parsed.message).kwargs,
        &payload(&parsed.message).transparent,
    ]
    .into_iter()
    .flatten()
    {
        let ptr = part.as_ptr() as usize;
        if !part.is_empty() {
            let alias = ranges.iter().any(|(base, len)| ptr >= *base
                && ptr.checked_add(part.len()).unwrap() <= base.checked_add(*len).unwrap());
            let expected_alias = !BEFORE_COPYING_DECODER || ranges.len() == 1;
            assert_eq!(alias, expected_alias,
                "Original input pointer: baseline segmented coalescing is a KNOWN DEFECT; candidate and contiguous controls must alias");
        }
    }
    let p = payload(&parsed.message);
    let body = if shape == "opaque" {
        p.transparent.as_ref().unwrap().to_vec()
    } else if shape == "control" {
        Vec::new()
    } else {
        let Value::Seq(mut values) = serde_cbor::from_slice(p.args.as_ref().unwrap()).unwrap()
        else {
            panic!("args")
        };
        assert_eq!(values.len(), 1);
        let Value::Bytes(body) = values.remove(0) else {
            panic!("body")
        };
        body
    };
    assert_eq!(body.len(), size);
    assert!(
        body.iter()
            .enumerate()
            .all(|(i, b)| *b == pattern(i, nonce)),
        "Full decoded fresh body mismatch"
    );
}
fn decode_once(
    message: WampMessage,
    mode: &str,
    shape: &str,
    size: usize,
    nonce: u64,
    sample: bool,
) -> (Vec<u8>, Counts, usize, u64, u64) {
    // A fresh producer/message/body and actual encoded receiver input precede the decoder counter.
    let parts = encode_flatbuffers_message_segments(&message).unwrap();
    let wire: Vec<u8> = parts.iter().flat_map(|b| b.iter().copied()).collect();
    let part_count = parts.len();
    let (parsed, c, ranges, before_copies) = if mode == "contiguous" {
        let raw = Bytes::from(wire.clone());
        let ranges = vec![(raw.as_ptr() as usize, raw.len())];
        drop(parts);
        let before_copies = raw_frame_copy_metrics_snapshot();
        let (result, c) = if sample {
            measure(|| parse_message(RawSocketSerializer::Flatbuffers, raw))
        } else {
            (
                parse_message(RawSocketSerializer::Flatbuffers, raw),
                Counts::default(),
            )
        };
        (result.unwrap(), c, ranges, before_copies)
    } else {
        let ranges = parts
            .iter()
            .map(|b| (b.as_ptr() as usize, b.len()))
            .collect::<Vec<_>>();
        let before_copies = raw_frame_copy_metrics_snapshot();
        let (result, c) = if sample {
            measure(|| parse_message_segments(RawSocketSerializer::Flatbuffers, parts))
        } else {
            (
                parse_message_segments(RawSocketSerializer::Flatbuffers, parts),
                Counts::default(),
            )
        };
        (result.unwrap(), c, ranges, before_copies)
    };
    let after_copies = raw_frame_copy_metrics_snapshot();
    let coalesced = after_copies.coalescing_copy_bytes_total - before_copies.coalescing_copy_bytes_total;
    let range_copied = after_copies.range_copy_bytes_total - before_copies.range_copy_bytes_total;
    let expected = if BEFORE_COPYING_DECODER && mode == "segmented" && part_count > 1 { wire.len() as u64 } else { 0 };
    assert_eq!(coalesced, expected, "Explicit before-defect/candidate copy-control expectation");
    assert_eq!(range_copied, 0, "Every application field is contained in an actual encoded input piece");
    verify_decoded(&message, &parsed, &ranges, shape, size, nonce, mode);
    drop(message);
    // ParsedMessage itself still owns its actual input frame after all producer owners are dropped.
    verify_decoded(&parsed.message, &parsed, &ranges, shape, size, nonce, mode);
    (wire, c, part_count, coalesced, range_copied)
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let arg = std::env::args()
        .nth(1)
        .ok_or("pass --selftest or a new output directory")?;
    let ((bytes, vec), test) =
        measure(|| (black_box(Box::new([1u8; 19])), black_box(vec![7u8; 37])));
    assert!(test.calls >= 2 && test.requested_bytes >= 56);
    drop((bytes, vec));
    let (untouched, c) = measure(|| black_box(17u64));
    assert_eq!(untouched, 17);
    assert_eq!((c.calls, c.requested_bytes), (0, 0));
    if arg == "--selftest" {
        for (i, (variant, meta, shape, size)) in cases().into_iter().enumerate() {
            for (j, mode) in ["contiguous", "segmented"].into_iter().enumerate() {
                let nonce = (if BEFORE_COPYING_DECODER { 122_000_000 } else { 124_000_000 }) + 2 * i as u64 + j as u64 + 1;
                let message = prepare(variant, meta, shape, size, nonce);
                decode_once(message, mode, shape, size, nonce, false);
            }
        }
        println!("SELFTEST PASS: allocator positive/zero controls; all148 fullsize decoder shapes/modes/metadata and complete fresh body/EXPECTED-source-alias/copy/roundtrip checks");
        return Ok(());
    }
    let output = PathBuf::from(arg);
    std::fs::create_dir(&output)?;
    let mut case = 0u64;
    for (variant, meta, shape, size) in cases() {
        for mode in ["contiguous", "segmented"] {
            for repeat in 1..=5 {
                case += 1;
                let nonce = (if BEFORE_COPYING_DECODER { 123_000_000 } else { 125_000_000 }) + case;
                let message = prepare(variant, meta, shape, size, nonce);
                let (wire, c, segments, coalesced, range_copied) = decode_once(message, mode, shape, size, nonce, true);
                std::fs::write(
                    output.join(format!(
                        "{nonce}-{variant}-{meta}-{shape}-{size}-{mode}-{repeat}.bin"
                    )),
                    &wire,
                )?;
                println!(
                    "{}",
                    serde_json::json!({"case":case,"variant":variant,"metadata":meta,"shape":shape,"body_bytes":size,"input_mode":mode,"repeat":repeat,"fresh_nonce":nonce,"calls":c.calls,"requested_bytes":c.requested_bytes,"wire_bytes":wire.len(),"input_segments":segments,"full_body_roundtrip_expected_source_alias_verified":true,"arm":if BEFORE_COPYING_DECODER {"before_known_copy_defect"}else{"candidate"},"coalesced_bytes":coalesced,"range_copy_bytes":range_copied,"scope":"fresh_public_native_decoder_requested_allocations_and_observed_copy_bytes_NOT_RSS_timing_transport_or_acceptance"})
                );
            }
        }
    }
    assert_eq!(case, 740);
    Ok(())
}
