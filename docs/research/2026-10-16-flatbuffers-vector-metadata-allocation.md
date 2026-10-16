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
