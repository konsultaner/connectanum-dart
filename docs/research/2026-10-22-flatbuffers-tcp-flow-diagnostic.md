# Owned-socket observations for the intermittent TLS payload timeout

The faithful original-process replay at `17f` (run 39808842310) fails after
257 of 360 rows on the 1-MiB Dart TLS WebSocket FlatBuffers case. The raw
archive, independent source/input audit and unsuccessful replay remain in
`out/flatbuffers-resume-20261022/`. A separately labelled reduced 90-row replay
passes; it does not accept the complete payload shard or primary parity.

Three owned-process captures show established server/client sockets. The server
send queue changes from 497,155 to 953,806 to 363,982 bytes; receive queues are
zero. Over about 120 seconds, owned native Tokio threads accumulate no CPU ticks
and the client Dart worker accumulates eleven. VM stacks have no runnable Dart
frames. These observations do not establish an application deadlock or a cause.

The retained `/proc/net/tcp` timer value is 4. The kernel's
[proc TCP documentation](https://docs.kernel.org/networking/proc_net_tcp.html)
identifies that value as a pending zero-window probe. Queue sizes alone cannot
show which TCP window or buffer is limiting progress. An empty deprecated VM
`Stack.messages` field also says nothing about an application event queue.

## Additional observation

`tool/wamp_stall_tcp_info.py` augments the existing original-process diagnostic
with TCP_INFO, socket-memory and timer output. It queries only established IPv4
loopback application sockets already found through the verified process's FD
inodes. Application ports come from the unchanged router listener configuration;
the control HTTP listener is excluded. IPv6 TCP_INFO is explicitly unmeasured.

The command uses `ss -H -O -n -t -4 -i -m -e -o` and an exact numeric source/
destination tuple with an established-state filter. It does not use a shell,
DNS resolution, a process inventory, or socket-mutating options. The result is
retained only after checking its tuple and single inode against the owned
record. Target/observer/root process identities are checked before and after.
At most eight socket commands, two seconds per command and 16 KiB per result
are retained. Closed sockets between snapshots are explicitly unavailable;
missing tools, malformed output, timeouts and ownership mismatches remain errors.

The [ss manual](https://man7.org/linux/man-pages/man8/ss.8.html) documents its
filters, TCP counters and memory fields. In particular, `rcv_space` is an
autotuning helper, not the peer's advertised window. Counter deltas across
captures can distinguish continued transfer from a prolonged absence of
progress; they do not by themselves identify an application-level cause.

## Verification and limits

The isolated staging suite passes 46 discovery/capture/Linux/TCP_INFO cases.
Its first two harness attempts fail because the private staging directory lacks
unchanged tool imports and then the workflow fixture; both attempts are retained.
Supplying those unchanged dependencies restores the suite. Tests cover exact
tuple/inode checks, numeric loopback endpoints, process identity changes,
bounded output/socket counts, missing tools, timeouts, closed sockets and
listener-port filtering. All 49 production-source capture contracts and 14 CI contracts subsequently
pass. A completed focused Qwen review claims combined tuple filters are invalid
and process identity checks might only test PID existence. Both assumptions are
checked: the primary manual explicitly permits `src/dst ADDRESS:PORT`; identities
compare parent/start ticks for driver, target and observer. The returned tuple
and single owned inode must also match. No concrete defect is established.
Real Linux smoke and the resulting-source faithful replay must still run.

The first real Linux attempt (39840625793, artifact 12452618295) fails before
any workload row: no selected IPv4 socket matches the advertised VM-service
port. Its snapshot is not saved, so endpoint ownership/family cannot be inferred
from that failed capture. The archive SHA-256 is
`b5cf60b8186084d4e0d79792475468d6ce73f5215ca236ad9e1bd5a43e0533cd`.

The corrected Linux smoke binds an explicit IPv4 listener inside the test VM,
holds an accepted Python peer, and captures that known owned listener endpoint.
It also checks the expected local endpoint independently of collector filtering.
A redacted snapshot is saved before validation, so failed observations survive.
Five isolated cases, all 54 resulting-source capture/smoke cases, 14 CI
contracts and real local Dart listener readiness/acceptance/shutdown pass.
Real Linux `ss` validation and replay remain pending. This listener exists
only in the smoke; it adds no benchmark workload. The original full replay keeps
its package entrypoints, listener ports, router configuration, scenario order,
sample/duration floors and deadlines. Stack/socket observations can perturb
scheduling and are diagnostic only. They are outside copy accounting and cannot
establish primary performance acceptance. No transport fix is justified yet.
