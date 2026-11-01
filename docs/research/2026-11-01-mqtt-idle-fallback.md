# Defer idle fallback until queued wakes have run

An apparently idle router pass currently creates a fallback Timer before a
queued native wake event can run. A root-zone observer around the unchanged
public `7476ff6e` broker retains twenty original runs / four million verified
fresh deliveries. On local Darwin, WebSocket rows create and cancel about
57,000–59,000 one-millisecond idle timers per 200,000 publications. These are
observer counts, not a performance or Linux/RAM acceptance result.
[Complete observer evidence](https://github.com/konsultaner/connectanum-dart/blob/ac16d10d/docs/research/2026-11-01-mqtt-timer-lifecycle-observer.json).

This isolated change yields one existing RawReceivePort event turn on an
apparently idle wait, then consumes a queued wake before allocating a timer.
An elapsed monotonic budget retains the VM's original whole-millisecond timer
resolution. In particular, 1 ms minus a 500 µs event turn retains a positive
1 ms fallback instead of accidentally constructing a zero-delay timer. The
original VM truncation for fractional initial intervals is preserved. An already
exhausted deadline returns after that event turn. Genuine idle timers still
cancel on early wake; busy fairness, close/reuse and resource ownership remain.
No GC/allocator/SDK policy, workload, body generation/verification, sample/window
or native buffer/pattern reuse changes.

The branch starts at `7476ff6e`, excluding the later MQTT forwarding-header
experiment that did not demonstrate a network improvement. This is a scheduler
hypothesis, not an adopted CI repair. Its before/after queued microtask and actual
RawReceivePort-event regressions fail before with one timer and pass after with
zero. All fifteen pacing cases pass, including a genuinely armed timer remaining
active before wake and cancelled afterward, VM timer rounding, exhausted deadline,
close/reuse, event fairness and isolate exit. The full router file passes 620
cases; all 115 MQTT cases pass, including seven Paho TCP/TLS/WS/WSS/version cases.
Targeted analysis and formatting pass. The original missing native-env / wrong
package-cwd manual invocations are retained as setup failures; no source behavior
or test expectation was changed for them.

Before source edits, fresh bootstrap and full `bin/test-fast` pass on clean
unchanged `7476ff6e` (fast log SHA
`feaf3519e969857524c76e983c8efa372d7b6ad7d7841e8f02e860e26926ec61`).
Local model review is advisory; speculative close/Duration-equality concerns were
checked against complete source, SDK equality semantics and passing regression
cases. No model output establishes a performance pass.

The predeclared uninstrumented matched comparison must retain all fifty rows /
8.05 million verified deliveries under the original five profiles/five pairs.
Timer-observer counts are a separate diagnostic and do not supply performance
ratios. One unchanged client and identical-source standard native library serve
both legs; retain exact source/binary/budget inputs and all cleanup. No favorable
unchanged rerun is selected. Even a component/transport improvement needs its own
frozen full canonical, hosted copy/lifetime, clean complete CI and complete final
strict 48-/50-case acceptance before adoption or PR readiness/merge/closure.

[Predeclared complete matched method](2026-11-01-mqtt-idle-fallback-predeclaration.json).
