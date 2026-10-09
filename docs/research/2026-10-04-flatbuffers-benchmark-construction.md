# Benchmark construction and correctness preparation

Date: 2026-10-04. Source-backed preparation for issue #103. No measured parity,
new construction mode or typed benchmark workload is claimed.

The current `_buildLazyPayloadFactory` in the Dart workload runner pre-encodes
ordinary argument containers into Dart `Uint8List` fragments. Both CBOR and
ordinary FlatBuffers use CBOR argument fragments. This reuses encoded bytes
between iterations, but does not create a native-owned allocation or prove a
copy-free Dart/native submission boundary.

`_runRpcIteration` forces receive-side unpacking for PPT scenarios and releases
the result payload in `finally`. Its worker/iteration fields identify the recorded
sample; this function does not compare echoed application identity or contents.
Consequently, a typed provider substitution alone would not establish benchmark
correctness. The existing ordinary workloads remain regression controls.

The next typed application fixture must encode campaign, worker and sequence
identity in the application payload, alongside the same deterministic body and
operation fields used by CBOR/MessagePack. A caller must reject another operation's
response even if its byte length is correct. Pub/sub must validate the same
identity and ordering without placing sequence metadata in a typed PPT keyword
container, which that profile rejects.

Declare ordinary-value, native construction and pre-encoded-span modes explicitly.
Use the corresponding actual owner/submission APIs and prove input allocation
identity, copies and final release; neither an encoding label nor a fragment
count proves a construction mode. Time equivalent validation and receive access
for every codec, report encoded wire size separately from application size, and
compile/generate fixtures before timed runs. Controlled measurement must wait
until correctness, lifecycle and the declared performance policy are complete.

Local summarization correctly identifies the pre-encoded Dart fragment factory
and `finally` cleanup, but supplies no evidence of a native construction path or
worker/sequence validation. These conclusions were checked against the selected
RPC and fragment-factory source.
