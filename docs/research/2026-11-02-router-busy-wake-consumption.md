# Consume queued readiness during a busy router pass

Candidate branch: `codex/router-busy-wake-consumption`, from frozen `11521160`.
It changes only how the router pacer consumes an already-queued wake flag.
`didWork || _consumeWakeRequest()` skipped consumption whenever work was found,
so the flag could force a redundant immediate turn on the next otherwise idle
pass. Consume the flag into a local before combining it with `didWork`.

The busy pass still yields through the same event queue. A new wake delivered
during that await remains pending; the following pass observes it. Idle fallback,
period, drain budget, fairness, worker policy, shutdown and reuse are preserved.
The close/reuse fixture removes its obsolete extra wake-consumption turn, and
the new regression checks the replacement idle-wait behavior directly.

A fresh clean pre-change bootstrap/full `bin/test-fast` passes before source
edits. The new deterministic test observes timer creation through a zone rather
than sleep timing. It fails first with expected one timer / actual zero, while
the late-arriving wake control passes. Both pass after the minimal correction.
All 615 router-runtime tests and 115 MQTT cases, including seven actual Paho
cases across TCP/TLS/WS/WSS/client paths, pass. Phase logs, locks, code and actual
own native `bf607a9bd74823a8c8152b0f2dbfc8ca19444d68fd3b108c214392fb54b7a474`
independently rehash unchanged. Native Rust and all body/copy boundaries are intact.
[Focused audit](2026-11-02-router-busy-wake-correctness-audit.json).

A bounded GLM advisory review completed without a confirmed defect. Its loop
ordering observation was checked against the source: awaits occur before MQTT
queue drain, with none between final drains and pacing. Root review verifies
the late-wake and close/fairness cases; advisory output is not acceptance proof.

The predecessor's count-only census motivates this investigation, but does not
establish its performance impact. It measured roughly 82% empty WS polls on
Xeon 8573C using exact retained old runtime bytes and uncalibrated counters.
That is not causal proof about previous EPYC 7763 failures.

Own full canonical verification, exact-source CI/copy proof and a new complete
Dart-source control are pending. The control must compile actual baseline and
candidate Dart brokers separately, hold the same verified native/client bytes
constant, and retain all five profiles/five AB/BA pairs/fifty rows/8.05 million
fresh verified deliveries. Native-only comparison labels cannot establish a
Dart-source effect. No original numerical gate is retried or selected.

No gate, workload, window, sample count, body verification, SDK, GC or allocator
policy changes. This candidate is not adopted. Complete final-runtime strict
48-/50-case acceptance and clean CI are required before PR #132 can merge;
RAM and broad WAMP parity remain unresolved.
