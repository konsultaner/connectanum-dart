# Segmented decoder source comparison (2026-11-02)

The complete public Rust decoder comparison preserves **1,480 fresh operations**:
74 message/metadata/payload shapes, contiguous and segmented input, five fresh
repetitions and both frozen sources (`600e82f5` before, `d9cb93c2` candidate).
All 1,480 complete wires and 920 nonempty full bodies independently verify with
unique nonces/patterns and an independent C/Python pattern implementation.
All source archives, own canonical receipts/logs/native witnesses, three locks,
actual probe executables and all 121 static library inputs per arm rehash.

The before arm is explicitly the known copying defect, never a zero-copy pass.
Actual multipart coalescing totals 121,805,120 bytes before and zero afterward.
All 370 contiguous pairs have identical allocation-request counts and sizes.
Of the 74 segmented shapes, 69 request fewer allocation bytes. Five plain
single-piece control shapes request **one extra allocation / 32 bytes**; these
regressions are preserved and motivate a separate small-index investigation.

| Segmented CALL | Before requests | Candidate requests | Coalesced bytes per operation |
| --- | --- | --- | --- |
| Plain control, one piece | 6 / 809 bytes | 7 / 841 bytes | 0 → 0 |
| 10 KiB transparent PPT | 16 / 12,172 bytes | 15 / 1,788 bytes | 10,392 → 0 |
| 1 MiB transparent PPT | 16 / 1,050,508 bytes | 15 / 1,788 bytes | 1,048,728 → 0 |

Every listed observation occurs identically in all five fresh repetitions;
all series and rows are retained. Input preparation/encoding precedes both
counters; only public parse calls are measured. Complete message/body, actual
storage pointer/extent/representation, producer-release lifetime and copy
checks follow. No input Bytes clone prewarms ownership for pointer checks.
System allocation forwards unchanged; replacement realloc sizes are requests,
not live bytes. Candidate and contiguous controls retain input aliases; the
before multipart arm intentionally requires its observed copy/nonalias defect.

Both full-size 148-case preflights and 17 positive/adversarial guards pass before
the single capture. Earlier dependency-isolation and external-API compile
failures are retained and occurred before any measured rows. Root review
qualifies advisory claims against owning storage and actual counter boundaries.
A later read-only auditor syntax correction changed no observation or source.
The four direct codec dependency archives are identical across arms. Five TLS
archives differ despite identical bound sources; the cause is unmeasured.
Those byte identities remain recorded. This synchronous codec diagnostic makes
no TLS, FFI, timing, RSS, transport-parity or final-acceptance claim. Original
canonical native libraries are separate witnesses, not measured DLLs.

The candidate remains frozen for its complete strict48/50 campaigns. A separate
checkout will reproduce the avoidable small-index allocation before any new
production edit; this source comparison is not a reason to cancel or select
campaign results.

[Complete source/input audit and all series](2026-11-02-flatbuffers-segmented-receive-source-control-audit.json),
[all before rows](2026-11-02-flatbuffers-segmented-receive-source-control-before.jsonl),
[all candidate rows](2026-11-02-flatbuffers-segmented-receive-source-control-candidate.jsonl),
[actual compiled probe](2026-11-02-flatbuffers-segmented-receive-source-control-probe.rs),
[independent body-pattern implementation](2026-11-02-flatbuffers-segmented-receive-source-control-pattern.c).
