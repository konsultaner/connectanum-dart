# MQTT ready-batch WebSocket framing prototype

This isolated prototype starts at `7476ff6e`, excluding the unadopted forwarding
and idle-fallback changes. It targets a shipped MQTT WebSocket path with known
predecessor CI failures; it does not establish a FlatBuffers RAM cause or pass.

The current native writer batches up to sixteen already-ready chunks but builds
one WebSocket header per chunk. The prototype joins only already-collected
vectored batches whose combined payload is at most 64 KiB into one unmasked
binary frame. Original `Bytes` payload slices are borrowed directly. Singletons,
nonvectored writers and batches exceeding 64 KiB retain the previous framing.
Queue collection may overshoot its target; this fallback preserves that behavior
without creating a larger joined frame. There is no added wait or payload copy.
TCP, control priority, permits through flush, failure cleanup and queue bounds
remain intact. Every benchmark body is still generated and verified as before.

Both primary specifications permit multiple or partial MQTT Control Packets in
a binary WebSocket frame and require receivers to accept packet boundaries that
differ from frame boundaries: [MQTT 5 section 6](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html)
and [MQTT 3.1.1 section 6](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html),
requirement MQTT-6.0.0-2. This supports framing compatibility, not an assumption
about another broker's implementation or a performance benefit.

The exact clean parent already passed full `bin/test-fast`; its independently
rehashed receipt is retained. This fresh worktree passes bootstrap and its
pre-change native egress suite. A one-frame/borrowed-original-slices regression
fails before the runtime edit and passes afterward. All 471 native core tests
and three codec integrations pass, including header length boundaries, empty
chunks, partial writes, overshooting and 1 MiB fallback, genuine queued-control
priority and error cleanup. Expected wire tests now assert the intended allowed
framing and unchanged full payload order; gates and workloads are not changed.

An independently checked compiled component extracts the exact production
writer/header functions from both sources. Eight pairs prepare fresh payloads
before measurement and verify the full 2,048-byte payload and permit return.
For sixteen ready 128-byte chunks, allocation requests fall from 33 / 544 bytes
to three / 34 bytes; frame count falls sixteen→one, wire bytes 2,112→2,052 and
IoSlices 32→17, with one write in each leg. An immediate sink uses preallocated
capture storage; inactive fallback branches panic if unexpectedly reached.
This is a private-function allocation component, not a public-ABI, transport,
RSS or GC result. An initial missing-trait fixture compilation failure is retained;
no initial numerical data existed. Live interoperability, controlled source
comparison and own frozen canonical/copy/CI/strict acceptance are still pending.
The existing frozen `75295eb0` full campaigns continue unchanged despite its
negative Linux source control. This prototype is not adopted into PR #132.
