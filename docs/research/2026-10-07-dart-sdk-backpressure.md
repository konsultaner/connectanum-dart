# Dart SDK socket backpressure and storage identity

The [Linux diagnostic](../../packages/connectanum_client/tool/sdk_socket_backpressure_probe.dart)
uses the existing C write interposer with a real paused loopback receiver.
Unlike the earlier forced short-write/EINTR probe, it requires genuine kernel
EAGAIN and a pending Socket.flush before permitting reads. It records accepted
bytes at that boundary, resumes the receiver, requires positive later writes,
and validates every received byte and the complete accepted-byte total.
It observes every write address, including errors, without changing errno or
faking readiness. The calloc allocation remains alive until drain and cleanup.

All four 16 MiB cases pass on Dart 3.13.5 Linux arm64: full mutable/read-only
views retain their original addresses plus accepted offsets across resumption;
partial mutable/read-only views use distinct SDK storage throughout. Each case
observes four EAGAIN results. Before the explicit reader resume, 2,625,195 bytes
are accepted; the remaining 14,152,021 bytes are accepted afterward. The
[checked result](2026-10-07-dart-sdk-backpressure-proof.json) retains all
observations and source hashes, verified against the executed Linux files.

The actual CI step compiles the C interposer with strict warnings and passes
the existing SDK probe, all 36 real RawSocket PPT cases, all four backpressure
cases and the original absent-interposer control. The new tool independently
fails without the interposer at its required symbol lookup. CI uploads
backpressure.jsonl beside the earlier evidence. Root analysis passes.

A local Qwen review completed. Its proposed write lock is unnecessary: no
event-loop yield occurs between the final probe observation and the pending-flush
assertion, and an unexpectedly completed flush rejects rather than falsely
accepts the required resumption condition. The pinned SDK's
[consumer stop](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/sdk/lib/_internal/vm/bin/socket_patch.dart#L2697)
and [Socket.destroy](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/sdk/lib/_internal/vm/bin/socket_patch.dart#L2796)
cancel the consumer and disable writes before clearing the raw socket. The
probe destroys sockets and cancels subscriptions before freeing storage. Missing
preload cannot silently return garbage: the shared required-symbol lookup fails,
as verified by the explicit absence control. Companion claims stay advisory.

This establishes the selected SDK pointer boundary through actual backpressure.
It does not establish Rust/database ownership, FlatBuffers routing under
backpressure, TLS/masking/internal copy totals, performance parity or all-platform
behaviour. Partial-view copying, complete copy attribution and the full declared
paired benchmark campaign remain open.

After bootstrap, reproduce on Linux with the same process-only preload:

```bash
probe_dir="$(mktemp -d)"
cc -shared -fPIC -Wall -Wextra -Werror \
  -o "$probe_dir/socket_probe.so" tool/sdk_socket_copy_probe.c -ldl -pthread
(
  cd packages/connectanum_client
  CONNECTANUM_SKIP_NATIVE_BUILD=1 LD_PRELOAD="$probe_dir/socket_probe.so" \
    dart run tool/sdk_socket_backpressure_probe.dart
)
```

Fresh quiet `bin/verify` passes at exit 0, including Rust, VM, consumers, all
1,563 benchmark and 4,958 router cases, 4,751 core Chrome/Dart2Wasm and 2,829
client browser cases with 20 declared native-only skips. Evidence:
`/tmp/connectanum-sdk-backpressure-verify.{log,exit}`. Final sequential
`bin/test-fast` also passes at exit 0, including all 1,563 benchmark cases and
the unchanged readiness regression. Evidence:
`/tmp/connectanum-sdk-backpressure-final-fast.{log,exit}`. Resulting-head hosted
execution remains pending.
The preceding local commit d4d91317 passed both canonical commands and independent
interop before these tool/CI additions.
