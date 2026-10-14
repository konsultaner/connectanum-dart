# Standard SDK copy acceptance

On 2026-10-14 the user explicitly selects the standard Dart SDK: verify
Connectanum's buffer copies and label unmeasured dependency internals. This
supersedes the requirement to instrument every internal SDK/TLS/crypto copy.
All throughput, latency, CPU, allocation, GC and RSS budgets remain unchanged,
as do the 48 primary cases, three warmups, seven measurements, ten-second
minimum windows and 1,000-sample minimum. FlatBuffers must still meet parity
against the better CBOR/MessagePack baseline for each case and metric.

The report marker `measurement_scope: connectanum_buffer_boundaries_v1`
identifies the new contract. Reports without it remain legacy evidence; the
old failed campaign is preserved and cannot silently become accepted.

`transport_copy_bytes` covers the documented Connectanum client and router
transport buffer boundaries. The client records all six Dart transport
counters, or its native Dart-to-Rust bridge and both prefetched-input counters,
plus native WebSocket mask/coalescing copies when active. The router records
its Dart-to-Rust bridge, both input counters and active WebSocket coalescing.
The total must equal these independently retained breakdowns. An absent,
invalid, fractional or negative counter still prevents complete coverage.
Builder input/growth, optimized payload reuse and transcodes stay separate.

The coverage object separates `unknown_boundaries` inside this owned contract
from `unmeasured_dependency_boundaries`. The former must be empty for complete
coverage. The latter must match the active client/transport/TLS configuration;
arbitrary exclusions cannot hide an owned copy. Numeric byte counts alone
cannot certify complete coverage, and the standard SDK does not require a
custom SDK build.

Only two mandatory diagnostic fields may be dependency-labelled
`not_measured`: TLS internals on a TLS row, and SDK WebSocket masking on a Dart
WebSocket row. Their entries require `scope: dependency_internals`, the actual
dependency identity and a nonempty explanation. Native WebSocket masking
remains measured. Active transformations cannot be labelled `not_applicable`.
Partial Rustls/Tokio-Rustls observations remain available without claiming a
whole-dependency total. Accepted plaintext volume remains a separate
diagnostic rather than a memory-copy count.

E2EE and mixed-serializer copies performed by Connectanum remain required
when those paths are exercised. Crypto dependency internals may be unmeasured,
but that does not excuse missing provider, bridge, serializer or framing
observations inside the declared contract. The current E2EE lower bound and
mixed-serializer aggregate still do not certify complete owned coverage.
The primary homogeneous, unencrypted payload matrix must not imply acceptance
of those separate paths.

New tests cover secure/clear and Dart/native transport combinations; missing
owned counters despite permitted dependency exclusions; forged totals;
legacy scope markers; incorrect dependency identities; and inactive or
unexplained exclusions. The comparison's human-readable report describes the
scope and retains detailed raw evidence. Fresh resulting-source and hosted
verification remain required before accepting issues or performance.
