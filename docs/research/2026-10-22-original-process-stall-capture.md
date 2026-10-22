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

## Original-process reproduction

[Run 39803270108](https://github.com/konsultaner/connectanum-dart/actions/runs/39803270108)
passes the focused contracts and real authenticated VM smoke on `f0875fef`.
The original 360-row replay then fails after 47 rows on the same one-MiB TLS
WebSocket Dart-value FlatBuffers workload, at the unchanged 300-second deadline.
Independent audit verifies all 3,178 tracked source hashes, three resolved lock
contents, original command/config/scenario paths, all retained order/floors,
production binaries matching the copy proof, every recorded invariance flag and
clean process/reader/monitor shutdown. The ignored package configuration is not
recorded by this historical diagnostic; the follow-up retains and checks it too.

All three captures verify live router/client VM identities and return stacks
without errors. All nine application isolates have empty synchronous and async
continuation stacks at these observations. This does not locate the suspended
operation. `Stack.messages` is deprecated and always empty in the installed VM
service protocol; it cannot establish that the message queues are empty. Source:
`vm_service` 15.3.0 `Stack`/`getStack` API documentation. No worker crash is
inferred from the later cleanup warning.

The next diagnostic adds bounded Linux thread CPU/wait-channel observations and
TCP queues for socket inodes held by those same owned targets. It retains only
matching socket rows, not ordinary descriptor paths or unrelated process
inventories, and rejects changed PID identities before/after observation. Limits,
missing records and errors remain explicit. This is non-atomic observation,
never performance acceptance. Focused contracts and the real smoke now check
those observations; this follow-up is not yet behaviorally verified.

Both local focused-validation waits and the full-verification wait expire at
another task's preserved resource lease without executing. Local debug/review
companions are likewise resource-blocked. No lock is bypassed, no chronological
fail-first result is claimed, and the reconstructed old-source check remains
pending. Runtime diagnosis and unchanged primary performance gates remain open.

Artifact `12438351850`, archive SHA256
`3b3dd2ef926b247ccadf18d18efb3c4e35b73dbc185f50c1ddc5ee2119713095`,
all three captures and `original-process-f087-independent-audit.json` are retained
under `out/flatbuffers-resume-20261022/`.
