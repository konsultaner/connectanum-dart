# Bounded segment lookup without a heap index

The frozen D9CB decoder comparison exposed one extra allocation /32 requested
bytes in five plain one-piece controls. This isolated follow-up retains D9CB's
segmented receive validation and original frame ownership. Lists of at most64
pieces use a bounded scan from zero; longer lists retain the sparse index.
Physical length/cache validation still runs for every segmented frame.

Fresh bootstrap/full fast baseline passes before editing. A test-only public
parse regression then fails with exactly +1allocation/+32bytes while the fresh
contiguous/counter control passes. After the minimal correction,1/2/64-piece
inputs match the contiguous budget (6 allocations /798 requested bytes), with
zero observed coalescing/range-copy bytes. The65-piece indexed control decodes.
All474 core,2alias,2allocation,3codec,319FFI,22fragmented WebSocket,7client
FlatBuffers lifetime,615router-runtime and115MQTT cases including7actualPaho pass.
The Dart checks use this checkout's rebuilt native, with all three locks held
constant. Existing empty/malformed/truncation/mutation and crossing-field tests
remain intact. Bounded advisory review found no confirmed defect; entry-count
and hypothetical underflow claims were checked and qualified against source.
[Focused correctness and log digests](2026-11-02-flatbuffers-small-segment-index-correctness.json).

Canonical, hosted copy/CI, controlled source comparison and final strict48/50
acceptance remain separate requirements. These requested-byte/component checks
do not establish RSS, live allocations, timing, transport parity or adoption.
D9CB's original numerical campaigns and all their rows remain retained. No
schema, bounds, copy/lifetime, body, window, worker, SDK, GC, allocator or gate
policy changes accompany this patch.
