use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use crate::report::{
    bench_http_stream_counter_delta, router_counter_delta, transport_counter_after,
    transport_counter_delta, transport_http_response_stream_counter_delta, HttpConnectionUsage,
    HttpNativeResponseStreamSlowPathSummary, HttpNativeResponseStreamTimingSummary,
    HttpPhaseTimingSummary, HttpServerEmissionTimingSummary, WorkloadReport,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WorkloadArtifactSummary {
    pub scenario: String,
    pub workload: String,
    pub protocol: String,
    pub client_impl: String,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub http_connection_usage: Option<HttpConnectionUsageSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub http_phase_timing: Option<HttpPhaseTimingSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub http_server_emission_timing: Option<HttpServerEmissionTimingSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub http_native_response_stream_timing: Option<HttpNativeResponseStreamTimingSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub http_native_response_stream_slow_path: Option<HttpNativeResponseStreamSlowPathSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HttpConnectionUsageSummary {
    pub reuse_connections: bool,
    pub streams_per_connection: u32,
    pub connections_opened: u32,
    pub samples_per_connection_avg: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
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

pub fn load_artifact_bundle(path: &Path) -> Result<ArtifactBundle> {
    let bytes = fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_slice(&bytes).with_context(|| format!("failed to parse {}", path.display()))
}

pub fn load_artifact_gate_policy(path: &Path) -> Result<ArtifactGatePolicy> {
    let bytes = fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_slice(&bytes)
        .with_context(|| format!("failed to parse artifact gate policy {}", path.display()))
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactGateSeverity {
    Warning,
    Critical,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactGateMetricComparison {
    Min,
    Max,
}

const THROUGHPUT_MBPS_MIN: &str = "throughput_mbps_min";
const LATENCY_P95_MS_MAX: &str = "latency_p95_ms_max";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ArtifactGateFinding {
    pub severity: ArtifactGateSeverity,
    pub scenario: String,
    pub workload: String,
    pub protocol: String,
    pub client_impl: String,
    pub router_workers: u32,
    pub native_runtime_threads: u32,
    pub kind: String,
    pub observed: u64,
    pub threshold: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ArtifactGateMetricFinding {
    pub severity: ArtifactGateSeverity,
    pub scenario: String,
    pub workload: String,
    pub protocol: String,
    pub client_impl: String,
    pub router_workers: u32,
    pub native_runtime_threads: u32,
    pub kind: String,
    pub observed: f64,
    pub threshold: f64,
    pub comparison: ArtifactGateMetricComparison,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ArtifactGateReport {
    pub generated_at_ms: u128,
    pub source_summary: String,
    pub source_results: String,
    pub workload_count: usize,
    pub findings: Vec<ArtifactGateFinding>,
    #[serde(default)]
    pub metric_findings: Vec<ArtifactGateMetricFinding>,
}

impl ArtifactGateReport {
    pub fn failed(&self) -> bool {
        self.finding_count() > 0
    }

    pub fn finding_count(&self) -> usize {
        self.findings.len() + self.metric_findings.len()
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ArtifactGatePolicy {
    #[serde(default)]
    pub thresholds: Vec<ArtifactGateThreshold>,
    #[serde(default)]
    pub metrics: Vec<ArtifactGateMetricThreshold>,
}

impl ArtifactGatePolicy {
    pub fn threshold_for(&self, workload: &WorkloadArtifactSummary, kind: &str) -> u64 {
        let mut best: Option<(usize, u64)> = None;
        for threshold in &self.thresholds {
            if !threshold.matches(workload, kind) {
                continue;
            }

            let specificity = threshold.specificity();
            match best {
                None => best = Some((specificity, threshold.threshold)),
                Some((best_specificity, best_threshold)) => {
                    if specificity > best_specificity
                        || (specificity == best_specificity && threshold.threshold > best_threshold)
                    {
                        best = Some((specificity, threshold.threshold));
                    }
                }
            }
        }

        best.map(|(_, threshold)| threshold).unwrap_or(0)
    }

    pub fn metric_threshold_for(
        &self,
        workload: &WorkloadArtifactSummary,
        kind: &str,
    ) -> Option<f64> {
        let comparison = metric_kind_comparison(kind)?;
        let mut best: Option<(usize, f64)> = None;
        for threshold in &self.metrics {
            if !threshold.matches(workload, kind) || !threshold.threshold.is_finite() {
                continue;
            }

            let specificity = threshold.specificity();
            match best {
                None => best = Some((specificity, threshold.threshold)),
                Some((best_specificity, best_threshold)) => {
                    if specificity > best_specificity
                        || (specificity == best_specificity
                            && metric_threshold_is_more_permissive(
                                threshold.threshold,
                                best_threshold,
                                comparison,
                            ))
                    {
                        best = Some((specificity, threshold.threshold));
                    }
                }
            }
        }

        best.map(|(_, threshold)| threshold)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ArtifactGateThreshold {
    pub kind: String,
    pub threshold: u64,
    #[serde(default)]
    pub scenario: Option<String>,
    #[serde(default)]
    pub workload: Option<String>,
    #[serde(default)]
    pub protocol: Option<String>,
    #[serde(default)]
    pub client_impl: Option<String>,
    #[serde(default)]
    pub router_workers: Option<u32>,
    #[serde(default)]
    pub native_runtime_threads: Option<u32>,
}

impl ArtifactGateThreshold {
    fn matches(&self, workload: &WorkloadArtifactSummary, kind: &str) -> bool {
        self.kind == kind
            && self.matches_str(self.scenario.as_deref(), &workload.scenario)
            && self.matches_str(self.workload.as_deref(), &workload.workload)
            && self.matches_str(self.protocol.as_deref(), &workload.protocol)
            && self.matches_str(self.client_impl.as_deref(), &workload.client_impl)
            && self
                .router_workers
                .map(|expected| expected == workload.router_workers)
                .unwrap_or(true)
            && self
                .native_runtime_threads
                .map(|expected| expected == workload.native_runtime_threads)
                .unwrap_or(true)
    }

    fn matches_str(&self, expected: Option<&str>, actual: &str) -> bool {
        expected.map(|expected| expected == actual).unwrap_or(true)
    }

    fn specificity(&self) -> usize {
        [
            self.scenario.is_some(),
            self.workload.is_some(),
            self.protocol.is_some(),
            self.client_impl.is_some(),
            self.router_workers.is_some(),
            self.native_runtime_threads.is_some(),
        ]
        .into_iter()
        .filter(|specified| *specified)
        .count()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ArtifactGateMetricThreshold {
    pub kind: String,
    pub threshold: f64,
    #[serde(default)]
    pub scenario: Option<String>,
    #[serde(default)]
    pub workload: Option<String>,
    #[serde(default)]
    pub protocol: Option<String>,
    #[serde(default)]
    pub client_impl: Option<String>,
    #[serde(default)]
    pub router_workers: Option<u32>,
    #[serde(default)]
    pub native_runtime_threads: Option<u32>,
}

impl ArtifactGateMetricThreshold {
    fn matches(&self, workload: &WorkloadArtifactSummary, kind: &str) -> bool {
        self.kind == kind
            && self.matches_str(self.scenario.as_deref(), &workload.scenario)
            && self.matches_str(self.workload.as_deref(), &workload.workload)
            && self.matches_str(self.protocol.as_deref(), &workload.protocol)
            && self.matches_str(self.client_impl.as_deref(), &workload.client_impl)
            && self
                .router_workers
                .map(|expected| expected == workload.router_workers)
                .unwrap_or(true)
            && self
                .native_runtime_threads
                .map(|expected| expected == workload.native_runtime_threads)
                .unwrap_or(true)
    }

    fn matches_str(&self, expected: Option<&str>, actual: &str) -> bool {
        expected.map(|expected| expected == actual).unwrap_or(true)
    }

    fn specificity(&self) -> usize {
        [
            self.scenario.is_some(),
            self.workload.is_some(),
            self.protocol.is_some(),
            self.client_impl.is_some(),
            self.router_workers.is_some(),
            self.native_runtime_threads.is_some(),
        ]
        .into_iter()
        .filter(|specified| *specified)
        .count()
    }
}

pub fn summarize_reports(reports: &[WorkloadReport]) -> Vec<WorkloadArtifactSummary> {
    reports.iter().map(summarize_report).collect()
}

pub fn evaluate_default_artifact_gate(
    bundle: &ArtifactBundle,
    summary_path: &Path,
) -> ArtifactGateReport {
    evaluate_artifact_gate(bundle, summary_path, &ArtifactGatePolicy::default())
}

pub fn evaluate_artifact_gate(
    bundle: &ArtifactBundle,
    summary_path: &Path,
    policy: &ArtifactGatePolicy,
) -> ArtifactGateReport {
    let mut findings = Vec::new();
    let mut metric_findings = Vec::new();
    for workload in &bundle.workloads {
        push_gate_i64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Warning,
            "backpressure_events",
            workload.transport.backpressure_events,
            policy.threshold_for(workload, "backpressure_events"),
        );
        push_gate_i64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Warning,
            "backpressure_alerts",
            workload.transport.backpressure_alerts,
            policy.threshold_for(workload, "backpressure_alerts"),
        );
        push_gate_i64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Warning,
            "transport_alerts",
            workload.transport.transport_alerts,
            policy.threshold_for(workload, "transport_alerts"),
        );
        push_gate_i64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Critical,
            "goaway_alerts",
            workload.transport.goaway_alerts,
            policy.threshold_for(workload, "goaway_alerts"),
        );
        push_gate_i64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Critical,
            "idle_timeout_alerts",
            workload.transport.idle_timeout_alerts,
            policy.threshold_for(workload, "idle_timeout_alerts"),
        );
        push_gate_i64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Critical,
            "body_timeout_alerts",
            workload.transport.body_timeout_alerts,
            policy.threshold_for(workload, "body_timeout_alerts"),
        );
        push_gate_i64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Critical,
            "protocol_error_alerts",
            workload.transport.protocol_error_alerts,
            policy.threshold_for(workload, "protocol_error_alerts"),
        );
        push_gate_i64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Critical,
            "internal_error_alerts",
            workload.transport.internal_error_alerts,
            policy.threshold_for(workload, "internal_error_alerts"),
        );
        push_gate_u64_finding(
            &mut findings,
            workload,
            ArtifactGateSeverity::Critical,
            "active_throttles",
            workload.transport.active_throttles_after,
            policy.threshold_for(workload, "active_throttles"),
        );
        push_gate_metric_finding(
            &mut metric_findings,
            workload,
            ArtifactGateSeverity::Warning,
            THROUGHPUT_MBPS_MIN,
            workload.throughput_mbps,
            policy.metric_threshold_for(workload, THROUGHPUT_MBPS_MIN),
            ArtifactGateMetricComparison::Min,
        );
        push_gate_metric_finding(
            &mut metric_findings,
            workload,
            ArtifactGateSeverity::Warning,
            LATENCY_P95_MS_MAX,
            workload.latency_p95_ms,
            policy.metric_threshold_for(workload, LATENCY_P95_MS_MAX),
            ArtifactGateMetricComparison::Max,
        );
    }

    ArtifactGateReport {
        generated_at_ms: now_millis(),
        source_summary: summary_path.display().to_string(),
        source_results: bundle.source_results.clone(),
        workload_count: bundle.workloads.len(),
        findings,
        metric_findings,
    }
}

pub fn render_artifact_gate_markdown(report: &ArtifactGateReport) -> String {
    let mut lines = vec![
        "# Bench Artifact Gate".to_string(),
        "".to_string(),
        format!("Summary: `{}`", report.source_summary.replace('`', "\\`")),
        format!(
            "Source results: `{}`",
            report.source_results.replace('`', "\\`")
        ),
        format!("Workloads checked: {}", report.workload_count),
        "".to_string(),
    ];

    if !report.failed() {
        lines.push(
            "Gate passed. No transport or performance regressions were detected.".to_string(),
        );
        return lines.join("\n") + "\n";
    }

    lines.push(
        "Gate failed. The transformed bench artifacts captured transport or performance regressions."
            .to_string(),
    );
    if !report.findings.is_empty() {
        lines.push("".to_string());
        lines.push("## Transport Findings".to_string());
        lines.push("".to_string());
        lines.push(
            "| Severity | Scenario | Workload | Protocol | Client | Router workers | Native runtime threads | Kind | Observed | Threshold |"
                .to_string(),
        );
        lines.push("| --- | --- | --- | --- | --- | ---: | ---: | --- | ---: | ---: |".to_string());
        for finding in &report.findings {
            lines.push(format!(
                "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |",
                severity_label(finding.severity),
                finding.scenario,
                finding.workload,
                finding.protocol,
                finding.client_impl,
                finding.router_workers,
                native_runtime_threads_label(finding.native_runtime_threads),
                finding.kind,
                finding.observed,
                finding.threshold,
            ));
        }
    }
    if !report.metric_findings.is_empty() {
        lines.push("".to_string());
        lines.push("## Performance Findings".to_string());
        lines.push("".to_string());
        lines.push(
            "| Severity | Scenario | Workload | Protocol | Client | Router workers | Native runtime threads | Kind | Observed | Threshold | Rule |"
                .to_string(),
        );
        lines.push(
            "| --- | --- | --- | --- | --- | ---: | ---: | --- | ---: | ---: | --- |".to_string(),
        );
        for finding in &report.metric_findings {
            lines.push(format!(
                "| {} | {} | {} | {} | {} | {} | {} | {} | {:.3} | {:.3} | {} |",
                severity_label(finding.severity),
                finding.scenario,
                finding.workload,
                finding.protocol,
                finding.client_impl,
                finding.router_workers,
                native_runtime_threads_label(finding.native_runtime_threads),
                finding.kind,
                finding.observed,
                finding.threshold,
                metric_comparison_label(finding.comparison),
            ));
        }
    }

    lines.join("\n") + "\n"
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
    let http_connection_usage =
        summarize_http_connection_usage(report.http_connection_usage.as_ref(), sample_count);
    let http_phase_timing = summarize_http_phase_timing(&report.samples);
    let http_server_emission_timing = summarize_http_server_emission_timing(report);
    let http_native_response_stream_timing = summarize_http_native_response_stream_timing(report);
    let http_native_response_stream_slow_path =
        summarize_http_native_response_stream_slow_path(report);

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
        client_impl: report.client_impl.clone(),
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
        http_connection_usage,
        http_phase_timing,
        http_server_emission_timing,
        http_native_response_stream_timing,
        http_native_response_stream_slow_path,
    }
}

fn summarize_http_connection_usage(
    usage: Option<&HttpConnectionUsage>,
    sample_count: usize,
) -> Option<HttpConnectionUsageSummary> {
    usage.map(|usage| HttpConnectionUsageSummary {
        reuse_connections: usage.reuse_connections,
        streams_per_connection: usage.streams_per_connection,
        connections_opened: usage.connections_opened,
        samples_per_connection_avg: if usage.connections_opened == 0 {
            0.0
        } else {
            sample_count as f64 / usage.connections_opened as f64
        },
    })
}

fn summarize_http_phase_timing(
    samples: &[crate::report::WorkloadSample],
) -> Option<HttpPhaseTimingSummary> {
    let mut stream_acquire_waits = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.stream_acquire_wait_ms)
        .collect::<Vec<_>>();
    if stream_acquire_waits.is_empty() {
        return None;
    }

    let mut request_enqueue_times = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.request_enqueue_ms)
        .collect::<Vec<_>>();
    let mut response_headers_waits = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.response_headers_wait_ms)
        .collect::<Vec<_>>();
    let mut response_headers_connection_read_waits = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_headers_connection_read_wait_ms)
        .collect::<Vec<_>>();
    let mut response_headers_connection_read_to_headers = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_headers_connection_read_to_headers_ms)
        .collect::<Vec<_>>();
    let mut response_headers_connection_write_waits = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_headers_connection_write_wait_ms)
        .collect::<Vec<_>>();
    let mut response_headers_connection_write_spans = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_headers_connection_write_span_ms)
        .collect::<Vec<_>>();
    let mut response_headers_last_write_to_first_reads = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_headers_last_write_to_first_read_ms)
        .collect::<Vec<_>>();
    let mut response_body_reads = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.response_body_read_ms)
        .collect::<Vec<_>>();
    let mut response_body_first_chunk_waits = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.response_body_first_chunk_wait_ms)
        .collect::<Vec<_>>();
    let mut response_body_tail_reads = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.response_body_tail_read_ms)
        .collect::<Vec<_>>();
    let mut response_body_chunk_counts = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.response_body_chunk_count as f64)
        .collect::<Vec<_>>();
    let mut response_body_first_chunk_bytes = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.response_body_first_chunk_bytes as f64)
        .collect::<Vec<_>>();
    let mut response_body_post_header_connection_read_waits = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_body_post_header_connection_read_wait_ms)
        .collect::<Vec<_>>();
    let mut response_body_connection_read_to_first_chunks = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_body_connection_read_to_first_chunk_ms)
        .collect::<Vec<_>>();
    let mut response_body_tail_connection_read_waits = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_body_tail_connection_read_wait_ms)
        .collect::<Vec<_>>();
    let mut response_body_tail_connection_read_to_ends = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_body_tail_connection_read_to_end_ms)
        .collect::<Vec<_>>();
    let mut request_round_trips = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .map(|timing| timing.request_round_trip_ms)
        .collect::<Vec<_>>();

    stream_acquire_waits.sort_by(|left, right| left.total_cmp(right));
    request_enqueue_times.sort_by(|left, right| left.total_cmp(right));
    response_headers_waits.sort_by(|left, right| left.total_cmp(right));
    response_headers_connection_read_waits.sort_by(|left, right| left.total_cmp(right));
    response_headers_connection_read_to_headers.sort_by(|left, right| left.total_cmp(right));
    response_headers_connection_write_waits.sort_by(|left, right| left.total_cmp(right));
    response_headers_connection_write_spans.sort_by(|left, right| left.total_cmp(right));
    response_headers_last_write_to_first_reads.sort_by(|left, right| left.total_cmp(right));
    response_body_reads.sort_by(|left, right| left.total_cmp(right));
    response_body_first_chunk_waits.sort_by(|left, right| left.total_cmp(right));
    response_body_tail_reads.sort_by(|left, right| left.total_cmp(right));
    response_body_chunk_counts.sort_by(|left, right| left.total_cmp(right));
    response_body_first_chunk_bytes.sort_by(|left, right| left.total_cmp(right));
    response_body_post_header_connection_read_waits.sort_by(|left, right| left.total_cmp(right));
    response_body_connection_read_to_first_chunks.sort_by(|left, right| left.total_cmp(right));
    response_body_tail_connection_read_waits.sort_by(|left, right| left.total_cmp(right));
    response_body_tail_connection_read_to_ends.sort_by(|left, right| left.total_cmp(right));
    request_round_trips.sort_by(|left, right| left.total_cmp(right));

    let stream_acquire_wait_avg_ms =
        stream_acquire_waits.iter().sum::<f64>() / stream_acquire_waits.len() as f64;
    let request_enqueue_avg_ms =
        request_enqueue_times.iter().sum::<f64>() / request_enqueue_times.len() as f64;
    let response_headers_wait_avg_ms =
        response_headers_waits.iter().sum::<f64>() / response_headers_waits.len() as f64;
    let response_headers_connection_read_wait_avg_ms =
        if response_headers_connection_read_waits.is_empty() {
            0.0
        } else {
            response_headers_connection_read_waits.iter().sum::<f64>()
                / response_headers_connection_read_waits.len() as f64
        };
    let response_headers_connection_read_to_headers_avg_ms =
        if response_headers_connection_read_to_headers.is_empty() {
            0.0
        } else {
            response_headers_connection_read_to_headers
                .iter()
                .sum::<f64>()
                / response_headers_connection_read_to_headers.len() as f64
        };
    let response_headers_connection_write_wait_avg_ms =
        if response_headers_connection_write_waits.is_empty() {
            0.0
        } else {
            response_headers_connection_write_waits.iter().sum::<f64>()
                / response_headers_connection_write_waits.len() as f64
        };
    let response_headers_connection_write_span_avg_ms =
        if response_headers_connection_write_spans.is_empty() {
            0.0
        } else {
            response_headers_connection_write_spans.iter().sum::<f64>()
                / response_headers_connection_write_spans.len() as f64
        };
    let response_headers_last_write_to_first_read_avg_ms =
        if response_headers_last_write_to_first_reads.is_empty() {
            0.0
        } else {
            response_headers_last_write_to_first_reads
                .iter()
                .sum::<f64>()
                / response_headers_last_write_to_first_reads.len() as f64
        };
    let response_body_read_avg_ms =
        response_body_reads.iter().sum::<f64>() / response_body_reads.len() as f64;
    let request_round_trip_avg_ms =
        request_round_trips.iter().sum::<f64>() / request_round_trips.len() as f64;

    Some(HttpPhaseTimingSummary {
        stream_acquire_wait_avg_ms,
        stream_acquire_wait_p95_ms: percentile(&stream_acquire_waits, 0.95),
        request_enqueue_avg_ms,
        request_enqueue_p95_ms: percentile(&request_enqueue_times, 0.95),
        response_headers_wait_avg_ms,
        response_headers_wait_p95_ms: percentile(&response_headers_waits, 0.95),
        response_headers_connection_read_wait_samples_total: response_headers_connection_read_waits
            .len() as u64,
        response_headers_connection_read_wait_avg_ms,
        response_headers_connection_read_wait_p95_ms: if response_headers_connection_read_waits
            .is_empty()
        {
            0.0
        } else {
            percentile(&response_headers_connection_read_waits, 0.95)
        },
        response_headers_connection_read_to_headers_samples_total:
            response_headers_connection_read_to_headers.len() as u64,
        response_headers_connection_read_to_headers_avg_ms,
        response_headers_connection_read_to_headers_p95_ms:
            if response_headers_connection_read_to_headers.is_empty() {
                0.0
            } else {
                percentile(&response_headers_connection_read_to_headers, 0.95)
            },
        response_headers_connection_write_wait_samples_total:
            response_headers_connection_write_waits.len() as u64,
        response_headers_connection_write_wait_avg_ms:
            response_headers_connection_write_wait_avg_ms,
        response_headers_connection_write_wait_p95_ms: if response_headers_connection_write_waits
            .is_empty()
        {
            0.0
        } else {
            percentile(&response_headers_connection_write_waits, 0.95)
        },
        response_headers_connection_write_span_samples_total:
            response_headers_connection_write_spans.len() as u64,
        response_headers_connection_write_span_avg_ms:
            response_headers_connection_write_span_avg_ms,
        response_headers_connection_write_span_p95_ms: if response_headers_connection_write_spans
            .is_empty()
        {
            0.0
        } else {
            percentile(&response_headers_connection_write_spans, 0.95)
        },
        response_headers_last_write_to_first_read_samples_total:
            response_headers_last_write_to_first_reads.len() as u64,
        response_headers_last_write_to_first_read_avg_ms:
            response_headers_last_write_to_first_read_avg_ms,
        response_headers_last_write_to_first_read_p95_ms:
            if response_headers_last_write_to_first_reads.is_empty() {
                0.0
            } else {
                percentile(&response_headers_last_write_to_first_reads, 0.95)
            },
        response_body_read_avg_ms,
        response_body_read_p95_ms: percentile(&response_body_reads, 0.95),
        response_body_first_chunk_wait_avg_ms: response_body_first_chunk_waits.iter().sum::<f64>()
            / response_body_first_chunk_waits.len() as f64,
        response_body_first_chunk_wait_p95_ms: percentile(&response_body_first_chunk_waits, 0.95),
        response_body_tail_read_avg_ms: response_body_tail_reads.iter().sum::<f64>()
            / response_body_tail_reads.len() as f64,
        response_body_tail_read_p95_ms: percentile(&response_body_tail_reads, 0.95),
        response_body_chunk_count_avg: response_body_chunk_counts.iter().sum::<f64>()
            / response_body_chunk_counts.len() as f64,
        response_body_chunk_count_p95: percentile(&response_body_chunk_counts, 0.95),
        response_body_first_chunk_bytes_avg: response_body_first_chunk_bytes.iter().sum::<f64>()
            / response_body_first_chunk_bytes.len() as f64,
        response_body_first_chunk_bytes_p95: percentile(&response_body_first_chunk_bytes, 0.95),
        response_body_post_header_connection_read_wait_samples_total:
            response_body_post_header_connection_read_waits.len() as u64,
        response_body_post_header_connection_read_wait_avg_ms:
            if response_body_post_header_connection_read_waits.is_empty() {
                0.0
            } else {
                response_body_post_header_connection_read_waits
                    .iter()
                    .sum::<f64>()
                    / response_body_post_header_connection_read_waits.len() as f64
            },
        response_body_post_header_connection_read_wait_p95_ms:
            if response_body_post_header_connection_read_waits.is_empty() {
                0.0
            } else {
                percentile(&response_body_post_header_connection_read_waits, 0.95)
            },
        response_body_connection_read_to_first_chunk_samples_total:
            response_body_connection_read_to_first_chunks.len() as u64,
        response_body_connection_read_to_first_chunk_avg_ms:
            if response_body_connection_read_to_first_chunks.is_empty() {
                0.0
            } else {
                response_body_connection_read_to_first_chunks
                    .iter()
                    .sum::<f64>()
                    / response_body_connection_read_to_first_chunks.len() as f64
            },
        response_body_connection_read_to_first_chunk_p95_ms:
            if response_body_connection_read_to_first_chunks.is_empty() {
                0.0
            } else {
                percentile(&response_body_connection_read_to_first_chunks, 0.95)
            },
        response_body_tail_connection_read_wait_samples_total:
            response_body_tail_connection_read_waits.len() as u64,
        response_body_tail_connection_read_wait_avg_ms: if response_body_tail_connection_read_waits
            .is_empty()
        {
            0.0
        } else {
            response_body_tail_connection_read_waits.iter().sum::<f64>()
                / response_body_tail_connection_read_waits.len() as f64
        },
        response_body_tail_connection_read_wait_p95_ms: if response_body_tail_connection_read_waits
            .is_empty()
        {
            0.0
        } else {
            percentile(&response_body_tail_connection_read_waits, 0.95)
        },
        response_body_tail_connection_read_to_end_samples_total:
            response_body_tail_connection_read_to_ends.len() as u64,
        response_body_tail_connection_read_to_end_avg_ms:
            if response_body_tail_connection_read_to_ends.is_empty() {
                0.0
            } else {
                response_body_tail_connection_read_to_ends
                    .iter()
                    .sum::<f64>()
                    / response_body_tail_connection_read_to_ends.len() as f64
            },
        response_body_tail_connection_read_to_end_p95_ms:
            if response_body_tail_connection_read_to_ends.is_empty() {
                0.0
            } else {
                percentile(&response_body_tail_connection_read_to_ends, 0.95)
            },
        request_round_trip_avg_ms,
        request_round_trip_p95_ms: percentile(&request_round_trips, 0.95),
    })
}

fn summarize_http_server_emission_timing(
    report: &WorkloadReport,
) -> Option<HttpServerEmissionTimingSummary> {
    let requests_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "requests_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    if requests_total == 0 {
        return None;
    }

    let synthetic_responses_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "synthetic_responses_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let native_forwarded_responses_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "native_forwarded_responses_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let buffered_responses_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "buffered_responses_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let request_body_drain_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "request_body_drain_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let stream_open_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "stream_open_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_chunk_queued_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_chunk_queued_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_body_write_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_body_write_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_body_write_completed_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_body_write_completed_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_to_first_body_write_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_to_first_body_write_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_to_first_body_write_completed_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_to_first_body_write_completed_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let queue_to_first_body_write_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "queue_to_first_body_write_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let queue_to_first_body_write_completed_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "queue_to_first_body_write_completed_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_body_write_call_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_body_write_call_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let direct_stream_open_round_trip_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "direct_stream_open_round_trip_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let direct_stream_request_queue_delay_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "direct_stream_request_queue_delay_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let direct_stream_descriptor_open_call_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "direct_stream_descriptor_open_call_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let direct_stream_reply_delivery_delay_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "direct_stream_reply_delivery_delay_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let handler_samples_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "handler_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;

    let request_body_drain_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "request_body_drain_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let stream_open_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "stream_open_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_chunk_queued_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_chunk_queued_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_body_write_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_body_write_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_body_write_completed_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_body_write_completed_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_to_first_body_write_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_to_first_body_write_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_to_first_body_write_completed_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_to_first_body_write_completed_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let queue_to_first_body_write_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "queue_to_first_body_write_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let queue_to_first_body_write_completed_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "queue_to_first_body_write_completed_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_body_write_call_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_body_write_call_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let direct_stream_open_round_trip_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "direct_stream_open_round_trip_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let direct_stream_request_queue_delay_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "direct_stream_request_queue_delay_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let direct_stream_descriptor_open_call_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "direct_stream_descriptor_open_call_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let direct_stream_reply_delivery_delay_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "direct_stream_reply_delivery_delay_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let handler_us_total = bench_http_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "handler_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;

    Some(HttpServerEmissionTimingSummary {
        requests_total,
        synthetic_responses_total,
        native_forwarded_responses_total,
        buffered_responses_total,
        request_body_drain_avg_ms: average_microseconds_to_millis(
            request_body_drain_us_total,
            request_body_drain_samples_total,
        ),
        stream_open_avg_ms: average_microseconds_to_millis(
            stream_open_us_total,
            stream_open_samples_total,
        ),
        first_chunk_queued_avg_ms: average_microseconds_to_millis(
            first_chunk_queued_us_total,
            first_chunk_queued_samples_total,
        ),
        first_body_write_avg_ms: average_microseconds_to_millis(
            first_body_write_us_total,
            first_body_write_samples_total,
        ),
        first_body_write_completed_avg_ms: average_microseconds_to_millis(
            first_body_write_completed_us_total,
            first_body_write_completed_samples_total,
        ),
        headers_to_first_body_write_avg_ms: average_microseconds_to_millis(
            headers_to_first_body_write_us_total,
            headers_to_first_body_write_samples_total,
        ),
        headers_to_first_body_write_completed_avg_ms: average_microseconds_to_millis(
            headers_to_first_body_write_completed_us_total,
            headers_to_first_body_write_completed_samples_total,
        ),
        queue_to_first_body_write_avg_ms: average_microseconds_to_millis(
            queue_to_first_body_write_us_total,
            queue_to_first_body_write_samples_total,
        ),
        queue_to_first_body_write_completed_avg_ms: average_microseconds_to_millis(
            queue_to_first_body_write_completed_us_total,
            queue_to_first_body_write_completed_samples_total,
        ),
        first_body_write_call_avg_ms: average_microseconds_to_millis(
            first_body_write_call_us_total,
            first_body_write_call_samples_total,
        ),
        direct_stream_open_round_trip_avg_ms: average_microseconds_to_millis(
            direct_stream_open_round_trip_us_total,
            direct_stream_open_round_trip_samples_total,
        ),
        direct_stream_request_queue_delay_avg_ms: average_microseconds_to_millis(
            direct_stream_request_queue_delay_us_total,
            direct_stream_request_queue_delay_samples_total,
        ),
        direct_stream_descriptor_open_call_avg_ms: average_microseconds_to_millis(
            direct_stream_descriptor_open_call_us_total,
            direct_stream_descriptor_open_call_samples_total,
        ),
        direct_stream_reply_delivery_delay_avg_ms: average_microseconds_to_millis(
            direct_stream_reply_delivery_delay_us_total,
            direct_stream_reply_delivery_delay_samples_total,
        ),
        handler_avg_ms: average_microseconds_to_millis(handler_us_total, handler_samples_total),
    })
}

fn summarize_http_native_response_stream_timing(
    report: &WorkloadReport,
) -> Option<HttpNativeResponseStreamTimingSummary> {
    let streaming_responses_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "streaming_responses_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    if streaming_responses_total == 0 {
        return None;
    }

    let stream_open_to_headers_send_samples_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "stream_open_to_headers_send_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let stream_open_to_headers_send_us_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "stream_open_to_headers_send_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_send_call_samples_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_send_call_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_send_call_us_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_send_call_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_to_first_connection_write_samples_total =
        transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "headers_to_first_connection_write_samples_total",
        )
        .unwrap_or(0)
        .max(0) as u64;
    let headers_to_first_connection_write_us_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_to_first_connection_write_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_chunk_channel_wait_samples_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_chunk_channel_wait_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_chunk_channel_wait_us_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_chunk_channel_wait_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_to_first_chunk_dequeue_samples_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_to_first_chunk_dequeue_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_to_first_chunk_dequeue_us_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_to_first_chunk_dequeue_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_chunk_send_call_samples_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_chunk_send_call_samples_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let first_chunk_send_call_us_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "first_chunk_send_call_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    let headers_to_first_chunk_send_call_samples_total =
        transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "headers_to_first_chunk_send_call_samples_total",
        )
        .unwrap_or(0)
        .max(0) as u64;
    let headers_to_first_chunk_send_call_us_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "headers_to_first_chunk_send_call_us_total",
    )
    .unwrap_or(0)
    .max(0) as u64;

    Some(HttpNativeResponseStreamTimingSummary {
        streaming_responses_total,
        stream_open_to_headers_send_avg_ms: average_microseconds_to_millis(
            stream_open_to_headers_send_us_total,
            stream_open_to_headers_send_samples_total,
        ),
        headers_send_call_avg_ms: average_microseconds_to_millis(
            headers_send_call_us_total,
            headers_send_call_samples_total,
        ),
        headers_to_first_connection_write_avg_ms: average_microseconds_to_millis(
            headers_to_first_connection_write_us_total,
            headers_to_first_connection_write_samples_total,
        ),
        first_chunk_channel_wait_avg_ms: average_microseconds_to_millis(
            first_chunk_channel_wait_us_total,
            first_chunk_channel_wait_samples_total,
        ),
        headers_to_first_chunk_dequeue_avg_ms: average_microseconds_to_millis(
            headers_to_first_chunk_dequeue_us_total,
            headers_to_first_chunk_dequeue_samples_total,
        ),
        first_chunk_send_call_avg_ms: average_microseconds_to_millis(
            first_chunk_send_call_us_total,
            first_chunk_send_call_samples_total,
        ),
        headers_to_first_chunk_send_call_avg_ms: average_microseconds_to_millis(
            headers_to_first_chunk_send_call_us_total,
            headers_to_first_chunk_send_call_samples_total,
        ),
    })
}

fn summarize_http_native_response_stream_slow_path(
    report: &WorkloadReport,
) -> Option<HttpNativeResponseStreamSlowPathSummary> {
    let streaming_responses_total = transport_http_response_stream_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "streaming_responses_total",
    )
    .unwrap_or(0)
    .max(0) as u64;
    if streaming_responses_total == 0 {
        return None;
    }

    Some(HttpNativeResponseStreamSlowPathSummary {
        streaming_responses_total,
        headers_to_first_connection_write_ge_1ms_total:
            transport_http_response_stream_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "headers_to_first_connection_write_ge_1ms_total",
            )
            .unwrap_or(0)
            .max(0) as u64,
        headers_to_first_connection_write_ge_5ms_total:
            transport_http_response_stream_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "headers_to_first_connection_write_ge_5ms_total",
            )
            .unwrap_or(0)
            .max(0) as u64,
        headers_to_first_connection_write_ge_10ms_total:
            transport_http_response_stream_counter_delta(
                &report.metrics_before,
                &report.metrics_after,
                "headers_to_first_connection_write_ge_10ms_total",
            )
            .unwrap_or(0)
            .max(0) as u64,
        first_chunk_channel_wait_ge_1ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "first_chunk_channel_wait_ge_1ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
        first_chunk_channel_wait_ge_5ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "first_chunk_channel_wait_ge_5ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
        first_chunk_channel_wait_ge_10ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "first_chunk_channel_wait_ge_10ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
        headers_to_first_chunk_dequeue_ge_1ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "headers_to_first_chunk_dequeue_ge_1ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
        headers_to_first_chunk_dequeue_ge_5ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "headers_to_first_chunk_dequeue_ge_5ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
        headers_to_first_chunk_dequeue_ge_10ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "headers_to_first_chunk_dequeue_ge_10ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
        first_chunk_send_call_ge_1ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "first_chunk_send_call_ge_1ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
        first_chunk_send_call_ge_5ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "first_chunk_send_call_ge_5ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
        first_chunk_send_call_ge_10ms_total: transport_http_response_stream_counter_delta(
            &report.metrics_before,
            &report.metrics_after,
            "first_chunk_send_call_ge_10ms_total",
        )
        .unwrap_or(0)
        .max(0) as u64,
    })
}

fn average_microseconds_to_millis(total_us: u64, sample_count: u64) -> f64 {
    if sample_count == 0 {
        return 0.0;
    }
    total_us as f64 / sample_count as f64 / 1000.0
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
    output.push_str(
        "# HELP connectanum_bench_artifact_workload_http_connection_usage HTTP connection usage observed for a workload\n",
    );
    output.push_str("# TYPE connectanum_bench_artifact_workload_http_connection_usage gauge\n");

    for summary in summaries {
        let router_workers = summary.router_workers.to_string();
        let native_runtime_threads = native_runtime_threads_label(summary.native_runtime_threads);
        let base_labels = [
            ("scenario", summary.scenario.as_str()),
            ("workload", summary.workload.as_str()),
            ("protocol", summary.protocol.as_str()),
            ("client_impl", summary.client_impl.as_str()),
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
        if let Some(connection_usage) = &summary.http_connection_usage {
            for (kind, value) in [
                (
                    "connections_opened",
                    connection_usage.connections_opened as f64,
                ),
                (
                    "streams_per_connection",
                    connection_usage.streams_per_connection as f64,
                ),
                (
                    "samples_per_connection_avg",
                    connection_usage.samples_per_connection_avg,
                ),
                (
                    "reuse_connections",
                    if connection_usage.reuse_connections {
                        1.0
                    } else {
                        0.0
                    },
                ),
            ] {
                output.push_str(&format!(
                    "connectanum_bench_artifact_workload_http_connection_usage{} {}\n",
                    format_labels_with_extra(&base_labels, &[("kind", kind)]),
                    value
                ));
            }
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

fn severity_label(severity: ArtifactGateSeverity) -> &'static str {
    match severity {
        ArtifactGateSeverity::Warning => "warning",
        ArtifactGateSeverity::Critical => "critical",
    }
}

fn metric_comparison_label(comparison: ArtifactGateMetricComparison) -> &'static str {
    match comparison {
        ArtifactGateMetricComparison::Min => "min",
        ArtifactGateMetricComparison::Max => "max",
    }
}

fn metric_kind_comparison(kind: &str) -> Option<ArtifactGateMetricComparison> {
    match kind {
        THROUGHPUT_MBPS_MIN => Some(ArtifactGateMetricComparison::Min),
        LATENCY_P95_MS_MAX => Some(ArtifactGateMetricComparison::Max),
        _ => None,
    }
}

fn metric_threshold_is_more_permissive(
    candidate: f64,
    current: f64,
    comparison: ArtifactGateMetricComparison,
) -> bool {
    match comparison {
        ArtifactGateMetricComparison::Min => candidate < current,
        ArtifactGateMetricComparison::Max => candidate > current,
    }
}

fn push_gate_i64_finding(
    findings: &mut Vec<ArtifactGateFinding>,
    workload: &WorkloadArtifactSummary,
    severity: ArtifactGateSeverity,
    kind: &str,
    observed: i64,
    threshold: u64,
) {
    if observed <= 0 {
        return;
    }
    push_gate_finding(
        findings,
        workload,
        severity,
        kind,
        observed as u64,
        threshold,
    );
}

fn push_gate_u64_finding(
    findings: &mut Vec<ArtifactGateFinding>,
    workload: &WorkloadArtifactSummary,
    severity: ArtifactGateSeverity,
    kind: &str,
    observed: u64,
    threshold: u64,
) {
    if observed <= threshold {
        return;
    }
    push_gate_finding(findings, workload, severity, kind, observed, threshold);
}

fn push_gate_finding(
    findings: &mut Vec<ArtifactGateFinding>,
    workload: &WorkloadArtifactSummary,
    severity: ArtifactGateSeverity,
    kind: &str,
    observed: u64,
    threshold: u64,
) {
    if observed <= threshold {
        return;
    }

    findings.push(ArtifactGateFinding {
        severity,
        scenario: workload.scenario.clone(),
        workload: workload.workload.clone(),
        protocol: workload.protocol.clone(),
        client_impl: workload.client_impl.clone(),
        router_workers: workload.router_workers,
        native_runtime_threads: workload.native_runtime_threads,
        kind: kind.to_string(),
        observed,
        threshold,
    });
}

fn push_gate_metric_finding(
    findings: &mut Vec<ArtifactGateMetricFinding>,
    workload: &WorkloadArtifactSummary,
    severity: ArtifactGateSeverity,
    kind: &str,
    observed: f64,
    threshold: Option<f64>,
    comparison: ArtifactGateMetricComparison,
) {
    let Some(threshold) = threshold else {
        return;
    };
    if !observed.is_finite() || !threshold.is_finite() {
        return;
    }
    let failed = match comparison {
        ArtifactGateMetricComparison::Min => observed < threshold,
        ArtifactGateMetricComparison::Max => observed > threshold,
    };
    if !failed {
        return;
    }

    findings.push(ArtifactGateMetricFinding {
        severity,
        scenario: workload.scenario.clone(),
        workload: workload.workload.clone(),
        protocol: workload.protocol.clone(),
        client_impl: workload.client_impl.clone(),
        router_workers: workload.router_workers,
        native_runtime_threads: workload.native_runtime_threads,
        kind: kind.to_string(),
        observed,
        threshold,
        comparison,
    });
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
    use crate::report::{HttpPhaseTimingSample, WorkloadReport, WorkloadSample};

    fn metrics(
        invocations: i64,
        publications: i64,
        transport: serde_json::Value,
    ) -> serde_json::Value {
        metrics_with_bench_http_stream(invocations, publications, transport, None)
    }

    fn metrics_with_bench_http_stream(
        invocations: i64,
        publications: i64,
        transport: serde_json::Value,
        bench_http_stream: Option<serde_json::Value>,
    ) -> serde_json::Value {
        json!({
            "metrics": {
                "total_invocations_dispatched": invocations,
                "total_publications_routed": publications,
                "transport": transport,
                "bench_http_stream": bench_http_stream,
            }
        })
    }

    fn sample_report() -> WorkloadReport {
        WorkloadReport {
            scenario: "full_stack".to_string(),
            workload: "load".to_string(),
            protocol: "h2".to_string(),
            client_impl: "n/a".to_string(),
            router_workers: 3,
            native_runtime_threads: 4,
            iterations: 4,
            concurrency: 2,
            started_at_ms: 1_000,
            completed_at_ms: 2_000,
            metrics_before: metrics_with_bench_http_stream(
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
                    "http_response_stream": {
                        "streaming_responses_total": 2,
                        "stream_open_to_headers_send_samples_total": 2,
                        "stream_open_to_headers_send_us_total": 4000,
                        "headers_send_call_samples_total": 2,
                        "headers_send_call_us_total": 1000,
                        "headers_to_first_connection_write_samples_total": 2,
                        "headers_to_first_connection_write_us_total": 3000,
                        "headers_to_first_connection_write_ge_1ms_total": 2,
                        "headers_to_first_connection_write_ge_5ms_total": 0,
                        "headers_to_first_connection_write_ge_10ms_total": 0,
                        "first_chunk_channel_wait_samples_total": 2,
                        "first_chunk_channel_wait_us_total": 3000,
                        "first_chunk_channel_wait_ge_1ms_total": 1,
                        "first_chunk_channel_wait_ge_5ms_total": 0,
                        "first_chunk_channel_wait_ge_10ms_total": 0,
                        "headers_to_first_chunk_dequeue_samples_total": 2,
                        "headers_to_first_chunk_dequeue_us_total": 5000,
                        "headers_to_first_chunk_dequeue_ge_1ms_total": 2,
                        "headers_to_first_chunk_dequeue_ge_5ms_total": 0,
                        "headers_to_first_chunk_dequeue_ge_10ms_total": 0,
                        "first_chunk_send_call_samples_total": 2,
                        "first_chunk_send_call_us_total": 2000,
                        "first_chunk_send_call_ge_1ms_total": 0,
                        "first_chunk_send_call_ge_5ms_total": 0,
                        "first_chunk_send_call_ge_10ms_total": 0,
                        "headers_to_first_chunk_send_call_samples_total": 2,
                        "headers_to_first_chunk_send_call_us_total": 7000,
                    },
                }),
                Some(json!({
                    "requests_total": 2,
                    "synthetic_responses_total": 2,
                    "native_forwarded_responses_total": 0,
                    "buffered_responses_total": 0,
                    "request_body_drain_samples_total": 2,
                    "stream_open_samples_total": 2,
                    "first_chunk_queued_samples_total": 2,
                    "first_body_write_samples_total": 2,
                    "first_body_write_completed_samples_total": 2,
                    "headers_to_first_body_write_samples_total": 2,
                    "headers_to_first_body_write_completed_samples_total": 2,
                    "queue_to_first_body_write_samples_total": 2,
                    "queue_to_first_body_write_completed_samples_total": 2,
                    "first_body_write_call_samples_total": 2,
                    "direct_stream_open_round_trip_samples_total": 2,
                    "direct_stream_request_queue_delay_samples_total": 2,
                    "direct_stream_descriptor_open_call_samples_total": 2,
                    "direct_stream_reply_delivery_delay_samples_total": 2,
                    "handler_samples_total": 2,
                    "request_body_drain_us_total": 4000,
                    "stream_open_us_total": 9000,
                    "first_chunk_queued_us_total": 12000,
                    "first_body_write_us_total": 15000,
                    "first_body_write_completed_us_total": 17000,
                    "headers_to_first_body_write_us_total": 6000,
                    "headers_to_first_body_write_completed_us_total": 8000,
                    "queue_to_first_body_write_us_total": 3000,
                    "queue_to_first_body_write_completed_us_total": 5000,
                    "first_body_write_call_us_total": 2000,
                    "direct_stream_open_round_trip_us_total": 3000,
                    "direct_stream_request_queue_delay_us_total": 500,
                    "direct_stream_descriptor_open_call_us_total": 1000,
                    "direct_stream_reply_delivery_delay_us_total": 300,
                    "handler_us_total": 18000,
                })),
            ),
            metrics_after: metrics_with_bench_http_stream(
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
                    "http_response_stream": {
                        "streaming_responses_total": 5,
                        "stream_open_to_headers_send_samples_total": 5,
                        "stream_open_to_headers_send_us_total": 15000,
                        "headers_send_call_samples_total": 5,
                        "headers_send_call_us_total": 3000,
                        "headers_to_first_connection_write_samples_total": 5,
                        "headers_to_first_connection_write_us_total": 18000,
                        "headers_to_first_connection_write_ge_1ms_total": 5,
                        "headers_to_first_connection_write_ge_5ms_total": 2,
                        "headers_to_first_connection_write_ge_10ms_total": 1,
                        "first_chunk_channel_wait_samples_total": 5,
                        "first_chunk_channel_wait_us_total": 12000,
                        "first_chunk_channel_wait_ge_1ms_total": 4,
                        "first_chunk_channel_wait_ge_5ms_total": 1,
                        "first_chunk_channel_wait_ge_10ms_total": 0,
                        "headers_to_first_chunk_dequeue_samples_total": 5,
                        "headers_to_first_chunk_dequeue_us_total": 23000,
                        "headers_to_first_chunk_dequeue_ge_1ms_total": 5,
                        "headers_to_first_chunk_dequeue_ge_5ms_total": 2,
                        "headers_to_first_chunk_dequeue_ge_10ms_total": 1,
                        "first_chunk_send_call_samples_total": 5,
                        "first_chunk_send_call_us_total": 8000,
                        "first_chunk_send_call_ge_1ms_total": 2,
                        "first_chunk_send_call_ge_5ms_total": 0,
                        "first_chunk_send_call_ge_10ms_total": 0,
                        "headers_to_first_chunk_send_call_samples_total": 5,
                        "headers_to_first_chunk_send_call_us_total": 28000,
                    },
                }),
                Some(json!({
                    "requests_total": 5,
                    "synthetic_responses_total": 5,
                    "native_forwarded_responses_total": 0,
                    "buffered_responses_total": 0,
                    "request_body_drain_samples_total": 5,
                    "stream_open_samples_total": 5,
                    "first_chunk_queued_samples_total": 5,
                    "first_body_write_samples_total": 5,
                    "first_body_write_completed_samples_total": 5,
                    "headers_to_first_body_write_samples_total": 5,
                    "headers_to_first_body_write_completed_samples_total": 5,
                    "queue_to_first_body_write_samples_total": 5,
                    "queue_to_first_body_write_completed_samples_total": 5,
                    "first_body_write_call_samples_total": 5,
                    "direct_stream_open_round_trip_samples_total": 5,
                    "direct_stream_request_queue_delay_samples_total": 5,
                    "direct_stream_descriptor_open_call_samples_total": 5,
                    "direct_stream_reply_delivery_delay_samples_total": 5,
                    "handler_samples_total": 5,
                    "request_body_drain_us_total": 16000,
                    "stream_open_us_total": 30000,
                    "first_chunk_queued_us_total": 39000,
                    "first_body_write_us_total": 51000,
                    "first_body_write_completed_us_total": 57000,
                    "headers_to_first_body_write_us_total": 21000,
                    "headers_to_first_body_write_completed_us_total": 27000,
                    "queue_to_first_body_write_us_total": 12000,
                    "queue_to_first_body_write_completed_us_total": 18000,
                    "first_body_write_call_us_total": 6000,
                    "direct_stream_open_round_trip_us_total": 15000,
                    "direct_stream_request_queue_delay_us_total": 1700,
                    "direct_stream_descriptor_open_call_us_total": 7000,
                    "direct_stream_reply_delivery_delay_us_total": 2700,
                    "handler_us_total": 60000,
                })),
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
            http_connection_usage: Some(HttpConnectionUsage {
                reuse_connections: true,
                streams_per_connection: 4,
                connections_opened: 2,
            }),
            http_phase_timing: None,
            samples: vec![
                WorkloadSample {
                    worker: 0,
                    iteration: 0,
                    latency_ms: 10.0,
                    request_bytes: 100,
                    response_bytes: 200,
                    http_phase_timing: Some(HttpPhaseTimingSample {
                        stream_acquire_wait_ms: 1.0,
                        request_enqueue_ms: 2.0,
                        response_headers_wait_ms: 3.0,
                        response_headers_connection_read_wait_ms: Some(0.25),
                        response_headers_connection_read_to_headers_ms: Some(0.75),
                        response_headers_connection_write_wait_ms: Some(0.5),
                        response_headers_connection_write_span_ms: Some(1.0),
                        response_headers_last_write_to_first_read_ms: Some(0.25),
                        response_body_read_ms: 4.0,
                        response_body_first_chunk_wait_ms: 2.0,
                        response_body_tail_read_ms: 2.0,
                        response_body_chunk_count: 1,
                        response_body_first_chunk_bytes: 200,
                        response_body_post_header_connection_read_wait_ms: Some(0.5),
                        response_body_connection_read_to_first_chunk_ms: Some(1.5),
                        response_body_tail_connection_read_wait_ms: Some(0.5),
                        response_body_tail_connection_read_to_end_ms: Some(1.5),
                        request_round_trip_ms: 9.0,
                    }),
                },
                WorkloadSample {
                    worker: 1,
                    iteration: 1,
                    latency_ms: 20.0,
                    request_bytes: 100,
                    response_bytes: 400,
                    http_phase_timing: Some(HttpPhaseTimingSample {
                        stream_acquire_wait_ms: 3.0,
                        request_enqueue_ms: 4.0,
                        response_headers_wait_ms: 5.0,
                        response_headers_connection_read_wait_ms: Some(0.75),
                        response_headers_connection_read_to_headers_ms: Some(1.25),
                        response_headers_connection_write_wait_ms: Some(1.0),
                        response_headers_connection_write_span_ms: Some(1.5),
                        response_headers_last_write_to_first_read_ms: Some(0.75),
                        response_body_read_ms: 8.0,
                        response_body_first_chunk_wait_ms: 3.0,
                        response_body_tail_read_ms: 5.0,
                        response_body_chunk_count: 2,
                        response_body_first_chunk_bytes: 160,
                        response_body_post_header_connection_read_wait_ms: Some(1.5),
                        response_body_connection_read_to_first_chunk_ms: Some(1.5),
                        response_body_tail_connection_read_wait_ms: Some(1.5),
                        response_body_tail_connection_read_to_end_ms: Some(3.5),
                        request_round_trip_ms: 17.0,
                    }),
                },
                WorkloadSample {
                    worker: 1,
                    iteration: 2,
                    latency_ms: 30.0,
                    request_bytes: 100,
                    response_bytes: 600,
                    http_phase_timing: Some(HttpPhaseTimingSample {
                        stream_acquire_wait_ms: 5.0,
                        request_enqueue_ms: 6.0,
                        response_headers_wait_ms: 7.0,
                        response_headers_connection_read_wait_ms: None,
                        response_headers_connection_read_to_headers_ms: None,
                        response_headers_connection_write_wait_ms: None,
                        response_headers_connection_write_span_ms: None,
                        response_headers_last_write_to_first_read_ms: None,
                        response_body_read_ms: 12.0,
                        response_body_first_chunk_wait_ms: 4.0,
                        response_body_tail_read_ms: 8.0,
                        response_body_chunk_count: 4,
                        response_body_first_chunk_bytes: 120,
                        response_body_post_header_connection_read_wait_ms: None,
                        response_body_connection_read_to_first_chunk_ms: None,
                        response_body_tail_connection_read_wait_ms: None,
                        response_body_tail_connection_read_to_end_ms: None,
                        request_round_trip_ms: 25.0,
                    }),
                },
            ],
        }
    }

    fn clean_report() -> WorkloadReport {
        let mut report = sample_report();
        let metrics = metrics(
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
                "http_response_stream": {
                    "streaming_responses_total": 2,
                    "stream_open_to_headers_send_samples_total": 2,
                    "stream_open_to_headers_send_us_total": 4000,
                    "headers_send_call_samples_total": 2,
                    "headers_send_call_us_total": 1000,
                    "headers_to_first_connection_write_samples_total": 2,
                    "headers_to_first_connection_write_us_total": 3000,
                    "headers_to_first_connection_write_ge_1ms_total": 2,
                    "headers_to_first_connection_write_ge_5ms_total": 0,
                    "headers_to_first_connection_write_ge_10ms_total": 0,
                    "first_chunk_channel_wait_samples_total": 2,
                    "first_chunk_channel_wait_us_total": 3000,
                    "first_chunk_channel_wait_ge_1ms_total": 1,
                    "first_chunk_channel_wait_ge_5ms_total": 0,
                    "first_chunk_channel_wait_ge_10ms_total": 0,
                    "headers_to_first_chunk_dequeue_samples_total": 2,
                    "headers_to_first_chunk_dequeue_us_total": 5000,
                    "headers_to_first_chunk_dequeue_ge_1ms_total": 2,
                    "headers_to_first_chunk_dequeue_ge_5ms_total": 0,
                    "headers_to_first_chunk_dequeue_ge_10ms_total": 0,
                    "first_chunk_send_call_samples_total": 2,
                    "first_chunk_send_call_us_total": 2000,
                    "first_chunk_send_call_ge_1ms_total": 0,
                    "first_chunk_send_call_ge_5ms_total": 0,
                    "first_chunk_send_call_ge_10ms_total": 0,
                    "headers_to_first_chunk_send_call_samples_total": 2,
                    "headers_to_first_chunk_send_call_us_total": 7000,
                },
            }),
        );
        report.metrics_after = metrics.clone();
        report.scenario_metrics_after = Some(metrics);
        report
    }

    #[test]
    fn summarize_report_computes_latency_and_deltas() {
        let summary = summarize_report(&sample_report());
        assert_eq!(summary.sample_count, 3);
        assert_eq!(summary.client_impl, "n/a");
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
        let connection_usage = summary.http_connection_usage.unwrap();
        assert!(connection_usage.reuse_connections);
        assert_eq!(connection_usage.streams_per_connection, 4);
        assert_eq!(connection_usage.connections_opened, 2);
        assert!((connection_usage.samples_per_connection_avg - 1.5).abs() < f64::EPSILON);
        let phase_timing = summary.http_phase_timing.unwrap();
        assert!((phase_timing.stream_acquire_wait_avg_ms - 3.0).abs() < f64::EPSILON);
        assert!((phase_timing.stream_acquire_wait_p95_ms - 5.0).abs() < f64::EPSILON);
        assert!((phase_timing.request_enqueue_avg_ms - 4.0).abs() < f64::EPSILON);
        assert!((phase_timing.request_enqueue_p95_ms - 6.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_headers_wait_avg_ms - 5.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_headers_wait_p95_ms - 7.0).abs() < f64::EPSILON);
        assert_eq!(
            phase_timing.response_headers_connection_read_wait_samples_total,
            2
        );
        assert!(
            (phase_timing.response_headers_connection_read_wait_avg_ms - 0.5).abs() < f64::EPSILON
        );
        assert!(
            (phase_timing.response_headers_connection_read_wait_p95_ms - 0.75).abs() < f64::EPSILON
        );
        assert_eq!(
            phase_timing.response_headers_connection_read_to_headers_samples_total,
            2
        );
        assert!(
            (phase_timing.response_headers_connection_read_to_headers_avg_ms - 1.0).abs()
                < f64::EPSILON
        );
        assert!(
            (phase_timing.response_headers_connection_read_to_headers_p95_ms - 1.25).abs()
                < f64::EPSILON
        );
        assert_eq!(
            phase_timing.response_headers_connection_write_wait_samples_total,
            2
        );
        assert!(
            (phase_timing.response_headers_connection_write_wait_avg_ms - 0.75).abs()
                < f64::EPSILON
        );
        assert!(
            (phase_timing.response_headers_connection_write_wait_p95_ms - 1.0).abs() < f64::EPSILON
        );
        assert_eq!(
            phase_timing.response_headers_connection_write_span_samples_total,
            2
        );
        assert!(
            (phase_timing.response_headers_connection_write_span_avg_ms - 1.25).abs()
                < f64::EPSILON
        );
        assert!(
            (phase_timing.response_headers_connection_write_span_p95_ms - 1.5).abs() < f64::EPSILON
        );
        assert_eq!(
            phase_timing.response_headers_last_write_to_first_read_samples_total,
            2
        );
        assert!(
            (phase_timing.response_headers_last_write_to_first_read_avg_ms - 0.5).abs()
                < f64::EPSILON
        );
        assert!(
            (phase_timing.response_headers_last_write_to_first_read_p95_ms - 0.75).abs()
                < f64::EPSILON
        );
        assert!((phase_timing.response_body_read_avg_ms - 8.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_read_p95_ms - 12.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_first_chunk_wait_avg_ms - 3.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_first_chunk_wait_p95_ms - 4.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_tail_read_avg_ms - 5.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_tail_read_p95_ms - 8.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_chunk_count_avg - (7.0 / 3.0)).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_chunk_count_p95 - 4.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_first_chunk_bytes_avg - 160.0).abs() < f64::EPSILON);
        assert!((phase_timing.response_body_first_chunk_bytes_p95 - 200.0).abs() < f64::EPSILON);
        assert_eq!(
            phase_timing.response_body_post_header_connection_read_wait_samples_total,
            2
        );
        assert!(
            (phase_timing.response_body_post_header_connection_read_wait_avg_ms - 1.0).abs()
                < f64::EPSILON
        );
        assert!(
            (phase_timing.response_body_post_header_connection_read_wait_p95_ms - 1.5).abs()
                < f64::EPSILON
        );
        assert_eq!(
            phase_timing.response_body_connection_read_to_first_chunk_samples_total,
            2
        );
        assert!(
            (phase_timing.response_body_connection_read_to_first_chunk_avg_ms - 1.5).abs()
                < f64::EPSILON
        );
        assert!(
            (phase_timing.response_body_connection_read_to_first_chunk_p95_ms - 1.5).abs()
                < f64::EPSILON
        );
        assert_eq!(
            phase_timing.response_body_tail_connection_read_wait_samples_total,
            2
        );
        assert!(
            (phase_timing.response_body_tail_connection_read_wait_avg_ms - 1.0).abs()
                < f64::EPSILON
        );
        assert!(
            (phase_timing.response_body_tail_connection_read_wait_p95_ms - 1.5).abs()
                < f64::EPSILON
        );
        assert_eq!(
            phase_timing.response_body_tail_connection_read_to_end_samples_total,
            2
        );
        assert!(
            (phase_timing.response_body_tail_connection_read_to_end_avg_ms - 2.5).abs()
                < f64::EPSILON
        );
        assert!(
            (phase_timing.response_body_tail_connection_read_to_end_p95_ms - 3.5).abs()
                < f64::EPSILON
        );
        assert!((phase_timing.request_round_trip_avg_ms - 17.0).abs() < f64::EPSILON);
        assert!((phase_timing.request_round_trip_p95_ms - 25.0).abs() < f64::EPSILON);
        let server_timing = summary.http_server_emission_timing.unwrap();
        assert_eq!(server_timing.requests_total, 3);
        assert_eq!(server_timing.synthetic_responses_total, 3);
        assert!((server_timing.request_body_drain_avg_ms - 4.0).abs() < f64::EPSILON);
        assert!((server_timing.stream_open_avg_ms - 7.0).abs() < f64::EPSILON);
        assert!((server_timing.first_chunk_queued_avg_ms - 9.0).abs() < f64::EPSILON);
        assert!((server_timing.first_body_write_avg_ms - 12.0).abs() < f64::EPSILON);
        assert!(
            (server_timing.first_body_write_completed_avg_ms - (40.0 / 3.0)).abs() < f64::EPSILON
        );
        assert!((server_timing.headers_to_first_body_write_avg_ms - 5.0).abs() < f64::EPSILON);
        assert!(
            (server_timing.headers_to_first_body_write_completed_avg_ms - (19.0 / 3.0)).abs()
                < f64::EPSILON
        );
        assert!((server_timing.queue_to_first_body_write_avg_ms - 3.0).abs() < f64::EPSILON);
        assert!(
            (server_timing.queue_to_first_body_write_completed_avg_ms - (13.0 / 3.0)).abs()
                < f64::EPSILON
        );
        assert!((server_timing.first_body_write_call_avg_ms - (4.0 / 3.0)).abs() < f64::EPSILON);
        assert!((server_timing.direct_stream_open_round_trip_avg_ms - 4.0).abs() < f64::EPSILON);
        assert!(
            (server_timing.direct_stream_request_queue_delay_avg_ms - 0.4).abs() < f64::EPSILON
        );
        assert!(
            (server_timing.direct_stream_descriptor_open_call_avg_ms - 2.0).abs() < f64::EPSILON
        );
        assert!(
            (server_timing.direct_stream_reply_delivery_delay_avg_ms - 0.8).abs() < f64::EPSILON
        );
        assert!((server_timing.handler_avg_ms - 14.0).abs() < f64::EPSILON);
        let native_stream_timing = summary.http_native_response_stream_timing.unwrap();
        assert_eq!(native_stream_timing.streaming_responses_total, 3);
        assert!(
            (native_stream_timing.stream_open_to_headers_send_avg_ms - (11.0 / 3.0)).abs()
                < f64::EPSILON
        );
        assert!((native_stream_timing.headers_send_call_avg_ms - (2.0 / 3.0)).abs() < f64::EPSILON);
        assert!(
            (native_stream_timing.headers_to_first_connection_write_avg_ms - 5.0).abs()
                < f64::EPSILON
        );
        assert!((native_stream_timing.first_chunk_channel_wait_avg_ms - 3.0).abs() < f64::EPSILON);
        assert!(
            (native_stream_timing.headers_to_first_chunk_dequeue_avg_ms - 6.0).abs() < f64::EPSILON
        );
        assert!((native_stream_timing.first_chunk_send_call_avg_ms - 2.0).abs() < f64::EPSILON);
        assert!(
            (native_stream_timing.headers_to_first_chunk_send_call_avg_ms - 7.0).abs()
                < f64::EPSILON
        );
        let native_stream_slow_path = summary.http_native_response_stream_slow_path.unwrap();
        assert_eq!(native_stream_slow_path.streaming_responses_total, 3);
        assert_eq!(
            native_stream_slow_path.headers_to_first_connection_write_ge_1ms_total,
            3
        );
        assert_eq!(
            native_stream_slow_path.headers_to_first_connection_write_ge_5ms_total,
            2
        );
        assert_eq!(
            native_stream_slow_path.headers_to_first_connection_write_ge_10ms_total,
            1
        );
        assert_eq!(
            native_stream_slow_path.first_chunk_channel_wait_ge_1ms_total,
            3
        );
        assert_eq!(
            native_stream_slow_path.first_chunk_channel_wait_ge_5ms_total,
            1
        );
        assert_eq!(
            native_stream_slow_path.first_chunk_channel_wait_ge_10ms_total,
            0
        );
        assert_eq!(
            native_stream_slow_path.headers_to_first_chunk_dequeue_ge_1ms_total,
            3
        );
        assert_eq!(
            native_stream_slow_path.headers_to_first_chunk_dequeue_ge_5ms_total,
            2
        );
        assert_eq!(
            native_stream_slow_path.headers_to_first_chunk_dequeue_ge_10ms_total,
            1
        );
        assert_eq!(
            native_stream_slow_path.first_chunk_send_call_ge_1ms_total,
            2
        );
        assert_eq!(
            native_stream_slow_path.first_chunk_send_call_ge_5ms_total,
            0
        );
        assert_eq!(
            native_stream_slow_path.first_chunk_send_call_ge_10ms_total,
            0
        );
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
        assert!(text.contains("client_impl=\"n/a\""));
        assert!(text.contains("router_workers=\"3\""));
        assert!(text.contains("native_runtime_threads=\"4\""));
        assert!(text.contains("kind=\"active_throttles\""));
        assert!(text.contains("counter=\"invocations_dispatched\""));
        assert!(text.contains("connectanum_bench_artifact_workload_http_connection_usage"));
        assert!(text.contains("kind=\"connections_opened\""));
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

    #[test]
    fn load_artifact_bundle_reads_written_summary_json() {
        let temp_dir = unique_temp_dir("load_bundle");
        let results_path = temp_dir.join("bench_results.jsonl");
        let output_dir = temp_dir.join("artifacts");
        fs::create_dir_all(&output_dir).unwrap();
        fs::write(&results_path, "").unwrap();

        let paths =
            write_artifact_bundle(&[sample_report()], &results_path, Some(&output_dir)).unwrap();
        let bundle = load_artifact_bundle(&paths.summary_json).unwrap();

        assert_eq!(bundle.source_results, results_path.to_string_lossy());
        assert_eq!(bundle.workloads.len(), 1);
        assert_eq!(bundle.workloads[0].workload, "load");

        fs::remove_dir_all(&temp_dir).unwrap();
    }

    #[test]
    fn default_artifact_gate_passes_clean_summary() {
        let bundle = ArtifactBundle {
            generated_at_ms: 1,
            source_results: "bench_results.jsonl".to_string(),
            workloads: vec![summarize_report(&clean_report())],
        };

        let report = evaluate_default_artifact_gate(
            &bundle,
            Path::new("native/bench/artifacts/bench_results.summary.json"),
        );

        assert_eq!(report.workload_count, 1);
        assert!(!report.failed());
        assert!(report.findings.is_empty());
        assert!(report.metric_findings.is_empty());
        assert!(render_artifact_gate_markdown(&report)
            .contains("Gate passed. No transport or performance regressions were detected."));
    }

    #[test]
    fn default_artifact_gate_flags_transport_regressions() {
        let bundle = ArtifactBundle {
            generated_at_ms: 1,
            source_results: "bench_results.jsonl".to_string(),
            workloads: vec![summarize_report(&sample_report())],
        };

        let report = evaluate_default_artifact_gate(
            &bundle,
            Path::new("native/bench/artifacts/bench_results.summary.json"),
        );
        let kinds = report
            .findings
            .iter()
            .map(|finding| finding.kind.as_str())
            .collect::<Vec<_>>();

        assert!(report.failed());
        assert_eq!(
            kinds,
            vec![
                "backpressure_events",
                "backpressure_alerts",
                "transport_alerts",
                "goaway_alerts",
                "body_timeout_alerts",
                "internal_error_alerts",
                "active_throttles",
            ]
        );
        assert!(render_artifact_gate_markdown(&report).contains(
            "Gate failed. The transformed bench artifacts captured transport or performance regressions."
        ));
    }

    #[test]
    fn artifact_gate_policy_allows_scoped_expected_counters() {
        let mut workload = summarize_report(&clean_report());
        workload.scenario = "h3_multiplex_scaling".to_string();
        workload.workload = "h3_multiplexed_streams_s4".to_string();
        workload.protocol = "h3".to_string();
        workload.transport.backpressure_events = 63;
        workload.transport.backpressure_alerts = 4;
        let bundle = ArtifactBundle {
            generated_at_ms: 1,
            source_results: "bench_results.jsonl".to_string(),
            workloads: vec![workload],
        };
        let policy = ArtifactGatePolicy {
            thresholds: vec![
                test_threshold("backpressure_events", 8, Some("h3_multiplex_scaling"), None),
                test_threshold(
                    "backpressure_events",
                    80,
                    Some("h3_multiplex_scaling"),
                    Some("h3_multiplexed_streams_s4"),
                ),
                test_threshold(
                    "backpressure_alerts",
                    4,
                    Some("h3_multiplex_scaling"),
                    Some("h3_multiplexed_streams_s4"),
                ),
            ],
            metrics: Vec::new(),
        };

        let report = evaluate_artifact_gate(
            &bundle,
            Path::new("native/bench/artifacts/bench_results.summary.json"),
            &policy,
        );

        assert!(!report.failed());
        assert!(report.findings.is_empty());
    }

    #[test]
    fn artifact_gate_policy_still_flags_values_above_threshold() {
        let mut workload = summarize_report(&clean_report());
        workload.scenario = "h3_multiplex_scaling".to_string();
        workload.workload = "h3_multiplexed_streams_s4".to_string();
        workload.protocol = "h3".to_string();
        workload.transport.backpressure_events = 81;
        let bundle = ArtifactBundle {
            generated_at_ms: 1,
            source_results: "bench_results.jsonl".to_string(),
            workloads: vec![workload],
        };
        let policy = ArtifactGatePolicy {
            thresholds: vec![test_threshold(
                "backpressure_events",
                80,
                Some("h3_multiplex_scaling"),
                Some("h3_multiplexed_streams_s4"),
            )],
            metrics: Vec::new(),
        };

        let report = evaluate_artifact_gate(
            &bundle,
            Path::new("native/bench/artifacts/bench_results.summary.json"),
            &policy,
        );

        assert!(report.failed());
        assert_eq!(report.findings.len(), 1);
        assert_eq!(report.findings[0].kind, "backpressure_events");
        assert_eq!(report.findings[0].observed, 81);
        assert_eq!(report.findings[0].threshold, 80);
    }

    #[test]
    fn artifact_gate_policy_allows_thread_scoped_thresholds() {
        let mut workload = summarize_report(&clean_report());
        workload.scenario = "h2_ktls_benchmark".to_string();
        workload.workload = "h2_multiplexed_streams".to_string();
        workload.protocol = "h2".to_string();
        workload.router_workers = 1;
        workload.native_runtime_threads = 4;
        workload.transport.backpressure_events = 87;
        workload.transport.backpressure_alerts = 6;
        let bundle = ArtifactBundle {
            generated_at_ms: 1,
            source_results: "bench_results.jsonl".to_string(),
            workloads: vec![workload],
        };
        let policy = ArtifactGatePolicy {
            thresholds: vec![
                ArtifactGateThreshold {
                    kind: "backpressure_events".to_string(),
                    threshold: 8,
                    scenario: Some("h2_ktls_benchmark".to_string()),
                    workload: Some("h2_multiplexed_streams".to_string()),
                    protocol: Some("h2".to_string()),
                    client_impl: None,
                    router_workers: Some(1),
                    native_runtime_threads: Some(1),
                },
                ArtifactGateThreshold {
                    kind: "backpressure_events".to_string(),
                    threshold: 128,
                    scenario: Some("h2_ktls_benchmark".to_string()),
                    workload: Some("h2_multiplexed_streams".to_string()),
                    protocol: Some("h2".to_string()),
                    client_impl: None,
                    router_workers: Some(1),
                    native_runtime_threads: Some(4),
                },
                ArtifactGateThreshold {
                    kind: "backpressure_alerts".to_string(),
                    threshold: 8,
                    scenario: Some("h2_ktls_benchmark".to_string()),
                    workload: Some("h2_multiplexed_streams".to_string()),
                    protocol: Some("h2".to_string()),
                    client_impl: None,
                    router_workers: Some(1),
                    native_runtime_threads: Some(4),
                },
            ],
            metrics: Vec::new(),
        };

        let report = evaluate_artifact_gate(
            &bundle,
            Path::new("native/bench/artifacts/bench_results.summary.json"),
            &policy,
        );

        assert!(!report.failed());
        assert!(report.findings.is_empty());
    }

    #[test]
    fn artifact_gate_metric_policy_flags_performance_regressions() {
        let bundle = ArtifactBundle {
            generated_at_ms: 1,
            source_results: "bench_results.jsonl".to_string(),
            workloads: vec![summarize_report(&clean_report())],
        };
        let policy = ArtifactGatePolicy {
            thresholds: Vec::new(),
            metrics: vec![
                test_metric_threshold(THROUGHPUT_MBPS_MIN, 1.0, None, None),
                test_metric_threshold(LATENCY_P95_MS_MAX, 25.0, None, None),
            ],
        };

        let report = evaluate_artifact_gate(
            &bundle,
            Path::new("native/bench/artifacts/bench_results.summary.json"),
            &policy,
        );
        let kinds = report
            .metric_findings
            .iter()
            .map(|finding| finding.kind.as_str())
            .collect::<Vec<_>>();

        assert!(report.failed());
        assert!(report.findings.is_empty());
        assert_eq!(report.finding_count(), 2);
        assert_eq!(kinds, vec![THROUGHPUT_MBPS_MIN, LATENCY_P95_MS_MAX]);
        assert_eq!(
            report.metric_findings[0].comparison,
            ArtifactGateMetricComparison::Min
        );
        assert_eq!(
            report.metric_findings[1].comparison,
            ArtifactGateMetricComparison::Max
        );
        assert!(render_artifact_gate_markdown(&report).contains("## Performance Findings"));
    }

    #[test]
    fn artifact_gate_metric_policy_passes_values_within_thresholds() {
        let bundle = ArtifactBundle {
            generated_at_ms: 1,
            source_results: "bench_results.jsonl".to_string(),
            workloads: vec![summarize_report(&clean_report())],
        };
        let policy = ArtifactGatePolicy {
            thresholds: Vec::new(),
            metrics: vec![
                test_metric_threshold(THROUGHPUT_MBPS_MIN, 0.009, None, None),
                test_metric_threshold(LATENCY_P95_MS_MAX, 30.0, None, None),
            ],
        };

        let report = evaluate_artifact_gate(
            &bundle,
            Path::new("native/bench/artifacts/bench_results.summary.json"),
            &policy,
        );

        assert!(!report.failed());
        assert!(report.findings.is_empty());
        assert!(report.metric_findings.is_empty());
    }

    fn test_threshold(
        kind: &str,
        threshold: u64,
        scenario: Option<&str>,
        workload: Option<&str>,
    ) -> ArtifactGateThreshold {
        ArtifactGateThreshold {
            kind: kind.to_string(),
            threshold,
            scenario: scenario.map(ToString::to_string),
            workload: workload.map(ToString::to_string),
            protocol: Some("h3".to_string()),
            client_impl: None,
            router_workers: None,
            native_runtime_threads: None,
        }
    }

    fn test_metric_threshold(
        kind: &str,
        threshold: f64,
        scenario: Option<&str>,
        workload: Option<&str>,
    ) -> ArtifactGateMetricThreshold {
        ArtifactGateMetricThreshold {
            kind: kind.to_string(),
            threshold,
            scenario: scenario.map(ToString::to_string),
            workload: workload.map(ToString::to_string),
            protocol: None,
            client_impl: None,
            router_workers: None,
            native_runtime_threads: None,
        }
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("connectanum_bench_{prefix}_{}", unique))
    }
}
