# FlatBuffers vector writes and metadata allocation

Scalar metadata dictionaries now validate and materialize in one scan. That scan
checks the map root, inclusive 1 MiB limit, item charging, string keys, duplicate
keys, UTF-8, integer width and portable range, indefinite chunks and trailing
input. Complex and wide values retain the original complete validator and CBOR
materializer. Exact integers at both +2^53 and -2^53 remain supported. Unicode
keys retain their exact strings, without case folding or normalization. The
isolated comparison checks 16,415 valid, malformed, mutated and truncated inputs;
regressions include every truncated prefix of seeded Unicode dictionaries and
both sides of the metadata byte limit.

The pinned Dart `flat_buffers` 25.9.23 byte writer was also compared with a
read-only word-view writer. Although exact VM/JS/Wasm wire and ownership tests
passed, end-to-end and component measurements below reject that experiment.
The selected implementation uses the standard SDK byte writer.

## End-to-end result and selected follow-up

The word-writer experiment at `1785387e` does not pass: the three paired local
throughput ratios are 0.9347 / 0.9875 / 0.9478 and allocation ratios are
1.1348 / 1.1691 / 1.0589. All 180 raw allocation observations independently
validate. Component probes show 64 KiB read-only inputs regress even with aligned
storage, so the standard SDK byte writer is restored. This experiment remains
on its separate branch and is not carried into the accounting PR.

The selected follow-up preserves normal message representation. Fragmented
clean typed FlatBuffers PPT sends retain a small canonical CBOR singleton-array
and binary-length prefix plus the original byte body. The byte vector on the
wire is unchanged. Ordinary contiguous serialization, pre-encoded vectors,
explicit kwargs/references and encrypted/wamp modes retain their existing paths.
All prefix-width boundaries are checked against the independent CBOR encoder.
Byte-vector parts have a bounded total length, retain their original owners,
and observe copies if a caller explicitly requests contiguous bytes. Encoded
body contents must stay unchanged until transmission completes, as required by
the existing fragment API.

Outgoing native profile checks now omit only retained Call/Publish dictionary
snapshots, after the same wire, metadata, concrete-model and projection checks.
Bootstrap and other message types retain their original metadata. The internal
reader is not exported through the public serializer library. Two clone-copy
regressions fail before the change and pass after it; malformed prefixes,
forwarding metadata, bootstrap dictionaries and lazy data remain covered.

Hosted baseline `63a802f7` passes every CI job, including complete Linux VM
coverage with zero findings and benchmark coverage 98.74% (3,846/3,895). New
candidate full verification and timed acceptance remain pending.


The selected implementation passes 3,370 VM, 3,376 JavaScript and 3,366 Wasm
serializer tests, plus 54 serial native profile/network checks. Interoperability
passes the independent upstream/extended 33/42 fixtures, bidirectional
Python/Dart/Rust Call conformance, and contiguous/segmented output for all 25
public messages. Multipart tests compare all prefix-width boundaries with the
independent CBOR encoder, partial/read-only sources, effective dictionary
metadata, kwargs exclusions, explicit coalescing counters and the 64 MiB budget.
Analysis and the existing mutation-inventory preflight pass. Local bounded
GLM review reports no confirmed arithmetic/ownership defect. These are
correctness checks, not performance acceptance. All original primary cases,
durations, samples, repetitions, coverage floors and metric budgets remain.


## Renewed copy proof and measured allocation bottleneck

Source `d12196ce` passes 120 real HTTP E2EE/transcode cases with all 3,096
source inputs and HEAD unchanged. An independent replay checks each disjoint
owned-copy total and all three clean process exits. Production native consumers
pass 170 cases on five platforms with zero skips and independently audited log
hashes. All 180 stock-SDK allocation observations in its 90-row local diagnostic
validate. It still fails: throughput ratios are 0.9518 / 0.9887 / 0.9740 and
allocation ratios 1.0384 / 1.1694 / 1.0535. No result is discarded or accepted as
parity. Full verification reaches Rust, client/core/benchmark VM and router
checks, then fails one unchanged FastCGI fixture: an intentional oversized-output
rejection can reset the upstream socket instead of delivering EOF. The fixture
now allows only reset/broken-pipe for that one rejecting case; its actual HTTP
502, response-too-large reason and event checks remain. All 29 focused FastCGI
checks pass. Whole-source verification must run again.

Allocation traces identify small CBOR metadata encoding as the next bottleneck.
A representative four-field dictionary allocates 8,910 / 8,864 managed bytes per
encode in two stock-SDK heap/GC volume observations. A narrow direct encoder for
at most 23 ASCII scalar entries (strings, bool/null and uint32/nint32 integers)
reduces that to 669 / 641 bytes through the public codec. Every other value,
oversized input, dictionary size and construction rule retains the existing
complete encoder. It creates encoded scalar bytes directly; no existing payload
buffer is copied by that shortcut. Byte-vector copy observation is unchanged.
Independent 3,055-case VM/JavaScript reference probes preserve exact pinned CBOR
bytes. New tests retain prefix/integer/dictionary boundaries, Unicode/complex
fallbacks, inclusive budgets, key validation and insertion order. These are
component allocation and correctness results, not end-to-end parity acceptance.

The hosted workflow adds an explicit three-case Linux diagnostic at the same
3 warmups, 7 paired repetitions, 10-second windows and 1,000 minimum samples.
This obtains CPU/RSS observations before another long primary campaign. It is
always labelled diagnostic and fails primary acceptance by design. The complete
48-case / 1,440-row primary inventory, policy and all numeric gates are unchanged.


## Immutable projection lookup follow-up

At `249e0c8a`, the fresh 120-case owned-copy proof again passes with all 3,097
inputs and HEAD unchanged. Its short 90-row diagnostic improves native-buffer
throughput to 1.0170 and p95/p99 to 0.9625 / 0.9927; allocation still fails at
1.1503. Managed/pre-encoded throughput remains 0.9836 / 0.9860 and allocation
1.0234 / 1.0374. All observations are retained; no parity acceptance is inferred.

Component isolation finds native FlatBuffers construction already allocates less
than MessagePack: 68,057 / 67,965 bytes versus 71,430 / 71,006 per operation.
The major remaining cost is in frame/profile checking. Immutable membership sets
were rebuilt inside every metadata-field projection. The selected change shares
constant routing/common/error/payload lookup sets and preserves the same union
membership checks without a mutable `addAll`. No validation, model conversion,
projection, ownership or copy observer is removed. Repeated stock-SDK observations
reduce frame allocation from 12,074 / 12,065 to 4,965 / 4,962 bytes and profile
allocation from 22,088 / 21,980 to 8,651 / 8,544. Independent raw heap/GC replay
validates all component observations. VM serializer checks pass all 3,375 cases;
browser verification and renewed end-to-end measurements are required before
accepting this candidate. The SDK byte-vector writer is unchanged.
