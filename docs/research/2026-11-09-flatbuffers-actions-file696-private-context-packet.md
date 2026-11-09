# PR #132 private context packet and collector integration frontier

The original full private scope now has a local, lossless packet representation for a proposed GitHub Actions secret handoff. It remains opaque: the preparation did not decompress or parse the original scope. No secret upload, runtime handoff, collector execution or source publication occurred.

The original 70,049 compressed bytes (`e97264c25e31c836f8447a5ec1d9b421bf939642b6f75e2a57f7dd7eb3134d2d`) become 93,400 Base64 ASCII bytes (`dddd99c67da9b3bb4643db887f0211316c99cb3870b568a7bfcb55c3a6d38387`). Each newly created output was read back on its original output FD. Concatenating those saved readbacks and strictly decoding Base64 equalled every original compressed byte; canonical re-encoding also matched. This is the first check of a new representation, with no replay of the consumed original scope classification or copy proof.

| Part | ASCII bytes | SHA256 |
| --- | ---: | --- |
| 0 | 32,768 | `72b66e4f014529d9187bc8020ca0b6b43dfb81d6c1fb358ec254233ba3690157` |
| 1 | 32,768 | `d66049bc28de81536b5190549af45cbd28edea0037b40bfb322944f7bebfc6d2` |
| 2 | 27,864 | `f4874519a10a10933376c3b2aea665c7bcaa6a248f08437b290c57777740f4c0` |

The packet namespace was created with mode0700 and new private files with mode0600. Original native creation/FD/stat-time/IO/known-close values are retained privately; those points do not establish original driver credentials, global actor ownership, continuous physical EX or crash qualification. Base64 is an encoding, not encryption. Neither packet bytes nor the full private contexts enter the public archive.

## Proposed provider interface

GitHub documents a48KB limit per secret and100 repository secrets. The proposed three values fit individually; available slots, access and actual runtime behavior have not been queried or established. Repository secrets are read when a run is queued. These are provider interface facts, not permission to upload or dispatch. [GitHub secrets reference](https://docs.github.com/en/actions/reference/security/secrets).

A future qualified upload can supply each complete part through standard input to the official CLI, selecting the repository and Actions application. Payloads must stay out of command-line arguments. The CLI documents local encryption before sending; no CLI secret command, public-key request, secret inventory or upload was performed here. [GitHub CLI secret interface](https://cli.github.com/manual/gh_secret_set).

The proposed staging actor receives explicit step-scoped secret environment values. Secret expressions must never be interpolated into shell commands or source literals. A separate staging actor would reconstruct the original compressed bytes into an explicitly declared private metadata input file using exclusive/no-follow creation, owned handles and mode0600. This contract has no staging implementation or collector input loader yet. [Using secrets in workflows](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets), [secure workflow use](https://docs.github.com/en/actions/reference/security/secure-use).

The original collector and driver must retain the original Linux/Dart/Rust recipe, PATH, argv, environment and credentials. The proposal must not use a global environment update, pass secret payloads into the collector environment, or replace the original driver parent with the staging actor. Actual credential/environment/FD equality, generated-output cohort and continuous official physical EX/crash qualification remain unperformed.

## First selected glue qualification

The newly assembled full draft remains80,496,772 bytes/`a57ffdba308c769d8ac5ba2f4b7f119ead53c635844b4b0963f3f8fc20c6a7b9`. Its first local syntax parse98777 and the workflow YAML qualification90454 are consumed and were not repeated.

A first manual review of the selected new stage integration frontier observed that the stage reports query permission and alias identity as unproved, then calls the file reader. No qualified original preflight is supplied by that new callsite. This is a source-flow finding and an unresolved integration obligation; it is not an executed supported BEFORE failure or a conclusion about uninspected parent-prefix behavior.

The assembled source still embeds the explicit public operand projection. Preserving the original private scope and creating this packet do not install a runtime path that forwards all71 full contexts, all696 full references, private fields, stat-times, FDcredentials, ancestry, native order, duplicate positions, relationships and original/new static nulls. All remain unchanged in their original evidence. Actual future runtime facts must be separate.

Next, prepare the fail-closed prequery integration contract and the full-context staging/input-loader design. All SDK file-body IO must remain withheld until applicable actual original-source/known-ledger/SDK/ownership/actorFD/generatedcohort/continuous physical EX/crash preflight is complete. Literal nonmatches, regular modes, syntax labels, copied bytes, a new namespace or a receipt declaration cannot supply that authority.

## Evidence and limits

The [public assessment](2026-11-09-flatbuffers-actions-file696-private-context-packet-assessment.json) and [selected evidence archive](2026-11-09-flatbuffers-actions-file696-private-context-packet-evidence.tar.gz) contain explicit derived metadata only. Complete original metadata values, actual ROOT request/return roles and original creation/IO context remain private. Public projection excludes private contexts only; no original field, historical epoch, relationship, raw limitation or null is rewritten.

The packet assessment is17,545 bytes/`ba128ccb8c2c62750c9b8a60aaa9a7fd02dbfc3091d1cbb5fadcbd5db9002595`; its original native creation/IO receipt is13,519 bytes/`45827897cca1e4614b94a891fd2875bc94a9fb47782ad33bbe7f044e6408cd96`. Outer tool pipe EOF remains unprovided/null. These metadata files are not full private SDK/report/source/runtime payloads or an admitted Source20/runtime package.

No Source20/runtime file, original workflow recipe, SDK, GC, allocator, workload, copy/cohort rule, gate or schema was changed. No SDK body query, collector import/exec, workflow source publication/dispatch, bootstrap/build, native/driver/broker/profiler/numerical execution, adoption or cleanup occurred. All admission flags remain false and ownership remains null. RAM repair, own FINAL strict48/50 and clean final production CI remain incomplete; preparation-only skip-ci does not waive final CI.
