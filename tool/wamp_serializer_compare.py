#!/usr/bin/env python3

"""Compare paired WAMP serializer benchmark runs and enforce release budgets."""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
import random
import re
import statistics
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


CODECS = ("flatbuffers", "cbor", "msgpack")
METRICS = ("throughput_mbps", "latency_p95_ms", "latency_p99_ms")
RESOURCE_METRICS = (
    "cpu_us_per_operation",
    "allocated_bytes_per_operation",
    "gc_pause_us_per_operation",
    "summed_sampled_peak_rss_bytes",
)
ALL_METRICS = METRICS + RESOURCE_METRICS
PROCESS_METRICS = (
    "cpu_user_us_delta",
    "cpu_system_us_delta",
    "allocated_bytes_delta",
    "gc_count_delta",
    "gc_pause_us_delta",
    "current_rss_bytes",
    "peak_rss_during_bytes",
)
PROCESS_IDENTITY_METRICS = (
    "pid",
    "rss_before_bytes",
    "current_rss_bytes",
    "max_rss_bytes",
)
COPY_METRICS = (
    "optimized_payload_copy_bytes",
    "builder_input_copy_bytes",
    "builder_growth_copy_bytes",
    "transport_copy_bytes",
    "websocket_mask_copy_bytes",
    "tls_copy_bytes",
    "transcode_copy_bytes",
    "e2ee_copy_bytes",
)


class CampaignError(ValueError):
    pass


def _campaign_findings(manifest: dict[str, Any]) -> list[str]:
    findings: list[str] = []
    metadata = manifest.get("metadata")
    if not isinstance(metadata, dict):
        return ["manifest is missing campaign metadata"]
    revision = metadata.get("source_revision")
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40,64}", revision):
        findings.append("metadata.source_revision must be a full Git commit hash")
    if metadata.get("working_tree_clean") is not True:
        findings.append("metadata must affirm a clean working tree")
    kind = metadata.get("campaign_kind")
    if kind == "diagnostic":
        findings.append("diagnostic campaigns cannot establish primary acceptance")
    elif kind is not None and kind != "primary":
        findings.append("metadata.campaign_kind is unsupported")
    if metadata.get("inputs_unchanged") is False or (
        kind == "primary" and metadata.get("inputs_unchanged") is not True
    ):
        findings.append("campaign inputs must remain unchanged throughout execution")
    execution = manifest.get("execution")
    if execution is not None or kind is not None:
        if not isinstance(execution, dict):
            findings.append("campaign execution metadata is missing")
        else:
            if execution.get("status") != "completed":
                findings.append("campaign execution did not complete")
            exit_code = execution.get("driver_exit_code")
            if isinstance(exit_code, bool) or not isinstance(exit_code, int) or exit_code != 0:
                findings.append("campaign execution driver did not exit successfully")
            if execution.get("process_group_stopped") is not True:
                findings.append("campaign execution did not confirm process teardown")
            for run in [*manifest.get("warmup_runs", []), *manifest.get("measured_runs", [])]:
                if not isinstance(run, dict) or run.get("status") != "completed":
                    findings.append("campaign execution contains an incomplete pass")
                    break
                order, completed = run.get("order"), run.get("rows_completed")
                if not isinstance(order, list) or isinstance(completed, bool) or (
                    not isinstance(completed, int) or completed != len(order)
                ):
                    findings.append("campaign execution pass has an incomplete report count")
                    break
    if kind == "primary":
        cases = manifest.get("cases")
        expected = set(itertools.product(
            ("rpc", "pubsub"), ("rawsocket", "websocket"), (False, True),
            ("dart", "native"), ("values", "native_buffer", "pre_encoded_span"),
        ))
        fields = ("mode", "transport", "secure_transport", "client_impl", "construction")
        actual = [tuple(case.get(field) for field in fields) for case in cases
                  if isinstance(case, dict)] if isinstance(cases, list) else []
        valid_types = all(type(item[2]) is bool and all(
            isinstance(item[index], str) for index in (0, 1, 3, 4)
        ) for item in actual)
        if len(actual) != 48 or not valid_types or set(actual) != expected:
            findings.append("primary campaign matrix must contain all 48 distinct declared cases")
        for key in ("router_config_sha256", "policy_sha256"):
            if not isinstance(metadata.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", metadata[key]):
                findings.append(f"primary metadata.{key} must be a SHA-256 hash")
        artifacts = metadata.get("artifacts_sha256")
        for key in ("driver", "native_library"):
            digest = artifacts.get(key) if isinstance(artifacts, dict) else None
            if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                findings.append(f"primary metadata.artifacts_sha256.{key} must be a SHA-256 hash")
    for key in ("scenario_sha256",):
        if not isinstance(metadata.get(key), str) or not re.fullmatch(
            r"[0-9a-f]{64}", metadata[key]
        ):
            findings.append(f"metadata.{key} must be a SHA-256 hash")
    lock_hashes = metadata.get("lockfiles_sha256")
    if not isinstance(lock_hashes, dict) or not lock_hashes:
        findings.append("metadata.lockfiles_sha256 must contain dependency lock hashes")
    elif any(
        not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value)
        for value in lock_hashes.values()
    ):
        findings.append("metadata.lockfiles_sha256 contains an invalid SHA-256 hash")
    platform = metadata.get("platform")
    required_platform = (
        "os",
        "kernel",
        "cpu_model",
        "logical_cpu_count",
        "runner_image",
        "dart_version",
        "rustc_version",
    )
    if not isinstance(platform, dict):
        findings.append("metadata.platform is missing")
    else:
        for key in required_platform:
            value = platform.get(key)
            if value is None or (isinstance(value, str) and not value.strip()):
                findings.append(f"metadata.platform.{key} is missing")
        os_name = platform.get("os")
        if isinstance(os_name, str) and os_name.strip().lower() != "linux":
            findings.append(
                "metadata.platform.os must be Linux because process CPU and RSS "
                "evidence uses /proc"
            )
    load_average = metadata.get("load_average")
    if not isinstance(load_average, list) or len(load_average) != 3 or any(
        not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0
        for value in load_average
    ):
        findings.append("metadata.load_average must record the host's 1, 5 and 15 minute load")

    previous_end: datetime | None = None
    ordered_runs = [*manifest.get("warmup_runs", []), *manifest.get("measured_runs", [])]
    for index, run in enumerate(ordered_runs, start=1):
        if not isinstance(run, dict):
            findings.append(f"campaign run {index} metadata is invalid")
            continue
        try:
            start = datetime.fromisoformat(run["started_at_utc"].replace("Z", "+00:00"))
            end = datetime.fromisoformat(run["completed_at_utc"].replace("Z", "+00:00"))
        except (KeyError, AttributeError, ValueError):
            findings.append(f"campaign run {index} is missing UTC start/end timestamps")
            continue
        if start.tzinfo is None or end.tzinfo is None or end <= start:
            findings.append(f"campaign run {index} has invalid UTC start/end timestamps")
        if previous_end is not None and start < previous_end:
            findings.append(f"campaign run {index} overlaps the preceding run")
        previous_end = end
    return findings


def _finite_number(value: Any, label: str, *, allow_zero: bool = True) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CampaignError(f"{label} must be numeric")
    number = float(value)
    if not math.isfinite(number) or number < 0 or (not allow_zero and number == 0):
        raise CampaignError(f"{label} must be a finite positive value")
    return number


def _percentile(values: list[float], quantile: float) -> float:
    """Return the nearest-rank percentile used for per-run latency."""
    if not values:
        raise CampaignError("cannot compute a percentile from an empty sample")
    ordered = sorted(values)
    index = max(0, math.ceil(quantile * len(ordered)) - 1)
    return ordered[index]


def _interpolated_percentile(values: list[float], quantile: float) -> float:
    if not values:
        raise CampaignError("cannot compute a percentile from an empty distribution")
    ordered = sorted(values)
    position = (len(ordered) - 1) * quantile
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] * (1 - fraction) + ordered[upper] * fraction


def _bootstrap_median_ci(
    paired_ratios: list[float], *, resamples: int, seed: int, confidence: float
) -> tuple[float, float]:
    if len(paired_ratios) < 2:
        raise CampaignError("at least two paired repetitions are required for a CI")
    rng = random.Random(seed)
    medians = [
        statistics.median(rng.choices(paired_ratios, k=len(paired_ratios)))
        for _ in range(resamples)
    ]
    tail = (1.0 - confidence) / 2.0
    return (
        _interpolated_percentile(medians, tail),
        _interpolated_percentile(medians, 1.0 - tail),
    )


def _load_jsonl(path: Path) -> tuple[list[dict[str, Any]], list[str]]:
    reports: list[dict[str, Any]] = []
    order: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise CampaignError(f"cannot read results file {path}: {error}") from error
    for line_number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            report = json.loads(line)
        except json.JSONDecodeError as error:
            raise CampaignError(f"invalid JSON at {path}:{line_number}: {error}") from error
        if not isinstance(report, dict) or not isinstance(report.get("workload"), str):
            raise CampaignError(f"{path}:{line_number} is not a workload report")
        if report["workload"] in order:
            raise CampaignError(
                f"{path} contains duplicate workload {report['workload']!r}"
            )
        order.append(report["workload"])
        reports.append(report)
    if not reports:
        raise CampaignError(f"{path} contains no workload reports")
    return reports, order


def _resolve_results(base_dir: Path, run: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    raw_path = run.get("results")
    if not isinstance(raw_path, str) or not raw_path:
        raise CampaignError("each run must declare a non-empty results path")
    path = (base_dir / raw_path).resolve()
    reports, actual_order = _load_jsonl(path)
    expected_order = run.get("order")
    if not isinstance(expected_order, list) or not all(
        isinstance(item, str) for item in expected_order
    ):
        raise CampaignError(f"run {run.get('index', '?')} must record workload order")
    if actual_order != expected_order:
        raise CampaignError(
            f"run {run.get('index', '?')} report order does not match its recorded schedule"
        )
    return reports, {report["workload"]: report for report in reports}


def _validate_evidence(report: dict[str, Any], *, label: str) -> list[str]:
    missing: list[str] = []
    process_sets: dict[str, dict[str, Any]] = {}
    for process_name in ("client_process_metrics", "server_process_metrics"):
        process_metrics = report.get(process_name)
        if not isinstance(process_metrics, dict):
            missing.append(f"{label}: missing {process_name}")
            continue
        process_sets[process_name] = process_metrics
        for key in PROCESS_IDENTITY_METRICS + PROCESS_METRICS:
            value = process_metrics.get(key)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                missing.append(f"{label}: missing {process_name}.{key}")
            elif not math.isfinite(float(value)) or value < 0:
                missing.append(f"{label}: invalid {process_name}.{key}")
        for key in ("pid", "rss_before_bytes", "current_rss_bytes", "peak_rss_during_bytes"):
            value = process_metrics.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool) and value <= 0:
                missing.append(f"{label}: {process_name}.{key} must be positive")
        user_cpu = process_metrics.get("cpu_user_us_delta")
        system_cpu = process_metrics.get("cpu_system_us_delta")
        if (
            isinstance(user_cpu, (int, float))
            and not isinstance(user_cpu, bool)
            and isinstance(system_cpu, (int, float))
            and not isinstance(system_cpu, bool)
            and user_cpu + system_cpu <= 0
        ):
            missing.append(f"{label}: {process_name} CPU delta must be positive")
        allocated_bytes = process_metrics.get("allocated_bytes_delta")
        if (
            isinstance(allocated_bytes, (int, float))
            and not isinstance(allocated_bytes, bool)
            and allocated_bytes <= 0
        ):
            missing.append(f"{label}: {process_name} allocation delta must be positive")
        current_rss = process_metrics.get("current_rss_bytes")
        peak_rss = process_metrics.get("peak_rss_during_bytes")
        if (
            isinstance(current_rss, (int, float))
            and not isinstance(current_rss, bool)
            and isinstance(peak_rss, (int, float))
            and not isinstance(peak_rss, bool)
            and current_rss > peak_rss
        ):
            missing.append(f"{label}: {process_name} peak RSS is below final live RSS")
        max_rss = process_metrics.get("max_rss_bytes")
        if (
            isinstance(current_rss, (int, float))
            and not isinstance(current_rss, bool)
            and isinstance(max_rss, (int, float))
            and not isinstance(max_rss, bool)
            and current_rss > max_rss
        ):
            missing.append(f"{label}: {process_name} max RSS is below final live RSS")
    client_metrics = process_sets.get("client_process_metrics")
    server_metrics = process_sets.get("server_process_metrics")
    if (
        client_metrics is not None
        and server_metrics is not None
        and client_metrics.get("pid") == server_metrics.get("pid")
    ):
        missing.append(f"{label}: client and server process metrics must use distinct PIDs")

    copy_metrics = report.get("copy_metrics")
    if not isinstance(copy_metrics, dict):
        return missing + [f"{label}: missing copy_metrics"]
    for key in COPY_METRICS:
        value = copy_metrics.get(key)
        if isinstance(value, dict) and value.get("status") == "not_applicable":
            if key == "transport_copy_bytes":
                missing.append(f"{label}: transport_copy_bytes cannot be not_applicable")
            elif key == "e2ee_copy_bytes" and (
                report.get("ppt_scheme") == "wamp"
                or isinstance(report.get("wamp_configuration"), dict)
                and report["wamp_configuration"].get("ppt_scheme") == "wamp"
            ):
                missing.append(f"{label}: encrypted e2ee_copy_bytes cannot be not_applicable")
            elif not isinstance(value.get("reason"), str) or not value["reason"].strip():
                missing.append(f"{label}: {key} not-applicable entry needs a reason")
        elif not isinstance(value, (int, float)) or isinstance(value, bool):
            missing.append(f"{label}: missing copy_metrics.{key}")
        elif not math.isfinite(float(value)) or value < 0:
            missing.append(f"{label}: invalid copy_metrics.{key}")
    transport_copy_bytes = copy_metrics.get("transport_copy_bytes")
    if isinstance(transport_copy_bytes, (int, float)) and not isinstance(
        transport_copy_bytes, bool
    ):
        coverage = copy_metrics.get("coverage")
        if not isinstance(coverage, dict):
            missing.append(f"{label}: missing copy_metrics.coverage")
        elif coverage.get("transport_copy_bytes") != "complete_connectanum_owned_path":
            missing.append(
                f"{label}: transport_copy_bytes requires complete Connectanum-owned-path coverage"
            )
        elif coverage.get("unknown_boundaries") != []:
            missing.append(
                f"{label}: complete transport_copy_bytes coverage cannot have unknown boundaries"
            )
        breakdown = copy_metrics.get("known_own_copy_breakdown")
        processes = ("router", "client") if report.get("client_impl") == "native" else ("router",)
        for process in processes:
            counters = breakdown.get(process) if isinstance(breakdown, dict) else None
            for field in ("io_buffer_front_copy_bytes", "io_buffered_read_copy_bytes"):
                value = counters.get(field) if isinstance(counters, dict) else None
                if (
                    not isinstance(value, (int, float))
                    or isinstance(value, bool)
                    or not math.isfinite(float(value))
                    or value < 0
                ):
                    missing.append(
                        f"{label}: complete transport coverage requires measured {process}.{field}"
                    )
    e2ee_copy_bytes = copy_metrics.get("e2ee_copy_bytes")
    if isinstance(e2ee_copy_bytes, (int, float)) and not isinstance(e2ee_copy_bytes, bool):
        breakdown = copy_metrics.get("e2ee_copy_breakdown")
        if (
            not isinstance(breakdown, dict)
            or breakdown.get("coverage") != "complete_pipeline"
            or breakdown.get("unknown_boundaries") != []
        ):
            missing.append(f"{label}: e2ee_copy_bytes requires complete pipeline coverage without unknown boundaries")
    return missing


def _configuration_findings(report: dict[str, Any], case: dict[str, Any], codec: str,
                            *, label: str, required: bool) -> list[str]:
    configuration = report.get("wamp_configuration")
    if not isinstance(configuration, dict):
        return [f"{label}: missing actual WAMP configuration"] if required else []
    expected = {"serializer": codec}
    findings = []
    if required:
        expected.update({
            "peer_serializer": None, "peer_count": 1,
            "secure_transport": case.get("secure_transport"),
            "ppt_scheme": "x_connectanum_bench_typed", "ppt_serializer": codec,
            "payload_construction": case.get("construction"),
            "ppt_cipher": None, "ppt_keyid": None,
        })
        for field, value in {
            "protocol": f'wamp_{case.get("transport")}_{case.get("mode")}',
            "client_impl": case.get("client_impl"),
            "request_chunk_bytes": 65536, "response_chunk_bytes": 65536,
        }.items():
            if report.get(field) != value:
                findings.append(f"{label}: reported {field} does not match the declared case")
    for field, value in expected.items():
        if field not in configuration or type(configuration[field]) is not type(value) or configuration[field] != value:
            findings.append(f"{label}: actual WAMP {field} does not match the declared case")
    return findings


def _summarize_report(
    report: dict[str, Any], *, min_duration_ms: int, min_samples: int, label: str
) -> tuple[dict[str, float], list[str]]:
    findings = _validate_evidence(report, label=label)
    samples = report.get("samples")
    if not isinstance(samples, list) or not samples:
        raise CampaignError(f"{label}: missing operation samples")
    if len(samples) < min_samples:
        findings.append(
            f"{label}: has {len(samples)} samples; requires at least {min_samples}"
        )
    elapsed_ms = _finite_number(
        report.get("data_window_elapsed_ms"), f"{label}.data_window_elapsed_ms", allow_zero=False
    )
    if elapsed_ms < min_duration_ms:
        findings.append(
            f"{label}: measured window {elapsed_ms:.1f} ms is below {min_duration_ms} ms"
        )

    identities: set[tuple[int, int]] = set()
    per_worker_iterations: dict[int, set[int]] = {}
    latencies: list[float] = []
    request_bytes = 0
    response_bytes = 0
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise CampaignError(f"{label}: sample {index} is not an object")
        worker = sample.get("worker")
        iteration = sample.get("iteration")
        if not isinstance(worker, int) or not isinstance(iteration, int):
            raise CampaignError(f"{label}: sample {index} has invalid identity")
        identity = (worker, iteration)
        if identity in identities:
            findings.append(f"{label}: duplicate worker/iteration identity {identity}")
        identities.add(identity)
        per_worker_iterations.setdefault(worker, set()).add(iteration)
        latencies.append(_finite_number(sample.get("latency_ms"), f"{label}.latency_ms"))
        request_bytes += int(_finite_number(sample.get("request_bytes"), f"{label}.request_bytes"))
        response_bytes += int(_finite_number(sample.get("response_bytes"), f"{label}.response_bytes"))
    for worker, iterations in per_worker_iterations.items():
        if iterations != set(range(len(iterations))):
            findings.append(f"{label}: worker {worker} has a gap in iteration identities")

    throughput_mbps = (
        max(request_bytes, response_bytes) * 8.0 / 1_000_000.0
    ) / (elapsed_ms / 1000.0)
    process_metrics = [
        report.get("client_process_metrics"),
        report.get("server_process_metrics"),
    ]

    def process_value(key: str) -> float:
        total = 0.0
        for process in process_metrics:
            value = process.get(key) if isinstance(process, dict) else None
            if (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(float(value))
                or value < 0
            ):
                return 0.0
            total += float(value)
        return total

    return (
        {
            "throughput_mbps": throughput_mbps,
            "latency_p50_ms": _percentile(latencies, 0.50),
            "latency_p95_ms": _percentile(latencies, 0.95),
            "latency_p99_ms": _percentile(latencies, 0.99),
            "sample_count": float(len(samples)),
            "data_window_elapsed_ms": elapsed_ms,
            "request_bytes_total": float(request_bytes),
            "response_bytes_total": float(response_bytes),
            "cpu_us_per_operation": (
                process_value("cpu_user_us_delta")
                + process_value("cpu_system_us_delta")
            )
            / len(samples),
            "allocated_bytes_per_operation": process_value("allocated_bytes_delta")
            / len(samples),
            "gc_pause_us_per_operation": process_value("gc_pause_us_delta")
            / len(samples),
            "summed_sampled_peak_rss_bytes": process_value("peak_rss_during_bytes"),
        },
        findings,
    )


def _ratio_gate(
    ratios: list[float],
    policy: dict[str, Any],
    *,
    seed: int,
    resamples: int,
    confidence: float,
) -> dict[str, Any]:
    median = statistics.median(ratios)
    ci_low, ci_high = _bootstrap_median_ci(
        ratios,
        resamples=resamples,
        seed=seed,
        confidence=confidence,
    )
    gate = policy["gate"]
    direction = gate["direction"]
    if direction == "higher_is_better":
        passed = median >= float(gate["median_min_ratio"]) and ci_low >= float(
            gate["ci_lower_min_ratio"]
        )
    else:
        passed = median <= float(gate["median_max_ratio"]) and ci_high <= float(
            gate["ci_upper_max_ratio"]
        )
    return {
        "paired_ratios": ratios,
        "median_ratio": median,
        "ci_95_low": ci_low,
        "ci_95_high": ci_high,
        "passed": passed,
    }


def evaluate_campaign(
    manifest: dict[str, Any], base_dir: Path, policy: dict[str, Any]
) -> dict[str, Any]:
    minimum_repetitions = int(policy["minimum_repetitions"])
    minimum_warmups = int(policy["minimum_warmup_runs"])
    min_duration_ms = int(policy["minimum_duration_ms"])
    min_samples = int(policy["minimum_samples_per_run"])
    cases = manifest.get("cases")
    warmups = manifest.get("warmup_runs")
    runs = manifest.get("measured_runs")
    if manifest.get("schema_version") != 1:
        raise CampaignError("manifest schema_version must be 1")
    if manifest.get("overlap_detected") is not False:
        raise CampaignError("manifest must affirm that campaign runs did not overlap")
    if not isinstance(cases, list) or not cases:
        raise CampaignError("manifest must contain at least one comparison case")
    if not isinstance(warmups, list) or len(warmups) < minimum_warmups:
        raise CampaignError(f"campaign requires at least {minimum_warmups} warm-up runs")
    if not isinstance(runs, list) or len(runs) < minimum_repetitions:
        raise CampaignError(
            f"campaign requires at least {minimum_repetitions} measured repetitions"
        )
    if not manifest.get("order_seed"):
        raise CampaignError("manifest must record a non-zero deterministic order_seed")

    findings: list[str] = _campaign_findings(manifest)
    metadata = manifest.get("metadata")
    configuration_required = isinstance(metadata, dict) and metadata.get("campaign_kind") is not None
    loaded_warmups: list[dict[str, dict[str, Any]]] = []
    for run in warmups:
        _, by_name = _resolve_results(base_dir, run)
        loaded_warmups.append(by_name)
    loaded_runs: list[dict[str, dict[str, Any]]] = []
    for expected_index, run in enumerate(runs, start=1):
        if run.get("index") != expected_index:
            raise CampaignError("measured run indices must be consecutive and start at 1")
        _, by_name = _resolve_results(base_dir, run)
        loaded_runs.append(by_name)

    if configuration_required:
        execution = manifest.get("execution")
        observed = execution.get("observed_process_pids") if isinstance(execution, dict) else None
        for process_name in ("client_process_metrics", "server_process_metrics"):
            pids = []
            for by_name in [*loaded_warmups, *loaded_runs]:
                for report in by_name.values():
                    process = report.get(process_name)
                    pid = process.get("pid") if isinstance(process, dict) else None
                    pids.append(pid)
            if not all(type(pid) is int and pid > 0 for pid in pids) or len(set(pids)) != 1:
                findings.append(f"campaign {process_name}.pid must remain stable across warmup and measurement")
            elif not isinstance(observed, dict) or observed.get(process_name) != pids[0]:
                findings.append(f"campaign {process_name}.pid does not match execution attribution")

    results: list[dict[str, Any]] = []
    for case in cases:
        case_id = case.get("id")
        rows = case.get("workloads")
        if not isinstance(case_id, str) or not case_id:
            raise CampaignError("every case must have a non-empty id")
        if not isinstance(rows, dict) or set(rows) != set(CODECS):
            raise CampaignError(f"case {case_id} must map exactly {CODECS} to workload names")
        if len(set(rows.values())) != len(CODECS) or not all(
            isinstance(name, str) and name for name in rows.values()
        ):
            raise CampaignError(f"case {case_id} must use three distinct workload names")
        if not isinstance(case.get("construction"), str):
            raise CampaignError(f"case {case_id} must declare its payload construction")
        for warmup_index, warmup in enumerate(loaded_warmups, start=1):
            missing_warmup_rows = [
                name for name in rows.values() if name not in warmup
            ]
            if missing_warmup_rows:
                findings.append(
                    f"{case_id} warm-up {warmup_index}: missing workloads "
                    + ", ".join(missing_warmup_rows)
                )
            for codec, name in rows.items():
                if name in warmup:
                    findings.extend(_configuration_findings(
                        warmup[name], case, codec,
                        label=f"{case_id} warm-up {warmup_index} {codec}",
                        required=configuration_required,
                    ))

        case_reports: dict[str, list[dict[str, Any]]] = {codec: [] for codec in CODECS}
        for run_index, by_name in enumerate(loaded_runs, start=1):
            for codec in CODECS:
                name = rows[codec]
                report = by_name.get(name)
                if report is None:
                    findings.append(
                        f"{case_id} repetition {run_index}: missing {codec} workload {name}"
                    )
                    continue
                case_reports[codec].append(report)

        # A fixed TOML serializer order is biased. Record and validate a varied,
        # deterministic per-case codec order across measured repetitions.
        codec_orders: list[tuple[str, ...]] = []
        first_counts: Counter[str] = Counter()
        for run_index, run in enumerate(runs, start=1):
            order = run["order"]
            positions = {name: index for index, name in enumerate(order)}
            names = [rows[codec] for codec in CODECS]
            if any(name not in positions for name in names):
                continue
            codec_order = tuple(sorted(CODECS, key=lambda codec: positions[rows[codec]]))
            codec_orders.append(codec_order)
            first_counts[codec_order[0]] += 1
        unique_orders = len(set(codec_orders))
        if unique_orders < 2:
            findings.append(f"{case_id}: serializer order did not vary between repetitions")
        max_order_count = math.ceil(len(runs) / 2)
        if any(count > max_order_count for count in Counter(codec_orders).values()):
            findings.append(f"{case_id}: one serializer order dominates the schedule")
        if any(count == 0 for count in (first_counts[codec] for codec in CODECS)):
            findings.append(f"{case_id}: each codec must appear first at least once")

        summaries: dict[str, list[dict[str, float]]] = {codec: [] for codec in CODECS}
        signatures: dict[str, tuple[Any, ...]] = {}
        for codec in CODECS:
            for run_index, report in enumerate(case_reports[codec], start=1):
                label = f"{case_id} repetition {run_index} {codec}"
                findings.extend(_configuration_findings(
                    report, case, codec, label=label, required=configuration_required,
                ))
                summary, evidence_findings = _summarize_report(
                    report,
                    min_duration_ms=min_duration_ms,
                    min_samples=min_samples,
                    label=label,
                )
                findings.extend(evidence_findings)
                signature = tuple(
                    report.get(field)
                    for field in (
                        "protocol",
                        "client_impl",
                        "concurrency",
                        "iterations",
                        "request_chunk_bytes",
                        "response_chunk_bytes",
                    )
                )
                if codec not in signatures:
                    signatures[codec] = signature
                elif signatures[codec] != signature:
                    findings.append(f"{label}: workload configuration changed between runs")
                summaries[codec].append(summary)

        for codec in CODECS:
            if codec not in signatures:
                continue
            base_signature = signatures[codec]
            for other_codec in CODECS:
                other_signature = signatures.get(other_codec)
                if other_signature is not None and other_signature != base_signature:
                    findings.append(
                        f"{case_id}: {codec} and {other_codec} reports use different workload settings"
                    )

        metric_results: dict[str, Any] = {}
        available_repetitions = min(len(summaries[codec]) for codec in CODECS)
        if available_repetitions != len(runs):
            continue
        evidence: dict[str, list[dict[str, Any]]] = {}
        for codec in CODECS:
            evidence[codec] = []
            for index, report in enumerate(case_reports[codec]):
                summary = summaries[codec][index]
                evidence[codec].append(
                    {
                        "repetition": index + 1,
                        "data_window_elapsed_ms": summary["data_window_elapsed_ms"],
                        "sample_count": int(summary["sample_count"]),
                        "wire_bytes": {
                            "request": int(summary["request_bytes_total"]),
                            "response": int(summary["response_bytes_total"]),
                        },
                        "latency_ms": {
                            "p50": summary["latency_p50_ms"],
                            "p95": summary["latency_p95_ms"],
                            "p99": summary["latency_p99_ms"],
                        },
                        "client_process_metrics": report.get("client_process_metrics"),
                        "server_process_metrics": report.get("server_process_metrics"),
                        "combined_process_resource_metrics": {
                            key: summary[key]
                            for key in RESOURCE_METRICS
                            if key in summary
                        },
                        "copy_metrics": report.get("copy_metrics"),
                        "wamp_configuration": report.get("wamp_configuration"),
                    }
                )
        for metric in ALL_METRICS:
            ratios: list[float] = []
            winner_counts: Counter[str] = Counter()
            observations: list[dict[str, Any]] = []
            for index in range(len(runs)):
                candidate = summaries["flatbuffers"][index][metric]
                cbor = summaries["cbor"][index][metric]
                msgpack = summaries["msgpack"][index][metric]
                if metric == "throughput_mbps":
                    baseline_codec = "cbor" if cbor >= msgpack else "msgpack"
                    baseline = max(cbor, msgpack)
                else:
                    baseline_codec = "cbor" if cbor <= msgpack else "msgpack"
                    baseline = min(cbor, msgpack)
                winner_counts[baseline_codec] += 1
                if baseline <= 0:
                    ratio = 1.0 if candidate == 0 else 1e12
                    findings.append(
                        f"{case_id} repetition {index + 1} {metric}: baseline metric is zero"
                    )
                else:
                    ratio = candidate / baseline
                ratios.append(ratio)
                observations.append(
                    {
                        "repetition": index + 1,
                        "flatbuffers": candidate,
                        "cbor": cbor,
                        "msgpack": msgpack,
                        "best_baseline_codec": baseline_codec,
                        "best_baseline": baseline,
                        "ratio": ratio,
                    }
                )
            metric_policy = policy["metrics"][metric]
            seed_material = f"{policy['random_seed']}:{case_id}:{metric}".encode()
            seed = int.from_bytes(hashlib.sha256(seed_material).digest()[:4], "big")
            gate = _ratio_gate(
                ratios,
                metric_policy,
                seed=seed,
                resamples=int(policy["bootstrap_resamples"]),
                confidence=float(policy["confidence_level"]),
            )
            gate["best_baseline_by_repetition"] = dict(winner_counts)
            gate["observations"] = observations
            metric_results[metric] = gate
            if not gate["passed"]:
                findings.append(
                    f"{case_id} {metric}: paired ratio median {gate['median_ratio']:.4f}, "
                    f"95% CI [{gate['ci_95_low']:.4f}, {gate['ci_95_high']:.4f}] "
                    "misses the declared parity gate"
                )

        if case.get("zero_copy_codecs"):
            for codec in case["zero_copy_codecs"]:
                if codec not in CODECS:
                    raise CampaignError(f"case {case_id} names unknown zero-copy codec {codec}")
                for run_index, report in enumerate(case_reports[codec], start=1):
                    copy_metrics = report.get("copy_metrics")
                    value = copy_metrics.get("optimized_payload_copy_bytes") if isinstance(copy_metrics, dict) else None
                    if value != 0:
                        findings.append(
                            f"{case_id} repetition {run_index} {codec}: optimized payload boundary "
                            f"copied {value!r} bytes; expected zero"
                        )

        results.append(
            {
                "id": case_id,
                "construction": case["construction"],
                "workloads": rows,
                "repetitions": len(runs),
                "codec_orders": [list(order) for order in codec_orders],
                "metrics": metric_results,
                "evidence": evidence,
            }
        )

    return {
        "schema_version": 1,
        "status": "passed" if not findings else "failed",
        "policy": policy,
        "source_manifest": manifest.get("campaign_id"),
        "case_count": len(results),
        "findings": findings,
        "cases": results,
    }


def render_markdown(result: dict[str, Any]) -> str:
    lines = [
        "# WAMP serializer performance comparison",
        "",
        f"Status: **{result['status'].upper()}**",
        "",
        f"Cases analyzed: {result['case_count']}",
        "",
        "| Case | Construction | Metric | Median ratio | Paired 95% CI | Gate |",
        "|---|---|---|---:|---:|---|",
    ]
    for case in result["cases"]:
        for metric, data in case["metrics"].items():
            lines.append(
                f"| {case['id']} | {case['construction']} | {metric} | "
                f"{data['median_ratio']:.4f} | [{data['ci_95_low']:.4f}, "
                f"{data['ci_95_high']:.4f}] | {'PASS' if data['passed'] else 'FAIL'} |"
            )
    lines.extend(["", "## Findings", ""])
    if result["findings"]:
        lines.extend(f"- {finding}" for finding in result["findings"])
    else:
        lines.append("No gate findings.")
    lines.extend(["", "Ratios compare FlatBuffers to the better of CBOR and MessagePack within each paired repetition.", ""])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--policy", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    parser.add_argument("--output-markdown", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        policy = json.loads(args.policy.read_text(encoding="utf-8"))
        result = evaluate_campaign(manifest, args.manifest.parent, policy)
        args.output_json.parent.mkdir(parents=True, exist_ok=True)
        args.output_markdown.parent.mkdir(parents=True, exist_ok=True)
        args.output_json.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        args.output_markdown.write_text(render_markdown(result), encoding="utf-8")
    except (OSError, json.JSONDecodeError, CampaignError, KeyError, TypeError) as error:
        print(f"WAMP serializer comparison failed: {error}", file=sys.stderr)
        return 2
    print(render_markdown(result))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
