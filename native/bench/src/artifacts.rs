use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Serialize;

use crate::report::{
    router_counter_delta, transport_counter_after, transport_counter_delta, WorkloadReport,
};

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct TransportDeltaSummary {
    pub http_events: i64,
    pub goaway_events: i64,
    pub idle_timeout_events: i64,
    pub body_timeout_events: i64,
    pub protocol_error_events: i64,
    pub internal_error_events: i64,
    pub backpressure_events: i64,
    pub backpressure_alerts: i64,
    pub transport_alerts: i64,
    pub goaway_alerts: i64,
    pub idle_timeout_alerts: i64,
    pub body_timeout_alerts: i64,
    pub protocol_error_alerts: i64,
    pub internal_error_alerts: i64,
    pub max_backpressure_depth_after: u64,
    pub active_throttles_after: u64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct WorkloadArtifactSummary {
    pub scenario: String,
    pub workload: String,
    pub protocol: String,
    pub router_workers: u32,
    pub native_runtime_threads: u32,
    pub iterations: u32,
    pub concurrency: u32,
    pub started_at_ms: u128,
    pub completed_at_ms: u128,
    pub elapsed_ms: f64,
    pub sample_count: usize,
    pub latency_avg_ms: f64,
    pub latency_min_ms: f64,
    pub latency_max_ms: f64,
    pub latency_p95_ms: f64,
    pub request_bytes_total: u64,
    pub response_bytes_total: u64,
    pub throughput_mbps: f64,
    pub router_invocations_delta: i64,
    pub router_publications_delta: i64,
    pub scenario_router_invocations_delta: i64,
    pub scenario_router_publications_delta: i64,
    pub transport: TransportDeltaSummary,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ArtifactBundle {
    pub generated_at_ms: u128,
    pub source_results: String,
    pub workloads: Vec<WorkloadArtifactSummary>,
}

pub fn load_reports_from_jsonl(path: &Path) -> Result<Vec<WorkloadReport>> {
    let file =
        fs::File::open(path).with_context(|| format!("failed to open {}", path.display()))?;
    let reader = BufReader::new(file);
    let mut reports = Vec::new();
    for (index, line) in reader.lines().enumerate() {
        let line = line.with_context(|| {
            format!(
                "failed to read JSONL line {} from {}",
                index + 1,
                path.display()
            )
        })?;
        if line.trim().is_empty() {
            continue;
        }
        let report = serde_json::from_str::<WorkloadReport>(&line).with_context(|| {
            format!(
                "failed to parse workload report on line {} from {}",
                index + 1,
                path.display()
            )
        })?;
        reports.push(report);
    }
    Ok(reports)
}

pub fn summarize_reports(reports: &[WorkloadReport]) -> Vec<WorkloadArtifactSummary> {
    reports.iter().map(summarize_report).collect()
}

pub fn summarize_report(report: &WorkloadReport) -> WorkloadArtifactSummary {
    let sample_count = report.samples.len();
    let request_bytes_total = report
        .samples
        .iter()
        .map(|sample| sample.request_bytes)
        .sum();
    let response_bytes_total = report
        .samples
        .iter()
        .map(|sample| sample.response_bytes)
        .sum();
    let elapsed_ms = (report.completed_at_ms.saturating_sub(report.started_at_ms)) as f64;
    let mut latencies = report
        .samples
        .iter()
        .map(|sample| sample.latency_ms)
        .collect::<Vec<_>>();
    latencies.sort_by(|left, right| left.total_cmp(right));
    let latency_avg_ms = if sample_count == 0 {
        0.0
    } else {
        latencies.iter().sum::<f64>() / sample_count as f64
    };
    let latency_min_ms = latencies.first().copied().unwrap_or(0.0);
    let latency_max_ms = latencies.last().copied().unwrap_or(0.0);
    let latency_p95_ms = percentile(&latencies, 0.95);
    let throughput_mbps = if elapsed_ms <= 0.0 {
        0.0
    } else {
        (response_bytes_total as f64 * 8.0 / 1_000_000.0) / (elapsed_ms / 1000.0)
    };

    let scenario_before = report
        .scenario_metrics_before
        .as_ref()
        .unwrap_or(&report.metrics_before);
    let scenario_after = report
        .scenario_metrics_after
        .as_ref()
        .unwrap_or(&report.metrics_after);

    WorkloadArtifactSummary {
        scenario: report.scenario.clone(),
        workload: report.workload.clone(),
        protocol: report.protocol.clone(),
        router_workers: report.router_workers,
        native_runtime_threads: report.native_runtime_threads,
        iterations: report.iterations,
        concurrency: report.concurrency,
        started_at_ms: report.started_at_ms,
        completed_at_ms: report.completed_at_ms,
        elapsed_ms,
        sample_count,
        latency_avg_ms,
        latency_min_ms,
        latency_max_ms,
        latency_p95_ms,
        request_bytes_total,
        response_bytes_total,
        throughput_mbps,
        router_invocations_delta: router_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "total_invocations_dispatched",
        )
        .unwrap_or(0),
        router_publications_delta: router_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "total_publications_routed",
        )
        .unwrap_or(0),
        scenario_router_invocations_delta: router_counter_delta(
            scenario_before,
            scenario_after,
            "total_invocations_dispatched",
        )
        .unwrap_or(0),
        scenario_router_publications_delta: router_counter_delta(
            scenario_before,
            scenario_after,
            "total_publications_routed",
        )
        .unwrap_or(0),
        transport: TransportDeltaSummary {
            http_events: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "total_events",
            )
            .unwrap_or(0),
            goaway_events: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "goaway_events",
            )
            .unwrap_or(0),
            idle_timeout_events: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "idle_timeout_events",
            )
            .unwrap_or(0),
            body_timeout_events: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "body_timeout_events",
            )
            .unwrap_or(0),
            protocol_error_events: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "protocol_error_events",
            )
            .unwrap_or(0),
            internal_error_events: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "internal_error_events",
            )
            .unwrap_or(0),
            backpressure_events: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "backpressure_events",
            )
            .unwrap_or(0),
            backpressure_alerts: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "backpressure_alerts",
            )
            .unwrap_or(0),
            transport_alerts: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "transport_alerts",
            )
            .unwrap_or(0),
            goaway_alerts: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "goaway_alerts",
            )
            .unwrap_or(0),
            idle_timeout_alerts: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "idle_timeout_alerts",
            )
            .unwrap_or(0),
            body_timeout_alerts: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "body_timeout_alerts",
            )
            .unwrap_or(0),
            protocol_error_alerts: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "protocol_error_alerts",
            )
            .unwrap_or(0),
            internal_error_alerts: transport_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "internal_error_alerts",
            )
            .unwrap_or(0),
            max_backpressure_depth_after: transport_counter_after(
                &report.metrics_after,
                "max_backpressure_depth",
            )
            .unwrap_or(0),
            active_throttles_after: transport_counter_after(
                &report.metrics_after,
                "active_throttles",
            )
            .unwrap_or(0),
        },
    }
}

pub fn render_prometheus_metrics(
    source_results: &str,
    summaries: &[WorkloadArtifactSummary],
) -> String {
    let mut output = String::new();
    output.push_str(
        "# HELP connectanum_bench_artifact_info Artifact bundle metadata for transformed bench results\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_info gauge\n");
    output.push_str(&format!(
        "connectanum_bench_artifact_info{} 1\n",
        format_labels(&[("source_results", source_results)])
    ));
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_samples Number of samples recorded for a workload\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_samples gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_elapsed_ms Total wall-clock time spent running a workload\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_elapsed_ms gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_latency_avg_ms Average workload latency\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_latency_avg_ms gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_latency_min_ms Minimum workload latency\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_latency_min_ms gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_latency_max_ms Maximum workload latency\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_latency_max_ms gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_latency_p95_ms P95 workload latency\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_latency_p95_ms gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_throughput_mbps Approximate workload response throughput in megabits per second\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_throughput_mbps gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_request_bytes_total Total uploaded bytes recorded for a workload\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_request_bytes_total gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_response_bytes_total Total downloaded bytes recorded for a workload\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_response_bytes_total gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_router_delta_total Router counter deltas recorded during a workload\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_router_delta_total gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_scenario_router_delta_total Scenario-level router counter deltas observed up to the end of a workload\n",
    );
    output
        .push_str("# TYPE connectanum_bench_artifact_workload_scenario_router_delta_total gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_transport_delta_total Transport and alert deltas recorded during a workload\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_transport_delta_total gauge\n");
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_transport_after Transport gauge values observed after a workload\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_transport_after gauge\n");

    for summary in summaries {
        let router_workers = summary.router_workers.to_string();
        let native_runtime_threads = native_runtime_threads_label(summary.native_runtime_threads);
        let base_labels = [
            ("scenario", summary.scenario.as_str()),
            ("workload", summary.workload.as_str()),
            ("protocol", summary.protocol.as_str()),
            ("router_workers", router_workers.as_str()),
            ("native_runtime_threads", native_runtime_threads.as_str()),
        ];
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_samples{} {}\n",
            format_labels(&base_labels),
            summary.sample_count
        ));
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_elapsed_ms{} {}\n",
            format_labels(&base_labels),
            summary.elapsed_ms
        ));
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_latency_avg_ms{} {}\n",
            format_labels(&base_labels),
            summary.latency_avg_ms
        ));
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_latency_min_ms{} {}\n",
            format_labels(&base_labels),
            summary.latency_min_ms
        ));
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_latency_max_ms{} {}\n",
            format_labels(&base_labels),
            summary.latency_max_ms
        ));
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_latency_p95_ms{} {}\n",
            format_labels(&base_labels),
            summary.latency_p95_ms
        ));
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_throughput_mbps{} {}\n",
            format_labels(&base_labels),
            summary.throughput_mbps
        ));
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_request_bytes_total{} {}\n",
            format_labels(&base_labels),
            summary.request_bytes_total
        ));
        output.push_str(&format!(
            "connectanum_bench_artifact_workload_response_bytes_total{} {}\n",
            format_labels(&base_labels),
            summary.response_bytes_total
        ));

        for (counter, value) in [
            ("invocations_dispatched", summary.router_invocations_delta),
            ("publications_routed", summary.router_publications_delta),
        ] {
            output.push_str(&format!(
                "connectanum_bench_artifact_workload_router_delta_total{} {}\n",
                format_labels_with_extra(&base_labels, &[("counter", counter)]),
                value
            ));
        }
        for (counter, value) in [
            (
                "invocations_dispatched",
                summary.scenario_router_invocations_delta,
            ),
            (
                "publications_routed",
                summary.scenario_router_publications_delta,
            ),
        ] {
            output.push_str(&format!(
                "connectanum_bench_artifact_workload_scenario_router_delta_total{} {}\n",
                format_labels_with_extra(&base_labels, &[("counter", counter)]),
                value
            ));
        }
        for (kind, value) in [
            ("http_events", summary.transport.http_events),
            ("goaway_events", summary.transport.goaway_events),
            ("idle_timeout_events", summary.transport.idle_timeout_events),
            ("body_timeout_events", summary.transport.body_timeout_events),
            (
                "protocol_error_events",
                summary.transport.protocol_error_events,
            ),
            (
                "internal_error_events",
                summary.transport.internal_error_events,
            ),
            ("backpressure_events", summary.transport.backpressure_events),
            ("backpressure_alerts", summary.transport.backpressure_alerts),
            ("transport_alerts", summary.transport.transport_alerts),
            ("goaway_alerts", summary.transport.goaway_alerts),
            ("idle_timeout_alerts", summary.transport.idle_timeout_alerts),
            ("body_timeout_alerts", summary.transport.body_timeout_alerts),
            (
                "protocol_error_alerts",
                summary.transport.protocol_error_alerts,
            ),
            (
                "internal_error_alerts",
                summary.transport.internal_error_alerts,
            ),
        ] {
            output.push_str(&format!(
                "connectanum_bench_artifact_workload_transport_delta_total{} {}\n",
                format_labels_with_extra(&base_labels, &[("kind", kind)]),
                value
            ));
        }
        for (kind, value) in [
            (
                "max_backpressure_depth",
                summary.transport.max_backpressure_depth_after,
            ),
            ("active_throttles", summary.transport.active_throttles_after),
        ] {
            output.push_str(&format!(
                "connectanum_bench_artifact_workload_transport_after{} {}\n",
                format_labels_with_extra(&base_labels, &[("kind", kind)]),
                value
            ));
        }
    }

    output
}

fn native_runtime_threads_label(value: u32) -> String {
    if value == 0 {
        "auto".to_string()
    } else {
        value.to_string()
    }
}

pub fn write_artifact_bundle(
    reports: &[WorkloadReport],
    results_path: &Path,
    output_dir: Option<&Path>,
) -> Result<ArtifactBundlePaths> {
    let summaries = summarize_reports(reports);
    let paths = artifact_bundle_paths(results_path, output_dir);
    if let Some(parent) = paths.prometheus.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    if let Some(parent) = paths.summary_json.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }

    let bundle = ArtifactBundle {
        generated_at_ms: now_millis(),
        source_results: results_path.display().to_string(),
        workloads: summaries.clone(),
    };
    let summary_json = serde_json::to_vec_pretty(&bundle).context("failed to encode summary")?;
    fs::write(&paths.summary_json, summary_json)
        .with_context(|| format!("failed to write {}", paths.summary_json.display()))?;

    let prom = render_prometheus_metrics(&bundle.source_results, &summaries);
    let mut file = fs::File::create(&paths.prometheus)
        .with_context(|| format!("failed to create {}", paths.prometheus.display()))?;
    file.write_all(prom.as_bytes())
        .with_context(|| format!("failed to write {}", paths.prometheus.display()))?;

    Ok(paths)
}

pub fn artifact_bundle_paths(
    results_path: &Path,
    output_dir: Option<&Path>,
) -> ArtifactBundlePaths {
    let base_dir = output_dir
        .map(Path::to_path_buf)
        .or_else(|| results_path.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."));
    let stem = results_path
        .file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("bench_results");
    ArtifactBundlePaths {
        summary_json: base_dir.join(format!("{stem}.summary.json")),
        prometheus: base_dir.join(format!("{stem}.prom")),
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ArtifactBundlePaths {
    pub summary_json: PathBuf,
    pub prometheus: PathBuf,
}

fn percentile(values: &[f64], percentile: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let index = ((values.len() - 1) as f64 * percentile).round() as usize;
    values[index.min(values.len() - 1)]
}

fn format_labels(labels: &[(&str, &str)]) -> String {
    format_labels_with_extra(labels, &[])
}

fn format_labels_with_extra(base: &[(&str, &str)], extra: &[(&str, &str)]) -> String {
    let joined = base
        .iter()
        .chain(extra.iter())
        .map(|(key, value)| format!(r#"{key}="{}""#, escape_label(value)))
        .collect::<Vec<_>>()
        .join(",");
    format!("{{{joined}}}")
}

fn escape_label(value: &str) -> String {
    value
        .replace('\\', r"\\")
        .replace('\n', r"\n")
        .replace('"', r#"\""#)
}

fn now_millis() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;
    use std::time::{SystemTime, UNIX_EPOCH};

    use serde_json::json;

    use super::*;
    use crate::report::{WorkloadReport, WorkloadSample};

    fn metrics(
        invocations: i64,
        publications: i64,
        transport: serde_json::Value,
    ) -> serde_json::Value {
        json!({
            "metrics": {
                "total_invocations_dispatched": invocations,
                "total_publications_routed": publications,
                "transport": transport,
            }
        })
    }

    fn sample_report() -> WorkloadReport {
        WorkloadReport {
            scenario: "full_stack".to_string(),
            workload: "load".to_string(),
            protocol: "h2".to_string(),
            router_workers: 3,
            native_runtime_threads: 4,
            iterations: 4,
            concurrency: 2,
            started_at_ms: 1_000,
            completed_at_ms: 2_000,
            metrics_before: metrics(
                10,
                20,
                json!({
                    "total_events": 100,
                    "goaway_events": 1,
                    "idle_timeout_events": 2,
                    "body_timeout_events": 3,
                    "protocol_error_events": 4,
                    "internal_error_events": 5,
                    "backpressure_events": 6,
                    "backpressure_alerts": 1,
                    "transport_alerts": 2,
                    "goaway_alerts": 3,
                    "idle_timeout_alerts": 4,
                    "body_timeout_alerts": 5,
                    "protocol_error_alerts": 6,
                    "internal_error_alerts": 7,
                    "max_backpressure_depth": 8,
                    "active_throttles": 0,
                }),
            ),
            metrics_after: metrics(
                15,
                29,
                json!({
                    "total_events": 130,
                    "goaway_events": 3,
                    "idle_timeout_events": 2,
                    "body_timeout_events": 4,
                    "protocol_error_events": 4,
                    "internal_error_events": 8,
                    "backpressure_events": 10,
                    "backpressure_alerts": 2,
                    "transport_alerts": 5,
                    "goaway_alerts": 4,
                    "idle_timeout_alerts": 4,
                    "body_timeout_alerts": 6,
                    "protocol_error_alerts": 6,
                    "internal_error_alerts": 9,
                    "max_backpressure_depth": 11,
                    "active_throttles": 1,
                }),
            ),
            open_metrics_before: None,
            open_metrics_after: None,
            scenario_metrics_before: Some(metrics(
                8,
                18,
                json!({
                    "total_events": 90,
                    "goaway_events": 1,
                    "idle_timeout_events": 2,
                    "body_timeout_events": 3,
                    "protocol_error_events": 4,
                    "internal_error_events": 5,
                    "backpressure_events": 6,
                    "backpressure_alerts": 1,
                    "transport_alerts": 2,
                    "goaway_alerts": 3,
                    "idle_timeout_alerts": 4,
                    "body_timeout_alerts": 5,
                    "protocol_error_alerts": 6,
                    "internal_error_alerts": 7,
                    "max_backpressure_depth": 8,
                    "active_throttles": 0,
                }),
            )),
            scenario_metrics_after: Some(metrics(
                15,
                29,
                json!({
                    "total_events": 130,
                    "goaway_events": 3,
                    "idle_timeout_events": 2,
                    "body_timeout_events": 4,
                    "protocol_error_events": 4,
                    "internal_error_events": 8,
                    "backpressure_events": 10,
                    "backpressure_alerts": 2,
                    "transport_alerts": 5,
                    "goaway_alerts": 4,
                    "idle_timeout_alerts": 4,
                    "body_timeout_alerts": 6,
                    "protocol_error_alerts": 6,
                    "internal_error_alerts": 9,
                    "max_backpressure_depth": 11,
                    "active_throttles": 1,
                }),
            )),
            scenario_open_metrics_before: None,
            scenario_open_metrics_after: None,
            samples: vec![
                WorkloadSample {
                    worker: 0,
                    iteration: 0,
                    latency_ms: 10.0,
                    request_bytes: 100,
                    response_bytes: 200,
                },
                WorkloadSample {
                    worker: 1,
                    iteration: 1,
                    latency_ms: 20.0,
                    request_bytes: 100,
                    response_bytes: 400,
                },
                WorkloadSample {
                    worker: 1,
                    iteration: 2,
                    latency_ms: 30.0,
                    request_bytes: 100,
                    response_bytes: 600,
                },
            ],
        }
    }

    #[test]
    fn summarize_report_computes_latency_and_deltas() {
        let summary = summarize_report(&sample_report());
        assert_eq!(summary.sample_count, 3);
        assert_eq!(summary.router_workers, 3);
        assert_eq!(summary.native_runtime_threads, 4);
        assert_eq!(summary.request_bytes_total, 300);
        assert_eq!(summary.response_bytes_total, 1200);
        assert_eq!(summary.router_invocations_delta, 5);
        assert_eq!(summary.router_publications_delta, 9);
        assert_eq!(summary.scenario_router_invocations_delta, 7);
        assert_eq!(summary.scenario_router_publications_delta, 11);
        assert_eq!(summary.transport.http_events, 30);
        assert_eq!(summary.transport.goaway_events, 2);
        assert_eq!(summary.transport.backpressure_events, 4);
        assert_eq!(summary.transport.transport_alerts, 3);
        assert_eq!(summary.transport.active_throttles_after, 1);
        assert_eq!(summary.transport.max_backpressure_depth_after, 11);
        assert!((summary.latency_avg_ms - 20.0).abs() < f64::EPSILON);
        assert!((summary.latency_p95_ms - 30.0).abs() < f64::EPSILON);
    }

    #[test]
    fn render_prometheus_metrics_contains_expected_series() {
        let text =
            render_prometheus_metrics("bench_results.jsonl", &[summarize_report(&sample_report())]);
        assert!(text.contains("connectanum_bench_artifact_workload_latency_avg_ms"));
        assert!(text.contains("scenario=\"full_stack\""));
        assert!(text.contains("workload=\"load\""));
        assert!(text.contains("router_workers=\"3\""));
        assert!(text.contains("native_runtime_threads=\"4\""));
        assert!(text.contains("kind=\"active_throttles\""));
        assert!(text.contains("counter=\"invocations_dispatched\""));
    }

    #[test]
    fn artifact_bundle_paths_use_results_stem() {
        let paths = artifact_bundle_paths(
            Path::new("native/bench/artifacts/bench_results.jsonl"),
            Some(Path::new("native/bench/artifacts")),
        );
        assert_eq!(
            paths.prometheus,
            PathBuf::from("native/bench/artifacts/bench_results.prom")
        );
        assert_eq!(
            paths.summary_json,
            PathBuf::from("native/bench/artifacts/bench_results.summary.json")
        );
    }

    #[test]
    fn load_reports_from_jsonl_reads_multiple_rows() {
        let temp_dir = unique_temp_dir("load_jsonl");
        fs::create_dir_all(&temp_dir).unwrap();
        let path = temp_dir.join("bench_results.jsonl");
        let report = sample_report();
        let line = serde_json::to_string(&report).unwrap();
        fs::write(&path, format!("{line}\n{line}\n")).unwrap();

        let loaded = load_reports_from_jsonl(&path).unwrap();
        assert_eq!(loaded, vec![report.clone(), report]);

        fs::remove_dir_all(&temp_dir).unwrap();
    }

    #[test]
    fn write_artifact_bundle_emits_summary_and_prometheus_files() {
        let temp_dir = unique_temp_dir("write_bundle");
        let results_path = temp_dir.join("bench_results.jsonl");
        let output_dir = temp_dir.join("artifacts");
        fs::create_dir_all(&output_dir).unwrap();
        fs::write(&results_path, "").unwrap();

        let paths =
            write_artifact_bundle(&[sample_report()], &results_path, Some(&output_dir)).unwrap();

        let summary_json = fs::read_to_string(&paths.summary_json).unwrap();
        let prometheus = fs::read_to_string(&paths.prometheus).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&summary_json).unwrap();
        assert_eq!(
            parsed
                .get("source_results")
                .and_then(serde_json::Value::as_str),
            Some(results_path.to_string_lossy().as_ref())
        );
        assert_eq!(
            parsed["workloads"][0]["scenario"]
                .as_str()
                .unwrap_or_default(),
            "full_stack"
        );
        assert!(prometheus.contains("connectanum_bench_artifact_info"));
        assert!(prometheus.contains("connectanum_bench_artifact_workload_transport_after"));

        fs::remove_dir_all(&temp_dir).unwrap();
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("connectanum_bench_{prefix}_{}", unique))
    }
}
