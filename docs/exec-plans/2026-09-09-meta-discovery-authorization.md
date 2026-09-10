# Meta Discovery Authorization

Status: implementation verified; branch publication requested, master integration and package release pending
Started: 2026-09-09
Completed: 2026-09-09

## Contract

The user requires registration Meta discovery to disclose only callable
procedures and subscription Meta discovery to disclose only subscribable
topics. Permission to invoke a Meta procedure is not a grant to discover all
realm entities. Publishing alone must not expose subscription metadata.

The [WAMP Meta API specification](https://wamp-proto.org/wamp_latest_ietf.html)
defines list/lookup/match/get and participant/count procedures. It describes
publisher use cases for subscription introspection; subscribe-only visibility
is this router's explicitly requested stricter policy, not a universal
WAMP protocol requirement. Preserve existing response shapes and make hidden
IDs indistinguishable from missing IDs through the related Meta endpoints.

## Work

1. Reproduce publish-only subscription visibility on real WebSocket,
   RawSocket, router-hosted MCP direct JSON, and Streamable HTTP connections.
2. Require subscribe permission for live and configured subscription Meta
   snapshots, including the correct match policy for dynamic authorization.
3. Remove the configured documentation-only registration authorization bypass
   in MCP Meta snapshots. Leave explicitly configured general API documentation
   catalogs outside this change; those are not WAMP registration Meta results.
4. Exercise static grants/denies, dynamic denials, pattern subscriptions,
   related Meta lookup/detail/count methods, and authorized positive controls.
5. Run focused tests and analysis, local review, and `bin/verify` sequentially
   after the baseline `bin/test-fast`. Do not overlap native runtime test gates.

## Progress

- Initial inspection: live registration snapshots already check `call`.
  WAMP and MCP subscription snapshots use `publish OR subscribe`. Configured
  MCP registration snapshots skip authorization when `allow_call` is false.
  Subscription visibility also omits match-policy context for dynamic checks.
- Baseline `bin/test-fast` passed before implementation. All eight live-router
  regressions then failed on unauthorized subscription IDs across WebSocket,
  RawSocket, MCP direct JSON, and MCP Streamable HTTP, under both static and
  dynamic policies. The initial standalone run skipped without a resolved
  native library; the red and green runs explicitly loaded the ffi-test library.
- Implemented subscribe-only visibility and dynamic match-policy context on
  both paths, plus call authorization for configured MCP registration entries.
  All eight regressions now pass, including authorized positive controls,
  publish-only and register-only callers, explicit and dynamic denials,
  exact/prefix/wildcard subscriptions, configured entries, and hidden-ID parity.
- Router analysis and the combined 122-test Meta/session/auth suite pass.
  Local semantic review completed; source checks confirmed catalog separation,
  exhaustive match-policy conversion, and existing static/dynamic precedence
  coverage. No actionable production-code finding remained.
- The first full `bin/verify` run exposed a legacy MCP smoke expectation that
  anonymously disclosed a configured registration without call permission.
  That smoke now requires the ID to stay hidden publicly, while an authorized
  member retains synthetic ID/list/get/callee coverage. An ID learned by the
  member must also remain hidden when used on the public endpoint. The separate
  explicitly configured documentation catalog remains visible as before.
  The updated smoke passes independently and in the complete verification gate.
- Final `bin/verify` passes: 482 router tests (including all eight new discovery
  cases), six isolated remote-auth tests, 13 zero-copy tests, 124 benchmark tests,
  isolated package/live MCP consumer smokes, and Chrome/Dart2Wasm SCRAM and
  WebSocket coverage. Router analysis and `git diff --check` are clean. The
  test-only follow-up review was checked against the intentional nondisclosure
  contract and existing helper behavior; no actionable issue remained.
- The user requested a commit and push of the verified security branch.
  Published beta.5 consumers still require master integration and a synchronized
  release to receive this fix; pushing this branch does not publish packages.
  Resume the broader WampApp plan without treating this source verification as
  evidence of a package publication or deployment.
