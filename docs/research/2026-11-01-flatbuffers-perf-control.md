# Native perf control for FlatBuffers diagnostics

## Observed blocker

The first `ext_08_payload_sizes` CPU capture on `290480a3`, workflow
[41298322137](https://github.com/konsultaner/connectanum-dart/actions/runs/41298322137),
failed before readiness with exit 255. Build and diagnostic contract tests passed.
Its router/client PIDs remained 5603/5693 through the initial request, three
warmups and memory snapshots. Perf reported a missing `/proc/5764/status` entry.
The origin of that different process/thread ID is not established. No timed
profile result is accepted from this capture. Its partial artifact remains
retained; source/native hashes were unchanged and process-group cleanup passed.

## Protocol repair

Use perf's native control descriptors while attaching to the observed application
PIDs: start disabled, send `enable`, wait for its acknowledgement, run the existing
data request, then flush `stop` before closing the input pipe. Descriptor 0 is the
control input and descriptor 1 carries acknowledgements. There is no helper
workload inside perf. The acknowledgement establishes readiness; the existing
per-PID sample, operation-window, symbol and cleanup checks still determine
whether the resulting diagnostic evidence is complete.

The [perf record manual](https://www.man7.org/linux/man-pages/man1/perf-record.1.html)
documents disabled startup and control acknowledgements. Linux v7.0's
[control parser and processing](https://github.com/torvalds/linux/blob/v7.0/tools/perf/util/evlist.c)
accept descriptors 0/1 and acknowledge a processed command; its
[protocol tags](https://github.com/torvalds/linux/blob/v7.0/tools/perf/util/evlist.h)
define a newline-terminated acknowledgement, written with its trailing NUL.

The sample frequency, call graph, clocks, three warmups, 30-second request,
operation/body validation and diagnostic memory stages stay unchanged. These
profiles use symbols/frame pointers and existing post-workload diagnostic GC
snapshots; they never replace production performance acceptance or its binaries.
This repair does not claim a cause for the original missing ID or a RAM fix.

## Regression evidence

The regression runs the actual generated `CPU_PROBE`, two distinct live Dart VM
services and real subprocess pipes. An HTTP fixture deliberately fails the first
data request with 418, so no successful performance data is fabricated. The fake
perf endpoint exercises delayed enable acknowledgement, early exit and missing
acknowledgement. Checks require readiness before the data request, explicit stop,
bounded cleanup and preservation of the primary capture error.

Before the repair, the control-protocol fixture reports two failures across three
cases. Afterwards all three pass. The complete CPU diagnostic suite passes all
22 cases and the existing window suite passes all ten. Pre-change canonical
`bin/test-fast` passes on unchanged `290480a3` using this worktree's own native
build. Real Linux capture and final canonical verification remain required;
local protocol tests alone do not establish native sampling or parity.
