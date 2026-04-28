#!/usr/bin/env python3

import argparse
import json
import statistics
from collections import Counter
from pathlib import Path

import ktls_http2_compare as compare


THROUGHPUT_DELTA_SPAN_THRESHOLD_PCT = 25.0
LATENCY_P95_DELTA_SPAN_THRESHOLD_PCT = 50.0

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


def pack_phase_focus_row(row: dict | None) -> dict | None:
    if row is None:
        return None

    metrics = row.get("metrics") or {}
    selected_metrics = {
        key: metrics[key]
        for key, _ in PHASE_FOCUS_METRICS
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

        runs.append(
            {
                "repeat_index": repeat_index,
                "repeat_label": run_label,
                "comparison_source": str(path),
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
        "runs": runs,
        "row_stability": row_stability,
    }


def render_markdown(stability: dict) -> str:
    repeat_count = stability["repeat_count"]
    thresholds = stability["stability_thresholds"]
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

    phase_focus_rows = []
    for run in stability["runs"]:
        seen_labels = set()
        for focus_name, key in (
            ("Worst throughput", "worst_throughput_phase_timing"),
            ("Worst p95", "worst_latency_phase_timing"),
        ):
            phase_row = run.get(key)
            if phase_row is None:
                continue
            label_key = phase_row["label"]
            if label_key in seen_labels:
                continue
            seen_labels.add(label_key)
            phase_focus_rows.append((run["repeat_label"], focus_name, phase_row))

    lines.extend(
        [
            "",
            "## Repeat Phase-Timing Focus",
            "",
            "| Repeat | Focus | Row | "
            + " | ".join(label for _, label in PHASE_FOCUS_METRICS)
            + " |",
            "| --- | --- | --- | "
            + " | ".join("---:" for _ in PHASE_FOCUS_METRICS)
            + " |",
        ]
    )

    if phase_focus_rows:
        for repeat_label, focus_name, phase_row in phase_focus_rows:
            metrics = phase_row["metrics"]
            rendered_metrics = [
                compare.render_connection_metric_snapshot(metrics.get(key))
                for key, _ in PHASE_FOCUS_METRICS
            ]
            lines.append(
                "| {repeat} | {focus} | {row} | {metrics} |".format(
                    repeat=repeat_label,
                    focus=focus_name,
                    row=phase_row["label"],
                    metrics=" | ".join(rendered_metrics),
                )
            )
    else:
        lines.append(
            "| None | n/a | n/a | "
            + " | ".join("n/a" for _ in PHASE_FOCUS_METRICS)
            + " |"
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
