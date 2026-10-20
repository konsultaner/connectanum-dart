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

Ten focused tooling tests cover attribution, malformed/incomplete evidence,
negative-control rejection, package resolution, a real child-process cleanup
path and resource-lease isolation. Linux execution is pending. The local shared
lease is held by another active job, so native execution and local companion
review of the new tool are blocked; the holder and lease remain untouched.

Metadata ownership was also checked: both client and router already copy
metadata using `NativeMessageBytes.withCopiedBytes`, releasing the temporary
native export afterward. No additional metadata-copy change is justified.


The first hosted run on `14fb22db` correctly observes its throwing-loader
negative control, then the positive variant fails in
`Session._packMatchingLazyPayload` before native transport selection. Both
phases attest the private marker, exit zero during cleanup and preserve their
inputs. This is a valid failed experiment: existing deferred payload semantics
do not represent an unexported native packed body throughout the session layer.
Run [39481115738](https://github.com/konsultaner/connectanum-dart/actions/runs/39481115738)
and its failure artifacts are retained.

The next private-only variant restores the deferred payload into the outbound
message for the controlled FlatBuffers owner, leaving non-FlatBuffers and E2EE
paths unchanged. It still retains the throwing loader and original negative
control. This probes both earlier session access and native transport selection;
there is no public API or general provenance claim. The extended prototype passes on Linux as described below.


The extended prototype passes on `1c25277a` in
[39481566412](https://github.com/konsultaner/connectanum-dart/actions/runs/39481566412).
Independent inspection confirms the exact negative control, all six complete
byte-validation cases, twelve attributed snapshot groups, 36 post-GC rounds,
one stable worker PID, zero native counters before and after GC, unchanged
source/library inputs and complete owned-process cleanup. Raw memory observations
have SHA-256 `d1a5eb9355ab37f26d1af0f0eb215ac9a667e937a067f82724cfefde604a982d`.
This demonstrates the controlled path can avoid exporting a producer Dart view.
It does not establish an RSS, GC or throughput improvement.

The matched run adds the same six cases using the unchanged API in the same
Linux job. That baseline must reproduce at least one native producer allocation
awaiting collection, then return all tracked owners to zero after collection.
The prototype still requires zero before collection. Complete original source
and library hashes, independent child cleanup and the negative control remain
mandatory. This removes the platform difference in the earlier macOS baseline;
timing remains ineligible for parity acceptance.

A production solution still needs a separately owned, explicit disposable
payload lease. Native eligibility must derive from an unforgeable source identity,
not the prototype's structural anchor. Source identity must survive payload
anchor/provider/context copies and disappear on detached owned copies. A source
from a foreign allocator/library, an expired lease or an edited/replaced payload
must never lend an unrelated native allocation. Session preparation must retain
the encoded representation without forcing application values; safe serializer,
old-library and E2EE fallbacks must materialize independent views when necessary.
An exported view must outlive lease disposal. None of those public contracts is
implemented by this diagnostic.


## Matched Linux comparison

The matched run passes on `4eaf0684` in
[39482582437](https://github.com/konsultaner/connectanum-dart/actions/runs/39482582437).
Independent audit confirms the exact negative control, twelve complete
byte-validation cases, 24 attributed snapshot groups, 72 post-GC observations,
stable worker identities within each phase, unchanged source/library inputs and
complete cleanup. Both phases use the same ffi-test binary and scenario inventory.
The unchanged API retains producer allocations before requested collection:

| Construction | Body bytes | Existing API | Private prototype |
| --- | ---: | ---: | ---: |
| Native buffer | 0 | 410 | 0 |
| Native buffer | 65,536 | 268 | 0 |
| Native buffer | 1,048,576 | 1 | 0 |
| Pre-encoded span | 0 | 290 | 0 |
| Pre-encoded span | 65,536 | 125 | 0 |
| Pre-encoded span | 1,048,576 | 1 | 0 |

All tracked counters return to zero after requested collection in both phases.
All six existing-API preflights retain one producer allocation before collection;
the prototype retains zero. This is controlled evidence of avoidable producer
view retention. It does not prove the cause or magnitude of the primary RSS gap,
and its elapsed time, GC, allocation and RSS values cannot establish parity.

The artifact archive SHA-256 is
`2e8d8acc157014335ff2c8b21bb36f00f70b5bc6d77db7263523fdd9e02de72a`.
Raw memory observations have SHA-256
`aff011378fad26a1fe974c55d45fd48b1f04638457372c72c1281e54b0009cab`
(existing API) and
`3300e2dd57df2b7a44be0f620b1d760bbc1740087b5ea0444125d46f51df738e`
(prototype). Independent audit is retained under
`out/flatbuffers-resume-20261020/linux-native-view-baseline-4eaf-independent-audit.json`.

The next implementation step is the explicit disposable lease described above,
with tests for provenance, owner/library mismatch, application-byte edits,
anchor/provider/context clones, detached copies, producer/lease disposal orders,
exported/derived-view survival, old-library fallback and E2EE/transcode accounting.
Keep existing reusable APIs intact. Only after that production contract passes
verification should equivalent benchmark native-construction paths use it and
the complete unchanged-policy timing campaigns be repeated.
