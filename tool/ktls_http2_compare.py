#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


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


def render_pct(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value:+.2f}%"


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

    baseline = load_summary(baseline_path)
    ktls = load_summary(ktls_path)

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
