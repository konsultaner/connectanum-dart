# Deferred retention of native FlatBuffers control metadata

The unchanged-source [Linux profile](https://github.com/konsultaner/connectanum-dart/actions/runs/38961389070)
at `0ab8c54c430ced62d7f07d2bb5419aa35256da4f` retains 3,120 source hashes,
distinct router/client PIDs, actual sampling-window coverage, native perf data,
per-PID reports and standard Dart router JIT maps. An independent local audit
verifies those inputs. Dart router samples include 46 inclusive `retainMetadata`
ticks, including its projection and snapshot work. Inclusive stacks overlap;
these ticks are not a per-operation CPU cost or a parity result. Linux perf
still reports anonymous Dart code addresses despite the retained maps, so native
reports do not establish resolved Dart function costs.

A separate fail-first regression makes the avoidable work explicit. Binding a
native CALL, PUBLISH or YIELD with a 4 KiB binary extension dictionary records
16 KiB of owned clones before a resend or application access. Retention eagerly
decodes metadata, projects its typed model and snapshots both dictionaries.
Native forwarding does not need those dictionaries.

The candidate validates the complete bounded metadata CBOR immediately. Tagged
dictionaries retain eager semantic decoding: a bounded 10,240-value diagnostic
finds two syntactically valid date-tag values that the materializer rejects. A
fail-first regression reproduces delayed rejection before this fallback. Nested
tags are detected; tag-like byte-string contents are skipped. The candidate captures
original model-root identities and starts field-assignment observation. It
retains the immutable native metadata owner. Original dictionary decoding and
baseline projection/snapshots wait until a Dart serializer or `metadataFor`
needs them. A separate immutable control-field record reconstructs the initial
model; it captures no application vectors and disables recursive retention and
the opaque-payload flag. Later edits are compared with that original model,
never with a snapshot of the already-edited message. Root replacement can skip
unused history. The existing eager retention API remains available for mutable
external input and other message families.

The generic `retainNativeMetadata` API requires immutable, owner-backed encoded
bytes and an independent payload-free factory for the original control model.
The router uses it for directly bound CALL, PUBLISH and YIELD. Other bindings
retain their existing behavior. Tests compare eager/deferred metadata after
nested edits, binary edits, root replacement, custom-field removal and null
assignments before the first resend. They also cover explicit default presence,
malformed dictionaries, opaque bodies, one-time baseline construction, detached
metadata access and segmented resends without application decoding.

The three copy regressions now pass at zero eager clone bytes. The tag-safe
follow-up passes 312 focused VM and 160 Chrome/WASM cases with clean analysis. All 129 focused metadata cases, five Chrome/WASM cases and
3,877 existing binding/fragment regressions pass. Resulting-source full verification, hosted checks,
accounting renewal and controlled performance measurements remain required.
Canonical parity budgets and campaign requirements are unchanged.
