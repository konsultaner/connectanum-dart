# Native opaque payload lifetimes

Date: 2026-10-20. Scope: issue #103, performance PR #132.
Source: `28fa80117a8ce463ca20d89fde4dee06ea0ab38f`.

The strict ninety-row Linux diagnostic completes with no integrity findings and
eleven numerical gate failures. All three summed sampled-peak RSS comparisons
fail, with median ratios from 1.0130 to 1.0264. Native construction throughput,
CPU and allocation comparisons pass. These measurements require further work;
no numerical budget or confidence requirement changes.

## Lifetime diagnostic

A private copy of `wamp_client_main.dart` records actual ffi-test counters after
each completed workload, then requests three standard-SDK collections. It observes
native owned allocations, owned handles, external-byte-buffer owners and write
receipts, along with process RSS and VM heap/class summaries. The server and
worker use an isolated copy of the verified ffi-test library. This instrumentation
is absent from production libraries and the source tree remains unchanged.

Eighteen HTTP requests exercise all three codecs and all three construction
groups twice, with reverse codec order on the second pass. Each real workload
uses a 64-KiB body and at least 1,000 operations. The existing server warmup also
runs one iteration with a body of at most one KiB, producing two snapshot groups
per request. One worker PID remains stable. The driver/server exits zero and
all source/library hashes match before and after execution.

Every tracked counter is zero after every requested collection: 36 snapshot
groups, three collections each. This reproducer does not find a native-owner
leak. Before collection, the real workload observations retain these producer
allocations:

| Construction | FlatBuffers | MessagePack | CBOR |
| --- | --- | --- | --- |
| Native buffer | 99, 85 | 43, 35 | 53, 44 |
| Pre-encoded span | 48, 53 | 27, 24 | 35, 35 |
| Dart values | 0, 0 | 0, 0 | 0, 0 |

These counts describe this macOS diagnostic. Forced collections, ffi-test
counters, one-second duration floors and short repetition counts make its timing,
GC/allocation and RSS values ineligible for performance acceptance. They do not
prove the cause of the hosted Linux RSS gap. Freed native allocations can also
leave process RSS reserved; these counters do not measure dependency internals.

## Next investigation

`NativeOwnedBuffer.asPptPayload` eagerly exports an independently owned,
read-only Dart view. Its SDK finalizer must preserve exported and derived views
after producer disposal. Replacing this behavior with a borrowed pointer or
invalidating those views would violate the existing contract. Receive buffers
and native owners already provide explicit external-size observations.

Investigate an explicit disposable payload lease that can retain native storage
without exporting a Dart view until application access or a fallback path needs
bytes. Such an addition must preserve existing APIs, foreign/old-library fallback,
encoded-byte provenance, anchor/context views, owned-copy detachment and complete
copy accounting. Explicit cleanup may release an unexported lease; already
exported views must retain independent ownership. Any benchmark use must keep
equivalent application data, operations and the original full acceptance policy.
This remains an investigation, with no new lease API implemented here.

Evidence is retained under `out/flatbuffers-native-memory-probe-20261020/`:
`provenance.json`, instrumented `worker.dart`, `command.json`, `reports.jsonl`,
`memory-observations.jsonl`, `result.json` and `independent-audit.json`. The raw
memory-observation SHA-256 is
`d927bfe8654118dc8b91cc8010a73b5499816d86d520d7417c473f2a65dbff41`.


## Controlled native-view prototype

`tool/probe_native_ppt_views.py` is an opt-in Linux diagnostic. It archives the
clean current source, enforces its resolved dependency lock and verifies that
core/client/benchmark package URIs resolve into that private workspace. Public
production sources and the primary scenario matrix remain unchanged. The
private patch makes FlatBuffers payload creation deferred; its loader throws
`PROTOTYPE_FORCED_PRODUCER_VIEW`. The negative control must return this exact
failure. The positive variant recognizes a controlled, still-live native
producer and sends its buffer without evaluating that loader. This is not a
public lease API and does not guarantee adversarial provenance.

A first ad-hoc attempt placed its worker outside the private package workspace
and unexpectedly succeeded in its negative control. That attempt is retained
as failed harness evidence. The checked-in tool places its worker inside the
archive and requires a unique compile-time marker from the patched native
buffer library. A package-resolution mistake therefore cannot silently pass.

The positive inventory contains six original wire scenarios: both native
construction modes at zero, 64-KiB and one-MiB bodies. Each validates at least
1,000 complete echoes. Counters are observed before collection and after three
SDK-requested collections, for both server preflight and actual workloads. A
passing result requires every tracked counter to be zero even before forced GC,
one stable worker PID, unchanged inputs and owned-process cleanup. No numerical
performance acceptance can come from this ffi-test experiment.

Eight focused tooling tests cover attribution, malformed/incomplete evidence,
negative-control rejection, package resolution, a real child-process cleanup
path and resource-lease isolation. Linux execution is pending. The local shared
lease is held by another active job, so native execution and local companion
review of the new tool are blocked; the holder and lease remain untouched.

Metadata ownership was also checked: both client and router already copy
metadata using `NativeMessageBytes.withCopiedBytes`, releasing the temporary
native export afterward. No additional metadata-copy change is justified.
