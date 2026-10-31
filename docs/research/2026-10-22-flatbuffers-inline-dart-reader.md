# Inline Dart FlatBuffers reader cache

The common checked envelope has a root and a message table. The reader now
retains these first two `(offset, schema reference, map)` entries in fields and
keeps its first string offset/value in fields. Further entries retain the original
map keys and lookup behavior. Structural/CBOR validation, visit limits, model
projection, wire layout and borrowed byte-vector views remain unchanged.

## Private component and regression evidence

Separate copied package configurations run the actual public serializer on
64-KiB RESULT and CALL frames. Both variants verify identical encoded wires and
storage aliases. Allocation is collected externally using the existing VM
metrics collector; command/control overhead is retained separately. Baseline
and candidate sources, four resolved root inputs and private sources remain
unchanged through each successful run.

The balanced run uses ABBA worker order for each shape, four measured windows
per process and 100,000 decodes per window after 100,000 warmups: 40 total windows
including eight controls. There are two independent workers per variant/shape.
Median managed allocation decreases by about 259 bytes per RESULT decode and
456 per CALL decode (roughly 3.2%/4.9%). Median timing ratios are 1.0021/0.9911;
the small process count makes timing inconclusive. These are component results
on the standard local Dart 3.13.1 SDK, not Linux primary performance acceptance.
The earlier unbalanced 20-window observation is retained as exploratory evidence.

The initial combined guard rejected ByteBuffer wrapper identity before any
measurement. A direct backing-storage alias check, performed outside measurement
and followed by restoring the wire, passes for both variants. The original failed
bundle remains retained; this was not accepted as a production bug. An initial
private-test CLI invocation also rejected its unsupported package option and ran
zero tests; direct invocation of package:test with the isolated configuration
then passes all 433 cases separately on baseline and candidate. A marker test
ensures the intended copied core is loaded.

Three checked-in regressions cover repeated strings and table-vector aliases
after overflow, empty strings, and one physical table offset interpreted through
distinct schema references. Adding the file first exposes five strict mutation
wrapper-inventory failures; registering it in all VM/browser serializer wrappers
restores all 87 tooling cases without narrowing their inventories.

## Baseline and adoption

Frozen pre-adoption `bin/test-fast` on `de1b57f0` passes in 15m08s with all 3,185
sources/four resolved inputs unchanged and a clean tree. Log SHA-256:
`c2050df63a4f67f249a882765589957c1927c7b2867c8bd355e0d779a055dd46`.
The production reader matches the measured candidate methods and field order;
the private marker is removed and declarations are formatted. Resulting-source
checks, Linux copy/lifetime proofs and full performance acceptance remain pending.

## Follow-up: fresh metadata maps and generated enum lookup

After `dd6e674a` passes frozen full verification, a private candidate reuses the
fresh validated `FlatBufferFrame.dictionary` in model decoding and uses the
checked-in `AnyMessageTypeId.fromValue` switch. The original code copies that
map and linearly scans enum values. Each frame decode owns its fresh dictionary;
retention snapshots are still detached before the public mutable model returns.

Both configurations pass 434 selected cases, including a new public ERROR
metadata mutation, independent decode, lazy PPT and re-encoding regression.
Qwen reports no concrete defect; synchronous reader scope and the generated
factory are checked directly. Validation and wire/byte ownership are unchanged.

The retained first forty windows and subsequent 160-window experiment agree.
The latter uses four ABBA worker blocks per shape: eight independent workers
per variant for both RESULT and CALL, four measured rounds of 100,000 decodes
after warm-up, and a control window per worker. Median worker allocation saves
about 382/392 bytes per decode; median worker warm decode time ratios are
0.9251/0.9287. All wires and backing-storage aliases agree. All root, resolved
and private source inputs remain fixed during each run. Raw receipts and
worker-level selection are retained in `out/flatbuffers-resume-20261022/`
under `message-reader-probe/`. These are local component results: they cannot
accept whole-process CPU, RSS, GC, network performance or primary parity.
