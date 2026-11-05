# Native actor-creation and generated-input contract

## 2026-11-05 — Bound a native actor-creation and generated-input contract

A new static candidate specifies direct child creation with an original kernel pidfd and a preallocated actor/pipe registry. A later ROOT refinement proposes a shared atomic registration barrier and gives a conditional ordering argument. Both remain unimplemented: ABI, signal paths, child close journals, error handling and physical lease lifetime have no native execution proof.

The direct reference does not register descendants created inside an unchanged shell, Dart/pub or Cargo/compiler tree. Cgroup population and PID lists cannot supply the required actor/FD/exec/exit evidence; a new group, migration, freeze or privilege grant is not proposed. No original-host access or syscall was probed. Independent output validation is also contract-only: policy provenance, exact slot/search closure, bench first-writer schedule and validator implementation remain absent.

GLM's complete judgment recommends changes and is ROOT-qualified. Its claim about exhaustive kernel mechanisms is unsupported, and its proposed experiment is not authorized by this prose. GLM reviewed the first candidate, not ROOT's later paper barrier. No current twenty-helper/runtime source operation, new test, SDK/recipe/build/native syscall or capture occurred. Provider remains absent and all admission flags false; original-runtime qualification, RAM repair, final strict 48/50 and clean final CI remain incomplete.


The proposed native helper would use `clone3` with `CLONE_PIDFD`, without sharing FD tables or introducing namespaces/cgroups. The manual documents a child pidfd in parent storage; that direct reference does not establish a whole SDK process tree. See [clone(2)](https://man7.org/linux/man-pages/man2/clone.2.html).

Kernel cgroup documentation describes inherited membership, possible migration, non-atomic PID enumeration and live-process population. These observations do not establish signed reaping, actor identity or complete FD/exec ownership. No cgroup access, control or migration operation ran. See [cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html). Applying these API facts to reject a closure shortcut is ROOT's inference; original-host behavior remains unmeasured.

The paper barrier requires the child to perform only lock-free shared-atomic loads before parent registration succeeds. The parent would publish readiness with release ordering, and the child would use acquire ordering before its separately journaled close/read/exec continuation. That argument is conditional on an independently qualified native implementation and ABI. Parent failure keeps the proposed gate closed; crash survival, scheduling cost, native error outcomes and continuous physical EX remain unproved. It supplies no SDK or frozen-driver change authority.

Generated observations remain UNADMITTED. A separate validator and predeclared original-cohort policy must supply authority; the candidate, schema, absence statement and generator's own hashes cannot create it. Historical LOCAL/HOSTED cohorts remain distinct. No borrowed bytes, expected-hash filling, extra unlock/metadata recipe or favorable regeneration is permitted.

The full proposal, ROOT refinement, model answer and qualifications are retained in the evidence archive. New primary web tool returns stay local; the public index records their exact saved-return SHA/size and source URLs, not a full-page body hash. Initial checkpoint metadata was read without SH and supplies DATA only. The first combined documentation/policy output truncated; the entire frozen policy was then read under official SH. Neither omission was reconstructed.

Next work must specify native ABI/signal/FD-close/error/lease obligations before any finite non-SDK experiment, and separately establish a permitted original transitive registration mechanism and independent cohort authority. This static contract authorizes no invocation or admission.

[Assessment](2026-11-05-flatbuffers-native-perf-native-actor-contract-assessment.json), [evidence](2026-11-05-flatbuffers-native-perf-native-actor-contract-evidence.tar.gz).
