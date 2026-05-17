# Connectanum Auth Server Roadmap

This roadmap tracks the standalone authentication service that complements the
Connectanum router. The goal is full interoperability between Dart and Java
implementations (Connectanum Core / Connectanum Authentication), optional
administrative tooling, and flexible storage backends.

---

## Guiding Principles

1. **Protocol parity** – the Dart auth server must interoperate with
   `connectanum_core` (Dart) and the Java `connectanum-authentication` module.
   Any protocol divergence in the Java stack should be fixed upstream rather
   than introducing Dart-specific behaviour.
2. **Config reuse** – router and auth server should be able to consume the same
   realm/authenticator/credential configuration artifacts (JSON/YAML/etc.).
3. **Composable transport** – remote authentication is exposed over the WAMP RPC
   contract used by `RemoteAuthenticatorDelegate`, with optional HTTP/TLS
   front-ends for UI assets and API calls.
4. **Pluggable storage** – support both static configuration files and durable
   datastores without code changes.
5. **Operational UX** – bundle an optional Flutter admin console for managing
   users, roles, and permissions.

---

## Phase 1 – Core Service Bring-up

- [ ] Reuse router configuration
  - [ ] Implement shared loader that parses `RouterSettings` JSON/YAML manifests
        so both router and auth server share the same realm/authenticator
        definitions.
  - [ ] Make realm auto-creation explicitly configurable: default `autoCreate`
        to `false`, add an allow-list for realms that may be auto-created, and
        ensure auth server realms honour that policy.
  - [ ] Document the config contract (schemas, validation, migration steps).
- [ ] RPC surface
  - [ ] Implement WAMP procedures (`auth.onhello`, `auth.onauthenticate`) with
        strict parity to the Java `connectanum-authentication` reference.
  - [ ] Create interop test harnesses (Dart router ↔ Java auth server, Java
        router ↔ Dart auth server) and resolve any protocol mismatches.
  - [ ] Add fuzz/compat tests that replay recorded auth flows from Crossbar /
        other WAMP routers.
- [x] CLI executable (`bin/auth_server.dart`)
  - [x] Argument parsing (config paths, native library override, service realm,
        internal auth identity, and deployment `--check` mode).
  - [x] Boot native router runtime + `AuthServer` WAMP procedure binding from
        router/auth service configuration, including configured listener
        security.
  - [x] Health/metrics endpoints through the shared OpenMetrics HTTP exporter.

---

## Phase 2 – Storage & Persistence

- [ ] Storage abstraction
  - [ ] Define credential repository interface (read/write users, roles,
        secrets, metadata).
  - [ ] Static config adapter (read-only for existing JSON/YAML files).
  - [ ] Pluggable backends: filesystem write-back, SQL (PostgreSQL/MySQL),
        document store (MongoDB), and in-memory (for testing).
  - [ ] Support transactional updates for CRA and custom authenticators.
- [ ] Sync with Java implementation
  - [ ] Review `connectanum-authentication` storage expectations and ensure
        shared behaviour (e.g., password hashing, salt generation, audit hooks).
  - [ ] Contribute fixes upstream if protocol/format mismatches appear.

---

## Phase 3 – HTTP Serving & Flutter Admin Console

- [ ] Router HTTP extension
  - [ ] Extend `connectanum_router` to serve static assets + REST APIs alongside
        WAMP transports (graceful shutdown, compression, TLS).
  - [ ] Add middleware for authentication/authorization for management APIs.
- [ ] Flutter admin app (new sibling package)
  - [ ] Manage realms, authenticators, roles, users, credential lifecycle.
  - [ ] Real-time status dashboards (active sessions, audit logs).
  - [ ] Support offline-first mode when running against static config (change
        queue that writes back to file).
- [ ] Bundle Flutter assets with the auth server CLI (opt-in flag).

---

## Phase 4 – Operational & Security Enhancements

- [ ] Observability
  - [ ] Structured logging, metrics export (Prometheus/OpenTelemetry), tracing.
  - [ ] Failure analytics (rate limiting, lockouts, anomaly detection hooks).
- [ ] Deployment tooling
  - [ ] Docker images, Helm charts, systemd units.
  - [ ] Blue/green and canary deployment support (config hot-reload, draining).
- [ ] Security hardening
  - [ ] Secrets management integration (HashiCorp Vault, AWS Secrets Manager).
  - [ ] Key rotation for CRA/ticket/cryptosign secrets.
  - [ ] Mutual TLS & token-based router authentication, audit trails.

---

## Stretch Goals

- [ ] Clustering and replication for HA auth services.
- [ ] WebAuthn / OAuth2 delegation support for modern identity providers.
- [ ] Self-service portals (delegated user management, password resets).
- [ ] Agent integrations (MCP server, AI operator tooling).

---

## References & Dependencies

- `../../connectanum_core` – client/router shared models and serializers.
- `../connectanum_router` – router runtime, authenticator registry, config
  builders.
- `../../connectanum_authentication` (Java) – canonical auth-server behaviour.
- WAMP Advanced Profile specifications and Crossbar compatibility suite.

> Update this roadmap as features land or priorities shift. Each phase should
> produce a working milestone that can be published or adopted independently.
