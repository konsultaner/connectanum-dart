# Native-view proof startup and retained comparison inputs

The `bd59c076` hosted copy job completed its expected throwing-loader negative
control, then the existing-API positive baseline exited before READY with native
listener I/O error -7. It produced no positive rows. The underlying errno/cause
was not captured; neither a source defect nor provider-only transient nor port
collision is proven. Its three chosen listener ports differ from its recorded
VM-service port. The complete failed artifact is retained, and the job is not
rerun unchanged or relabelled an SDK setup failure.

A controlled real-process regression reproduces an observability defect: a child
that exits17 with a diagnostic log is reported as a generic readiness timeout.
The repair polls exit state while preserving the original sixty-second deadline
for a live process, reports exit status and a bounded log excerpt, and closes
pipes after process-group/reader cleanup. Complete original logs remain intact.
The negative control, positive inventory, actual lease/owner checks and body
verification are unchanged; there is no automatic phase or workload retry.

The setup previously selected future listeners with bind(0), releasing the
reservation set before starting Dart and its VM service. A deterministic real
socket fixture reproduces an active competing listener blocking a native-style
SO_REUSEADDR/bind/listen. On Darwin an established outbound source connection
alone did not block that sequence; this contrary result is retained. These are
class-level fixtures, not proof of the hosted failure's original cause.

For Linux, the selector reads `ip_local_port_range` and
`ip_unprivileged_port_start` without modifying them, then reserves currently free
nonprivileged ports outside the automatic range. The whole listener set remains
reserved through selection; only EADDRINUSE permits a bounded new reservation
attempt before process launch. Exhaustion and other errors fail closed. Other
platforms retain the previous ephemeral selector. Explicit competing listeners
can still race after reservations close; this limitation is not hidden.
The [Linux kernel documentation](https://docs.kernel.org/networking/ip-sysctl.html#ip-variables)
defines these automatic-allocation and privilege settings. No sysctl, SDK,
allocator/GC policy, measurement window or sample count is changed.

Two before-failing regressions now pass. All21 probe cases include real owned
process cleanup, namespace privilege/range validation, bounded port errors,
exhaustion and an unchanged sixty-second living deadline. A separate real-socket
fixture tests three future listeners alongside twenty automatic listeners using
the host's actual range; all native-style binds/listens succeed. All23 existing
CI execution contracts pass, and Ruby parses the complete workflow / Bash parses
the changed step. Fresh parent full fast regression passes. Own full canonical
verification remains required before handoff.

The CI matched-native comparison also retains both actual libraries, both source
archives and the exact shared Cargo.lock with hashes before data collection.
The earlier bd59 comparison's F9A baseline can be rehashed from an exact retained
prior artifact whose native inputs equal7476; future runs must not depend on that
coincidence. This is input retention, not a benchmark/gate change.

This tools-only branch must not trigger unchanged20-profile or48/50 numerical
reruns to seek a favorable outcome. Parent failures and every running campaign
remain retained; this tooling work grants no performance acceptance or adoption.
