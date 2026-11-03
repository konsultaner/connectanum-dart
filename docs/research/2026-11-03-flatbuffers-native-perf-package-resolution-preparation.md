# Helper package-configuration observation (2026-11-03)

Eleven new protocol guards pass. Two actual new SDK helper contexts also pass:
an owned outside-workspace isolate reports no active config, while an owned
workspace helper reports the exact predeclared config and all75 package mappings
in original order. All75 return file URIs; the nonce-specific absent package is
null in both contexts. Complete raw config bytes, stdout/stderr, signed statuses,
helper source and declarations remain. **This observes helper isolates, not the
WAMP workers, loaded source/native images or compiled-input closure.**

The SDK API reports the current isolate's package-config URI, which can be null;
its URI resolver does not promise source-file existence. [packageConfig](https://api.dart.dev/dart-isolate/Isolate/packageConfig.html),
[resolvePackageUri](https://api.dart.dev/dart-isolate/Isolate/resolvePackageUri.html).
Current docs identify3.13.7. Exact installed3.13.1 source signatures were checked
separately; no local/hosted SDK equality is inferred.

Source tracing found that PATH dart is a Flutter launcher, with optional bootstrap
and an upgrade/cache path before its ordinary cached-SDK delegation. The two
NONBENCHMARK method controls explicitly used the cached3.13.1 SDK leaf to avoid
running that updater. The original WAMP launcher and flags remain unchanged.
Selected SDK/launcher/API stamps, all3LOCAL locks, config and helper bytes verify
unchanged before/after. This is not proof of every delegated image or atomic
spawn identity, and does not establish historical wrapper updates.

The initial nine missing-API cases generated16 subtest errors, not production
failures. After nine passes, a new wrong-length payload reached the decoder;
its pre-decode length check now passes, while the authority-field negative was
already passing. No heap/RSS/allocation magnitude was measured. Existing45
producer methods are a byte-identical prefix and were not rerun. No aggregate
54-pass/new canonical claim is made.

[Qualified assessment and every member hash](2026-11-03-flatbuffers-native-perf-package-resolution-assessment.json),
[exact new source/guards/controls and retained failures](2026-11-03-flatbuffers-native-perf-package-resolution-evidence.tar.gz).
The initial SDK source locator mistake and all model advice remain. Advice to
mutate installed SDK/config files was rejected. The judge's generatorVersion2.0
concern does not apply: actual frozen pub metadata has configVersion2 and
generatorVersion3.13.1. No guard was relaxed; advice is not approval.

Fourteen Python tools remain uncommitted at HEAD601, production/helper12
unchanged. Generated Dart probes are separately declared and retained in ignored
owned directories; no production code changed. No WAMP/native benchmark, target
VMservice/profile/heap request, GC reset, new-tool canonical/build, Linux/perf/
kernel/capture or strict dispatch ran. Last free19.04GB exceeds12GiB; no cleanup.
Actual original launch/source/config and role/native-image association, complete
immutable admission/real receipt orchestration and appropriate own verification/
provenance plus real Linux non-benchmark controls remain required before data.
Both strict campaigns remain failed; PR132 stays draft/unadopted.
