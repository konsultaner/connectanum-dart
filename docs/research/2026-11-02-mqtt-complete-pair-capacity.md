# Complete native MQTT pair capacity

The first merge of a complete two-chunk inbound burst reserved 4 KiB, then
allocated sharing metadata when freezing the short buffer. The isolated change
sizes that initial buffer to the known output length when a split tail ends the
poll or the receiver is currently empty. If more chunks are already queued it
retains the original 4 KiB growth strategy. Later producers still drain through
the original loop and grow normally; output caps, ordering, ownership and wake
behavior are unchanged.

Fresh bootstrap/fullfast passed before edits with clean AD48 source and three
original locks. The real test-only complete-pair budget failed exactly once
while the longer-burst control passed. After correction it requests 64+256 bytes
(two requests), versus 64+4096+24 (three) before, on this Darwin toolchain. The
64-byte fresh-queue cost is retained and matched by an independent direct-queue
control. These are requested sizes, not physical heap, live memory, RSS, copying
bytes, timing, transport or EPYC 7763 gate acceptance.

All four new capacity/pending controls pass, including an allocator rendezvous
in test code that forces a producer after the exact capacity choice: all 384
bytes drain, normal growth occurs and storage survives queue release. There is
no production hook or delay. Local reviews are qualified against the actual
synchronous queue, arithmetic and RAII guard; no confirmed production defect
remains. All 480 core, two alias, two index-allocation and three codec tests,
319 FFI, 22 native WebSocket, seven lifetime, 615 router-runtime and 115 MQTT
cases including seven actual Paho cases pass with own rebuilt native
`5cfe237b5e656cf860235c104b02b879e9da581a31768e7b734428c67fac3dad`.
[Independently rehashed focused evidence](2026-11-02-mqtt-complete-pair-capacity-correctness.json).

The original 100-row requested-allocation census, raw rows, exact probe/source/
archive, 140 static RLIBs and before-native bytes remain retained. Its consumed
ignored capture entry is removed from the final regression module after focused
checks; all six executed controls and 20-shape coverage remain unchanged. Full
canonical verification must use this final module. The complete prior census
and original failed fixture assumptions are [retained separately](https://github.com/konsultaner/connectanum-dart/blob/bb996261/docs/research/2026-11-02-mqtt-small-burst-allocation-audit.json).

Own frozen canonical, copy/lifetime, hosted CI and a proper native-source
comparison with one actual Dart broker/client and a separately compiled fresh
producer are still required. Previous MQTT client 3020 reused its application
buffer and fixed pattern; earlier delivery checks/results stand, but fresh-body
claims for it are withdrawn. Do not reuse it as fresh source-control proof.
Every final runtime still requires complete strict 48/50 and clean CI. PR #132
remains draft at 40ddcb3f, stacked on #130. No adoption or RAM/throughput repair
is claimed; the separate 1% allocation-precision decision remains unanswered.
