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
- `GET /healthz` – 200 OK health check

If `open_metrics.auth_token` is set, `GET /metrics` requires
`Authorization: Bearer <token>`.

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
    "worker_count": 2
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
    "by_listener": [
      {
        "listener_id": 1,
        "protocol": "http2",
        "endpoint": "127.0.0.1:8080",
        "backpressure": 0,
        "goaway": 1,
        "idle_timeout": 0,
        "body_timeout": 0,
        "protocol_error": 0,
        "internal_error": 0
      }
    ]
  },
  "exporter": {
    "realm": "connectanum.metrics",
    "path": "/metrics",
    "listen": "127.0.0.1:9100"
  }
}
```

Consumers can call the snapshot procedure directly from any session that has
permission to `call` on the metrics realm. The OpenMetrics string is designed to
feed Prometheus/Grafana stacks and applies the same label strategy as the Java
metric store (per-realm gauges plus per-topic/procedure series).

## Compatibility Notes

- The exported metric names intentionally follow the Java router so dashboards
  can be shared between implementations.
- Metrics are computed from the authoritative router state store, so every
  invocation consistently reflects the latest snapshot.
- The exporter performs work only when invoked; there is no background polling,
  keeping overhead negligible until Prometheus scrapes the endpoint.
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

You can drop the following rules into a Prometheus rules file to alert on
transport/backpressure spikes. Adjust thresholds to match your deployment
defaults:

```yaml
groups:
  - name: connectanum-router-alerts
    rules:
      - alert: ConnectanumBackpressureSpike
        expr: |
          increase(connectanum_router_transport_alerts_total{reason="backpressure"}[5m]) > 0
        labels:
          severity: warning
        annotations:
          summary: "Backpressure alerts observed on Connectanum router"
          description: "Backpressure alerts fired in the last 5m; check listener throttle/queue depth."

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
spikes, and `connectanum_router_transport_alerts_by_listener_total` to pinpoint
the listener/protocol involved.

See `docs/grafana_transport_alerts_dashboard.json` for a starter Grafana
dashboard that charts per-reason alert counts, listener breakdowns, and a
table you can extend with throttle info from the snapshot JSON (`alerts.by_listener[*].throttle_until`).
