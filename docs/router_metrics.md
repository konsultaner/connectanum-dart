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
```

The router spawns an embedded session for every entry in `internal_realms`.
When the metrics exporter is enabled, the session matching
`open_metrics.realm` registers two RPC procedures:

- `connectanum.metrics.snapshot` – returns a JSON-friendly map with the current
  router counters plus per-realm topic/procedure breakdowns.
- `connectanum.metrics.openmetrics` – returns an OpenMetrics text payload using
  the same metric names as the Java router (`topics`, `topics_subscribed`,
  `topic_subscribers`, `registered_procedures`, `procedure_endpoints`, …).

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
