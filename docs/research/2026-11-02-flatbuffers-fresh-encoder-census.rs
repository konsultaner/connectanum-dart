//! Read-only diagnostic: fresh inputs, actual public encoder allocator requests.
use bytes::Bytes;
use ct_core::{
    encode_flatbuffers_message_segments, parse_message, RawSocketSerializer, WampMessage,
    WampPayload as Payload,
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
fn verify(message: &WampMessage, parts: &[Bytes], shape: &str, size: usize, nonce: u64) -> Vec<u8> {
    assert!(
        COUNTS.with(|c| c.get().is_none()),
        "Verification must remain outside allocator counter"
    );
    let p = payload(message);
    for b in [&p.args, &p.kwargs, &p.transparent].into_iter().flatten() {
        assert_eq!(
            parts
                .iter()
                .filter(|x| x.as_ptr() == b.as_ptr() && x.len() == b.len())
                .count(),
            1,
            "Every supplied allocation must remain aliased exactly once"
        );
    }
    let body = if shape == "opaque" {
        p.transparent.as_ref().unwrap().to_vec()
    } else if shape == "control" {
        Vec::new()
    } else {
        let Value::Seq(mut a) = serde_cbor::from_slice(p.args.as_ref().unwrap()).unwrap() else {
            panic!("args")
        };
        assert_eq!(a.len(), 1);
        let Value::Bytes(b) = a.remove(0) else {
            panic!("body")
        };
        b
    };
    assert_eq!(body.len(), size);
    assert!(
        body.iter()
            .enumerate()
            .all(|(i, b)| *b == pattern(i, nonce)),
        "Full fresh body mismatch"
    );
    let wire: Vec<u8> = parts.iter().flat_map(|b| b.iter().copied()).collect();
    let decoded =
        parse_message(RawSocketSerializer::Flatbuffers, Bytes::from(wire.clone())).unwrap();
    assert_eq!(
        &decoded.message, message,
        "Full schema/metadata/message/payload roundtrip mismatch"
    );
    wire
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
            let small = size;
            let nonce = 10_000_000 + i as u64 + 1;
            let m = prepare(variant, meta, shape, small, nonce);
            let p = encode_flatbuffers_message_segments(&m)?;
            verify(&m, &p, shape, small, nonce);
        }
        println!("SELFTEST PASS: allocator positive/zero controls; all74 valid schema/metadata/shape roundtrips and full fresh bodies/aliases");
        return Ok(());
    }
    let output = PathBuf::from(arg);
    std::fs::create_dir(&output)?;
    let mut case = 0u64;
    for (variant, meta, shape, size) in cases() {
        for repeat in 1..=5 {
            case += 1;
            let nonce = 1_000_000 + case;
            let message = prepare(variant, meta, shape, size, nonce);
            let (parts, c) = measure(|| encode_flatbuffers_message_segments(&message));
            let parts = parts?;
            let wire = verify(&message, &parts, shape, size, nonce);
            std::fs::write(
                output.join(format!(
                    "{nonce:03}-{variant}-{meta}-{shape}-{size}-{repeat}.bin"
                )),
                &wire,
            )?;
            println!(
                "{}",
                serde_json::json!({"case":case,"variant":variant,"metadata":meta,"shape":shape,"body_bytes":size,"repeat":repeat,"calls":c.calls,"requested_bytes":c.requested_bytes,"wire_bytes":wire.len(),"segments":parts.len(),"fresh_nonce":nonce,"full_body_roundtrip_alias_verified":true,"scope":"fresh_native_encoder_requested_allocations_only_NOT_RSS_timing_copy_or_acceptance"})
            );
        }
    }
    assert_eq!(case, 370);
    Ok(())
}
