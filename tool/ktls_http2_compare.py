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
        if ":" not in line:
            continue
        label, raw_value = line.split(":", 1)
        label = label.strip()
        value = raw_value.strip()
        for field_name, expected_label in RESOURCE_USAGE_KEYS.items():
            if label != expected_label:
                continue
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

    deltas = [row["delta"][metric] for row in comparable if row["delta"][metric] is not None]
    average_delta = sum(deltas) / len(deltas) if deltas else None

    def pack_row(row: dict) -> dict:
        return {
            "label": build_label(row),
            "workload": row["workload"],
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
    baseline_resource_path = baseline_path.parent / "resource-usage.txt"
    ktls_resource_path = ktls_path.parent / "resource-usage.txt"

    baseline = load_summary(baseline_path)
    ktls = load_summary(ktls_path)
    baseline_resource_usage = parse_resource_usage(baseline_resource_path)
    ktls_resource_usage = parse_resource_usage(ktls_resource_path)

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
        rows.append(row)

    comparable_rows = [row for row in rows if row["baseline"] and row["ktls"]]
    baseline_only_rows = [row for row in rows if row["baseline"] and not row["ktls"]]
    ktls_only_rows = [row for row in rows if row["ktls"] and not row["baseline"]]

    summary = {
        "comparable_rows": len(comparable_rows),
        "baseline_only_rows": len(baseline_only_rows),
        "ktls_only_rows": len(ktls_only_rows),
        "throughput": build_metric_summary(rows, "throughput_pct"),
        "latency_p95": build_metric_summary(rows, "latency_p95_pct"),
        "resource_usage": build_resource_usage_summary(
            baseline_resource_usage, ktls_resource_usage
        ),
    }

    comparison = {
        "baseline_source": str(baseline_path),
        "ktls_source": str(ktls_path),
        "baseline_summary_present": baseline_path.exists(),
        "ktls_summary_present": ktls_path.exists(),
        "summary": summary,
        "rows": rows,
    }
    comparison_json_path.write_text(json.dumps(comparison, indent=2) + "\n")

    lines = [
        "# HTTP/2 TLS vs kTLS Comparison",
        "",
    ]

    if not baseline_path.exists() or not ktls_path.exists():
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

    comparison_md_path.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
