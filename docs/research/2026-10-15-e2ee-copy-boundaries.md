# E2EE copy observation follow-up

The standard SDK scope requires Connectanum's explicit byte copies to remain
observable. Crypto-library computation and internal storage remain unmeasured;
nonce/tag writes performed here do not belong to that dependency exclusion.

## Reproduced gaps and changes

Portable AES copied its 12-byte nonce into the output while reporting zero
assembly bytes. A round-trip test fails first at zero instead of twelve for
both typed FlatBuffers and CBOR. It now records those twelve bytes. Nonce
randomness is generated directly in the final nonce array, removing the prior
intermediate integer-list conversion without changing nonce generation.

Native legacy CBOR coercion counted only a completely successful conversion.
The fresh-process probe fails first after copying one byte before a type error.
An explicit conversion loop with a finally block now observes successful writes
on both success and failure. Legacy integer wrapping, TypeError and Uint8List
reuse remain intact. Strict typed-profile validation stays separate.

Rust encryption also copied nonce/tag bytes outside its staging counters. An
actual-operation oracle fails first at zero instead of forty bytes for XSalsa.
The additive `ct_e2ee_nonce_tag_copy_metrics_snapshot(uint64_t*)` observes these
writes separately: forty bytes for XSalsa encryption, twenty-eight for AES
encryption, and twelve for AES nonce extraction on ordinary/in-place decryption,
including authentication failure. The AES file-encryption path is included.
Cipher processing and key material are outside this payload counter.

The old v1 struct remains sixteen bytes. The new scalar writes exactly eight
bytes, rejects a null output with -4, and preserves adjacent guards. Dart uses
optional lookup: an older production library leaves the scalar unavailable,
rather than inferring zero. Nullable deltas retain that missing capability.
Reports retain the separate process counter and include it in their known
lower bound. The complete E2EE total remains unavailable while serializer and
framing accounting is incomplete.

## Validation

Eight focused Rust crypto cases pass, including actual framing counts, retained
input/storage, empty and 64 KiB bodies, tampering, file bounds and ABI guards.
The final sequential portable/provider/report suite passes 117 cases against
the rebuilt matching library; the preceding production library correctly leaves
the additive scalar unavailable. Analysis is clean. The first combined test invocation runs
client and benchmark native-runtime users concurrently and fails on their
shared runtime shutdown; the sequential retry passes 116 cases. A later fresh
native build adds the new scalar; frozen canonical validation is pending.

An in-progress canonical fast run sees a transient unqualified ffi type while
source is being edited and fails three child-compilation checks. That name is
corrected to `ffi.Uint64`; analysis is clean. This run is not acceptance evidence.
A frozen resulting-source canonical verification remains required.

No performance parity, complete E2EE total or transcode total is established by
this checkpoint. Original matrix, sample, resource and copy gates are unchanged.

Local review raises counter-domain and integer-wrapping concerns. The native and
portable providers are alternative implementations, reported in separate fields;
there is no required synchronization or double counting. A real round-trip with
all ciphertext integers increased by 256 verifies legacy wrapping, and partial
malformed-list probes preserve TypeError. Neither concern reproduces.

The first frozen full verification keeps all twenty recorded input hashes but
fails one old live assertion (zero instead of 48 portable AES assembly bytes).
The live regression now verifies both RPC legs and exact native nonce/tag totals;
all four implementation/cipher combinations pass. Production artifacts on all
five platforms pass 170 visible cases with zero skips. Twenty-two downloaded
proof/log/archive/library hashes, ABI guards and lifecycle records are audited,
and the production library passes the fresh-process crypto probe. A fresh full
verification remains required after the assertion update.
