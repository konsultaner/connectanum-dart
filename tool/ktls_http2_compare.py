#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


RESOURCE_USAGE_KEYS = {
    "user_seconds": "User time (seconds)",
    "system_seconds": "System time (seconds)",
    "cpu_percent": "Percent of CPU this job got",
    "elapsed_seconds": "Elapsed (wall clock) time (h:mm:ss or m:ss)",
    "max_rss_kib": "Maximum resident set size (kbytes)",
}

TLS_STAT_SESSION_OPEN_KEYS = (
    ("TlsTxSw", "Software TX opens"),
    ("TlsRxSw", "Software RX opens"),
    ("TlsTxDevice", "Device TX opens"),
    ("TlsRxDevice", "Device RX opens"),
)

TLS_STAT_ERROR_KEYS = (
    ("TlsDecryptError", "Decrypt errors"),
    ("TlsDecryptRetry", "Decrypt retries"),
    ("TlsRxNoPadViolation", "RX no-pad violations"),
    ("TlsTxRekeyOk", "TX rekeys OK"),
    ("TlsRxRekeyOk", "RX rekeys OK"),
    ("TlsTxRekeyError", "TX rekey errors"),
    ("TlsRxRekeyError", "RX rekey errors"),
    ("TlsRxRekeyReceived", "RX KeyUpdate received"),
)

TLS_STAT_SUMMARY_KEYS = (
    *TLS_STAT_SESSION_OPEN_KEYS,
    *TLS_STAT_ERROR_KEYS,
)

TRANSPORT_EVENT_TOTAL_KEYS = (
    "goaway_events",
    "idle_timeout_events",
    "body_timeout_events",
    "protocol_error_events",
    "internal_error_events",
)

TRANSPORT_SUMMARY_KEYS = (
    ("backpressure_events", "Backpressure events"),
    ("backpressure_alerts", "Backpressure alerts"),
    ("transport_events_total", "Transport events"),
    ("transport_alerts", "Transport alerts"),
    ("max_backpressure_depth_after", "Max backpressure depth after"),
    ("active_throttles_after", "Active throttles after"),
)

CONNECTION_USAGE_SUMMARY_KEYS = (
    ("connections_opened", "Connections opened"),
    ("samples_per_connection_avg", "Samples per opened connection"),
)

PHASE_TIMING_SUMMARY_KEYS = (
    ("stream_acquire_wait_avg_ms", "Stream acquire wait avg"),
    ("stream_acquire_wait_p95_ms", "Stream acquire wait p95"),
    ("request_enqueue_avg_ms", "Request enqueue avg"),
    ("request_enqueue_p95_ms", "Request enqueue p95"),
    ("response_headers_wait_avg_ms", "Response headers wait avg"),
    ("response_headers_wait_p95_ms", "Response headers wait p95"),
    (
        "response_headers_connection_read_wait_samples_total",
        "Response headers connection read samples",
    ),
    (
        "response_headers_connection_read_wait_avg_ms",
        "Response headers connection read wait avg",
    ),
    (
        "response_headers_connection_read_wait_p95_ms",
        "Response headers connection read wait p95",
    ),
    (
        "response_headers_connection_read_to_headers_samples_total",
        "Response headers connection read-to-headers samples",
    ),
    (
        "response_headers_connection_read_to_headers_avg_ms",
        "Response headers connection read-to-headers avg",
    ),
    (
        "response_headers_connection_read_to_headers_p95_ms",
        "Response headers connection read-to-headers p95",
    ),
    (
        "response_headers_connection_write_wait_samples_total",
        "Response headers connection write samples",
    ),
    (
        "response_headers_connection_write_wait_avg_ms",
        "Response headers connection write wait avg",
    ),
    (
        "response_headers_connection_write_wait_p95_ms",
        "Response headers connection write wait p95",
    ),
    (
        "response_headers_connection_write_span_samples_total",
        "Response headers connection write-span samples",
    ),
    (
        "response_headers_connection_write_span_avg_ms",
        "Response headers connection write span avg",
    ),
    (
        "response_headers_connection_write_span_p95_ms",
        "Response headers connection write span p95",
    ),
    ("response_body_read_avg_ms", "Response body read avg"),
    ("response_body_read_p95_ms", "Response body read p95"),
    ("response_body_first_chunk_wait_avg_ms", "Response body first chunk wait avg"),
    ("response_body_first_chunk_wait_p95_ms", "Response body first chunk wait p95"),
    ("response_body_tail_read_avg_ms", "Response body tail read avg"),
    ("response_body_tail_read_p95_ms", "Response body tail read p95"),
    ("response_body_chunk_count_avg", "Response body chunks avg"),
    ("response_body_chunk_count_p95", "Response body chunks p95"),
    ("response_body_first_chunk_bytes_avg", "Response body first chunk bytes avg"),
    ("response_body_first_chunk_bytes_p95", "Response body first chunk bytes p95"),
    (
        "response_body_post_header_connection_read_wait_samples_total",
        "Response body post-header connection read samples",
    ),
    (
        "response_body_post_header_connection_read_wait_avg_ms",
        "Response body post-header connection read wait avg",
    ),
    (
        "response_body_post_header_connection_read_wait_p95_ms",
        "Response body post-header connection read wait p95",
    ),
    (
        "response_body_connection_read_to_first_chunk_samples_total",
        "Response body connection read-to-first-chunk samples",
    ),
    (
        "response_body_connection_read_to_first_chunk_avg_ms",
        "Response body connection read-to-first-chunk avg",
    ),
    (
        "response_body_connection_read_to_first_chunk_p95_ms",
        "Response body connection read-to-first-chunk p95",
    ),
    ("request_round_trip_avg_ms", "Request round trip avg"),
    ("request_round_trip_p95_ms", "Request round trip p95"),
)

SERVER_EMISSION_SUMMARY_KEYS = (
    ("request_body_drain_avg_ms", "Server request body drain avg"),
    ("stream_open_avg_ms", "Server stream open avg"),
    ("first_chunk_queued_avg_ms", "Server first chunk queued avg"),
    ("first_body_write_avg_ms", "Server first body write avg"),
    ("first_body_write_completed_avg_ms", "Server first body write completed avg"),
    (
        "headers_to_first_body_write_avg_ms",
        "Server headers-to-first-body-write avg",
    ),
    (
        "headers_to_first_body_write_completed_avg_ms",
        "Server headers-to-first-body-write-completed avg",
    ),
    (
        "queue_to_first_body_write_avg_ms",
        "Server queue-to-first-body-write avg",
    ),
    (
        "queue_to_first_body_write_completed_avg_ms",
        "Server queue-to-first-body-write-completed avg",
    ),
    ("first_body_write_call_avg_ms", "Server first body write call avg"),
    (
        "direct_stream_open_round_trip_avg_ms",
        "Server direct-stream open round trip avg",
    ),
    (
        "direct_stream_request_queue_delay_avg_ms",
        "Server direct-stream request queue delay avg",
    ),
    (
        "direct_stream_descriptor_open_call_avg_ms",
        "Server direct-stream descriptor-open call avg",
    ),
    (
        "direct_stream_reply_delivery_delay_avg_ms",
        "Server direct-stream reply delivery delay avg",
    ),
    ("handler_avg_ms", "Server handler avg"),
)

NATIVE_RESPONSE_STREAM_SUMMARY_KEYS = (
    (
        "stream_open_to_headers_send_avg_ms",
        "Native stream-open-to-headers-send avg",
    ),
    ("headers_send_call_avg_ms", "Native headers send call avg"),
    (
        "headers_to_first_connection_write_avg_ms",
        "Native headers-to-first-connection-write avg",
    ),
    ("first_chunk_channel_wait_avg_ms", "Native first chunk channel wait avg"),
    (
        "headers_to_first_chunk_dequeue_avg_ms",
        "Native headers-to-first-chunk-dequeue avg",
    ),
    ("first_chunk_send_call_avg_ms", "Native first chunk send call avg"),
    (
        "headers_to_first_chunk_send_call_avg_ms",
        "Native headers-to-first-chunk-send-call avg",
    ),
)

NATIVE_RESPONSE_STREAM_SLOW_PATH_KEYS = (
    (
        "headers_to_first_connection_write",
        "Native headers-to-first-connection-write",
    ),
    ("first_chunk_channel_wait", "Native first chunk channel wait"),
    (
        "headers_to_first_chunk_dequeue",
        "Native headers-to-first-chunk-dequeue",
    ),
    ("first_chunk_send_call", "Native first chunk send call"),
)

NATIVE_RESPONSE_STREAM_SLOW_PATH_BUCKET_KEYS = (
    "ge_1ms_total",
    "ge_5ms_total",
    "ge_10ms_total",
)


def load_summary(path: Path) -> dict:
    if not path.exists():
        return {"workloads": []}
    return json.loads(path.read_text())


def workload_key(entry: dict) -> tuple:
    return (
        entry["scenario"],
        entry["workload"],
        entry["protocol"],
        entry.get("client_impl", "n/a"),
        entry["router_workers"],
        entry["native_runtime_threads"],
    )


def pct_delta(base: float, current: float) -> float | None:
    if base == 0:
        return None
    return ((current - base) / base) * 100.0


def parse_elapsed_seconds(value: str) -> float | None:
    text = value.strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        pass

    parts = text.split(":")
    try:
        if len(parts) == 2:
            minutes, seconds = parts
            return float(minutes) * 60.0 + float(seconds)
        if len(parts) == 3:
            hours, minutes, seconds = parts
            return float(hours) * 3600.0 + float(minutes) * 60.0 + float(seconds)
    except ValueError:
        return None
    return None


def parse_resource_usage(path: Path) -> dict | None:
    if not path.exists():
        return None

    fields: dict[str, float] = {}
    for line in path.read_text().splitlines():
        normalized_line = line.lstrip()
        for field_name, expected_label in RESOURCE_USAGE_KEYS.items():
            prefix = f"{expected_label}:"
            if not normalized_line.startswith(prefix):
                continue
            value = normalized_line[len(prefix) :].strip()
            if field_name == "cpu_percent":
                normalized = value.rstrip("%").strip()
                try:
                    fields[field_name] = float(normalized)
                except ValueError:
                    pass
            elif field_name == "elapsed_seconds":
                parsed = parse_elapsed_seconds(value)
                if parsed is not None:
                    fields[field_name] = parsed
            else:
                try:
                    fields[field_name] = float(value)
                except ValueError:
                    pass
            break

    if not fields:
        return None

    fields["source"] = str(path)
    fields["cpu_total_seconds"] = fields.get("user_seconds", 0.0) + fields.get(
        "system_seconds", 0.0
    )
    return fields


def parse_tls_stat(path: Path) -> dict | None:
    if not path.exists():
        return None

    values: dict[str, int] = {}
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if "=" in stripped and " " not in stripped:
            continue

        parts = stripped.split()
        if len(parts) != 2:
            continue

        name, value = parts
        try:
            values[name] = int(value)
        except ValueError:
            continue

    if not values:
        return None

    return values


def build_label(row: dict) -> str:
    return (
        f"{row['workload']} "
        f"(workers={row['router_workers']}, "
        f"threads={row['native_runtime_threads']})"
    )


def build_metric_summary(rows: list[dict], metric: str) -> dict | None:
    comparable = [row for row in rows if row["delta"] is not None]
    if not comparable:
        return None

    if metric == "throughput_pct":
        ktls_wins = [row for row in comparable if (row["delta"][metric] or 0) > 0]
        baseline_wins = [
            row for row in comparable if (row["delta"][metric] or 0) < 0
        ]
        ties = [row for row in comparable if (row["delta"][metric] or 0) == 0]
        best_row = max(comparable, key=lambda row: row["delta"][metric] or 0)
        worst_row = min(comparable, key=lambda row: row["delta"][metric] or 0)
    else:
        ktls_wins = [row for row in comparable if (row["delta"][metric] or 0) < 0]
        baseline_wins = [
            row for row in comparable if (row["delta"][metric] or 0) > 0
        ]
        ties = [row for row in comparable if (row["delta"][metric] or 0) == 0]
        best_row = min(comparable, key=lambda row: row["delta"][metric] or 0)
        worst_row = max(comparable, key=lambda row: row["delta"][metric] or 0)

    deltas = [
        row["delta"][metric]
        for row in comparable
        if row["delta"][metric] is not None
    ]
    average_delta = sum(deltas) / len(deltas) if deltas else None

    def pack_row(row: dict) -> dict:
        return {
            "label": build_label(row),
            "scenario": row["scenario"],
            "workload": row["workload"],
            "protocol": row["protocol"],
            "client_impl": row["client_impl"],
            "router_workers": row["router_workers"],
            "native_runtime_threads": row["native_runtime_threads"],
            "delta_pct": row["delta"][metric],
        }

    return {
        "ktls_wins": len(ktls_wins),
        "baseline_wins": len(baseline_wins),
        "ties": len(ties),
        "average_pct_delta": average_delta,
        "best_row": pack_row(best_row),
        "worst_row": pack_row(worst_row),
    }


def group_severity_score(
    throughput_summary: dict | None, latency_summary: dict | None
) -> float:
    throughput_penalty = 0.0
    latency_penalty = 0.0

    if throughput_summary is not None:
        average_throughput_delta = throughput_summary.get("average_pct_delta")
        if average_throughput_delta is not None:
            throughput_penalty = max(0.0, -average_throughput_delta)

    if latency_summary is not None:
        average_latency_delta = latency_summary.get("average_pct_delta")
        if average_latency_delta is not None:
            latency_penalty = max(0.0, average_latency_delta)

    return throughput_penalty + latency_penalty


def build_group_summaries(
    rows: list[dict],
    group_key: str,
    group_value_for_row,
    group_label_for_row,
) -> list[dict]:
    buckets: dict[object, dict] = {}
    for row in rows:
        if not row["baseline"] or not row["ktls"] or not row["delta"]:
            continue
        group_value = group_value_for_row(row)
        bucket = buckets.setdefault(
            group_value,
            {
                "group_value": group_value,
                "label": group_label_for_row(row),
                "rows": [],
            },
        )
        bucket["rows"].append(row)

    groups = []
    for bucket in buckets.values():
        throughput = build_metric_summary(bucket["rows"], "throughput_pct")
        latency_p95 = build_metric_summary(bucket["rows"], "latency_p95_pct")
        groups.append(
            {
                "group_key": group_key,
                "group_value": bucket["group_value"],
                "label": bucket["label"],
                "comparable_rows": len(bucket["rows"]),
                "throughput": throughput,
                "latency_p95": latency_p95,
                "severity_score": group_severity_score(throughput, latency_p95),
            }
        )

    groups.sort(key=lambda group: (-group["severity_score"], str(group["label"])))
    return groups


def select_hotspot_group(groups: list[dict]) -> dict | None:
    if not groups:
        return None
    return groups[0]


def build_resource_usage_summary(baseline: dict | None, ktls: dict | None) -> dict | None:
    if baseline is None and ktls is None:
        return None

    summary = {
        "baseline": baseline,
        "ktls": ktls,
    }
    if baseline is None or ktls is None:
        summary["delta"] = None
        return summary

    delta: dict[str, float | None] = {}
    for metric in (
        "cpu_total_seconds",
        "user_seconds",
        "system_seconds",
        "elapsed_seconds",
        "cpu_percent",
        "max_rss_kib",
    ):
        base_value = baseline.get(metric)
        ktls_value = ktls.get(metric)
        if base_value is None or ktls_value is None:
            delta[metric] = None
            delta[f"{metric}_pct"] = None
            continue
        delta[metric] = ktls_value - base_value
        delta[f"{metric}_pct"] = pct_delta(base_value, ktls_value)

    summary["delta"] = delta
    return summary


def build_tls_stat_pass_summary(before: dict | None, after: dict | None) -> dict | None:
    if before is None and after is None:
        return None

    summary = {
        "before": before,
        "after": after,
    }
    if before is None or after is None:
        summary["delta"] = None
        return summary

    keys = sorted(set(before) | set(after))
    summary["delta"] = {key: after.get(key, 0) - before.get(key, 0) for key in keys}
    return summary


def build_tls_stat_metric_snapshot(
    baseline_pass: dict | None, ktls_pass: dict | None, metric: str
) -> dict | None:
    baseline_delta = None
    if baseline_pass is not None and baseline_pass.get("delta") is not None:
        baseline_delta = baseline_pass["delta"].get(metric, 0)

    ktls_delta = None
    if ktls_pass is not None and ktls_pass.get("delta") is not None:
        ktls_delta = ktls_pass["delta"].get(metric, 0)

    if baseline_delta is None and ktls_delta is None:
        return None

    return {
        "baseline_delta": baseline_delta,
        "ktls_delta": ktls_delta,
        "delta": None
        if baseline_delta is None or ktls_delta is None
        else ktls_delta - baseline_delta,
    }


def build_tls_stat_summary(
    baseline_pass: dict | None, ktls_pass: dict | None
) -> dict | None:
    if baseline_pass is None and ktls_pass is None:
        return None

    metrics: dict[str, dict | None] = {}
    signals: list[dict] = []
    for metric, label in TLS_STAT_SUMMARY_KEYS:
        snapshot = build_tls_stat_metric_snapshot(baseline_pass, ktls_pass, metric)
        metrics[metric] = snapshot
        if snapshot is None:
            continue
        baseline_delta = snapshot["baseline_delta"] or 0
        ktls_delta = snapshot["ktls_delta"] or 0
        if baseline_delta == 0 and ktls_delta == 0:
            continue
        signals.append(
            {
                "metric": metric,
                "label": label,
                "baseline_delta": snapshot["baseline_delta"],
                "ktls_delta": snapshot["ktls_delta"],
                "delta": snapshot["delta"],
            }
        )

    return {
        "baseline": baseline_pass,
        "ktls": ktls_pass,
        "metrics": metrics,
        "signals": signals,
    }


def build_transport_metric_snapshot(
    baseline_transport: dict, ktls_transport: dict, metric: str
) -> dict | None:
    if metric == "transport_events_total":
        baseline_value = sum(
            int(baseline_transport.get(key, 0)) for key in TRANSPORT_EVENT_TOTAL_KEYS
        )
        ktls_value = sum(
            int(ktls_transport.get(key, 0)) for key in TRANSPORT_EVENT_TOTAL_KEYS
        )
    else:
        baseline_value = baseline_transport.get(metric)
        ktls_value = ktls_transport.get(metric)

    if baseline_value is None or ktls_value is None:
        return None

    return {
        "baseline": baseline_value,
        "ktls": ktls_value,
        "delta": ktls_value - baseline_value,
    }


def summarize_row_transport(row: dict) -> dict | None:
    baseline = row.get("baseline")
    ktls = row.get("ktls")
    if not baseline or not ktls:
        return None

    baseline_transport = baseline.get("transport") or {}
    ktls_transport = ktls.get("transport") or {}

    metrics: dict[str, dict | None] = {}
    signals: list[dict] = []
    for metric, label in TRANSPORT_SUMMARY_KEYS:
        snapshot = build_transport_metric_snapshot(
            baseline_transport, ktls_transport, metric
        )
        metrics[metric] = snapshot
        if snapshot is None:
            continue
        if snapshot["baseline"] == 0 and snapshot["ktls"] == 0:
            continue
        signals.append(
            {
                "metric": metric,
                "label": label,
                "baseline": snapshot["baseline"],
                "ktls": snapshot["ktls"],
                "delta": snapshot["delta"],
            }
        )

    return {
        "metrics": metrics,
        "signals": signals,
    }


def find_matching_row(rows: list[dict], packed_row: dict | None) -> dict | None:
    if packed_row is None:
        return None

    for row in rows:
        if (
            row["scenario"] == packed_row["scenario"]
            and row["workload"] == packed_row["workload"]
            and row["protocol"] == packed_row["protocol"]
            and row["client_impl"] == packed_row["client_impl"]
            and row["router_workers"] == packed_row["router_workers"]
            and row["native_runtime_threads"] == packed_row["native_runtime_threads"]
        ):
            return row
    return None


def build_transport_focus(rows: list[dict], packed_row: dict | None) -> dict | None:
    row = find_matching_row(rows, packed_row)
    if row is None:
        return None

    transport = row.get("transport_summary")
    if transport is None:
        return None

    return {
        "label": build_label(row),
        "signals": transport["signals"],
        "metrics": transport["metrics"],
    }


def build_connection_metric_snapshot(
    baseline_usage: dict | None, ktls_usage: dict | None, metric: str
) -> dict | None:
    baseline_value = None if baseline_usage is None else baseline_usage.get(metric)
    ktls_value = None if ktls_usage is None else ktls_usage.get(metric)
    if baseline_value is None and ktls_value is None:
        return None

    delta = None
    delta_pct = None
    if baseline_value is not None and ktls_value is not None:
        delta = ktls_value - baseline_value
        if isinstance(baseline_value, (int, float)) and isinstance(ktls_value, (int, float)):
            delta_pct = pct_delta(float(baseline_value), float(ktls_value))

    return {
        "baseline": baseline_value,
        "ktls": ktls_value,
        "delta": delta,
        "delta_pct": delta_pct,
    }


def summarize_row_connection_usage(row: dict) -> dict | None:
    baseline = row.get("baseline")
    ktls = row.get("ktls")
    if not baseline or not ktls:
        return None

    baseline_usage = baseline.get("http_connection_usage")
    ktls_usage = ktls.get("http_connection_usage")
    if baseline_usage is None and ktls_usage is None:
        return None

    config = {
        "reuse_connections": {
            "baseline": None
            if baseline_usage is None
            else baseline_usage.get("reuse_connections"),
            "ktls": None if ktls_usage is None else ktls_usage.get("reuse_connections"),
        },
        "streams_per_connection": {
            "baseline": None
            if baseline_usage is None
            else baseline_usage.get("streams_per_connection"),
            "ktls": None if ktls_usage is None else ktls_usage.get("streams_per_connection"),
        },
    }

    metrics: dict[str, dict | None] = {}
    signals: list[dict] = []
    for metric, label in CONNECTION_USAGE_SUMMARY_KEYS:
        snapshot = build_connection_metric_snapshot(baseline_usage, ktls_usage, metric)
        metrics[metric] = snapshot
        if snapshot is None or snapshot["delta"] in (None, 0, 0.0):
            continue
        signals.append(
            {
                "metric": metric,
                "label": label,
                "baseline": snapshot["baseline"],
                "ktls": snapshot["ktls"],
                "delta": snapshot["delta"],
                "delta_pct": snapshot["delta_pct"],
            }
        )

    return {
        "config": config,
        "metrics": metrics,
        "signals": signals,
    }


def build_connection_focus(rows: list[dict], packed_row: dict | None) -> dict | None:
    row = find_matching_row(rows, packed_row)
    if row is None:
        return None

    connection_usage = row.get("connection_usage_summary")
    if connection_usage is None:
        return None

    return {
        "label": build_label(row),
        "config": connection_usage["config"],
        "metrics": connection_usage["metrics"],
        "signals": connection_usage["signals"],
    }


def build_phase_timing_metric_snapshot(
    baseline_timing: dict | None, ktls_timing: dict | None, metric: str
) -> dict | None:
    baseline_value = None if baseline_timing is None else baseline_timing.get(metric)
    ktls_value = None if ktls_timing is None else ktls_timing.get(metric)
    if baseline_value is None and ktls_value is None:
        return None

    delta = None
    delta_pct = None
    if baseline_value is not None and ktls_value is not None:
        delta = ktls_value - baseline_value
        delta_pct = pct_delta(float(baseline_value), float(ktls_value))

    return {
        "baseline": baseline_value,
        "ktls": ktls_value,
        "delta": delta,
        "delta_pct": delta_pct,
    }


def summarize_row_phase_timing(row: dict) -> dict | None:
    baseline = row.get("baseline")
    ktls = row.get("ktls")
    if not baseline or not ktls:
        return None

    baseline_timing = baseline.get("http_phase_timing")
    ktls_timing = ktls.get("http_phase_timing")
    if baseline_timing is None and ktls_timing is None:
        return None

    metrics: dict[str, dict | None] = {}
    signals: list[dict] = []
    for metric, label in PHASE_TIMING_SUMMARY_KEYS:
        snapshot = build_phase_timing_metric_snapshot(
            baseline_timing, ktls_timing, metric
        )
        metrics[metric] = snapshot
        if snapshot is None or snapshot["delta"] in (None, 0, 0.0):
            continue
        signals.append(
            {
                "metric": metric,
                "label": label,
                "baseline": snapshot["baseline"],
                "ktls": snapshot["ktls"],
                "delta": snapshot["delta"],
                "delta_pct": snapshot["delta_pct"],
            }
        )

    return {"metrics": metrics, "signals": signals}


def build_phase_timing_focus(rows: list[dict], packed_row: dict | None) -> dict | None:
    row = find_matching_row(rows, packed_row)
    if row is None:
        return None

    phase_timing = row.get("phase_timing_summary")
    if phase_timing is None:
        return None

    return {
        "label": build_label(row),
        "metrics": phase_timing["metrics"],
        "signals": phase_timing["signals"],
    }


def summarize_row_server_emission_timing(row: dict) -> dict | None:
    baseline = row.get("baseline")
    ktls = row.get("ktls")
    if not baseline or not ktls:
        return None

    baseline_timing = baseline.get("http_server_emission_timing")
    ktls_timing = ktls.get("http_server_emission_timing")
    if baseline_timing is None and ktls_timing is None:
        return None

    counts = {
        "requests_total": build_connection_metric_snapshot(
            baseline_timing, ktls_timing, "requests_total"
        ),
        "synthetic_responses_total": build_connection_metric_snapshot(
            baseline_timing, ktls_timing, "synthetic_responses_total"
        ),
        "native_forwarded_responses_total": build_connection_metric_snapshot(
            baseline_timing, ktls_timing, "native_forwarded_responses_total"
        ),
        "buffered_responses_total": build_connection_metric_snapshot(
            baseline_timing, ktls_timing, "buffered_responses_total"
        ),
    }

    metrics: dict[str, dict | None] = {}
    signals: list[dict] = []
    for metric, label in SERVER_EMISSION_SUMMARY_KEYS:
        snapshot = build_phase_timing_metric_snapshot(
            baseline_timing, ktls_timing, metric
        )
        metrics[metric] = snapshot
        if snapshot is None or snapshot["delta"] in (None, 0, 0.0):
            continue
        signals.append(
            {
                "metric": metric,
                "label": label,
                "baseline": snapshot["baseline"],
                "ktls": snapshot["ktls"],
                "delta": snapshot["delta"],
                "delta_pct": snapshot["delta_pct"],
            }
        )

    return {"counts": counts, "metrics": metrics, "signals": signals}


def build_server_emission_focus(rows: list[dict], packed_row: dict | None) -> dict | None:
    row = find_matching_row(rows, packed_row)
    if row is None:
        return None

    server_emission = row.get("server_emission_summary")
    if server_emission is None:
        return None

    return {
        "label": build_label(row),
        "counts": server_emission["counts"],
        "metrics": server_emission["metrics"],
        "signals": server_emission["signals"],
    }


def summarize_row_native_response_stream_timing(row: dict) -> dict | None:
    baseline = row.get("baseline")
    ktls = row.get("ktls")
    if not baseline or not ktls:
        return None

    baseline_timing = baseline.get("http_native_response_stream_timing")
    ktls_timing = ktls.get("http_native_response_stream_timing")
    if baseline_timing is None and ktls_timing is None:
        return None

    counts = {
        "streaming_responses_total": build_connection_metric_snapshot(
            baseline_timing, ktls_timing, "streaming_responses_total"
        ),
    }

    metrics: dict[str, dict | None] = {}
    signals: list[dict] = []
    for metric, label in NATIVE_RESPONSE_STREAM_SUMMARY_KEYS:
        snapshot = build_phase_timing_metric_snapshot(
            baseline_timing, ktls_timing, metric
        )
        metrics[metric] = snapshot
        if snapshot is None or snapshot["delta"] in (None, 0, 0.0):
            continue
        signals.append(
            {
                "metric": metric,
                "label": label,
                "baseline": snapshot["baseline"],
                "ktls": snapshot["ktls"],
                "delta": snapshot["delta"],
                "delta_pct": snapshot["delta_pct"],
            }
        )

    return {"counts": counts, "metrics": metrics, "signals": signals}


def build_native_response_stream_focus(
    rows: list[dict], packed_row: dict | None
) -> dict | None:
    row = find_matching_row(rows, packed_row)
    if row is None:
        return None

    native_stream = row.get("native_response_stream_summary")
    if native_stream is None:
        return None

    return {
        "label": build_label(row),
        "counts": native_stream["counts"],
        "metrics": native_stream["metrics"],
        "signals": native_stream["signals"],
    }


def build_native_response_stream_slow_path_snapshot(
    baseline_timing: dict | None, ktls_timing: dict | None, prefix: str
) -> dict | None:
    snapshots: dict[str, dict | None] = {}
    for suffix in NATIVE_RESPONSE_STREAM_SLOW_PATH_BUCKET_KEYS:
        metric = f"{prefix}_{suffix}"
        snapshots[suffix] = build_connection_metric_snapshot(
            baseline_timing, ktls_timing, metric
        )

    if all(snapshot is None for snapshot in snapshots.values()):
        return None
    return snapshots


def summarize_row_native_response_stream_slow_path(row: dict) -> dict | None:
    baseline = row.get("baseline")
    ktls = row.get("ktls")
    if not baseline or not ktls:
        return None

    baseline_timing = baseline.get("http_native_response_stream_slow_path")
    ktls_timing = ktls.get("http_native_response_stream_slow_path")
    if baseline_timing is None and ktls_timing is None:
        return None

    counts = {
        "streaming_responses_total": build_connection_metric_snapshot(
            baseline_timing, ktls_timing, "streaming_responses_total"
        ),
    }
    buckets = {
        prefix: build_native_response_stream_slow_path_snapshot(
            baseline_timing, ktls_timing, prefix
        )
        for prefix, _label in NATIVE_RESPONSE_STREAM_SLOW_PATH_KEYS
    }
    return {"counts": counts, "buckets": buckets}


def build_native_response_stream_slow_path_focus(
    rows: list[dict], packed_row: dict | None
) -> dict | None:
    row = find_matching_row(rows, packed_row)
    if row is None:
        return None

    native_stream = row.get("native_response_stream_slow_path_summary")
    if native_stream is None:
        return None

    return {
        "label": build_label(row),
        "counts": native_stream["counts"],
        "buckets": native_stream["buckets"],
    }


def render_pct(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value:+.2f}%"


def render_seconds(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value:.2f}s"


def render_kib(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value / 1024.0:.2f} MiB"


def render_int(value: int | None) -> str:
    if value is None:
        return "n/a"
    return str(value)


def render_bool(value: bool | None) -> str:
    if value is None:
        return "n/a"
    return "enabled" if value else "disabled"


def render_float(value: float | int | None) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):.2f}"


def render_summary_line(name: str, summary: dict | None, comparable_rows: int) -> str:
    if summary is None:
        return f"- {name}: no overlapping completed workloads."
    return (
        f"- {name}: kTLS wins {summary['ktls_wins']}/{comparable_rows}, "
        f"baseline wins {summary['baseline_wins']}/{comparable_rows}, "
        f"ties {summary['ties']}. "
        f"Average delta {render_pct(summary['average_pct_delta'])}. "
        f"Best kTLS result: {summary['best_row']['label']} "
        f"({render_pct(summary['best_row']['delta_pct'])}). "
        f"Worst kTLS result: {summary['worst_row']['label']} "
        f"({render_pct(summary['worst_row']['delta_pct'])})."
    )


def render_group_focus_line(name: str, group: dict | None) -> str:
    if group is None:
        return f"- {name}: no overlapping completed workloads."

    throughput = group.get("throughput")
    latency = group.get("latency_p95")
    throughput_worst_row = "n/a"
    latency_worst_row = "n/a"
    if throughput is not None:
        throughput_worst_row = (
            f"{throughput['worst_row']['label']} "
            f"({render_pct(throughput['worst_row']['delta_pct'])})"
        )
    if latency is not None:
        latency_worst_row = (
            f"{latency['worst_row']['label']} "
            f"({render_pct(latency['worst_row']['delta_pct'])})"
        )

    return (
        f"- {name}: {group['label']} across {group['comparable_rows']} workloads. "
        f"Average throughput delta "
        f"{render_pct(throughput['average_pct_delta'] if throughput else None)}. "
        f"Average p95 delta "
        f"{render_pct(latency['average_pct_delta'] if latency else None)}. "
        f"Worst throughput row: {throughput_worst_row}. "
        f"Worst p95 row: {latency_worst_row}."
    )


def render_transport_snapshot(snapshot: dict | None) -> str:
    if snapshot is None:
        return "n/a"
    return f"{snapshot['baseline']} -> {snapshot['ktls']} ({snapshot['delta']:+d})"


def render_transport_focus_line(name: str, focus: dict | None) -> str:
    if focus is None:
        return f"- {name}: no overlapping completed workloads."

    signals = focus.get("signals") or []
    if not signals:
        return (
            f"- {name}: {focus['label']} shows no non-zero transport counters "
            "in either pass."
        )

    rendered_signals = "; ".join(
        f"{signal['label']} {signal['baseline']} -> {signal['ktls']} "
        f"({signal['delta']:+d})"
        for signal in signals
    )
    return f"- {name}: {focus['label']} shows {rendered_signals}."


def render_connection_config_snapshot(snapshot: dict | None, *, bool_value: bool = False) -> str:
    if snapshot is None:
        return "n/a"
    baseline = snapshot.get("baseline")
    ktls = snapshot.get("ktls")
    if bool_value:
        baseline_rendered = render_bool(baseline)
        ktls_rendered = render_bool(ktls)
    else:
        baseline_rendered = render_int(baseline)
        ktls_rendered = render_int(ktls)
    if baseline == ktls:
        return baseline_rendered
    return f"{baseline_rendered} -> {ktls_rendered}"


def render_connection_metric_snapshot(snapshot: dict | None) -> str:
    if snapshot is None:
        return "n/a"
    baseline = snapshot.get("baseline")
    ktls = snapshot.get("ktls")
    delta = snapshot.get("delta")
    if isinstance(baseline, int) and isinstance(ktls, int) and isinstance(delta, int):
        return f"{baseline} -> {ktls} ({delta:+d})"
    if isinstance(baseline, (int, float)) and isinstance(ktls, (int, float)):
        if delta is None:
            return f"{float(baseline):.2f} -> {float(ktls):.2f}"
        return f"{float(baseline):.2f} -> {float(ktls):.2f} ({float(delta):+.2f})"
    return "n/a"


def connection_metric_snapshot_has_samples(snapshot: dict | None) -> bool:
    if snapshot is None:
        return False
    baseline = snapshot.get("baseline")
    ktls = snapshot.get("ktls")
    return bool((baseline or 0) > 0 or (ktls or 0) > 0)


def render_connection_focus_line(name: str, focus: dict | None) -> str:
    if focus is None:
        return f"- {name}: no HTTP connection usage metrics were present."

    config = focus["config"]
    metrics = focus["metrics"]
    return (
        f"- {name}: {focus['label']} uses "
        f"reuse {render_connection_config_snapshot(config['reuse_connections'], bool_value=True)}, "
        f"streams per connection {render_connection_config_snapshot(config['streams_per_connection'])}, "
        f"connections opened {render_connection_metric_snapshot(metrics['connections_opened'])}, "
        f"samples per opened connection {render_connection_metric_snapshot(metrics['samples_per_connection_avg'])}."
    )


def render_phase_timing_focus_line(name: str, focus: dict | None) -> str:
    if focus is None:
        return f"- {name}: no HTTP phase timing metrics were present."

    metrics = focus["metrics"]
    rendered = (
        f"- {name}: {focus['label']} shows "
        f"stream acquire wait avg {render_connection_metric_snapshot(metrics['stream_acquire_wait_avg_ms'])}, "
        f"response headers wait avg {render_connection_metric_snapshot(metrics['response_headers_wait_avg_ms'])}, "
        f"response body first chunk wait avg {render_connection_metric_snapshot(metrics['response_body_first_chunk_wait_avg_ms'])}, "
        f"response body tail read avg {render_connection_metric_snapshot(metrics['response_body_tail_read_avg_ms'])}, "
        f"response body chunks avg {render_connection_metric_snapshot(metrics['response_body_chunk_count_avg'])}, "
        f"response body first chunk bytes avg {render_connection_metric_snapshot(metrics['response_body_first_chunk_bytes_avg'])}, "
        f"response body read avg {render_connection_metric_snapshot(metrics['response_body_read_avg_ms'])}, "
        f"request round trip p95 {render_connection_metric_snapshot(metrics['request_round_trip_p95_ms'])}"
    )
    if connection_metric_snapshot_has_samples(
        metrics["response_headers_connection_read_wait_samples_total"]
    ):
        rendered += (
            f", response-header connection read samples "
            f"{render_connection_metric_snapshot(metrics['response_headers_connection_read_wait_samples_total'])}, "
            f"response-header connection read wait avg "
            f"{render_connection_metric_snapshot(metrics['response_headers_connection_read_wait_avg_ms'])}"
        )
    if connection_metric_snapshot_has_samples(
        metrics["response_headers_connection_read_to_headers_samples_total"]
    ):
        rendered += (
            f", response-header connection read-to-headers samples "
            f"{render_connection_metric_snapshot(metrics['response_headers_connection_read_to_headers_samples_total'])}, "
            f"response-header connection read-to-headers avg "
            f"{render_connection_metric_snapshot(metrics['response_headers_connection_read_to_headers_avg_ms'])}"
        )
    if connection_metric_snapshot_has_samples(
        metrics["response_headers_connection_write_wait_samples_total"]
    ):
        rendered += (
            f", response-header connection write samples "
            f"{render_connection_metric_snapshot(metrics['response_headers_connection_write_wait_samples_total'])}, "
            f"response-header connection write wait avg "
            f"{render_connection_metric_snapshot(metrics['response_headers_connection_write_wait_avg_ms'])}"
        )
    if connection_metric_snapshot_has_samples(
        metrics["response_headers_connection_write_span_samples_total"]
    ):
        rendered += (
            f", response-header connection write-span samples "
            f"{render_connection_metric_snapshot(metrics['response_headers_connection_write_span_samples_total'])}, "
            f"response-header connection write-span avg "
            f"{render_connection_metric_snapshot(metrics['response_headers_connection_write_span_avg_ms'])}"
        )
    if connection_metric_snapshot_has_samples(
        metrics["response_body_post_header_connection_read_wait_samples_total"]
    ):
        rendered += (
            f", post-header connection read samples "
            f"{render_connection_metric_snapshot(metrics['response_body_post_header_connection_read_wait_samples_total'])}, "
            f"post-header connection read wait avg "
            f"{render_connection_metric_snapshot(metrics['response_body_post_header_connection_read_wait_avg_ms'])}"
        )
    if connection_metric_snapshot_has_samples(
        metrics["response_body_connection_read_to_first_chunk_samples_total"]
    ):
        rendered += (
            f", connection read-to-first-chunk samples "
            f"{render_connection_metric_snapshot(metrics['response_body_connection_read_to_first_chunk_samples_total'])}, "
            f"connection read-to-first-chunk avg "
            f"{render_connection_metric_snapshot(metrics['response_body_connection_read_to_first_chunk_avg_ms'])}"
        )
    return rendered + "."


def render_server_emission_focus_line(name: str, focus: dict | None) -> str:
    if focus is None:
        return f"- {name}: no HTTP server emission metrics were present."

    counts = focus["counts"]
    metrics = focus["metrics"]
    return (
        f"- {name}: {focus['label']} shows "
        f"requests {render_connection_metric_snapshot(counts['requests_total'])}, "
        f"synthetic responses {render_connection_metric_snapshot(counts['synthetic_responses_total'])}, "
        f"server headers-to-first-body-write avg "
        f"{render_connection_metric_snapshot(metrics['headers_to_first_body_write_avg_ms'])}, "
        f"server headers-to-first-body-write-completed avg "
        f"{render_connection_metric_snapshot(metrics['headers_to_first_body_write_completed_avg_ms'])}, "
        f"server queue-to-first-body-write avg "
        f"{render_connection_metric_snapshot(metrics['queue_to_first_body_write_avg_ms'])}, "
        f"server queue-to-first-body-write-completed avg "
        f"{render_connection_metric_snapshot(metrics['queue_to_first_body_write_completed_avg_ms'])}, "
        f"server first body write avg "
        f"{render_connection_metric_snapshot(metrics['first_body_write_avg_ms'])}, "
        f"server first body write completed avg "
        f"{render_connection_metric_snapshot(metrics['first_body_write_completed_avg_ms'])}, "
        f"server first body write call avg "
        f"{render_connection_metric_snapshot(metrics['first_body_write_call_avg_ms'])}, "
        f"server direct-stream open round trip avg "
        f"{render_connection_metric_snapshot(metrics['direct_stream_open_round_trip_avg_ms'])}, "
        f"server direct-stream request queue delay avg "
        f"{render_connection_metric_snapshot(metrics['direct_stream_request_queue_delay_avg_ms'])}, "
        f"server direct-stream descriptor-open call avg "
        f"{render_connection_metric_snapshot(metrics['direct_stream_descriptor_open_call_avg_ms'])}, "
        f"server direct-stream reply delivery delay avg "
        f"{render_connection_metric_snapshot(metrics['direct_stream_reply_delivery_delay_avg_ms'])}, "
        f"server stream open avg "
        f"{render_connection_metric_snapshot(metrics['stream_open_avg_ms'])}, "
        f"server request body drain avg "
        f"{render_connection_metric_snapshot(metrics['request_body_drain_avg_ms'])}."
    )


def render_native_response_stream_focus_line(name: str, focus: dict | None) -> str:
    if focus is None:
        return f"- {name}: no HTTP native response-stream metrics were present."

    counts = focus["counts"]
    metrics = focus["metrics"]
    return (
        f"- {name}: {focus['label']} shows "
        f"streaming responses "
        f"{render_connection_metric_snapshot(counts['streaming_responses_total'])}, "
        f"native stream-open-to-headers-send avg "
        f"{render_connection_metric_snapshot(metrics['stream_open_to_headers_send_avg_ms'])}, "
        f"native headers send call avg "
        f"{render_connection_metric_snapshot(metrics['headers_send_call_avg_ms'])}, "
        f"native headers-to-first-connection-write avg "
        f"{render_connection_metric_snapshot(metrics['headers_to_first_connection_write_avg_ms'])}, "
        f"native first chunk channel wait avg "
        f"{render_connection_metric_snapshot(metrics['first_chunk_channel_wait_avg_ms'])}, "
        f"native headers-to-first-chunk-dequeue avg "
        f"{render_connection_metric_snapshot(metrics['headers_to_first_chunk_dequeue_avg_ms'])}, "
        f"native first chunk send call avg "
        f"{render_connection_metric_snapshot(metrics['first_chunk_send_call_avg_ms'])}, "
        f"native headers-to-first-chunk-send-call avg "
        f"{render_connection_metric_snapshot(metrics['headers_to_first_chunk_send_call_avg_ms'])}."
    )


def render_native_response_stream_slow_path_bucket(snapshot: dict | None) -> str:
    if snapshot is None:
        return "n/a"

    ordered = [snapshot.get(suffix) for suffix in NATIVE_RESPONSE_STREAM_SLOW_PATH_BUCKET_KEYS]
    if any(entry is None for entry in ordered):
        return "n/a"

    baseline = "/".join(str(int(entry["baseline"])) for entry in ordered)
    ktls = "/".join(str(int(entry["ktls"])) for entry in ordered)
    return f"{baseline} -> {ktls}"


def render_native_response_stream_slow_path_focus_line(
    name: str, focus: dict | None
) -> str:
    if focus is None:
        return f"- {name}: no HTTP native response-stream slow-path metrics were present."

    counts = focus["counts"]
    buckets = focus["buckets"]
    return (
        f"- {name}: {focus['label']} shows "
        f"streaming responses "
        f"{render_connection_metric_snapshot(counts['streaming_responses_total'])}, "
        f"native headers-to-first-connection-write >=1/5/10ms "
        f"{render_native_response_stream_slow_path_bucket(buckets['headers_to_first_connection_write'])}, "
        f"native first chunk channel wait >=1/5/10ms "
        f"{render_native_response_stream_slow_path_bucket(buckets['first_chunk_channel_wait'])}, "
        f"native headers-to-first-chunk-dequeue >=1/5/10ms "
        f"{render_native_response_stream_slow_path_bucket(buckets['headers_to_first_chunk_dequeue'])}, "
        f"native first chunk send call >=1/5/10ms "
        f"{render_native_response_stream_slow_path_bucket(buckets['first_chunk_send_call'])}."
    )


def render_resource_usage_line(summary: dict | None) -> list[str]:
    if summary is None:
        return ["- Resource usage: no per-pass usage artifacts were present."]

    baseline = summary.get("baseline")
    ktls = summary.get("ktls")
    delta = summary.get("delta")
    if baseline is None or ktls is None or delta is None:
        return ["- Resource usage: partial capture only; one pass did not emit usage data."]

    return [
        (
            "- CPU total: baseline "
            f"{render_seconds(baseline.get('cpu_total_seconds'))}, "
            f"kTLS {render_seconds(ktls.get('cpu_total_seconds'))}, "
            f"delta {render_seconds(delta.get('cpu_total_seconds'))} "
            f"({render_pct(delta.get('cpu_total_seconds_pct'))})."
        ),
        (
            "- Elapsed wall time: baseline "
            f"{render_seconds(baseline.get('elapsed_seconds'))}, "
            f"kTLS {render_seconds(ktls.get('elapsed_seconds'))}, "
            f"delta {render_seconds(delta.get('elapsed_seconds'))} "
            f"({render_pct(delta.get('elapsed_seconds_pct'))})."
        ),
        (
            "- Max RSS: baseline "
            f"{render_kib(baseline.get('max_rss_kib'))}, "
            f"kTLS {render_kib(ktls.get('max_rss_kib'))}, "
            f"delta {render_kib(delta.get('max_rss_kib'))} "
            f"({render_pct(delta.get('max_rss_kib_pct'))})."
        ),
    ]


def render_tls_stat_line(summary: dict | None) -> list[str]:
    if summary is None:
        return ["- Linux TLS stats: no `/proc/net/tls_stat` sidecars were present."]

    baseline_pass = summary.get("baseline")
    ktls_pass = summary.get("ktls")
    if (
        baseline_pass is None
        or ktls_pass is None
        or baseline_pass.get("delta") is None
        or ktls_pass.get("delta") is None
    ):
        return [
            "- Linux TLS stats: partial capture only; one or more `/proc/net/tls_stat` snapshots were missing."
        ]

    metrics = summary["metrics"]

    def metric_delta(metric: str, field: str) -> int | None:
        snapshot = metrics.get(metric)
        if snapshot is None:
            return None
        return snapshot.get(field)

    session_line = (
        "- Linux TLS session opens: baseline software TX/RX "
        f"{render_int(metric_delta('TlsTxSw', 'baseline_delta'))}/"
        f"{render_int(metric_delta('TlsRxSw', 'baseline_delta'))}, "
        "device TX/RX "
        f"{render_int(metric_delta('TlsTxDevice', 'baseline_delta'))}/"
        f"{render_int(metric_delta('TlsRxDevice', 'baseline_delta'))}; "
        "kTLS software TX/RX "
        f"{render_int(metric_delta('TlsTxSw', 'ktls_delta'))}/"
        f"{render_int(metric_delta('TlsRxSw', 'ktls_delta'))}, "
        "device TX/RX "
        f"{render_int(metric_delta('TlsTxDevice', 'ktls_delta'))}/"
        f"{render_int(metric_delta('TlsRxDevice', 'ktls_delta'))}."
    )

    error_signals = [
        signal
        for signal in summary.get("signals", [])
        if signal["metric"] in {metric for metric, _ in TLS_STAT_ERROR_KEYS}
    ]
    if not error_signals:
        return [
            session_line,
            "- Linux TLS anomalies: no non-zero decrypt/rekey counters were captured in either pass.",
        ]

    rendered_signals = "; ".join(
        f"{signal['label']} baseline {render_int(signal['baseline_delta'])}, "
        f"kTLS {render_int(signal['ktls_delta'])}"
        for signal in error_signals
    )
    return [
        session_line,
        f"- Linux TLS anomalies: {rendered_signals}.",
    ]


def append_group_table(lines: list[str], title: str, groups: list[dict]) -> None:
    lines.extend(
        [
            f"### {title}",
            "",
            "| Group | Comparable workloads | Avg throughput delta | Avg p95 delta | Worst throughput row | Worst p95 row |",
            "| --- | ---: | ---: | ---: | --- | --- |",
        ]
    )

    if not groups:
        lines.append("| No overlapping completed workloads | 0 | n/a | n/a | n/a | n/a |")
        lines.append("")
        return

    for group in groups:
        throughput = group.get("throughput")
        latency = group.get("latency_p95")
        worst_throughput = "n/a"
        worst_latency = "n/a"
        if throughput is not None:
            worst_throughput = (
                f"{throughput['worst_row']['label']} "
                f"({render_pct(throughput['worst_row']['delta_pct'])})"
            )
        if latency is not None:
            worst_latency = (
                f"{latency['worst_row']['label']} "
                f"({render_pct(latency['worst_row']['delta_pct'])})"
            )

        lines.append(
            "| {label} | {count} | {avg_throughput} | {avg_latency} | {worst_throughput} | {worst_latency} |".format(
                label=group["label"],
                count=group["comparable_rows"],
                avg_throughput=render_pct(
                    throughput["average_pct_delta"] if throughput else None
                ),
                avg_latency=render_pct(
                    latency["average_pct_delta"] if latency else None
                ),
                worst_throughput=worst_throughput,
                worst_latency=worst_latency,
            )
        )

    lines.append("")


def build_comparison(baseline_path: Path, ktls_path: Path) -> dict:
    baseline_resource_path = baseline_path.parent / "resource-usage.txt"
    ktls_resource_path = ktls_path.parent / "resource-usage.txt"
    baseline_tls_stat_before_path = baseline_path.parent / "tls-stat-before.txt"
    baseline_tls_stat_after_path = baseline_path.parent / "tls-stat-after.txt"
    ktls_tls_stat_before_path = ktls_path.parent / "tls-stat-before.txt"
    ktls_tls_stat_after_path = ktls_path.parent / "tls-stat-after.txt"

    baseline = load_summary(baseline_path)
    ktls = load_summary(ktls_path)
    baseline_resource_usage = parse_resource_usage(baseline_resource_path)
    ktls_resource_usage = parse_resource_usage(ktls_resource_path)
    baseline_tls_stat = build_tls_stat_pass_summary(
        parse_tls_stat(baseline_tls_stat_before_path),
        parse_tls_stat(baseline_tls_stat_after_path),
    )
    ktls_tls_stat = build_tls_stat_pass_summary(
        parse_tls_stat(ktls_tls_stat_before_path),
        parse_tls_stat(ktls_tls_stat_after_path),
    )

    baseline_workloads = {
        workload_key(entry): entry for entry in baseline.get("workloads", [])
    }
    ktls_workloads = {workload_key(entry): entry for entry in ktls.get("workloads", [])}
    all_keys = sorted(set(baseline_workloads) | set(ktls_workloads))

    rows: list[dict] = []
    for entry_key in all_keys:
        base = baseline_workloads.get(entry_key)
        current = ktls_workloads.get(entry_key)
        row = {
            "scenario": entry_key[0],
            "workload": entry_key[1],
            "protocol": entry_key[2],
            "client_impl": entry_key[3],
            "router_workers": entry_key[4],
            "native_runtime_threads": entry_key[5],
            "baseline": base,
            "ktls": current,
        }
        if base and current:
            row["delta"] = {
                "throughput_mbps": current["throughput_mbps"] - base["throughput_mbps"],
                "throughput_pct": pct_delta(
                    base["throughput_mbps"], current["throughput_mbps"]
                ),
                "latency_p95_ms": current["latency_p95_ms"] - base["latency_p95_ms"],
                "latency_p95_pct": pct_delta(
                    base["latency_p95_ms"], current["latency_p95_ms"]
                ),
                "latency_avg_ms": current["latency_avg_ms"] - base["latency_avg_ms"],
                "latency_avg_pct": pct_delta(
                    base["latency_avg_ms"], current["latency_avg_ms"]
                ),
            }
        else:
            row["delta"] = None
        row["transport_summary"] = summarize_row_transport(row)
        row["connection_usage_summary"] = summarize_row_connection_usage(row)
        row["phase_timing_summary"] = summarize_row_phase_timing(row)
        row["server_emission_summary"] = summarize_row_server_emission_timing(row)
        row["native_response_stream_summary"] = summarize_row_native_response_stream_timing(
            row
        )
        row["native_response_stream_slow_path_summary"] = (
            summarize_row_native_response_stream_slow_path(row)
        )
        rows.append(row)

    comparable_rows = [row for row in rows if row["baseline"] and row["ktls"]]
    baseline_only_rows = [row for row in rows if row["baseline"] and not row["ktls"]]
    ktls_only_rows = [row for row in rows if row["ktls"] and not row["baseline"]]
    workload_groups = build_group_summaries(
        rows,
        "workload",
        lambda row: row["workload"],
        lambda row: row["workload"],
    )
    runtime_thread_groups = build_group_summaries(
        rows,
        "native_runtime_threads",
        lambda row: row["native_runtime_threads"],
        lambda row: f"threads={row['native_runtime_threads']}",
    )

    throughput_summary = build_metric_summary(rows, "throughput_pct")
    latency_p95_summary = build_metric_summary(rows, "latency_p95_pct")

    summary = {
        "comparable_rows": len(comparable_rows),
        "baseline_only_rows": len(baseline_only_rows),
        "ktls_only_rows": len(ktls_only_rows),
        "throughput": throughput_summary,
        "latency_p95": latency_p95_summary,
        "resource_usage": build_resource_usage_summary(
            baseline_resource_usage, ktls_resource_usage
        ),
        "linux_tls_stat": build_tls_stat_summary(baseline_tls_stat, ktls_tls_stat),
        "transport_focus": {
            "worst_throughput_row": build_transport_focus(
                rows,
                throughput_summary["worst_row"] if throughput_summary else None,
            ),
            "worst_latency_row": build_transport_focus(
                rows,
                latency_p95_summary["worst_row"] if latency_p95_summary else None,
            ),
        },
        "connection_focus": {
            "worst_throughput_row": build_connection_focus(
                rows,
                throughput_summary["worst_row"] if throughput_summary else None,
            ),
            "worst_latency_row": build_connection_focus(
                rows,
                latency_p95_summary["worst_row"] if latency_p95_summary else None,
            ),
        },
        "phase_timing_focus": {
            "worst_throughput_row": build_phase_timing_focus(
                rows,
                throughput_summary["worst_row"] if throughput_summary else None,
            ),
            "worst_latency_row": build_phase_timing_focus(
                rows,
                latency_p95_summary["worst_row"] if latency_p95_summary else None,
            ),
        },
        "server_emission_focus": {
            "worst_throughput_row": build_server_emission_focus(
                rows,
                throughput_summary["worst_row"] if throughput_summary else None,
            ),
            "worst_latency_row": build_server_emission_focus(
                rows,
                latency_p95_summary["worst_row"] if latency_p95_summary else None,
            ),
        },
        "native_response_stream_focus": {
            "worst_throughput_row": build_native_response_stream_focus(
                rows,
                throughput_summary["worst_row"] if throughput_summary else None,
            ),
            "worst_latency_row": build_native_response_stream_focus(
                rows,
                latency_p95_summary["worst_row"] if latency_p95_summary else None,
            ),
        },
        "native_response_stream_slow_path_focus": {
            "worst_throughput_row": build_native_response_stream_slow_path_focus(
                rows,
                throughput_summary["worst_row"] if throughput_summary else None,
            ),
            "worst_latency_row": build_native_response_stream_slow_path_focus(
                rows,
                latency_p95_summary["worst_row"] if latency_p95_summary else None,
            ),
        },
        "group_summaries": {
            "by_workload": workload_groups,
            "by_native_runtime_threads": runtime_thread_groups,
        },
        "hotspots": {
            "by_workload": select_hotspot_group(workload_groups),
            "by_native_runtime_threads": select_hotspot_group(runtime_thread_groups),
        },
    }

    return {
        "baseline_source": str(baseline_path),
        "ktls_source": str(ktls_path),
        "baseline_summary_present": baseline_path.exists(),
        "ktls_summary_present": ktls_path.exists(),
        "summary": summary,
        "rows": rows,
    }


def render_markdown(comparison: dict) -> str:
    summary = comparison["summary"]
    rows = comparison["rows"]

    lines = [
        "# HTTP/2 TLS vs kTLS Comparison",
        "",
    ]

    if not comparison["baseline_summary_present"] or not comparison["ktls_summary_present"]:
        lines.extend(
            [
                "One or both per-pass summary files were missing, so this comparison is partial.",
                "",
            ]
        )

    lines.extend(
        [
            "## Summary",
            "",
            f"- Comparable workloads: {summary['comparable_rows']}",
            f"- Baseline-only workloads: {summary['baseline_only_rows']}",
            f"- kTLS-only workloads: {summary['ktls_only_rows']}",
            render_summary_line(
                "Throughput", summary["throughput"], summary["comparable_rows"]
            ),
            render_summary_line(
                "p95 latency", summary["latency_p95"], summary["comparable_rows"]
            ),
            *render_resource_usage_line(summary["resource_usage"]),
            *render_tls_stat_line(summary["linux_tls_stat"]),
            render_group_focus_line(
                "Workload-family investigation focus",
                summary["hotspots"]["by_workload"],
            ),
            render_group_focus_line(
                "Runtime-thread investigation focus",
                summary["hotspots"]["by_native_runtime_threads"],
            ),
            render_transport_focus_line(
                "Worst throughput row transport view",
                summary["transport_focus"]["worst_throughput_row"],
            ),
            render_transport_focus_line(
                "Worst p95 row transport view",
                summary["transport_focus"]["worst_latency_row"],
            ),
            render_connection_focus_line(
                "Worst throughput row connection view",
                summary["connection_focus"]["worst_throughput_row"],
            ),
            render_connection_focus_line(
                "Worst p95 row connection view",
                summary["connection_focus"]["worst_latency_row"],
            ),
            render_phase_timing_focus_line(
                "Worst throughput row phase view",
                summary["phase_timing_focus"]["worst_throughput_row"],
            ),
            render_phase_timing_focus_line(
                "Worst p95 row phase view",
                summary["phase_timing_focus"]["worst_latency_row"],
            ),
            render_server_emission_focus_line(
                "Worst throughput row server-emission view",
                summary["server_emission_focus"]["worst_throughput_row"],
            ),
            render_server_emission_focus_line(
                "Worst p95 row server-emission view",
                summary["server_emission_focus"]["worst_latency_row"],
            ),
            render_native_response_stream_focus_line(
                "Worst throughput row native-stream view",
                summary["native_response_stream_focus"]["worst_throughput_row"],
            ),
            render_native_response_stream_focus_line(
                "Worst p95 row native-stream view",
                summary["native_response_stream_focus"]["worst_latency_row"],
            ),
            render_native_response_stream_slow_path_focus_line(
                "Worst throughput row native-stream slow-path view",
                summary["native_response_stream_slow_path_focus"][
                    "worst_throughput_row"
                ],
            ),
            render_native_response_stream_slow_path_focus_line(
                "Worst p95 row native-stream slow-path view",
                summary["native_response_stream_slow_path_focus"][
                    "worst_latency_row"
                ],
            ),
            "",
            "## Linux TLS Stats",
            "",
            "| Metric | Baseline delta | kTLS delta |",
            "| --- | ---: | ---: |",
        ]
    )

    tls_stat_summary = summary["linux_tls_stat"]
    has_tls_stat_rows = False
    if tls_stat_summary is not None:
        for metric, label in TLS_STAT_SUMMARY_KEYS:
            snapshot = tls_stat_summary["metrics"].get(metric)
            if snapshot is None:
                continue
            has_tls_stat_rows = True
            lines.append(
                "| {label} | {baseline_delta} | {ktls_delta} |".format(
                    label=label,
                    baseline_delta=render_int(snapshot["baseline_delta"]),
                    ktls_delta=render_int(snapshot["ktls_delta"]),
                )
            )

    if not has_tls_stat_rows:
        lines.append("| No `/proc/net/tls_stat` capture | n/a | n/a |")

    lines.extend(
        [
            "",
            "## Group Rollups",
            "",
        ]
    )

    append_group_table(
        lines,
        "By workload family",
        summary["group_summaries"]["by_workload"],
    )
    append_group_table(
        lines,
        "By native runtime threads",
        summary["group_summaries"]["by_native_runtime_threads"],
    )

    lines.extend(
        [
            "## Transport Counter Deltas",
            "",
            "| Workload | Router workers | Native runtime threads | Backpressure events | Backpressure alerts | Transport events | Transport alerts | Max depth after | Active throttles after |",
            "| --- | ---: | ---: | --- | --- | --- | --- | --- | --- |",
        ]
    )

    has_transport_rows = False
    for row in rows:
        transport_summary = row.get("transport_summary")
        if transport_summary is None:
            continue
        has_transport_rows = True
        metrics = transport_summary["metrics"]
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {backpressure_events} | {backpressure_alerts} | {transport_events_total} | {transport_alerts} | {max_backpressure_depth_after} | {active_throttles_after} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                backpressure_events=render_transport_snapshot(
                    metrics["backpressure_events"]
                ),
                backpressure_alerts=render_transport_snapshot(
                    metrics["backpressure_alerts"]
                ),
                transport_events_total=render_transport_snapshot(
                    metrics["transport_events_total"]
                ),
                transport_alerts=render_transport_snapshot(
                    metrics["transport_alerts"]
                ),
                max_backpressure_depth_after=render_transport_snapshot(
                    metrics["max_backpressure_depth_after"]
                ),
                active_throttles_after=render_transport_snapshot(
                    metrics["active_throttles_after"]
                ),
            )
        )

    if not has_transport_rows:
        lines.append("| No overlapping completed workloads | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")

    lines.append("")
    lines.extend(
        [
            "## HTTP Connection Usage",
            "",
            "| Workload | Router workers | Native runtime threads | Reuse | Streams per connection | Connections opened | Samples per opened connection |",
            "| --- | ---: | ---: | --- | --- | --- | --- |",
        ]
    )

    has_connection_rows = False
    for row in rows:
        connection_usage = row.get("connection_usage_summary")
        if connection_usage is None:
            continue
        has_connection_rows = True
        config = connection_usage["config"]
        metrics = connection_usage["metrics"]
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {reuse} | {streams_per_connection} | {connections_opened} | {samples_per_connection_avg} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                reuse=render_connection_config_snapshot(
                    config["reuse_connections"],
                    bool_value=True,
                ),
                streams_per_connection=render_connection_config_snapshot(
                    config["streams_per_connection"]
                ),
                connections_opened=render_connection_metric_snapshot(
                    metrics["connections_opened"]
                ),
                samples_per_connection_avg=render_connection_metric_snapshot(
                    metrics["samples_per_connection_avg"]
                ),
            )
        )

    if not has_connection_rows:
        lines.append("| No HTTP connection usage metrics | n/a | n/a | n/a | n/a | n/a | n/a |")

    lines.append("")
    lines.extend(
        [
            "## HTTP Phase Timing",
            "",
            "| Workload | Router workers | Native runtime threads | Stream acquire wait avg ms | Request enqueue avg ms | Response headers wait avg ms | Response body read avg ms | Request round trip avg ms | Request round trip p95 ms |",
            "| --- | ---: | ---: | --- | --- | --- | --- | --- | --- |",
        ]
    )

    has_phase_rows = False
    for row in rows:
        phase_timing = row.get("phase_timing_summary")
        if phase_timing is None:
            continue
        has_phase_rows = True
        metrics = phase_timing["metrics"]
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {stream_acquire_wait_avg_ms} | {request_enqueue_avg_ms} | {response_headers_wait_avg_ms} | {response_body_read_avg_ms} | {request_round_trip_avg_ms} | {request_round_trip_p95_ms} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                stream_acquire_wait_avg_ms=render_connection_metric_snapshot(
                    metrics["stream_acquire_wait_avg_ms"]
                ),
                request_enqueue_avg_ms=render_connection_metric_snapshot(
                    metrics["request_enqueue_avg_ms"]
                ),
                response_headers_wait_avg_ms=render_connection_metric_snapshot(
                    metrics["response_headers_wait_avg_ms"]
                ),
                response_body_read_avg_ms=render_connection_metric_snapshot(
                    metrics["response_body_read_avg_ms"]
                ),
                request_round_trip_avg_ms=render_connection_metric_snapshot(
                    metrics["request_round_trip_avg_ms"]
                ),
                request_round_trip_p95_ms=render_connection_metric_snapshot(
                    metrics["request_round_trip_p95_ms"]
                ),
            )
        )

    if not has_phase_rows:
        lines.append("| No HTTP phase timing metrics | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")

    lines.append("")
    lines.extend(
        [
            "## HTTP Header-Receive Diagnostics",
            "",
            "| Workload | Router workers | Native runtime threads | Response headers wait avg ms | Header conn read samples | Header conn read wait avg ms | Header conn read-to-headers samples | Header conn read-to-headers avg ms | Header conn write samples | Header conn write wait avg ms | Header conn write-span samples | Header conn write-span avg ms | Response headers wait p95 ms |",
            "| --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )

    has_header_rows = False
    for row in rows:
        phase_timing = row.get("phase_timing_summary")
        if phase_timing is None:
            continue
        has_header_rows = True
        metrics = phase_timing["metrics"]
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {response_headers_wait_avg_ms} | {response_headers_connection_read_wait_samples_total} | {response_headers_connection_read_wait_avg_ms} | {response_headers_connection_read_to_headers_samples_total} | {response_headers_connection_read_to_headers_avg_ms} | {response_headers_connection_write_wait_samples_total} | {response_headers_connection_write_wait_avg_ms} | {response_headers_connection_write_span_samples_total} | {response_headers_connection_write_span_avg_ms} | {response_headers_wait_p95_ms} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                response_headers_wait_avg_ms=render_connection_metric_snapshot(
                    metrics["response_headers_wait_avg_ms"]
                ),
                response_headers_connection_read_wait_samples_total=render_connection_metric_snapshot(
                    metrics["response_headers_connection_read_wait_samples_total"]
                ),
                response_headers_connection_read_wait_avg_ms=render_connection_metric_snapshot(
                    metrics["response_headers_connection_read_wait_avg_ms"]
                ),
                response_headers_connection_read_to_headers_samples_total=render_connection_metric_snapshot(
                    metrics["response_headers_connection_read_to_headers_samples_total"]
                ),
                response_headers_connection_read_to_headers_avg_ms=render_connection_metric_snapshot(
                    metrics["response_headers_connection_read_to_headers_avg_ms"]
                ),
                response_headers_connection_write_wait_samples_total=render_connection_metric_snapshot(
                    metrics["response_headers_connection_write_wait_samples_total"]
                ),
                response_headers_connection_write_wait_avg_ms=render_connection_metric_snapshot(
                    metrics["response_headers_connection_write_wait_avg_ms"]
                ),
                response_headers_connection_write_span_samples_total=render_connection_metric_snapshot(
                    metrics["response_headers_connection_write_span_samples_total"]
                ),
                response_headers_connection_write_span_avg_ms=render_connection_metric_snapshot(
                    metrics["response_headers_connection_write_span_avg_ms"]
                ),
                response_headers_wait_p95_ms=render_connection_metric_snapshot(
                    metrics["response_headers_wait_p95_ms"]
                ),
            )
        )

    if not has_header_rows:
        lines.append(
            "| No HTTP header-receive metrics | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |"
        )

    lines.append("")
    lines.extend(
        [
            "## HTTP Response-Body Diagnostics",
            "",
            "| Workload | Router workers | Native runtime threads | First chunk wait avg ms | Tail read avg ms | Body chunks avg | First chunk bytes avg | Post-header conn read samples | Post-header conn read wait avg ms | Conn read-to-first-chunk samples | Conn read-to-first-chunk avg ms | Response body read p95 ms |",
            "| --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )

    has_body_rows = False
    for row in rows:
        phase_timing = row.get("phase_timing_summary")
        if phase_timing is None:
            continue
        has_body_rows = True
        metrics = phase_timing["metrics"]
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {response_body_first_chunk_wait_avg_ms} | {response_body_tail_read_avg_ms} | {response_body_chunk_count_avg} | {response_body_first_chunk_bytes_avg} | {response_body_post_header_connection_read_wait_samples_total} | {response_body_post_header_connection_read_wait_avg_ms} | {response_body_connection_read_to_first_chunk_samples_total} | {response_body_connection_read_to_first_chunk_avg_ms} | {response_body_read_p95_ms} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                response_body_first_chunk_wait_avg_ms=render_connection_metric_snapshot(
                    metrics["response_body_first_chunk_wait_avg_ms"]
                ),
                response_body_tail_read_avg_ms=render_connection_metric_snapshot(
                    metrics["response_body_tail_read_avg_ms"]
                ),
                response_body_chunk_count_avg=render_connection_metric_snapshot(
                    metrics["response_body_chunk_count_avg"]
                ),
                response_body_first_chunk_bytes_avg=render_connection_metric_snapshot(
                    metrics["response_body_first_chunk_bytes_avg"]
                ),
                response_body_post_header_connection_read_wait_samples_total=render_connection_metric_snapshot(
                    metrics[
                        "response_body_post_header_connection_read_wait_samples_total"
                    ]
                ),
                response_body_post_header_connection_read_wait_avg_ms=render_connection_metric_snapshot(
                    metrics["response_body_post_header_connection_read_wait_avg_ms"]
                ),
                response_body_connection_read_to_first_chunk_samples_total=render_connection_metric_snapshot(
                    metrics[
                        "response_body_connection_read_to_first_chunk_samples_total"
                    ]
                ),
                response_body_connection_read_to_first_chunk_avg_ms=render_connection_metric_snapshot(
                    metrics["response_body_connection_read_to_first_chunk_avg_ms"]
                ),
                response_body_read_p95_ms=render_connection_metric_snapshot(
                    metrics["response_body_read_p95_ms"]
                ),
            )
        )

    if not has_body_rows:
        lines.append(
            "| No HTTP response-body diagnostics | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |"
        )

    lines.append("")
    lines.extend(
        [
            "## HTTP Server Emission Timing",
            "",
            "| Workload | Router workers | Native runtime threads | Requests | Synthetic responses | Headers to first body write avg ms | Headers to first body write completed avg ms | Queue to first body write avg ms | Queue to first body write completed avg ms | First body write avg ms | First body write completed avg ms | First body write call avg ms | Direct stream open round trip avg ms | Request queue delay avg ms | Descriptor open call avg ms | Reply delivery delay avg ms | Stream open avg ms | Request body drain avg ms |",
            "| --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )

    has_server_emission_rows = False
    for row in rows:
        server_emission = row.get("server_emission_summary")
        if server_emission is None:
            continue
        has_server_emission_rows = True
        counts = server_emission["counts"]
        metrics = server_emission["metrics"]
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {requests_total} | {synthetic_responses_total} | {headers_to_first_body_write_avg_ms} | {headers_to_first_body_write_completed_avg_ms} | {queue_to_first_body_write_avg_ms} | {queue_to_first_body_write_completed_avg_ms} | {first_body_write_avg_ms} | {first_body_write_completed_avg_ms} | {first_body_write_call_avg_ms} | {direct_stream_open_round_trip_avg_ms} | {direct_stream_request_queue_delay_avg_ms} | {direct_stream_descriptor_open_call_avg_ms} | {direct_stream_reply_delivery_delay_avg_ms} | {stream_open_avg_ms} | {request_body_drain_avg_ms} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                requests_total=render_connection_metric_snapshot(
                    counts["requests_total"]
                ),
                synthetic_responses_total=render_connection_metric_snapshot(
                    counts["synthetic_responses_total"]
                ),
                headers_to_first_body_write_avg_ms=render_connection_metric_snapshot(
                    metrics["headers_to_first_body_write_avg_ms"]
                ),
                headers_to_first_body_write_completed_avg_ms=render_connection_metric_snapshot(
                    metrics["headers_to_first_body_write_completed_avg_ms"]
                ),
                queue_to_first_body_write_avg_ms=render_connection_metric_snapshot(
                    metrics["queue_to_first_body_write_avg_ms"]
                ),
                queue_to_first_body_write_completed_avg_ms=render_connection_metric_snapshot(
                    metrics["queue_to_first_body_write_completed_avg_ms"]
                ),
                first_body_write_avg_ms=render_connection_metric_snapshot(
                    metrics["first_body_write_avg_ms"]
                ),
                first_body_write_completed_avg_ms=render_connection_metric_snapshot(
                    metrics["first_body_write_completed_avg_ms"]
                ),
                first_body_write_call_avg_ms=render_connection_metric_snapshot(
                    metrics["first_body_write_call_avg_ms"]
                ),
                direct_stream_open_round_trip_avg_ms=render_connection_metric_snapshot(
                    metrics["direct_stream_open_round_trip_avg_ms"]
                ),
                direct_stream_request_queue_delay_avg_ms=render_connection_metric_snapshot(
                    metrics["direct_stream_request_queue_delay_avg_ms"]
                ),
                direct_stream_descriptor_open_call_avg_ms=render_connection_metric_snapshot(
                    metrics["direct_stream_descriptor_open_call_avg_ms"]
                ),
                direct_stream_reply_delivery_delay_avg_ms=render_connection_metric_snapshot(
                    metrics["direct_stream_reply_delivery_delay_avg_ms"]
                ),
                stream_open_avg_ms=render_connection_metric_snapshot(
                    metrics["stream_open_avg_ms"]
                ),
                request_body_drain_avg_ms=render_connection_metric_snapshot(
                    metrics["request_body_drain_avg_ms"]
                ),
            )
        )

    if not has_server_emission_rows:
        lines.append("| No HTTP server emission metrics | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")

    lines.append("")
    lines.extend(
        [
            "## HTTP Native Response-Stream Timing",
            "",
            "| Workload | Router workers | Native runtime threads | Streaming responses | Headers to first connection write avg ms | First chunk channel wait avg ms | Headers to first chunk dequeue avg ms | First chunk send call avg ms | Headers to first chunk send call avg ms |",
            "| --- | ---: | ---: | --- | --- | --- | --- | --- | --- |",
        ]
    )

    has_native_stream_rows = False
    for row in rows:
        native_stream = row.get("native_response_stream_summary")
        if native_stream is None:
            continue
        has_native_stream_rows = True
        counts = native_stream["counts"]
        metrics = native_stream["metrics"]
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {streaming_responses_total} | {headers_to_first_connection_write_avg_ms} | {first_chunk_channel_wait_avg_ms} | {headers_to_first_chunk_dequeue_avg_ms} | {first_chunk_send_call_avg_ms} | {headers_to_first_chunk_send_call_avg_ms} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                streaming_responses_total=render_connection_metric_snapshot(
                    counts["streaming_responses_total"]
                ),
                headers_to_first_connection_write_avg_ms=render_connection_metric_snapshot(
                    metrics["headers_to_first_connection_write_avg_ms"]
                ),
                first_chunk_channel_wait_avg_ms=render_connection_metric_snapshot(
                    metrics["first_chunk_channel_wait_avg_ms"]
                ),
                headers_to_first_chunk_dequeue_avg_ms=render_connection_metric_snapshot(
                    metrics["headers_to_first_chunk_dequeue_avg_ms"]
                ),
                first_chunk_send_call_avg_ms=render_connection_metric_snapshot(
                    metrics["first_chunk_send_call_avg_ms"]
                ),
                headers_to_first_chunk_send_call_avg_ms=render_connection_metric_snapshot(
                    metrics["headers_to_first_chunk_send_call_avg_ms"]
                ),
            )
        )

    if not has_native_stream_rows:
        lines.append("| No HTTP native response-stream metrics | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")

    lines.append("")
    lines.extend(
        [
            "## HTTP Native Response-Stream Slow Paths",
            "",
            "| Workload | Router workers | Native runtime threads | Streaming responses | Headers to first connection write >=1/5/10ms | Channel wait >=1/5/10ms | Headers to dequeue >=1/5/10ms | Send call >=1/5/10ms |",
            "| --- | ---: | ---: | --- | --- | --- | --- | --- |",
        ]
    )

    has_native_stream_slow_path_rows = False
    for row in rows:
        native_stream = row.get("native_response_stream_slow_path_summary")
        if native_stream is None:
            continue
        has_native_stream_slow_path_rows = True
        counts = native_stream["counts"]
        buckets = native_stream["buckets"]
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {streaming_responses_total} | {headers_to_first_connection_write} | {first_chunk_channel_wait} | {headers_to_first_chunk_dequeue} | {first_chunk_send_call} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                streaming_responses_total=render_connection_metric_snapshot(
                    counts["streaming_responses_total"]
                ),
                headers_to_first_connection_write=render_native_response_stream_slow_path_bucket(
                    buckets["headers_to_first_connection_write"]
                ),
                first_chunk_channel_wait=render_native_response_stream_slow_path_bucket(
                    buckets["first_chunk_channel_wait"]
                ),
                headers_to_first_chunk_dequeue=render_native_response_stream_slow_path_bucket(
                    buckets["headers_to_first_chunk_dequeue"]
                ),
                first_chunk_send_call=render_native_response_stream_slow_path_bucket(
                    buckets["first_chunk_send_call"]
                ),
            )
        )

    if not has_native_stream_slow_path_rows:
        lines.append("| No HTTP native response-stream slow-path metrics | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")

    lines.append("")

    lines.extend(
        [
            "## Per-workload Rows",
            "",
            "| Workload | Router workers | Native runtime threads | Baseline Mbps | kTLS Mbps | Delta | Baseline p95 ms | kTLS p95 ms | Delta |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )

    has_comparable_rows = False
    for row in rows:
        base = row["baseline"]
        current = row["ktls"]
        delta = row["delta"]
        if not base or not current or not delta:
            continue
        has_comparable_rows = True
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {baseline_mbps:.2f} | {ktls_mbps:.2f} | {throughput_delta:+.2f} Mbps ({throughput_pct}) | {baseline_p95:.2f} | {ktls_p95:.2f} | {latency_delta:+.2f} ms ({latency_pct}) |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                baseline_mbps=base["throughput_mbps"],
                ktls_mbps=current["throughput_mbps"],
                throughput_delta=delta["throughput_mbps"],
                throughput_pct=render_pct(delta["throughput_pct"]),
                baseline_p95=base["latency_p95_ms"],
                ktls_p95=current["latency_p95_ms"],
                latency_delta=delta["latency_p95_ms"],
                latency_pct=render_pct(delta["latency_p95_pct"]),
            )
        )

    if not has_comparable_rows:
        lines.append(
            "| No overlapping completed workloads | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |"
        )

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare HTTP/2 baseline TLS and required-kTLS benchmark summaries.",
    )
    parser.add_argument("baseline_summary")
    parser.add_argument("ktls_summary")
    parser.add_argument("comparison_json")
    parser.add_argument("comparison_md")
    args = parser.parse_args()

    baseline_path = Path(args.baseline_summary)
    ktls_path = Path(args.ktls_summary)
    comparison_json_path = Path(args.comparison_json)
    comparison_md_path = Path(args.comparison_md)

    comparison = build_comparison(baseline_path, ktls_path)
    comparison_json_path.write_text(json.dumps(comparison, indent=2) + "\n")
    comparison_md_path.write_text(render_markdown(comparison))


if __name__ == "__main__":
    main()
