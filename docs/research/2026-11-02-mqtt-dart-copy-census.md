# MQTT logical copy requests: diagnostic contract

This tools-only branch investigates the original AD48 MQTT CI failure. It does
not change runtime sources or rerun that numerical gate. Constructor requests
and explicit copied bytes are not physical heap allocations, live memory, RSS,
interior-window CPU, timing acceptance, or proof of a performance cause.

The exact AD48 source archive is reconstructed into independent shadow trees.
Three hash-bound broker/core source files receive fixed counters; contained
owned arrays, error handling, limits and all original runtime policies stay
intact. Native polling still copies its reused scratch buffer into owned data.
The frame decoder still produces mutable owned bodies. Counter methods receive
only lengths and use fixed preallocated storage, with one cleanup report.

An unchanged C forwarding shim from `7fc4c5d8` independently counts actual poll,
send and arm calls, forwarding arguments, pointers, results and errno. Positive
poll counts/bytes must equal the Dart owned-copy ledger. Negative terminal polls
remain visible in the whole-lifetime ledger; they are not copies or a new
error-free-lifetime requirement. Full delivery/integrity and graceful cleanup
remain separate mandatory checks.

## Client freshness correction

The original retained `3020a016…` MQTT client initializes one application buffer
with a fixed tail pattern and changes its ID prefix. Earlier MQTT delivery
totals/full verification remain valid, but fresh per-publication application
buffer/pattern claims based on that client are withdrawn. This limitation does
not affect the separate fresh WAMP campaign and public decoder/encoder probes.
No original result is changed or rerun.

The new diagnostic compiles a separate client from the exact original source.
Only body creation/full-byte expectations and freshness fields change. Every
warmup and measured publication receives a fresh owned body, keyed by a unique
row nonce and message ID. Window, count, payload size, ordering, duplicate,
warmup, timeout and shutdown checks are retained. The original client/AOT bytes
are witnesses, not measured by the new count-only capture. These changes and
observer overhead make its timings unsuitable for acceptance or comparison.

## Checks and one future capture

Fresh bootstrap/full `bin/test-fast` passed before tool edits. Portable source,
provenance, loader forwarding, readiness, workload and dispatch-mode guards
pass. Real original/shadow decoder controls preserve malformed/fragmented/growth/
mutable-body behavior. Actual fresh-body source/nonce/ownership/mutation controls
pass. Own-native no-data/TCP3.1.1/WebSocket5 controls verify complete bodies,
atomic evidence freshness and graceful cleanup. Independent C/Dart counters
agree on positive polls/bytes; terminal negative returns are retained.

Capture remains disabled until bounded companion/root review and the tools
branch's own frozen canonical verification complete. The external declaration
must bind clean tool HEAD, every tool/workflow hash, controls/review/canonical
receipts, AD48 source/run, original artifact ZIP hashes and actual native bytes.
The workflow's opt-in mode runs independently of CPU-profile/worker/host modes
and never cancels a started capture.

One future capture requires all five original profiles in declared order, five
fresh repetitions, 25 rows and 4,025,000 measured full-body deliveries, plus all
warmups. Nonces `196000001` through `196000025` are reserved for that single
capture; functional controls use disjoint domains. Every input/source/archive,
lock, actual broker/client/native/shim binary, stdout, counter, partial failure
and cleanup result must be retained and independently audited. No subset or
unchanged rerun may replace the declared capture. Final runtime adoption still
requires its own complete strict48/50 acceptance and clean CI.
