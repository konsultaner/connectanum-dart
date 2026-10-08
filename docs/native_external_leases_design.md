# External native leases and write completion

Status: producer-lease ABI v1, trusted Dart token adoption and local write
completion are implemented for milestone issue #97. The current candidate also
integrates native frame composition and transport/lifetime regressions. Current
verification and remaining milestone gates are recorded in the active plan;
earlier adoption-only logs do not verify this candidate. See
[the ownership and copy guide](native_buffer_ownership.md) for the current public
boundary and the future ObjectBox adapter scope.

The following design separates native producer ownership from transport progress.
It must be tested before being advertised as an adapter capability.

- A dedicated native producer thread registers an immutable pointer/length/token with its native callback and owner registry. No Dart callback is invoked on worker or producer native threads.
- Reserve a frozen-buffer handle before quota/token ownership changes. Admission/range/quota failures leave the native producer token unconsumed. After admission, Bytes::from_owner holds foreign storage without freeing/reconstructing it as Vec.
- Last native reference drops enqueue one producer release record and notify a Condvar. Only the registration thread may wait/pump and invoke its callback. Limits remain charged until callback returns.
- Limits count original lease bytes once (including fan-out/slices) plus outstanding leases. Closing stops registrations; deletion requires no pending leases/releases. Wrong thread, quota full and closing states fail explicitly.
- Empty leases still consume/release their resource token; empty subviews of nonempty storage retain its base owner.
- Separate frame completion guard has Written or Abandoned outcomes, defaulting to Abandoned when queued/active work drops during rejection, disconnect, cancellation or shutdown. Writer marks Written only after complete frame write and flush.
- Completion registry is bounded and has explicit release/finalizer support. Completion never means peer ACK or no other memory owners. Producer release has its independent signal.
- Queue barrier completion gives FIFO drainWrites(). Preserve/document legacy drain() separately for old ABI; reject unsupported new completion operations before ownership submission.
- Fake transaction-like native producer tests enforce producer thread, retained quota, exact pointers, delayed/partial writes, one slow fan-out recipient, cancellation, full queue, shutdown and registration construction failure.

The native producer owns registration and release dispatch. A Dart isolate is
not an OS-thread-affinity guarantee; an adapter with transaction-bound native
resources must use a dedicated native thread. Keeping a Dart wrapper alive does
not extend a transaction, cursor or other producer resource lifetime.

On admission, validate pointer/length and quota before consuming the producer
token. Reserve the native frozen handle first, with an RAII rollback so handle
exhaustion and admission failure cannot ambiguously consume a resource token.
After admission, last-reference cleanup is queued once; the queue does not free
foreign memory. Producer-thread dispatch invokes the native release callback
outside registry locks, then returns its quota. Owner close prevents new loans;
actual deletion requires every queued/live loan to drain.

The frozen-buffer store needs an internal reservation state and RAII rollback;
constructing a foreign Bytes owner before reserving its handle would consume the
producer token when insertion fails. Reserved entries are never exposed as
readable handles. Commit publishes the immutable owner only after every normal
admission check succeeds.

Owner creation reserves release-queue capacity for its maximum lease count.
Last-reference cleanup must not need a new queue allocation on a worker thread.
Quota includes queued releases and the callback currently being dispatched;
dispatch invokes callbacks outside locks and rejects recursive dispatch. Owner
deletion cannot race a callback because its outstanding lease remains charged
until return. These requirements have focused native regression coverage; the independent C
producer/GC probe verifies actual C-to-Dart adoption and owner-thread cleanup.

Retained-byte quota measures the complete registered memory span once, even
when a small/empty slice is sent or exported. A producer may keep a larger
transaction/cursor resource alive than that span; an adapter must impose its
own resource/time limits. Core byte quota cannot measure that external cost.

A producer must pump or wait on the release notification while loans are active.
It must not block that release loop waiting for a peer acknowledgement. Starving
dispatch retains its bounded quota and rejects new loans; it never authorizes an
early resource close. Wrong-thread dispatch is rejected. Worker-thread reference
drops remain valid and only enqueue/notify the producer.

Local completion means the whole frame was written and flushed to the native
writer. Queued/active cancellation or I/O failure is an abandoned write. Neither
outcome implies peer delivery. No remaining read references is a separate fact:
retained slices, fan-out destinations or exported Dart views can still hold the
loan after one frame completes. Conversely a writer can finish reading loaned
bytes before its final flush. Only producer release authorizes resource cleanup.

The first adapter example will use a fake transaction-like native producer. No
ObjectBox dependency, cursor model, database ID policy or actual adapter is
implemented in this repository. ObjectBox-specific rules belong in a separate
connectanum_objectbox_adapter package using the verified generic boundary.

## Implemented producer ABI

`ct_external_lease_abi_version()` returns 1. A separate store-identity cookie
binds `CtExternalBufferToken { int32_t handle; const void *identity; }` to its
loaded native library. Native integrations create an owner with byte/count
limits, register one immutable full span plus a used subrange, and publish one
initialized token to one Dart consumer. `adoptTrustedNativeToken()` checks the
complete symbol group, version, identity and frozen handle before clearing the
token. Copies of token fields do not retain references. Registration/adoption
is a trusted native boundary, not a pointer-validation or isolation mechanism.

The producer pumps `ct_external_owner_dispatch()` and may block its dedicated
thread in `ct_external_owner_wait()`. Metrics count the complete original span
once per loan. Close rejects new registrations immediately; destroy succeeds
only after all live references and queued/in-flight cleanup have drained. Both
operations require the creating native thread. The registry retains at most
1024 owners and is independent of transport shutdown. The producer thread and
callback library must remain alive until destroy succeeds. Callback code must
be native, must not unwind and must not enter Dart through a Dart callback.

Error codes -20 through -24 mean wrong thread, closing, quota full, busy and
recursive dispatch/wait, respectively. Registration failure zeroes its output
token and does not consume the native producer resource. Quota remains charged
until callback return; a cleanup notification alone does not return quota.

The independent C fixture holds a fake transaction on a native pthread and
publishes a subrange. A forced-GC Dart child proves immutable derived ByteData
keeps that resource alive after wrappers die, then observes exactly one cleanup
on the registering thread. The fixture does not integrate ObjectBox.

## Implemented write receipt boundary (candidate)

Completion uses an independent, versioned six-symbol ABI. A tracked send consumes
one valid frozen handle on queue, runtime, connection or receipt-quota rejection,
as the existing owned-send path does. Unsupported ABI/library identity and
Dart argument rejection occur before transfer. A positive receipt handle means
queue acceptance; its observable states are Pending, Written and Abandoned.
The receipt registry reserves capacity and an ID before enqueueing, so it cannot
report an allocation/handle error after an accepted frame. Explicit release or a
native finalizer returns registry capacity; releasing a receipt never cancels a
frame or frees another consumer's payload ownership.

Each tracked frame carries one native completion guard. Writers mark Written
only after all segments and the final flush succeed. Dropping queued or active
work marks Abandoned, covering rejection, deferred preparation failure, partial
write/flush errors and task cancellation. Receipts themselves retain no payload.
A FIFO internal barrier runs a flush in the same outbound queue and emits no
protocol bytes. Failure of an earlier write abandons the barrier. Dart's new
`drainWrites()` observes this barrier; legacy `drain()` remains an event-loop
yield and does not establish a native write boundary.

Six tests use a controllable AsyncWrite to stop after a partial write, block
flush independently and inject I/O failure. They cover both RawSocket and
WebSocket writers, cancellation of active and queued receipts, rejected queues,
invalid deferred preparation and two fan-out recipients sharing one loan. One
written receipt cannot authorize release while the slow recipient retains bytes.
The C producer/SDK lifetime probe remains separate evidence for thread-affine
resource release. Full receipt-candidate bin/verify passes in
/tmp/connectanum-write-completion-verify.log. Receipt support is committed as
ddc2e06b. The combined producer/network test now lends one 8 MiB allocation to
fast and stalled peers plus an exported view, across RawSocket/WebSocket and
disconnect/runtime shutdown. It verifies the original pointer, full independent
wire contents, pending/abandoned receipts, unchanged WebSocket source bytes,
quota return and final producer-thread cleanup. All 219 FFI tests pass; fresh
full network-candidate bin/verify passes, including Chrome/WASM, in
/tmp/connectanum-external-network-verify.log.


The receipt ABI consists of ct_write_receipt_abi_version,
ct_owned_buffer_send_tracked, ct_connection_drain_writes, ct_write_receipt_state,
ct_write_receipt_release and ct_write_receipt_finalizer. All six symbols and
version 1 are required independently of the producer lease capability. Capacity
is 8192 outstanding/reserved receipts; error -25 means receipt quota exhausted.
Terminal receipts count until explicitly disposed or finalized. IDs are never
recycled across runtime restart. State is readable from any native thread; the
Dart wait method polls asynchronously and a timeout stops observation without
cancelling native work. drainWrites() disposes its barrier receipt on every path.

Live Dart tests verify both native transport APIs and missing/mismatched ABI
rejection. A VM-service child abandons a receipt, confirms the frame still
arrives, then forces GC and observes the registry capacity return. A separate
native test cancels a deferred write while the worker keeps its loan: the
receipt becomes Abandoned before that worker releases storage. This explicitly
proves that abandonment cannot authorize premature producer resource cleanup.
