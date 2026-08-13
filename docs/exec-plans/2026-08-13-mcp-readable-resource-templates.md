# MCP Readable Resource Templates

Status: active

## Goal

Make router-advertised MCP resource templates usable by consumer applications:
a concrete URI constructed from a listed template must resolve through ordinary
and direct JSON `resources/read`, retain route-principal authorization, and
reach the configured WAMP read procedure with safely decoded template
variables.

## Context

The router currently serializes `resource_templates` into
`resources/templates/list`, but both the core server and the router direct JSON
path resolve reads only through the exact-resource map. As a result, the
advertised template cannot supply context to an application or agent.

MCP defines `uriTemplate` as an RFC 6570 URI template used to construct
resource URIs. The official TypeScript SDK registers a template together with a
read callback, matches a concrete URI, and passes the decoded variables to that
callback. Connectanum will first support the bounded RFC 6570 Level 1 shape
already used by router configurations: simple `{variable}` expressions with
percent-encoded values and literal separators.

References:

- <https://modelcontextprotocol.io/specification/2025-11-25/server/resources>
- <https://modelcontextprotocol.io/specification/2025-11-25/schema>
- <https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/servers/resources.md>

## Plan

1. Preserve the preceding checkpoint's hosted-evidence notes and run repository
   workflow, Serena, overlap, both-roadmap, exact-head, and pre-change checks.
2. Add a fail-first core server regression proving an advertised template URI
   currently returns `Resource not found`.
3. Add bounded simple-template validation/matching, decoded variable delivery,
   exact-resource precedence, and centralized resource resolution in
   `connectanum_mcp`.
4. Add router WAMP template readers, pass extracted variables as keyword
   arguments, and filter procedure-backed templates from catalogs when the
   route principal lacks call authorization.
5. Extend neutral native/generated consumers and the pinned official SDK Router
   Image gate through public and protected legacy/modern template reads without
   exposing contextual content, credentials, or protocol/session identifiers.
6. Run focused and full verification, strict package/privacy checks, record
   durable Serena guidance, publish both maintained remotes, and audit exact-
   head GitHub CI and Router Image evidence.

## Progress

- 2026-08-13: Repository workflow, required skill, Serena, overlap,
  completed-plan, both-roadmap, exact-head, and worktree preflights pass. The
  only startup edits are the preceding completed checkpoint's expected hosted-
  evidence notes; no unrelated same-repository editor exists.
- 2026-08-13: Official protocol and TypeScript SDK guidance confirms that a
  listed URI template constructs readable resource URIs and that matched
  variables reach the registered read callback.
- 2026-08-13: Pre-change `bin/test-fast` passes the complete fast regression,
  live WAMP integration, generated-consumer, installed/global package, and
  Router Image contract matrix.
- 2026-08-13: A fail-first core regression reproduced the missing public
  `McpResourceTemplate.read` contract. The core registry now owns bounded
  Level 1 matching and validation, exact-resource precedence, percent-decoded
  variable delivery, deterministic template selection, and centralized exact
  plus template reads for standard MCP and direct JSON callers.
- 2026-08-13: Router templates may declare `read_procedure`; authorized reads
  send the concrete URI as the first WAMP positional argument and decoded
  variables as keyword arguments. Procedure-backed templates are excluded
  from direct and Streamable catalogs, reads, and notifications when the route
  principal lacks call permission.
- 2026-08-13: Core, native router, direct JSON, compatibility Streamable HTTP,
  authorization-filtering, and Router Image contract regressions pass. The
  pinned official SDK smoke now reads one concrete template URI on each public
  and protected legacy and modern client while exposing bounded booleans and
  counts only.
- 2026-08-13: Post-change `bin/test-fast` and full `bin/verify` pass. The final
  matrix includes 114 Rust core, 52 Rust FFI, 360 Dart core, 106 MCP, 280
  client/MCP, 97 benchmark, 37 live WAMP workload, 439 router, six remote-auth,
  and 13 native follow-up tests plus every maintained consumer and Chrome
  Dart2Wasm smoke. Formatting changes zero files.
- 2026-08-13: Clean strict release-ready dry-runs validate all seven
  synchronized `3.0.0-beta` package archives with zero warnings and no private
  workspace dependency blockers. Publication, exact-head hosted evidence, and
  the strict deployment-chain audit remain.
