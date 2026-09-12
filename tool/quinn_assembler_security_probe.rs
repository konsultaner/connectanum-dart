//! Bounded source-level probe of the resolved upstream QUIC assembler.
//!
//! Compile with QUINN_PROTO_SOURCE pointing at the resolved crate's src
//! directory and --extern bytes pointing at its built dependency. This uses
//! upstream implementation files verbatim; it is not a network/FFI integration
//! test and does not vendor or modify the production dependency.
#![allow(dead_code)]

mod range_set {
    include!(concat!(
        env!("QUINN_PROTO_SOURCE"),
        "/range_set/btree_range_set.rs"
    ));
}

mod assembler {
    include!(concat!(
        env!("QUINN_PROTO_SOURCE"),
        "/connection/assembler.rs"
    ));
}

fn insert(assembler: &mut assembler::Assembler, offset: u64, payload: bytes::Bytes) -> bool {
    // Both the vulnerable void API and the fixed Result API compile, so the
    // identical probe can demonstrate failure before the dependency upgrade.
    let allocation_size = payload.len();
    let result = assembler.insert(offset, payload.slice(..1), allocation_size);
    format!("{result:?}").starts_with("Err(")
}

fn main() {
    let mut normal = assembler::Assembler::new();
    for index in 0..1000 {
        assert!(!insert(&mut normal, index * 2 + 1, vec![42; 1500].into()));
    }
    assert!(normal.read(2000, true).is_none());
    let _ = normal.insert(0, vec![42; 2000].into(), 2000);
    let mut received = 0;
    while let Some(chunk) = normal.read(2000, true) {
        assert!(chunk.bytes.iter().all(|byte| *byte == 42));
        received += chunk.bytes.len();
    }
    assert_eq!(received, 2000, "ordinary reordering/overlaps lost data");

    let mut malicious = assembler::Assembler::new();
    for index in 0..4096 {
        // Each one-byte fragment retains its own packet-sized allocation,
        // with a missing prefix and gaps that defragmentation cannot merge.
        if insert(&mut malicious, index * 2 + 1, vec![42; 1500].into()) {
            println!(
                "ordinary_reordering=pass gapped_fragments_rejected_at={}",
                index + 1
            );
            return;
        }
        assert!(malicious.read(8192, true).is_none());
    }
    panic!("4096 gapped fragments accepted without a resource-limit error");
}
