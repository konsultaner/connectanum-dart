# Full paired campaign started at `8af2c337`

The first full primary campaign is running from an isolated, clean Linux
checkout of `8af2c337e5633ab77fef7e6e0c2298db388e6754`. A Git bundle preserves
the exact source history. The three dependency locks from the verified workspace
were copied before `dart pub get --enforce-lockfile` and locked release builds.
The source remains separate from the feature worktree and earlier diagnostic
checkouts. Release binaries were copied out of Cargo's mutable target caches.
The native library has no `ct_test_` exports.

The unchanged policy requires all 48 cases, three serializers, three warm-up
passes and seven measured passes: 1,440 rows. Each row requires at least ten
seconds and 1,000 samples. The run uses seed 20261005, one router worker, one
native runtime thread, concurrency one and one in-flight operation. The driver
and native library are release builds. The primary runner keeps its existing
20,000-resample, 95% confidence and better-CBOR/MessagePack parity gates.
No case, threshold or copy field was removed.

The campaign started at `2026-10-07T01:00:22.701439+00:00`. Initial authoritative
processes are runner 17154, driver 17178, server 17179 and client 17267 inside
`connectanum-flatbuffers-linux-bench`. The execution tool session is 79116.
Results live at `/tmp/connectanum-8af2c337-primary-campaign-01` in that container;
the host captures output at `/tmp/connectanum-8af2c337-primary-campaign.log`.
These identifiers locate running work; only current process/session inspection
proves continued liveness. Do not restart on an observation timeout.

The first three warm-up rows contain 3,802, 4,113 and 4,640 samples with windows
of 10,000.285, 10,004.161 and 10,000.987 ms. Their client/server identities agree.
This verifies initial execution, not completed passes or performance acceptance.
[The start proof](2026-10-07-primary-flatbuffers-campaign-proof.json) records
source, lock, policy, scenario and binary hashes and the exact command.

The pinned image is
`dart@sha256:7efb22ee3003e3aaa7af34840bfacb2fc1b06e1ac1295237dfcca1552816588e`.
It provides Dart 3.13.5, Rust 1.99.0 and Linux arm64. The guest exposes 24 virtual
CPUs with implementer `0x61`, architecture 8, variant `0x0`, part `0x000` and
revision 0. It does not expose a marketing model; the unchanged runner records
`cpu_model=unavailable`. Separately captured host evidence identifies Apple
M3 Ultra. The limitation remains explicit and does not waive platform evidence.

TLS and Dart SDK copies remain `not_measured` in initial results. The comparator
must reject those gaps even if timing improves. Further source inspection of
Rustls 0.23.45 confirms that writer acceptance cannot measure all copies:
`append_limited_copy` uses `to_vec`, whereas `ChunkVecBuffer::append` moves an
owned vector into a queue. Its `apply_limit` and borrowed `split_at` operations
do not themselves copy the payload. Local summary advice incorrectly labelled
those operations as copies and was rejected after source inspection. Encryption
and deframer internals need separate accounting; no complete-TLS claim follows.

The run is incomplete. Keep #100–#104 and the milestone open. Retain raw reports,
failed comparisons and hardware limitations, verify full execution and unchanged
inputs at completion, then use measured regressions to guide the remaining work.
