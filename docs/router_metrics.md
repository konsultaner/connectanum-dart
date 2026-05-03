# Router Metrics & OpenMetrics Exporter

The router now exposes an internal metrics service that mirrors the metrics
collected by the Java implementation. The exporter is hosted from an embedded
router session and is activated automatically when the `metrics` block enables
`open_metrics`.

## Configuration

```yaml
router:
  realms:
    - name: realm1
      auth:
        authmethods: [anonymous]
      roles:
        - name: member
          permissions:
            - uri: ''
              match: prefix
              allow: [subscribe, publish, call, register, unregister]

    - name: connectanum.metrics
      auth:
        authmethods: [anonymous]
      roles:
        - name: metrics
          permissions:
            - uri: ''
              match: prefix
              allow: [register, unregister, call, subscribe, publish]

  listeners:
    - type: rawsocket
      endpoint: 127.0.0.1:0
      authmethods: [anonymous]
      options:
        max_rawsocket_size_exponent: 16
        heartbeat_interval_ms: 15000
        heartbeat_timeout_ms: 45000

  internal_realms:
    - name: connectanum.metrics
      auth_id: metrics-daemon
      auth_role: metrics
      services: [metrics]

  metrics:
    open_metrics:
      enabled: true
      listen: 127.0.0.1:9100
      path: /metrics
      realm: connectanum.metrics
      collection_timeout_ms: 5000
    backpressure:
      depth_threshold: 16
      new_events_threshold: 1
      cooldown_ms: 250
    transport_alerts:
      goaway_delta_threshold: 1
      idle_timeout_delta_threshold: 1
      body_timeout_delta_threshold: 1
      protocol_error_delta_threshold: 1
      internal_error_delta_threshold: 1
      cooldown_ms: 500
      throttle_on_alert: true
```

The router spawns an embedded session for every entry in `internal_realms`.
When the metrics exporter is enabled, the session matching
`open_metrics.realm` registers two RPC procedures:

- `connectanum.metrics.snapshot` – returns a JSON-friendly map with the current
  router counters plus per-realm topic/procedure breakdowns.
- `connectanum.metrics.openmetrics` – returns an OpenMetrics text payload using
  the same metric names as the Java router (`topics`, `topics_subscribed`,
  `topic_subscribers`, `registered_procedures`, `procedure_endpoints`, …).

If `open_metrics.listen` is set and you run the router via
`dart run connectanum_router` (or call `RouterBinding.startOpenMetricsHttpServer`
from embedding code), the exporter is also served over HTTP:

- `GET /metrics` – OpenMetrics text payload
- `GET /healthz` – readiness check (`200 ok`, `503 draining` during graceful shutdown)

If `open_metrics.auth_token` is set, `GET /metrics` requires
`Authorization: Bearer <token>`.

`open_metrics.collection_timeout_ms` bounds the full scrape collection path
(router snapshot plus per-realm details). The default is `5000`; if collection
does not complete before the timeout, the HTTP endpoint returns `503` and the
internal `connectanum.metrics.openmetrics` RPC responds with a WAMP runtime
error instead of leaving the scrape pending indefinitely.

The OpenMetrics payload also exports drain/readiness counters:

- `connectanum_router_drain_in_progress`
- `connectanum_router_drain_total`
- `connectanum_router_drain_timeouts_total`
- `connectanum_router_listeners_closed_total`
- `connectanum_router_pending_connections_closed_total`

Process health gauges are included on the same scrape:

- `connectanum_router_process_info{pid}` – static process identity for the
  router VM process.
- `connectanum_router_process_resident_memory_bytes` – current resident set
  size reported by the Dart VM.
- `connectanum_router_process_max_resident_memory_bytes` – maximum resident set
  size observed by the process.

## Snapshot Payload

The snapshot response mirrors the `RouterMetricsSnapshot` structure and includes
per-realm details:

```json
{
  "router": {
    "timestamp": "2024-05-18T20:31:12.392Z",
    "realm_count": 2,
    "session_count": 3,
    "subscription_count": 4,
    "registration_count": 2,
    "pending_invocation_count": 0,
    "total_invocations_dispatched": 12,
    "total_publications_routed": 28,
    "active_connections": 1,
    "worker_count": 2,
    "process": {
      "pid": 12345,
      "current_rss_bytes": 98566144,
      "max_rss_bytes": 98566144
    },
    "shutdown": {
      "drain_in_progress": false,
      "drain_total": 0,
      "drain_timeouts": 0,
      "closed_listeners_total": 0,
      "closed_pending_connections_total": 0
    },
    "alerts": {
      "backpressure_alerts": 0,
      "throttled_backpressure_alerts": 0
    }
  },
  "realms": [
    {
      "realm": "realm1",
      "session_count": 2,
      "topics": 3,
      "topic_subscribers": 5,
      "topic_details": [
        {
          "id": 1001,
          "topic": "com.example.topic",
          "match": "exact",
          "subscriber_count": 2
        }
      ],
      "registered_procedures": 1,
      "procedure_endpoints": 2,
      "procedure_details": [
        {
          "id": 2001,
          "procedure": "com.example.proc",
          "match": "exact",
          "policy": "round_robin",
          "callee_count": 2
        }
      ]
    }
  ],
  "alerts": {
    "backpressure": 0,
    "transport": 1,
    "goaway": 1,
    "idle_timeout": 0,
    "body_timeout": 0,
    "protocol_error": 0,
    "internal_error": 0,
    "active_throttles": 1,
    "active_throttle_listeners": [
      {
        "listener_id": 1,
        "protocol": "http2",
        "endpoint": "127.0.0.1:8080",
        "backpressure": 0,
        "transport": 1,
        "goaway": 1,
        "idle_timeout": 0,
        "body_timeout": 0,
        "protocol_error": 0,
        "internal_error": 0,
        "throttle_active": true,
        "throttle_remaining_ms": 472,
        "throttle_until": "2024-05-18T20:31:12.864Z",
        "last_alert_at": "2024-05-18T20:31:12.364Z",
        "last_alert_category": "transport",
        "last_alert_reason": "go_away",
        "last_new_events": 1,
        "last_total_events": 1
      }
    ],
    "by_listener": [
      {
        "listener_id": 1,
        "protocol": "http2",
        "endpoint": "127.0.0.1:8080",
        "backpressure": 0,
        "transport": 1,
        "goaway": 1,
        "idle_timeout": 0,
        "body_timeout": 0,
        "protocol_error": 0,
        "internal_error": 0,
        "throttle_active": true,
        "throttle_remaining_ms": 472,
        "throttle_until": "2024-05-18T20:31:12.864Z",
        "last_alert_at": "2024-05-18T20:31:12.364Z",
        "last_alert_category": "transport",
        "last_alert_reason": "go_away",
        "last_new_events": 1,
        "last_total_events": 1
      }
    ]
  },
  "exporter": {
    "realm": "connectanum.metrics",
    "path": "/metrics",
    "listen": "127.0.0.1:9100",
    "collection_timeout_ms": 5000
  }
}
```

Consumers can call the snapshot procedure directly from any session that has
permission to `call` on the metrics realm. The OpenMetrics string is designed to
feed Prometheus/Grafana stacks and applies the same label strategy as the Java
metric store (per-realm gauges plus per-topic/procedure series).

The alert snapshot is intended for consumers that need the current throttle
state, not just cumulative counters. Each per-listener entry now includes
`throttle_active`, `throttle_remaining_ms`, `throttle_until`, and the most
recent alert metadata (`last_alert_*`).

## Backpressure Alerts & Thresholds

The boss loop now emits counters for listener backpressure alerts:

- `connectanum_router_backpressure_alerts_total` – all alerts triggered by the
  boss telemetry loop.
- `connectanum_router_backpressure_alerts_throttled_total` – alerts that
  exceeded the depth threshold and temporarily throttled accepts on the
  listener.
- `connectanum_router_backpressure_alerts_by_reason_total{reason="depth_threshold|new_events_threshold|depth_and_new_events"}`
  – grouped by the cause that tripped the alert.

Alert thresholds are configurable under `metrics.backpressure`:

```yaml
metrics:
  backpressure:
    depth_threshold: 32          # throttle when max pending depth reaches this
    new_events_threshold: 4      # alert when N new backpressure events arrive
    cooldown: 500ms              # throttle window for depth-based alerts
  open_metrics:
    enabled: true
    listen: 127.0.0.1:9100
    path: /metrics
    realm: connectanum.metrics
```

The exported alert counters mirror the running totals inside the boss telemetry
loop, so dashboards/alerts can track both the frequency of alerts and the reason
they were raised. The OpenMetrics payload also exports the current throttle
state:

- `connectanum_router_throttled_listeners`
- `connectanum_router_listener_throttle_active{listener_id,protocol,endpoint}`
- `connectanum_router_listener_throttle_remaining_ms{listener_id,protocol,endpoint}`

## Prometheus & Grafana Wiring

Expose an HTTP bridge route `/metrics` that targets the
`connectanum.metrics.openmetrics` procedure, and Prometheus can scrape the
router directly:

```yaml
scrape_configs:
  - job_name: connectanum-router
    metrics_path: /metrics
    scheme: http
    static_configs:
      - targets: ['127.0.0.1:9100']
    # If you set `auth_token` in `open_metrics`, send it as a header:
    # authorization:
    #   type: Bearer
    #   credentials: "<token>"
```

Grafana dashboards can reuse the exported names (all prefixed with
`connectanum_router_*`). Listener/realm labels are already attached, so panels
can filter by `listener_id`, `protocol`, or `realm`. The router does no
background scraping; Prometheus drives collection by polling the endpoint.

## CI Artifacts

Long-running integration tests and benchmarks can dump OpenMetrics payloads and
router snapshots to disk when the environment variable
`CONNECTANUM_ARTIFACT_DIR` is set. Each test writes
`<name>.openmetrics` (text) and `<name>.metrics.json` into that directory so CI
pipelines can upload them for inspection when regressions occur.

The native bench harness builds on top of that by rewriting
`native/bench/artifacts/bench_results.jsonl` into
`native/bench/artifacts/bench_results.prom` and
`native/bench/artifacts/bench_results.summary.json` after every workload. The
bundled `native/bench/docker-compose.yml` uses a `node-exporter` textfile
collector to ingest the `.prom` file, while Prometheus also loads
`native/bench/connectanum_bench_artifact_alerts.yml` so transport regressions
captured by a finished run surface as alertable series without a custom import
step. For CI or local bench gating, `bin/check-bench-artifacts --summary <...>`
evaluates the transformed summary directly and writes sibling
`*.gate.json` / `*.gate.md` reports before failing on the same regression
signals. The default gate uses zero counter thresholds and no performance
budgets; `--policy <path>` can supply scenario-scoped non-zero thresholds for
explicitly accepted counters plus opt-in `throughput_mbps_min` and
`latency_p95_ms_max` budgets.

## Compatibility Notes

- The exported metric names intentionally follow the Java router so dashboards
  can be shared between implementations.
- Metrics are computed from the authoritative router state store, so every
  invocation consistently reflects the latest snapshot.
- The exporter performs work only when invoked; there is no background polling,
  keeping overhead negligible until Prometheus scrapes the endpoint.
- Process memory gauges use the Dart VM's `ProcessInfo.currentRss` and
  `ProcessInfo.maxRss` values, so they reflect the current router process and
  do not require VM-service access or background sampling.
- Alert knobs:
  - `metrics.backpressure` controls when the boss emits `listener_backpressure_alert`
    events (queue depth and new-event thresholds) and how long it throttles new
    accepts after an alert (`cooldown_ms`).
  - `metrics.transport_alerts` governs deltas for GOAWAY/timeout/error spikes,
    whether the boss should throttle after an alert, and the throttle cooldown.
  - Alert counters flow into the OpenMetrics payload under
    `connectanum_router_transport_alerts_total{reason=*}` and
    `connectanum_router_transport_alerts_by_listener_total{...}` so Prometheus
    can trigger notifications on spikes.

## Prometheus Alerting Examples

The bench stack now ships a ready-to-load rules file at
`native/bench/connectanum_router_alerts.yml`. It covers active throttles,
backpressure spikes, GOAWAY bursts, and transport errors. Adjust thresholds and
`for` windows to match your deployment defaults.

```yaml
groups:
  - name: connectanum-router-alerts
    rules:
      - alert: ConnectanumListenerThrottleActive
        expr: connectanum_router_listener_throttle_active > 0
        for: 30s
        labels:
          severity: warning
        annotations:
          summary: "Connectanum listener throttle is active"
          description: "Listener {{ $labels.listener_id }} ({{ $labels.protocol }} on {{ $labels.endpoint }}) is currently throttled by the boss alert loop."

      - alert: ConnectanumBackpressureSpike
        expr: |
          increase(connectanum_router_transport_alerts_by_listener_total{reason="backpressure"}[5m]) > 0
        labels:
          severity: warning
        annotations:
          summary: "Backpressure alerts observed on Connectanum router"
          description: "Backpressure alerts fired in the last 5m for listener {{ $labels.listener_id }} ({{ $labels.protocol }} on {{ $labels.endpoint }})."

      - alert: ConnectanumGoAwaySpike
        expr: |
          increase(connectanum_router_transport_alerts_by_listener_total{reason="go_away"}[5m]) > 0
        labels:
          severity: critical
        annotations:
          summary: "GOAWAY spikes on listener {{ $labels.listener_id }} ({{ $labels.endpoint }})"
          description: "GOAWAY alerts fired in the last 5m for protocol {{ $labels.protocol }}."

      - alert: ConnectanumTransportErrors
        expr: |
          increase(connectanum_router_transport_alerts_by_listener_total{reason=~"protocol_error|internal_error"}[5m]) > 0
        labels:
          severity: critical
        annotations:
          summary: "Transport error alerts on listener {{ $labels.listener_id }} ({{ $labels.endpoint }})"
          description: "Protocol/internal error alerts fired in the last 5m for protocol {{ $labels.protocol }}."
```

Dashboards can chart `connectanum_router_transport_alerts_total` to show recent
spikes, `connectanum_router_transport_alerts_by_listener_total` to pinpoint the
listener/protocol involved, and the throttle gauges to show whether the boss is
currently suppressing accepts.

See `native/bench/grafana/dashboards/router_transport_alerts.json` for a
provisioned Grafana dashboard that charts per-reason alert counts, listener
breakdowns, and the current throttle state.
