# Unqualified user-space profiling

The complete diagnostic run 44699790883 uses AMD EPYC 7763 and misses
fragmentation, JSON file lifecycle and large RawSocket lifecycle floors.
Its checksum-verified artifact is 14612946770, SHA256
`6d998815262b56e1b1d02ded5b5d166ede3ba39a5b4747966cb963c842a46f53`.
No qualifying run is replaced by this investigation.

Kernel `perf` sampling is unavailable on the hosted runner. GNU gprofng
supports clock sampling and following descendant processes with `-p` and
`-F`, without compiling an instrumented binary. This investigation uses
10-ms clock sampling, disables hardware events, and makes no kernel-security
changes. Plain measurements and sampled runs are separate; original workload
parameters, compiler/allocator/GC defaults and frozen bundle checks remain.
The canonical qualification still runs the complete original eight scenarios.

Primary reference, checked 2026-11-20:
[GNU gprofng collect app manual](https://www.sourceware.org/binutils/docs/gprofng.html#Man-page-for-gprofng-collect-app).
