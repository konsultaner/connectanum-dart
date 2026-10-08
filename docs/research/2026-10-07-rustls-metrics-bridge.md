# Optional Rustls source metrics bridge

A new `ct_rustls_copy_metrics_snapshot` C symbol returns six cumulative source
observations in a separate 48-byte structure: outbound chunk copies, queue
reads, deframer appends/moves and record-buffer/content appends. It maps the
pinned observer fields directly; it does not derive copies from accepted bytes.
Snapshots are process-wide and do not synchronize concurrent TLS operations.
The original 24-byte and V2 40-byte transport snapshots remain unchanged.

Both Dart runtimes use optional symbol lookup. Missing source counters stay
null, including deltas when either endpoint lacks the ABI. Available endpoints
retain each named integer counter. The existing reset behavior is preserved.
Native benchmark client/router breakdowns retain six separate partial fields;
no total TLS/transport/crypto acceptance gate is changed or inferred from them.
A separate fail-first negative-value control rejects invalid partial source
counts as unmeasured using the existing strict byte-count validator.

Twelve fail-first cases expose absent router partial-counter metadata on both
transports. They pass with explicit unknown metadata. A separate propagation
case uses distinct field values and still requires unmeasured total TLS and
transport coverage. Twelve DTO cases exercise changes, zeros, resets and both
null endpoint directions for both runtimes. The native check guards the new
48-byte layout, untouched tail and null pointer contract and checks the source
observations. Both old/new library ABI probes preserve old layouts and nullable
fallback. MacOS passes 56 merge/delta cases and both ABI probes; Linux matches
all 2,996 final frozen source/lock inputs and passes 56 merge/delta cases
plus its new-ABI probe, its
native guard and the old published-library probe. This is correctness evidence,
not a paired performance or whole-copy result.

Companion test advice completes and informs old/new-library and nullable delta
checks. Final review is blocked by an active native-mutation resource lease;
no completed review is claimed or lease bypassed. Source mapping, bounds/layout
and separate partial reporting are inspected directly. The initial canonical fast run finds a local SDK path in the published artifact
proof; the separate repair normalizes command metadata and retains raw report
hashes. Direct public-reference validation passes. Fresh canonical `bin/test-fast` and full `bin/verify` pass at exit 0, including
1,642 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser cases
with 20 unchanged native-only skips. Direct crate formatting passes after only
sorting module declarations/reexports; Linux guards and the new-ABI replay
pass with all 2,996 formatted inputs matched. The narrowed review retry remains
blocked by the same native-mutation lease. See [scoped proof](2026-10-07-rustls-metrics-bridge-proof.json).

Tokio-Rustls extraction, remaining growth/record/crypto and Dart SDK boundaries,
mixed-serializer copies, full primary and original supplemental acceptance,
and all-five production runtime evidence remain open. No milestone or complete
TLS/crypto-copy claim follows.
