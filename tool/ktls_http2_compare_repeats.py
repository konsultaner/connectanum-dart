#!/usr/bin/env python3

import argparse
import json
import statistics
from collections import Counter
from pathlib import Path

import ktls_http2_compare as compare


THROUGHPUT_DELTA_SPAN_THRESHOLD_PCT = 25.0
LATENCY_P95_DELTA_SPAN_THRESHOLD_PCT = 50.0
PHASE_SIGNAL_MIN_ABS_DELTA_MS = 0.01
FOCUS_SIGNAL_MIN_MEDIAN_ABS_DELTA_MS = 0.10

PHASE_FOCUS_METRICS = (
    ("response_headers_wait_avg_ms", "Headers wait avg ms"),
    (
        "response_headers_last_write_to_first_read_avg_ms",
        "Header last-write-to-first-read avg ms",
    ),
    ("response_body_read_avg_ms", "Body read avg ms"),
    ("response_body_first_chunk_wait_avg_ms", "First chunk wait avg ms"),
    ("response_body_tail_read_avg_ms", "Tail read avg ms"),
    (
        "response_body_connection_read_to_first_chunk_avg_ms",
        "Conn read-to-first-chunk avg ms",
    ),
    (
        "response_body_tail_connection_read_wait_avg_ms",
        "Tail conn read wait avg ms",
    ),
    (
        "response_body_tail_connection_read_to_end_avg_ms",
        "Tail conn read-to-end avg ms",
    ),
    (
        "response_body_tail_connection_read_count_avg",
        "Tail conn read-count avg",
    ),
    (
        "response_body_tail_connection_read_span_avg_ms",
        "Tail conn read-span avg ms",
    ),
    (
        "response_body_tail_connection_last_read_to_end_avg_ms",
        "Tail conn last-read-to-end avg ms",
    ),
)

SERVER_EMISSION_FOCUS_METRICS = (
    (
        "headers_to_first_body_write_avg_ms",
        "Headers-to-first-body avg ms",
    ),
    (
        "headers_to_first_body_write_completed_avg_ms",
        "Headers-to-first-body completed avg ms",
    ),
    (
        "queue_to_first_body_write_avg_ms",
        "Queue-to-first-body avg ms",
    ),
    (
        "queue_to_first_body_write_completed_avg_ms",
        "Queue-to-first-body completed avg ms",
    ),
    ("first_body_write_avg_ms", "First body write avg ms"),
    ("first_body_write_completed_avg_ms", "First body write completed avg ms"),
    ("first_body_write_call_avg_ms", "First body write call avg ms"),
    (
        "direct_stream_open_round_trip_avg_ms",
        "Direct stream open round trip avg ms",
    ),
    (
        "direct_stream_request_queue_delay_avg_ms",
        "Request queue delay avg ms",
    ),
    (
        "direct_stream_reply_delivery_delay_avg_ms",
        "Reply delivery delay avg ms",
    ),
)

NATIVE_RESPONSE_STREAM_FOCUS_METRICS = (
    (
        "stream_open_to_headers_send_avg_ms",
        "Stream-open-to-headers avg ms",
    ),
    (
        "headers_to_first_connection_write_avg_ms",
        "Headers-to-first-write avg ms",
    ),
    ("first_chunk_channel_wait_avg_ms", "First chunk channel wait avg ms"),
    (
        "headers_to_first_chunk_dequeue_avg_ms",
        "Headers-to-first-chunk dequeue avg ms",
    ),
    ("first_chunk_send_call_avg_ms", "First chunk send call avg ms"),
    (
        "headers_to_first_chunk_send_call_avg_ms",
        "Headers-to-first-chunk send-call avg ms",
    ),
    ("tail_chunk_channel_wait_avg_ms", "Tail chunk channel wait avg ms"),
    ("tail_chunk_send_call_avg_ms", "Tail chunk send call avg ms"),
    ("first_to_last_chunk_send_avg_ms", "First-to-last chunk send avg ms"),
)


def row_key(row: dict) -> tuple:
    return (
        row["scenario"],
        row["workload"],
        row["protocol"],
        row.get("client_impl", "n/a"),
        row["router_workers"],
        row["native_runtime_threads"],
    )


def numeric_summary(values: list[float | int | None]) -> dict | None:
    filtered = [float(value) for value in values if value is not None]
    if not filtered:
        return None

    minimum = min(filtered)
    maximum = max(filtered)
    return {
        "min": minimum,
        "median": statistics.median(filtered),
        "max": maximum,
        "span": 0.0 if len(filtered) == 1 else maximum - minimum,
    }


def render_span(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value:.2f}pp"


def render_range(summary: dict | None, unit: str = "") -> str:
    if summary is None:
        return "n/a"
    suffix = unit if unit else ""
    return (
        f"{summary['min']:.2f}{suffix}..{summary['max']:.2f}{suffix} "
        f"(median {summary['median']:.2f}{suffix})"
    )


def render_signed_range(summary: dict | None, unit: str = "") -> str:
    if summary is None:
        return "n/a"
    suffix = unit if unit else ""
    return (
        f"{summary['min']:+.2f}{suffix}..{summary['max']:+.2f}{suffix} "
        f"(median {summary['median']:+.2f}{suffix})"
    )


def classify_span_source(
    baseline_summary: dict | None, ktls_summary: dict | None
) -> str:
    baseline_span = 0.0 if baseline_summary is None else baseline_summary["span"]
    ktls_span = 0.0 if ktls_summary is None else ktls_summary["span"]
    if baseline_span <= 0.0 and ktls_span <= 0.0:
        return "stable"
    if baseline_span >= ktls_span * 2.0 and baseline_span > 0.0:
        return "baseline"
    if ktls_span >= baseline_span * 2.0 and ktls_span > 0.0:
        return "kTLS"
    return "mixed"


def render_span_source(source: str) -> str:
    if source == "baseline":
        return "baseline-side"
    if source == "kTLS":
        return "kTLS-side"
    if source == "mixed":
        return "mixed"
    return "stable"


def pack_worst_row(row: dict | None) -> dict | None:
    if row is None:
        return None
    return {
        "label": row["label"],
        "scenario": row["scenario"],
        "workload": row["workload"],
        "protocol": row["protocol"],
        "client_impl": row["client_impl"],
        "router_workers": row["router_workers"],
        "native_runtime_threads": row["native_runtime_threads"],
        "delta_pct": row["delta_pct"],
    }


def pack_focus_row(
    row: dict | None, metric_specs: tuple[tuple[str, str], ...]
) -> dict | None:
    if row is None:
        return None

    metrics = row.get("metrics") or {}
    selected_metrics = {
        key: metrics[key]
        for key, _ in metric_specs
        if metrics.get(key) is not None
    }
    if not selected_metrics:
        return None

    return {
        "label": row["label"],
        "scenario": row.get("scenario"),
        "workload": row.get("workload"),
        "protocol": row.get("protocol"),
        "client_impl": row.get("client_impl"),
        "router_workers": row.get("router_workers"),
        "native_runtime_threads": row.get("native_runtime_threads"),
        "metrics": selected_metrics,
    }


def pack_phase_focus_row(row: dict | None) -> dict | None:
    return pack_focus_row(row, PHASE_FOCUS_METRICS)


def render_worst_row(row: dict | None) -> str:
    if row is None:
        return "n/a"
    return f"{row['label']} ({compare.render_pct(row['delta_pct'])})"


def build_consensus(runs: list[dict], key: str) -> dict:
    counts = Counter(
        run[key]["label"] for run in runs if run.get(key) is not None
    )
    ordered = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return {
        "consistent": len(ordered) <= 1,
        "counts": [
            {
                "label": label,
                "count": count,
            }
            for label, count in ordered
        ],
    }


def format_consensus_line(title: str, consensus: dict, repeat_count: int) -> str:
    counts = consensus["counts"]
    if not counts:
        return f"- {title}: n/a."
    if consensus["consistent"]:
        return f"- {title}: stable at {counts[0]['label']} across all {repeat_count} repeats."

    detail = ", ".join(
        f"{entry['label']} ({entry['count']}/{repeat_count})" for entry in counts
    )
    return f"- {title}: changed across repeats: {detail}."


def build_focus_signals(
    runs: list[dict],
    focus_keys: tuple[str, str],
    metric_specs: tuple[tuple[str, str], ...],
) -> list[dict]:
    buckets: dict[tuple[str, str], dict] = {}
    metric_labels = {key: label for key, label in metric_specs}

    for run in runs:
        seen_labels = set()
        for key in focus_keys:
            phase_row = run.get(key)
            if phase_row is None:
                continue

            row_label = phase_row["label"]
            if row_label in seen_labels:
                continue
            seen_labels.add(row_label)

            for metric, _ in metric_specs:
                snapshot = phase_row["metrics"].get(metric)
                if snapshot is None:
                    continue

                baseline = snapshot.get("baseline")
                ktls = snapshot.get("ktls")
                delta = snapshot.get("delta")
                if not all(
                    isinstance(value, (int, float))
                    for value in (baseline, ktls, delta)
                ):
                    continue
                if abs(float(delta)) < PHASE_SIGNAL_MIN_ABS_DELTA_MS:
                    continue

                bucket = buckets.setdefault(
                    (row_label, metric),
                    {
                        "label": row_label,
                        "metric": metric,
                        "metric_label": metric_labels[metric],
                        "repeat_labels": [],
                        "baseline_ms": [],
                        "ktls_ms": [],
                        "delta_ms": [],
                        "delta_pct": [],
                    },
                )
                bucket["repeat_labels"].append(run["repeat_label"])
                bucket["baseline_ms"].append(float(baseline))
                bucket["ktls_ms"].append(float(ktls))
                bucket["delta_ms"].append(float(delta))
                if isinstance(snapshot.get("delta_pct"), (int, float)):
                    bucket["delta_pct"].append(float(snapshot["delta_pct"]))

    signals = []
    for bucket in buckets.values():
        deltas = bucket["delta_ms"]
        if len(deltas) < 2:
            continue
        if all(delta > 0 for delta in deltas):
            direction = "kTLS higher"
        elif all(delta < 0 for delta in deltas):
            direction = "kTLS lower"
        else:
            continue

        delta_summary = numeric_summary(deltas)
        if (
            delta_summary is None
            or abs(delta_summary["median"]) < FOCUS_SIGNAL_MIN_MEDIAN_ABS_DELTA_MS
        ):
            continue

        signals.append(
            {
                "label": bucket["label"],
                "metric": bucket["metric"],
                "metric_label": bucket["metric_label"],
                "repeat_count": len(deltas),
                "repeat_labels": bucket["repeat_labels"],
                "direction": direction,
                "baseline_ms": numeric_summary(bucket["baseline_ms"]),
                "ktls_ms": numeric_summary(bucket["ktls_ms"]),
                "delta_ms": delta_summary,
                "delta_pct": numeric_summary(bucket["delta_pct"]),
            }
        )

    signals.sort(
        key=lambda signal: (
            -signal["repeat_count"],
            -abs(signal["delta_ms"]["median"]),
            signal["label"],
            signal["metric"],
        )
    )
    return signals


def build_phase_signals(runs: list[dict]) -> list[dict]:
    return build_focus_signals(
        runs,
        (
            "worst_throughput_phase_timing",
            "worst_latency_phase_timing",
        ),
        PHASE_FOCUS_METRICS,
    )


def build_server_emission_signals(runs: list[dict]) -> list[dict]:
    return build_focus_signals(
        runs,
        (
            "worst_throughput_server_emission",
            "worst_latency_server_emission",
        ),
        SERVER_EMISSION_FOCUS_METRICS,
    )


def build_native_response_stream_signals(runs: list[dict]) -> list[dict]:
    return build_focus_signals(
        runs,
        (
            "worst_throughput_native_response_stream",
            "worst_latency_native_response_stream",
        ),
        NATIVE_RESPONSE_STREAM_FOCUS_METRICS,
    )


def collect_repeat_focus_rows(
    runs: list[dict], focus_keys: tuple[tuple[str, str], ...]
) -> list[tuple[str, str, dict]]:
    focus_rows = []
    for run in runs:
        seen_labels = set()
        for focus_name, key in focus_keys:
            focus_row = run.get(key)
            if focus_row is None:
                continue
            label_key = focus_row["label"]
            if label_key in seen_labels:
                continue
            seen_labels.add(label_key)
            focus_rows.append((run["repeat_label"], focus_name, focus_row))
    return focus_rows


def build_repeat_labels(paths: list[Path]) -> list[str]:
    labels = [path.parent.name for path in paths]
    if len(set(labels)) == len(labels):
        return labels

    labels = []
    for path in paths:
        parent = path.parent
        grandparent = parent.parent
        if grandparent == parent:
            labels.append(parent.name)
        else:
            labels.append(f"{grandparent.name}/{parent.name}")

    if len(set(labels)) == len(labels):
        return labels

    return [str(path.parent) for path in paths]


def build_repeat_stability(comparison_paths: list[Path]) -> dict:
    comparisons = []
    for path in comparison_paths:
        comparisons.append((path, json.loads(path.read_text())))

    repeat_labels = build_repeat_labels([path for path, _ in comparisons])
    runs: list[dict] = []
    rows_by_key: dict[tuple, dict] = {}
    for repeat_index, ((path, comparison_data), run_label) in enumerate(
        zip(comparisons, repeat_labels),
        start=1,
    ):
        summary = comparison_data["summary"]
        throughput = summary.get("throughput")
        latency = summary.get("latency_p95")
        phase_timing_focus = summary.get("phase_timing_focus") or {}
        server_emission_focus = summary.get("server_emission_focus") or {}
        native_response_stream_focus = (
            summary.get("native_response_stream_focus") or {}
        )
        comparable_rows = int(summary.get("comparable_rows") or 0)
        baseline_only_rows = int(summary.get("baseline_only_rows") or 0)
        ktls_only_rows = int(summary.get("ktls_only_rows") or 0)

        runs.append(
            {
                "repeat_index": repeat_index,
                "repeat_label": run_label,
                "comparison_source": str(path),
                "comparable_rows": comparable_rows,
                "baseline_only_rows": baseline_only_rows,
                "ktls_only_rows": ktls_only_rows,
                "comparison_complete": (
                    comparable_rows > 0
                    and baseline_only_rows == 0
                    and ktls_only_rows == 0
                ),
                "average_throughput_pct_delta": None
                if throughput is None
                else throughput.get("average_pct_delta"),
                "average_latency_p95_pct_delta": None
                if latency is None
                else latency.get("average_pct_delta"),
                "worst_throughput_row": None
                if throughput is None
                else pack_worst_row(throughput.get("worst_row")),
                "worst_latency_row": None
                if latency is None
                else pack_worst_row(latency.get("worst_row")),
                "worst_throughput_phase_timing": pack_phase_focus_row(
                    phase_timing_focus.get("worst_throughput_row")
                ),
                "worst_latency_phase_timing": pack_phase_focus_row(
                    phase_timing_focus.get("worst_latency_row")
                ),
                "worst_throughput_server_emission": pack_focus_row(
                    server_emission_focus.get("worst_throughput_row"),
                    SERVER_EMISSION_FOCUS_METRICS,
                ),
                "worst_latency_server_emission": pack_focus_row(
                    server_emission_focus.get("worst_latency_row"),
                    SERVER_EMISSION_FOCUS_METRICS,
                ),
                "worst_throughput_native_response_stream": pack_focus_row(
                    native_response_stream_focus.get("worst_throughput_row"),
                    NATIVE_RESPONSE_STREAM_FOCUS_METRICS,
                ),
                "worst_latency_native_response_stream": pack_focus_row(
                    native_response_stream_focus.get("worst_latency_row"),
                    NATIVE_RESPONSE_STREAM_FOCUS_METRICS,
                ),
            }
        )

        for row in comparison_data["rows"]:
            if row.get("delta") is None:
                continue

            key = row_key(row)
            bucket = rows_by_key.setdefault(
                key,
                {
                    "scenario": row["scenario"],
                    "workload": row["workload"],
                    "protocol": row["protocol"],
                    "client_impl": row["client_impl"],
                    "router_workers": row["router_workers"],
                    "native_runtime_threads": row["native_runtime_threads"],
                    "label": compare.build_label(row),
                    "throughput_pct_deltas": [],
                    "latency_p95_pct_deltas": [],
                    "baseline_throughput_mbps": [],
                    "ktls_throughput_mbps": [],
                    "baseline_latency_p95_ms": [],
                    "ktls_latency_p95_ms": [],
                },
            )
            bucket["throughput_pct_deltas"].append(row["delta"]["throughput_pct"])
            bucket["latency_p95_pct_deltas"].append(row["delta"]["latency_p95_pct"])
            bucket["baseline_throughput_mbps"].append(row["baseline"]["throughput_mbps"])
            bucket["ktls_throughput_mbps"].append(row["ktls"]["throughput_mbps"])
            bucket["baseline_latency_p95_ms"].append(row["baseline"]["latency_p95_ms"])
            bucket["ktls_latency_p95_ms"].append(row["ktls"]["latency_p95_ms"])

    row_stability = []
    for row in rows_by_key.values():
        row_stability.append(
            {
                "scenario": row["scenario"],
                "workload": row["workload"],
                "protocol": row["protocol"],
                "client_impl": row["client_impl"],
                "router_workers": row["router_workers"],
                "native_runtime_threads": row["native_runtime_threads"],
                "label": row["label"],
                "repeat_count": len(row["throughput_pct_deltas"]),
                "throughput_pct_delta": numeric_summary(row["throughput_pct_deltas"]),
                "latency_p95_pct_delta": numeric_summary(
                    row["latency_p95_pct_deltas"]
                ),
                "baseline_throughput_mbps": numeric_summary(
                    row["baseline_throughput_mbps"]
                ),
                "ktls_throughput_mbps": numeric_summary(row["ktls_throughput_mbps"]),
                "baseline_latency_p95_ms": numeric_summary(
                    row["baseline_latency_p95_ms"]
                ),
                "ktls_latency_p95_ms": numeric_summary(row["ktls_latency_p95_ms"]),
                "throughput_span_source": classify_span_source(
                    numeric_summary(row["baseline_throughput_mbps"]),
                    numeric_summary(row["ktls_throughput_mbps"]),
                ),
                "latency_p95_span_source": classify_span_source(
                    numeric_summary(row["baseline_latency_p95_ms"]),
                    numeric_summary(row["ktls_latency_p95_ms"]),
                ),
            }
        )

    def instability_score(row: dict) -> float:
        throughput_span = row["throughput_pct_delta"]["span"]
        latency_span = row["latency_p95_pct_delta"]["span"]
        return max(throughput_span, latency_span)

    row_stability.sort(
        key=lambda row: (
            -instability_score(row),
            row["workload"],
            row["native_runtime_threads"],
        )
    )

    max_throughput_span_row = max(
        row_stability,
        key=lambda row: row["throughput_pct_delta"]["span"],
        default=None,
    )
    max_latency_p95_span_row = max(
        row_stability,
        key=lambda row: row["latency_p95_pct_delta"]["span"],
        default=None,
    )

    worst_throughput_consensus = build_consensus(runs, "worst_throughput_row")
    worst_latency_consensus = build_consensus(runs, "worst_latency_row")

    instability_reasons: list[str] = []
    if not row_stability:
        instability_reasons.append("No comparable rows were produced across repeats.")
    for run in runs:
        if run["comparable_rows"] == 0:
            instability_reasons.append(
                f"{run['repeat_label']} produced no comparable rows "
                f"(baseline-only {run['baseline_only_rows']}, "
                f"kTLS-only {run['ktls_only_rows']})."
            )
        elif not run["comparison_complete"]:
            instability_reasons.append(
                f"{run['repeat_label']} produced unmatched rows "
                f"(comparable {run['comparable_rows']}, "
                f"baseline-only {run['baseline_only_rows']}, "
                f"kTLS-only {run['ktls_only_rows']})."
            )
    if not worst_throughput_consensus["consistent"]:
        instability_reasons.append("Worst throughput row changed across repeats.")
    if not worst_latency_consensus["consistent"]:
        instability_reasons.append("Worst p95 row changed across repeats.")
    if (
        max_throughput_span_row is not None
        and max_throughput_span_row["throughput_pct_delta"]["span"]
        > THROUGHPUT_DELTA_SPAN_THRESHOLD_PCT
    ):
        instability_reasons.append(
            f"Largest throughput delta span exceeded {render_span(THROUGHPUT_DELTA_SPAN_THRESHOLD_PCT)}."
        )
    if (
        max_latency_p95_span_row is not None
        and max_latency_p95_span_row["latency_p95_pct_delta"]["span"]
        > LATENCY_P95_DELTA_SPAN_THRESHOLD_PCT
    ):
        instability_reasons.append(
            f"Largest p95 delta span exceeded {render_span(LATENCY_P95_DELTA_SPAN_THRESHOLD_PCT)}."
        )

    return {
        "mode": "repeat_stability",
        "repeat_count": len(runs),
        "decision_quality": not instability_reasons,
        "stability_thresholds": {
            "throughput_pct_delta_span": THROUGHPUT_DELTA_SPAN_THRESHOLD_PCT,
            "latency_p95_pct_delta_span": LATENCY_P95_DELTA_SPAN_THRESHOLD_PCT,
        },
        "instability_reasons": instability_reasons,
        "worst_throughput_consensus": worst_throughput_consensus,
        "worst_latency_consensus": worst_latency_consensus,
        "max_throughput_span_row": max_throughput_span_row,
        "max_latency_p95_span_row": max_latency_p95_span_row,
        "phase_signals": build_phase_signals(runs),
        "server_emission_signals": build_server_emission_signals(runs),
        "native_response_stream_signals": build_native_response_stream_signals(runs),
        "runs": runs,
        "row_stability": row_stability,
    }


def render_markdown(stability: dict) -> str:
    repeat_count = stability["repeat_count"]
    thresholds = stability["stability_thresholds"]
    phase_signals = stability.get("phase_signals") or []
    server_emission_signals = stability.get("server_emission_signals") or []
    native_response_stream_signals = (
        stability.get("native_response_stream_signals") or []
    )
    lines = [
        "# HTTP/2 TLS vs kTLS Repeat Stability",
        "",
        "## Summary",
        "",
        f"- Repeats: {repeat_count}",
        f"- Decision quality: {'yes' if stability['decision_quality'] else 'no'}",
        (
            "- Stability thresholds: throughput delta span <= "
            f"{render_span(thresholds['throughput_pct_delta_span'])}, "
            f"p95 delta span <= {render_span(thresholds['latency_p95_pct_delta_span'])}."
        ),
        format_consensus_line(
            "Worst throughput row consistency",
            stability["worst_throughput_consensus"],
            repeat_count,
        ),
        format_consensus_line(
            "Worst p95 row consistency",
            stability["worst_latency_consensus"],
            repeat_count,
        ),
    ]

    if phase_signals:
        lines.append(
            "- Repeat phase signals: "
            f"{len(phase_signals)} sign-consistent phase deltas across repeated focus rows."
        )
    else:
        lines.append("- Repeat phase signals: none across repeated focus rows.")

    if server_emission_signals:
        lines.append(
            "- Repeat server-emission signals: "
            f"{len(server_emission_signals)} sign-consistent server deltas across repeated focus rows."
        )
    else:
        lines.append("- Repeat server-emission signals: none across repeated focus rows.")

    if native_response_stream_signals:
        lines.append(
            "- Repeat native response-stream signals: "
            f"{len(native_response_stream_signals)} sign-consistent native stream deltas across repeated focus rows."
        )
    else:
        lines.append(
            "- Repeat native response-stream signals: none across repeated focus rows."
        )

    incomplete_runs = [
        run for run in stability["runs"] if not run["comparison_complete"]
    ]
    if incomplete_runs:
        lines.append(
            "- Repeat completeness: "
            f"{len(incomplete_runs)}/{repeat_count} repeats had no comparable rows "
            "or unmatched baseline/kTLS rows."
        )
    else:
        lines.append("- Repeat completeness: all repeats produced matched rows.")

    if stability["instability_reasons"]:
        lines.append("- Repeat-stability result: not decision-quality because:")
        for reason in stability["instability_reasons"]:
            lines.append(f"  - {reason}")
    else:
        lines.append("- Repeat-stability result: decision-quality.")

    max_throughput_span_row = stability.get("max_throughput_span_row")
    if max_throughput_span_row is not None:
        lines.append(
            "- Largest throughput delta span: "
            f"{max_throughput_span_row['label']} spans "
            f"{render_span(max_throughput_span_row['throughput_pct_delta']['span'])}; "
            f"baseline {render_range(max_throughput_span_row['baseline_throughput_mbps'], ' Mbps')}, "
            f"kTLS {render_range(max_throughput_span_row['ktls_throughput_mbps'], ' Mbps')}, "
            f"delta {compare.render_pct(max_throughput_span_row['throughput_pct_delta']['min'])}.."
            f"{compare.render_pct(max_throughput_span_row['throughput_pct_delta']['max'])}."
        )

    max_latency_p95_span_row = stability.get("max_latency_p95_span_row")
    if max_latency_p95_span_row is not None:
        lines.append(
            "- Largest p95 delta span: "
            f"{max_latency_p95_span_row['label']} spans "
            f"{render_span(max_latency_p95_span_row['latency_p95_pct_delta']['span'])}; "
            f"baseline {render_range(max_latency_p95_span_row['baseline_latency_p95_ms'], ' ms')}, "
            f"kTLS {render_range(max_latency_p95_span_row['ktls_latency_p95_ms'], ' ms')}, "
            f"delta {compare.render_pct(max_latency_p95_span_row['latency_p95_pct_delta']['min'])}.."
            f"{compare.render_pct(max_latency_p95_span_row['latency_p95_pct_delta']['max'])}."
        )

    threshold_rows = [
        row
        for row in stability["row_stability"]
        if row["throughput_pct_delta"]["span"]
        > thresholds["throughput_pct_delta_span"]
        or row["latency_p95_pct_delta"]["span"]
        > thresholds["latency_p95_pct_delta_span"]
    ]
    if threshold_rows:
        lines.append("- Instability source highlights:")
        for row in threshold_rows[:3]:
            notes = []
            if row["throughput_pct_delta"]["span"] > thresholds["throughput_pct_delta_span"]:
                notes.append(
                    f"{render_span_source(row['throughput_span_source'])} throughput span"
                )
            if (
                row["latency_p95_pct_delta"]["span"]
                > thresholds["latency_p95_pct_delta_span"]
            ):
                notes.append(
                    f"{render_span_source(row['latency_p95_span_source'])} p95 span"
                )
            note_text = ", ".join(notes) if notes else "stable"
            lines.append(f"  - {row['label']}: {note_text}.")

    lines.extend(
        [
            "",
            "## Repeat Completeness",
            "",
            "| Repeat | Comparable rows | Baseline-only rows | kTLS-only rows | Result |",
            "| --- | ---: | ---: | ---: | --- |",
        ]
    )

    for run in stability["runs"]:
        lines.append(
            "| {repeat_label} | {comparable_rows} | {baseline_only_rows} | {ktls_only_rows} | {result} |".format(
                repeat_label=run["repeat_label"],
                comparable_rows=run["comparable_rows"],
                baseline_only_rows=run["baseline_only_rows"],
                ktls_only_rows=run["ktls_only_rows"],
                result="complete" if run["comparison_complete"] else "incomplete",
            )
        )

    lines.extend(
        [
            "",
            "## Repeat Overview",
            "",
            "| Repeat | Avg throughput delta | Avg p95 delta | Worst throughput row | Worst p95 row |",
            "| --- | ---: | ---: | --- | --- |",
        ]
    )

    for run in stability["runs"]:
        lines.append(
            "| {repeat_label} | {avg_throughput} | {avg_latency} | {worst_throughput} | {worst_latency} |".format(
                repeat_label=run["repeat_label"],
                avg_throughput=compare.render_pct(run["average_throughput_pct_delta"]),
                avg_latency=compare.render_pct(run["average_latency_p95_pct_delta"]),
                worst_throughput=render_worst_row(run["worst_throughput_row"]),
                worst_latency=render_worst_row(run["worst_latency_row"]),
            )
        )

    def append_signal_table(title: str, signals: list[dict]) -> None:
        lines.extend(
            [
                "",
                title,
                "",
                "| Row | Metric | Repeats | Direction | Baseline range | kTLS range | Delta range |",
                "| --- | --- | ---: | --- | --- | --- | --- |",
            ]
        )

        if signals:
            for signal in signals:
                lines.append(
                    "| {row} | {metric} | {repeats} | {direction} | {baseline} | {ktls} | {delta} |".format(
                        row=signal["label"],
                        metric=signal["metric_label"],
                        repeats=signal["repeat_count"],
                        direction=signal["direction"],
                        baseline=render_range(signal["baseline_ms"], " ms"),
                        ktls=render_range(signal["ktls_ms"], " ms"),
                        delta=render_signed_range(signal["delta_ms"], " ms"),
                    )
                )
        else:
            lines.append("| None | n/a | n/a | n/a | n/a | n/a | n/a |")

    append_signal_table("## Repeat Phase Signals", phase_signals)
    append_signal_table("## Repeat Server-Emission Signals", server_emission_signals)
    append_signal_table(
        "## Repeat Native Response-Stream Signals",
        native_response_stream_signals,
    )

    def append_focus_table(
        title: str,
        metric_specs: tuple[tuple[str, str], ...],
        focus_rows: list[tuple[str, str, dict]],
    ) -> None:
        lines.extend(
            [
                "",
                title,
                "",
                "| Repeat | Focus | Row | "
                + " | ".join(label for _, label in metric_specs)
                + " |",
                "| --- | --- | --- | "
                + " | ".join("---:" for _ in metric_specs)
                + " |",
            ]
        )

        if focus_rows:
            for repeat_label, focus_name, focus_row in focus_rows:
                metrics = focus_row["metrics"]
                rendered_metrics = [
                    compare.render_connection_metric_snapshot(metrics.get(key))
                    for key, _ in metric_specs
                ]
                lines.append(
                    "| {repeat} | {focus} | {row} | {metrics} |".format(
                        repeat=repeat_label,
                        focus=focus_name,
                        row=focus_row["label"],
                        metrics=" | ".join(rendered_metrics),
                    )
                )
        else:
            lines.append(
                "| None | n/a | n/a | "
                + " | ".join("n/a" for _ in metric_specs)
                + " |"
            )

    phase_focus_rows = collect_repeat_focus_rows(
        stability["runs"],
        (
            ("Worst throughput", "worst_throughput_phase_timing"),
            ("Worst p95", "worst_latency_phase_timing"),
        ),
    )
    server_emission_focus_rows = collect_repeat_focus_rows(
        stability["runs"],
        (
            ("Worst throughput", "worst_throughput_server_emission"),
            ("Worst p95", "worst_latency_server_emission"),
        ),
    )
    native_response_stream_focus_rows = collect_repeat_focus_rows(
        stability["runs"],
        (
            ("Worst throughput", "worst_throughput_native_response_stream"),
            ("Worst p95", "worst_latency_native_response_stream"),
        ),
    )

    append_focus_table(
        "## Repeat Phase-Timing Focus",
        PHASE_FOCUS_METRICS,
        phase_focus_rows,
    )
    append_focus_table(
        "## Repeat Server-Emission Focus",
        SERVER_EMISSION_FOCUS_METRICS,
        server_emission_focus_rows,
    )
    append_focus_table(
        "## Repeat Native Response-Stream Focus",
        NATIVE_RESPONSE_STREAM_FOCUS_METRICS,
        native_response_stream_focus_rows,
    )

    lines.extend(
        [
            "",
            "## Rows Exceeding Stability Thresholds",
            "",
            "| Workload | Router workers | Native runtime threads | Throughput delta span | Throughput source | p95 delta span | p95 source |",
            "| --- | ---: | ---: | ---: | --- | ---: | --- |",
        ]
    )

    if threshold_rows:
        for row in threshold_rows:
            lines.append(
                "| {workload} | {router_workers} | {native_runtime_threads} | {throughput_span} | {throughput_source} | {latency_span} | {latency_source} |".format(
                    workload=row["workload"],
                    router_workers=row["router_workers"],
                    native_runtime_threads=row["native_runtime_threads"],
                    throughput_span=render_span(row["throughput_pct_delta"]["span"]),
                    throughput_source=render_span_source(row["throughput_span_source"]),
                    latency_span=render_span(row["latency_p95_pct_delta"]["span"]),
                    latency_source=render_span_source(row["latency_p95_span_source"]),
                )
            )
    else:
        lines.append("| None | n/a | n/a | n/a | n/a | n/a | n/a |")

    lines.extend(
        [
            "",
            "## Per-row Stability",
            "",
            "| Workload | Router workers | Native runtime threads | Repeats | Throughput delta min..max | Throughput delta span | p95 delta min..max | p95 delta span |",
            "| --- | ---: | ---: | ---: | --- | ---: | --- | ---: |",
        ]
    )

    for row in stability["row_stability"]:
        lines.append(
            "| {workload} | {router_workers} | {native_runtime_threads} | {repeat_count} | {throughput_range} | {throughput_span} | {latency_range} | {latency_span} |".format(
                workload=row["workload"],
                router_workers=row["router_workers"],
                native_runtime_threads=row["native_runtime_threads"],
                repeat_count=row["repeat_count"],
                throughput_range=(
                    f"{compare.render_pct(row['throughput_pct_delta']['min'])}.."
                    f"{compare.render_pct(row['throughput_pct_delta']['max'])}"
                ),
                throughput_span=render_span(row["throughput_pct_delta"]["span"]),
                latency_range=(
                    f"{compare.render_pct(row['latency_p95_pct_delta']['min'])}.."
                    f"{compare.render_pct(row['latency_p95_pct_delta']['max'])}"
                ),
                latency_span=render_span(row["latency_p95_pct_delta"]["span"]),
            )
        )

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Aggregate repeated HTTP/2 baseline TLS versus kTLS comparisons.",
    )
    parser.add_argument("comparison_json")
    parser.add_argument("comparison_md")
    parser.add_argument("repeat_comparison_json", nargs="+")
    args = parser.parse_args()

    repeat_paths = [Path(path) for path in args.repeat_comparison_json]
    stability = build_repeat_stability(repeat_paths)
    Path(args.comparison_json).write_text(json.dumps(stability, indent=2) + "\n")
    Path(args.comparison_md).write_text(render_markdown(stability))


if __name__ == "__main__":
    main()
