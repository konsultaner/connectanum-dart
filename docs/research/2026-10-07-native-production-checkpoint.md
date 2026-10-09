# Native production checkpoint 8503f31c

[Native Artifacts 37546766311](https://github.com/konsultaner/connectanum-dart/actions/runs/37546766311)
passes five platform builds and its dry-run preview at
`8503f31cdb966a592b52e774ed32bda0d19c22db`.
The downloaded archive and library checksums match their manifests. All fifteen
attestations verify with the exact source digest, branch and signer workflow,
with self-hosted runners rejected. The preview lists exactly the thirty verified
assets; its release notes match the renderer at this source checkpoint.

Fresh commit-pinned consumer source archives match on macOS Apple Silicon and
Linux arm64. Both production libraries pass all eight consumer steps: dependency
resolution, all four encodings, native construction, twenty external-buffer
provenance cases, ten owned-segment cases, sixteen live owned-PPT cases and
104 public mixed-PPT cases. Actual GC is included in the provenance suite.
Every retained log hash matches. Neither production library exports test oracles;
the macOS ffi-test library provides an eighteen-symbol positive control.

macOS Intel, Linux x64 and Windows have build/provenance evidence only. These
consumer runs verify runtime correctness, not performance or complete-copy
coverage. No release was published. Resulting-head required CI and the unresolved
milestone acceptance criteria remain pending. The [evidence record](2026-10-07-native-production-checkpoint-proof.json)
retains manifest/library hashes, attestation commands, preview checks and
consumer commands/results for reproducing the checks.
