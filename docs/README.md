# Connectanum Documentation

Use this page as the entry point for building, deploying, and operating the
Connectanum 3.x stack. The root README stays product-focused; detailed guides,
contracts, and examples live here or in the package `example/` directories.

## Start Here

- [Quick-start application](../examples/quickstart/README.md) - run a local
  router and exercise Publisher, Subscriber, Caller, and Callee from Dart.
- [Example catalog](examples.md) - progressive results, cancellation, lazy
  payloads, router startup, authentication, and MCP workflows.
- [WAMP profile support](wamp_profile_support.md) - audited Basic and Advanced
  Profile coverage, unsupported features, and readiness limits.
- [Package architecture](../STRUCTURE.md) - workspace packages and native
  runtime layout.

## Build Applications

- [Client package](../packages/connectanum_client/README.md)
- [Router package](../packages/connectanum_router/README.md)
- [MCP package](../packages/connectanum_mcp/README.md)
- [Remote auth server package](../packages/connectanum_auth_server/README.md)
- [Compatibility facade](../packages/connectanum/README.md)
- [Benchmark package](../packages/connectanum_bench/README.md)

## Deploy And Operate

- [Router deployment](deployment.md)
- [TLS and mTLS](tls.md)
- [Router authentication and credential storage](router_auth_credentials.md)
- [Remote authentication interoperability](remote_auth_interop.md)
- [Metrics and OpenMetrics](router_metrics.md)
- [HTTP bridge design](http_bridge_design.md)

## Validate And Release

- [WAMP benchmark contract](wamp_profile_benchmarks.md)
- [GitHub deployment chain](github_deployment_chain.md)
- [Dart package publishing](dart_package_publishing.md)

For API-level details, follow the package documentation and generated Dart API
reference once the modular packages are published. Implementation plans and
historical project state are maintained under `docs/exec-plans/` and
`docs/project_state.md`; application developers normally do not need them.
