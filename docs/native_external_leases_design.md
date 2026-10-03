# External native leases and write completion

Status: planned for milestone issue #97. The implemented ABI v1 owns its Rust
allocations; it does not yet support foreign memory or write completion.

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
