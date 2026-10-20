# FlatBuffers control construction follow-up

The pinned native FlatBuffers writer starts from zero capacity. Both contiguous
and segmented construction now reserve 256 bytes. The representative typed RPC
control frame is 192 bytes with FlatBuffers, CBOR or MessagePack PPT metadata;
its previous final backing allocation was already 256 bytes. Larger frames
still grow normally. Smaller controls can retain more capacity than before,
which must stay visible in subsequent small-message/resource measurements.

The Dart writer also reuses private field-name sets from the constant pinned
schema instead of rebuilding each set for every table. Field validation, schema,
wire layout and payload ownership stay unchanged; encoded output is not cached.

All 366 Rust core cases, 514 focused Dart cases and pinned Python/Dart/Rust
interop pass (33 upstream fixtures, 42 extensions, both directions and all 25
public codec message types). The production library builds successfully. Raw-frame
runtime/ABI coverage also verifies named cumulative fields and unknown-version
rejection. Client and router suites pass separately (83 and 34 cases). An initial
combined root invocation collides on their process-global native runtime; those
failed logs remain preserved. Bounded local review reports no confirmed issue.
New-source timing and final canonical verification remain pending.

## Exact fixture capacity is not parity

The preceding 90-row before/after diagnostics compare `2372a196` with `fc1881d3`
on the same saved production library. Both executions complete, validate payloads
and stop their process groups. The FlatBuffers/better-binary median throughput
ratios are:

| RPC construction | Before | Exact capacity |
| --- | ---: | ---: |
| Dart values | 0.8086 | 0.8051 |
| Native buffer | 0.8044 | 0.8019 |
| Pre-encoded span | 0.7946 | 0.8091 |

Allocation and latency ratios still regress. These short macOS runs neither
establish a useful speed improvement nor supply required Linux CPU/RSS evidence.
Some comparator ratio placeholders are 1 when process measurements are missing;
they are not measurements and must not be cited as passed budgets. Original raw
reports retain the missing-evidence failures. No budget, case, duration or sample
floor changes, and issues #100/#101/#103 remain open.

Evidence is retained under ignored `out/flatbuffers-milestone-finish/`, with
`control-capacity-`, `control-cache-`, `raw-frame-*-optional-abi` and
`exact-capacity-` prefixes.
