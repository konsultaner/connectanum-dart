# Original-process payload stall capture

The supplemental payload campaign on `36a6df24` again stops on the one-MiB TLS
WebSocket Dart-value FlatBuffers case at the unchanged 300-second workload
deadline. It retains 85/360 rows, including two complete passes; its final
source-invariance confirmation is absent. The previous passing diagnostic
changes entrypoint wrappers, ports and HTTP/3 settings, and resolves different
Cargo graphs. Both use JIT. It therefore cannot identify a causal fix.

`ExternalDartVmMetricsCollector.connect` already starts a separate
`dart_vm_metrics_observer_main.dart` process with JSON arguments containing its
authenticated service URI, target PID and `all_isolates` role. This is the source
of endpoints for the new `capture_wamp_stall.py --original-processes` mode.
The mode retains the default package entrypoints, original scenario/router
paths, original ports/HTTP3 and existing deadlines. It writes no Dart wrappers.

Discovery walks only the diagnostic driver's Linux descendant tree, including
children spawned by non-leader threads. It reads observer arguments only within
that tree, requires the target to be another owned descendant, and checks PID
start ticks and parent identity before and after RPC. Endpoints must be numeric
loopback HTTP URIs; `getVM.pid` must match before requesting bounded stacks.
Authentication URLs are redacted from added captures and logs. No unrelated
process inventory is read, and no benchmark behavior or parity policy changes.

Focused tests cover original command/config preservation, non-leader discovery,
foreign/malformed endpoints, disappearing/reused/reparented processes, bounded
inventory, mismatched VM PIDs and URL redaction. A Linux smoke launches an actual
authenticated Dart VM and the production metrics observer, discovers their
existing endpoint, captures a stack, and checks clean process/reader shutdown.
The existing hosted payload diagnostic runs those checks before its original
360-row replay. Debugger RPC can perturb scheduling; every result is diagnostic
and cannot accept performance.

At this checkpoint these new tests/smoke are not yet verified. Local validation
is queued behind another task's exclusive resource lease; no lease is bypassed.
The initial fail-before test attempt expires without running. The queued
old-committed-source regression check, if it runs, is a reconstructed comparison
after implementation, not a chronological fail-first claim. Local companion
review is also blocked by the preserved resource lease. Runtime diagnosis and
the unchanged primary performance gates remain open.
