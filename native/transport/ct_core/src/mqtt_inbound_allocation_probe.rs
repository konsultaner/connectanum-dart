//! Test-only requested-allocation census of the actual private queue consumer.
//! No timing, RSS, physical allocation, transport or gate acceptance is inferred.
use super::*;
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::hint::black_box;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Counts {
    allocs: usize,
    reallocs: usize,
    requested: usize,
    events: usize,
    sizes: [usize; 32],
}
thread_local! { static COUNTS: Cell<Option<Counts>> = const { Cell::new(None) }; }
thread_local! { static PAUSE_AT_PAIR_ALLOCATION: Cell<bool> = const { Cell::new(false) }; }
static PAIR_ALLOCATION_REACHED: AtomicBool = AtomicBool::new(false);
static LATE_PRODUCER_DONE: AtomicU64 = AtomicU64::new(0);
fn allow_producer_after_capacity_choice(size: usize) {
    if size != 256 {
        return;
    }
    let _ = PAUSE_AT_PAIR_ALLOCATION.try_with(|armed| {
        if armed.replace(false) {
            // Test-only rendezvous, before System allocation and without holding
            // a queue/malloc lock. No production hook or sleep is involved.
            PAIR_ALLOCATION_REACHED.store(true, Ordering::Release);
            while LATE_PRODUCER_DONE.load(Ordering::Acquire) == 0 {
                std::thread::yield_now();
            }
        }
    });
}
fn record(size: usize, realloc: bool) {
    let _ = COUNTS.try_with(|state| {
        if let Some(mut count) = state.get() {
            count.allocs += usize::from(!realloc);
            count.reallocs += usize::from(realloc);
            count.requested += size;
            if count.events < count.sizes.len() {
                count.sizes[count.events] = size;
            }
            count.events += 1;
            state.set(Some(count));
        }
    });
}
struct ForwardSystem;
unsafe impl GlobalAlloc for ForwardSystem {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        record(layout.size(), false);
        allow_producer_after_capacity_choice(layout.size());
        unsafe { System.alloc(layout) }
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        record(layout.size(), false);
        unsafe { System.alloc_zeroed(layout) }
    }
    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        record(size, true);
        unsafe { System.realloc(pointer, layout, size) }
    }
    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        unsafe { System.dealloc(pointer, layout) }
    }
}
#[global_allocator]
static ALLOCATOR: ForwardSystem = ForwardSystem;
fn measure<T>(operation: impl FnOnce() -> T) -> (T, Counts) {
    struct DisableOnUnwind;
    impl Drop for DisableOnUnwind {
        fn drop(&mut self) {
            COUNTS.with(|state| state.set(None));
        }
    }
    COUNTS.with(|state| {
        assert!(state.get().is_none());
        state.set(Some(Counts::default()));
    });
    let guard = DisableOnUnwind;
    let value = operation();
    let counts = COUNTS.with(|state| state.replace(None).unwrap());
    drop(guard);
    (value, counts)
}

#[derive(Clone, Debug, serde::Serialize)]
struct Shape {
    name: &'static str,
    lengths: Vec<usize>,
    cap: usize,
    disconnect: bool,
}
fn shapes() -> Vec<Shape> {
    let mut cases = vec![
        ("empty-open", vec![], 65536),
        ("single128", vec![128], 65536),
        ("two128", vec![128; 2], 65536),
        ("three128", vec![128; 3], 65536),
        ("many32x128", vec![128; 32], 65536),
        ("many64x128", vec![128; 64], 65536),
        ("many512x128", vec![128; 512], 65536),
        ("many513x128", vec![128; 513], 65536),
        ("single65536", vec![65536], 65536),
        ("two4096", vec![4096; 2], 65536),
        ("two8192", vec![8192; 2], 65536),
        ("mixed128-8192-128", vec![128, 8192, 128], 65536),
        ("first8192-128", vec![8192, 128], 65536),
        ("oversize65537", vec![65537], 65536),
        ("split150-300-cap200", vec![150, 300], 200),
        ("exact256", vec![128; 2], 256),
        ("tail256", vec![128; 3], 256),
        ("empty-pieces", vec![0, 128, 0, 128], 65536),
    ]
    .into_iter()
    .map(|(name, lengths, cap)| Shape {
        name,
        lengths,
        cap,
        disconnect: false,
    })
    .collect::<Vec<_>>();
    cases.push(Shape {
        name: "empty-disconnected",
        lengths: vec![],
        cap: 65536,
        disconnect: true,
    });
    cases.push(Shape {
        name: "drain-disconnected",
        lengths: vec![128, 65537, 128],
        cap: 65536,
        disconnect: true,
    });
    cases
}
// Every row owns newly allocated chunks with disjoint row/chunk nonce keys.
// Inputs are raw transport chunks, not an MQTT protocol/client benchmark.
fn pattern(nonce: u64, chunk: usize, offset: usize) -> u8 {
    if offset < 8 {
        return nonce.to_le_bytes()[offset];
    }
    if offset < 16 {
        return (chunk as u64).to_le_bytes()[offset - 8];
    }
    let mut word = nonce
        ^ (chunk as u64 + 1)
            .wrapping_mul(0x9e3779b185ebca87_u64)
            .wrapping_add(offset as u64);
    word = (word ^ (word >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    word = (word ^ (word >> 27)).wrapping_mul(0x94d049bb133111eb);
    (word ^ (word >> 31)) as u8
}
fn fresh(nonce: u64, chunk: usize, len: usize) -> Bytes {
    Bytes::from(
        (0..len)
            .map(|i| pattern(nonce, chunk, i))
            .collect::<Vec<_>>(),
    )
}

#[derive(Debug, serde::Serialize)]
struct Call {
    output_len: Option<usize>,
    error: Option<&'static str>,
    aliased_input: bool,
    allocs: usize,
    reallocs: usize,
    requested: usize,
    request_sizes: Vec<usize>,
}
#[derive(Debug, serde::Serialize)]
struct Row {
    shape: Shape,
    nonce: u64,
    calls: Vec<Call>,
    input_bytes: usize,
    output_sha1: String,
    full_bytes_verified: bool,
    survives_queue_release: bool,
}
fn run_shape(shape: Shape, nonce: u64) -> Row {
    let (sender, receiver) = mpsc::channel(shape.lengths.len().max(1));
    let mut originals = Vec::with_capacity(shape.lengths.len());
    for (chunk, &len) in shape.lengths.iter().enumerate() {
        let bytes = fresh(nonce, chunk, len);
        originals.push((bytes.as_ptr() as usize, bytes.len()));
        // Never clone queued Bytes for verification: ownership affects promotion.
        sender.try_send(bytes).unwrap();
    }
    let sender = if shape.disconnect {
        drop(sender);
        None
    } else {
        Some(sender)
    };
    let mut inbound = MqttInbound::new(receiver);
    let total: usize = shape.lengths.iter().sum();
    let bound = shape.lengths.len() + total / shape.cap + 4;
    let mut outputs = Vec::with_capacity(bound);
    let mut calls = Vec::with_capacity(bound);
    for _ in 0..bound {
        // Only the real private operation is inside the thread-local counter.
        let (result, count) = measure(|| inbound.try_recv_limited(black_box(shape.cap)));
        assert!(
            count.events <= count.sizes.len(),
            "request-event truncation"
        );
        let mut call = Call {
            output_len: None,
            error: None,
            aliased_input: false,
            allocs: count.allocs,
            reallocs: count.reallocs,
            requested: count.requested,
            request_sizes: count.sizes[..count.events].to_vec(),
        };
        match result {
            Ok(bytes) => {
                assert!(bytes.len() <= shape.cap);
                call.output_len = Some(bytes.len());
                let start = bytes.as_ptr() as usize;
                call.aliased_input = !bytes.is_empty()
                    && originals
                        .iter()
                        .any(|&(p, n)| start >= p && start + bytes.len() <= p + n);
                outputs.push(bytes);
                calls.push(call);
            }
            Err(error) => {
                assert_eq!(
                    error,
                    if shape.disconnect {
                        TryRecvError::Disconnected
                    } else {
                        TryRecvError::Empty
                    }
                );
                call.error = Some(if shape.disconnect {
                    "disconnected"
                } else {
                    "empty"
                });
                calls.push(call);
                break;
            }
        }
    }
    assert!(
        calls.last().unwrap().error.is_some(),
        "poll bound exhausted"
    );
    assert!(inbound.pending.is_none());
    drop(inbound);
    drop(sender);
    // Verify every byte after releasing both queue endpoints and pending owner.
    let mut output = outputs.iter().flat_map(|b| b.iter().copied());
    let mut hash = Sha1::new();
    for (chunk, &len) in shape.lengths.iter().enumerate() {
        for offset in 0..len {
            let value = output.next().expect("missing byte");
            assert_eq!(value, pattern(nonce, chunk, offset));
            hash.update([value]);
        }
    }
    assert!(output.next().is_none(), "extra bytes");
    Row {
        shape,
        nonce,
        calls,
        input_bytes: total,
        output_sha1: format!("{:x}", hash.finalize()),
        full_bytes_verified: true,
        survives_queue_release: true,
    }
}

#[test]
fn mqtt_probe_counter_and_wake_ownership_controls() {
    let (boxed, count) = measure(|| black_box(Box::new([0_u8; 19])));
    assert_eq!((count.allocs, count.reallocs, count.requested), (1, 0, 19));
    drop(boxed);
    let (_, zero) = measure(|| black_box(19_u64));
    assert_eq!(zero, Counts::default());
    // Reallocation is a new requested size, not live or physical allocation.
    let layout = Layout::from_size_align(17, 1).unwrap();
    let (pointer, count) = measure(|| unsafe { std::alloc::alloc(layout) });
    assert!(!pointer.is_null());
    assert_eq!((count.allocs, count.requested), (1, 17));
    let (grown, count) = measure(|| unsafe { std::alloc::realloc(pointer, layout, 53) });
    assert!(!grown.is_null());
    assert_eq!((count.reallocs, count.requested), (1, 53));
    unsafe { std::alloc::dealloc(grown, Layout::from_size_align(53, 1).unwrap()) };

    let (sender, receiver) = mpsc::channel(2);
    let mut inbound = MqttInbound::new(receiver);
    let pending = AtomicBool::new(true);
    let nonce = fresh_live_test_nonce();
    let raced = fresh(nonce, 0, 128);
    let p = raced.as_ptr();
    let out = inbound
        .poll_with_wake_reset(65536, &pending, || {
            assert!(!pending.load(Ordering::Acquire));
            sender.try_send(raced).unwrap();
        })
        .unwrap();
    assert_eq!(out.as_ptr(), p);
    assert!(!pending.load(Ordering::Acquire));
    drop(inbound);
    drop(sender);
    assert!(out
        .iter()
        .enumerate()
        .all(|(i, b)| *b == pattern(nonce, 0, i)));

    let (sender, receiver) = mpsc::channel(1);
    drop(sender);
    let mut inbound = MqttInbound::new(receiver);
    pending.store(true, Ordering::Release);
    assert!(inbound
        .poll_with_wake_reset(65536, &pending, || panic!("disconnected must not reset"))
        .is_none());
    assert!(pending.load(Ordering::Acquire));
}

fn fresh_queue_control(nonce: u64) -> Counts {
    let (sender, mut receiver) = mpsc::channel(1);
    sender.try_send(fresh(nonce, 0, 128)).unwrap();
    let (value, counts) = measure(|| receiver.try_recv());
    let value = value.unwrap();
    drop(receiver);
    drop(sender);
    assert!(value
        .iter()
        .enumerate()
        .all(|(i, b)| *b == pattern(nonce, 0, i)));
    counts
}
#[test]
fn mqtt_probe_full_matrix_preflight() {
    // Fresh bounded queues may initialize platform-specific synchronization on
    // first receive. Retain that real cost and compare the single-chunk path to
    // an independently fresh direct queue receive; do not warm it away.
    let direct = fresh_queue_control(fresh_live_test_nonce());
    let mutex = Mutex::new(());
    let (guard, lock_counts) = measure(|| mutex.lock().unwrap());
    drop(guard);
    println!("FRESH_QUEUE_CONTROL {direct:?} MUTEX_CONTROL {lock_counts:?}");
    for shape in shapes() {
        let row = run_shape(shape, fresh_live_test_nonce());
        match row.shape.name {
            "empty-open" | "empty-disconnected" => {
                assert!(
                    row.calls.iter().all(|c| c.allocs == 0 && c.reallocs == 0),
                    "unexpected requests in {row:?}"
                );
            }
            "single128" | "single65536" => {
                let first = &row.calls[0];
                assert!(first.aliased_input);
                assert_eq!(
                    (first.allocs, first.reallocs, first.requested),
                    (direct.allocs, direct.reallocs, direct.requested),
                    "single-chunk consumer differs from direct fresh queue: {row:?}"
                );
                assert_eq!(first.request_sizes, direct.sizes[..direct.events]);
                assert!(row.calls[1..]
                    .iter()
                    .all(|c| c.allocs == 0 && c.reallocs == 0));
            }
            "split150-300-cap200" => assert_eq!(
                row.calls
                    .iter()
                    .filter_map(|c| c.output_len)
                    .collect::<Vec<_>>(),
                [200, 200, 50]
            ),
            _ => (),
        }
    }
}

fn fresh_live_test_nonce() -> u64 {
    static NEXT: OnceLock<AtomicU64> = OnceLock::new();
    NEXT.get_or_init(|| {
        AtomicU64::new(
            std::env::var("CONNECTANUM_MQTT_CAPACITY_TEST_NONCE")
                .map(|value| value.parse().unwrap())
                .unwrap_or_else(|_| {
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_nanos() as u64
                }),
        )
    })
    .fetch_add(1, Ordering::Relaxed)
}

#[test]
fn mqtt_capacity_complete_pair_avoids_spare_buffer_and_metadata() {
    let direct = fresh_queue_control(fresh_live_test_nonce());
    let row = run_shape(
        Shape {
            name: "complete-pair-budget",
            lengths: vec![128, 128],
            cap: 65536,
            disconnect: false,
        },
        fresh_live_test_nonce(),
    );
    let call = &row.calls[0];
    println!("COMPLETE_PAIR_OBSERVATION row={row:?} direct={direct:?}");
    assert_eq!(
        call.allocs - direct.allocs,
        1,
        "complete_pair_output_allocations"
    );
    assert_eq!(call.reallocs, 0);
    assert_eq!(call.requested - direct.requested, 256);
    assert_eq!(call.output_len, Some(256));
}

#[test]
fn mqtt_capacity_more_queued_retains_original_growth() {
    let direct = fresh_queue_control(fresh_live_test_nonce());
    let row = run_shape(
        Shape {
            name: "more-queued-growth-control",
            lengths: vec![128; 3],
            cap: 65536,
            disconnect: false,
        },
        fresh_live_test_nonce(),
    );
    let call = &row.calls[0];
    assert_eq!(call.allocs - direct.allocs, 2);
    assert_eq!(call.reallocs, 0);
    assert_eq!(call.requested - direct.requested, 4096 + 24);
    assert_eq!(call.output_len, Some(384));
}

#[test]
fn mqtt_capacity_pending_tail_precedes_queued_and_later_bytes() {
    for cap in [4096, 16384, 65536] {
        let row = run_shape(
            Shape {
                name: "split-before-queued",
                lengths: vec![64, cap, 24],
                cap,
                disconnect: true,
            },
            fresh_live_test_nonce(),
        );
        assert_eq!(
            row.calls
                .iter()
                .filter_map(|call| call.output_len)
                .collect::<Vec<_>>(),
            [cap, 88]
        );
    }
    // This is a post-call producer control, not a forced arrival at is_empty.
    let nonce = fresh_live_test_nonce();
    let (sender, receiver) = mpsc::channel(4);
    let first = fresh(nonce, 0, 128);
    let second = fresh(nonce, 1, 128);
    let later = fresh(nonce, 2, 128);
    sender.try_send(first).unwrap();
    sender.try_send(second).unwrap();
    let mut inbound = MqttInbound::new(receiver);
    let complete = inbound.try_recv_limited(65536).unwrap();
    sender.try_send(later).unwrap();
    let late = inbound.try_recv_limited(65536).unwrap();
    drop(inbound);
    drop(sender);
    assert_eq!(complete.len(), 256);
    assert!(complete
        .iter()
        .enumerate()
        .all(|(i, b)| *b == pattern(nonce, i / 128, i % 128)));
    assert_eq!(late.len(), 128);
    assert!(late
        .iter()
        .enumerate()
        .all(|(i, b)| *b == pattern(nonce, 2, i)));
}

#[test]
fn mqtt_capacity_producer_after_exact_choice_drains_with_normal_growth() {
    struct ReleaseProducer;
    impl Drop for ReleaseProducer {
        fn drop(&mut self) {
            PAUSE_AT_PAIR_ALLOCATION.with(|armed| armed.set(false));
            PAIR_ALLOCATION_REACHED.store(true, Ordering::Release);
        }
    }
    let nonce = fresh_live_test_nonce();
    let (sender, receiver) = mpsc::channel(4);
    let first = fresh(nonce, 0, 128);
    let second = fresh(nonce, 1, 128);
    let late = fresh(nonce, 2, 128);
    sender.try_send(first).unwrap();
    sender.try_send(second).unwrap();
    let mut inbound = MqttInbound::new(receiver);
    PAIR_ALLOCATION_REACHED.store(false, Ordering::Release);
    LATE_PRODUCER_DONE.store(0, Ordering::Release);
    let release = ReleaseProducer;
    let producer = std::thread::spawn(move || {
        while !PAIR_ALLOCATION_REACHED.load(Ordering::Acquire) {
            std::thread::yield_now();
        }
        let result = sender.try_send(late);
        LATE_PRODUCER_DONE.store(if result.is_ok() { 1 } else { 2 }, Ordering::Release);
    });
    PAUSE_AT_PAIR_ALLOCATION.with(|armed| armed.set(true));
    let (result, counts) = measure(|| inbound.try_recv_limited(65536));
    let triggered = !PAUSE_AT_PAIR_ALLOCATION.with(|armed| armed.replace(false));
    // Also releases a waiting producer on an unexpected non-exact branch.
    drop(release);
    producer.join().unwrap();
    assert!(triggered, "exact-capacity rendezvous was not reached");
    assert_eq!(LATE_PRODUCER_DONE.load(Ordering::Acquire), 1);
    let bytes = result.unwrap();
    assert_eq!(bytes.len(), 384);
    assert!(counts.reallocs > 0);
    drop(inbound);
    assert!(bytes
        .iter()
        .enumerate()
        .all(|(i, b)| *b == pattern(nonce, i / 128, i % 128)));
}
