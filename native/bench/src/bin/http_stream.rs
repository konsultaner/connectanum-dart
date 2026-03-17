use std::collections::{BTreeMap, BTreeSet};
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, bail, Context, Result};
use bytes::{Buf, Bytes};
use clap::Parser;
use h3_quinn::Connection as H3QuinnConnection;
use http as http3;
use hyper::body::HttpBody as _;
use hyper::client::conn::Builder as HyperConnBuilder;
use hyper::http::{
    header::{HeaderValue as HyperHeaderValue, ACCEPT, USER_AGENT},
    Method as HyperMethod,
};
use hyper::{Body, Request};
use quinn::{ClientConfig as QuinnClientConfig, Endpoint as QuinnEndpoint, TransportConfig};
use quinn_proto::crypto::rustls::QuicClientConfig;
use reqwest::blocking::Client as BlockingHttpClient;
use reqwest::Url as ReqwestUrl;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto;
use rustls::crypto::ring;
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::net::lookup_host;
use tokio::runtime::Runtime;
use tokio::task::JoinSet;
use tokio_rustls::TlsConnector;
use url::Url;

use connectanum_bench_orchestrator::artifacts::summarize_report;
use connectanum_bench_orchestrator::artifacts::{write_artifact_bundle, WorkloadArtifactSummary};
use connectanum_bench_orchestrator::report::{
    router_counter_delta, WorkloadReport, WorkloadSample,
};

type H3RequestSender = h3::client::SendRequest<h3_quinn::OpenStreams, Bytes>;
const NATIVE_RUNTIME_THREADS_ENV: &str = "CONNECTANUM_NATIVE_RUNTIME_THREADS";

#[derive(Parser, Debug)]
#[command(author, version, about = "Connectanum bench orchestrator")]
struct Args {
    /// Dart executable to invoke
    #[arg(long, default_value = "dart")]
    dart: String,

    /// Path to bench_main.dart entrypoint
    #[arg(
        long,
        default_value = "packages/connectanum_bench/tool/bench_main.dart"
    )]
    bench_main: String,

    /// Path to router config consumed by bench_main
    #[arg(long, default_value = "native/bench/bench_router.json")]
    router_config: String,

    /// Path to libct_ffi.so
    #[arg(long, env = "CONNECTANUM_NATIVE_LIB")]
    native_lib: String,

    /// Base URL for the /bench/* HTTP control endpoints.
    #[arg(long, default_value = "https://localhost:8080/bench")]
    control_base: String,

    /// Optional HTTP/3 port override (defaults to control port).
    #[arg(long)]
    h3_port: Option<u16>,

    /// Scenario file describing workloads (TOML).
    #[arg(long, default_value = "native/bench/scenarios/h2_smoke.toml")]
    scenario: String,

    /// Router worker isolate counts to benchmark. Accepts comma-separated
    /// values and inclusive ranges, e.g. `1,2,4-8`.
    #[arg(long)]
    router_worker_counts: Option<String>,

    /// Native Tokio runtime thread counts to benchmark. Accepts comma-separated
    /// values, inclusive ranges, and `auto`, e.g. `auto,1-4`.
    #[arg(long)]
    native_runtime_thread_counts: Option<String>,

    /// JSONL results output file.
    #[arg(long, default_value = "native/bench/artifacts/bench_results.jsonl")]
    results: String,

    /// Directory that receives transformed bench artifact outputs (.prom + summary json).
    #[arg(long)]
    artifact_dir: Option<String>,

    /// Timeout per workload in milliseconds (guards against hung tests).
    #[arg(long, default_value = "300000")]
    workload_timeout_ms: u64,

    /// Skip collecting /bench/metrics before/after each workload to reduce overhead.
    #[arg(long, default_value_t = false)]
    skip_metrics: bool,
}

fn main() -> Result<()> {
    ring::default_provider()
        .install_default()
        .expect("failed to install ring crypto provider");
    let args = Args::parse();

    let router_worker_counts =
        resolve_router_worker_counts(args.router_worker_counts.as_deref(), &args.router_config)?;
    let native_runtime_thread_counts =
        resolve_native_runtime_thread_counts(args.native_runtime_thread_counts.as_deref())?;
    let mut results_writer =
        ResultsWriter::create(&args.results).context("failed to open results file")?;
    let results_path = Path::new(&args.results);
    let artifact_dir = args.artifact_dir.as_deref().map(Path::new);
    let mut reports = Vec::<WorkloadReport>::new();

    for native_runtime_threads in native_runtime_thread_counts {
        for &router_workers in &router_worker_counts {
            println!(
                "\n=== Native runtime threads {} / router worker count {} ===",
                format_native_runtime_threads(native_runtime_threads),
                router_workers
            );
            let config_variant =
                prepare_router_config_variant(&args.router_config, router_workers)?;
            let run_result = run_bench_suite(
                &args,
                &config_variant.path,
                router_workers,
                native_runtime_threads,
                &mut results_writer,
                &mut reports,
                results_path,
                artifact_dir,
            );
            config_variant.cleanup();
            run_result?;
        }
    }

    print_router_worker_scaling_summary(&reports);
    print_native_runtime_thread_scaling_summary(&reports);
    println!("Bench run completed successfully");
    Ok(())
}

fn run_bench_suite(
    args: &Args,
    router_config_path: &str,
    router_workers: u32,
    native_runtime_threads: u32,
    results_writer: &mut ResultsWriter,
    reports: &mut Vec<WorkloadReport>,
    results_path: &Path,
    artifact_dir: Option<&Path>,
) -> Result<()> {
    println!(
        "Starting bench runner via {} {}",
        args.dart, args.bench_main
    );

    let mut command = Command::new(&args.dart);
    command
        .arg("run")
        .arg(&args.bench_main)
        .arg("--router-config")
        .arg(router_config_path)
        .arg("--native-lib")
        .arg(&args.native_lib)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    if native_runtime_threads == 0 {
        command.env_remove(NATIVE_RUNTIME_THREADS_ENV);
    } else {
        command.env(
            NATIVE_RUNTIME_THREADS_ENV,
            native_runtime_threads.to_string(),
        );
    }
    let mut child_process = command.spawn().context("failed to spawn bench_main")?;

    let mut child_stdin = child_process.stdin.take();
    let stdout = child_process
        .stdout
        .take()
        .context("failed to capture bench_main stdout")?;
    let mut reader = BufReader::new(stdout);

    let mut ready = false;
    let mut line = String::new();
    while reader.read_line(&mut line)? > 0 {
        let trimmed = line.trim();
        if trimmed == "READY" {
            println!("bench_main reported READY");
            ready = true;
            break;
        }
        if !trimmed.is_empty() {
            println!("[bench_main] {trimmed}");
        }
        line.clear();
    }

    if !ready {
        bail!("bench_main exited before signaling READY");
    }

    let stdout_reader = thread::spawn(move || -> Result<()> {
        let mut reader = reader;
        let mut line = String::new();
        loop {
            line.clear();
            let read = reader.read_line(&mut line)?;
            if read == 0 {
                break;
            }
            let trimmed = line.trim();
            if !trimmed.is_empty() && trimmed != "READY" {
                println!("[bench_main] {trimmed}");
            }
        }
        Ok(())
    });

    let scenarios = load_scenarios(&args.scenario)?;
    println!("Loaded {} scenario(s)", scenarios.len());

    let requires_h3 = scenarios.iter().any(|(scenario, _)| {
        scenario
            .workloads
            .iter()
            .any(|w| matches!(w.protocol.to_lowercase().as_str(), "h3" | "http3"))
    });
    let inferred_h3_port = if requires_h3 {
        args.h3_port
            .or_else(|| infer_h3_port(router_config_path))
            .or(Some(8443))
    } else {
        args.h3_port
    };

    let http_control = BenchHttpClient::new(&args.control_base)?;
    let endpoint = HttpEndpoint::from_control_base(&args.control_base, inferred_h3_port)?;

    let health = http_control
        .healthz()
        .context("failed to read /bench/healthz")?;
    println!(
        "bench_main healthz status: {}",
        health
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
    );

    let runtime = Runtime::new().context("failed to create tokio runtime")?;
    let workload_timeout = Duration::from_millis(args.workload_timeout_ms);

    let workloads_result: Result<()> = (|| {
        for (scenario, scenario_path) in scenarios {
            println!(
                "\n=== Scenario \"{}\" (path: {}) with {} workload(s) ===",
                scenario.name,
                scenario_path,
                scenario.workloads.len()
            );
            if let Some(description) = scenario.description.as_deref() {
                println!("Description: {description}");
            }

            let (scenario_metrics_before, scenario_open_metrics_before) = if args.skip_metrics {
                (Value::Object(Default::default()), None)
            } else {
                let raw = http_control.metrics().unwrap_or_else(|err| {
                    eprintln!(
                        "Warning: failed to fetch metrics before scenario {}: {err}",
                        scenario.name
                    );
                    Value::Object(Default::default())
                });
                split_metrics_payload(raw)
            };

            let mut scenario_metrics_after = scenario_metrics_before.clone();
            let mut scenario_open_metrics_after = scenario_open_metrics_before.clone();

            for workload in &scenario.workloads {
                println!(
                    "\n=== Workload \"{}\" (protocol {}, {} iters x {} concurrency) ===",
                    workload.name, workload.protocol, workload.iterations, workload.concurrency
                );
                let prepared = PreparedWorkload::from_config(workload)?;
                if let Some(ms) = workload.warmup_ms {
                    println!("  Warm-up: {ms} ms");
                    std::thread::sleep(Duration::from_millis(ms));
                }
                let (metrics_before, open_metrics_before) = if args.skip_metrics {
                    (Value::Object(Default::default()), None)
                } else {
                    let raw = http_control.metrics().unwrap_or_else(|err| {
                        eprintln!(
                            "Warning: failed to fetch metrics before workload {}: {err}",
                            workload.name
                        );
                        Value::Object(Default::default())
                    });
                    split_metrics_payload(raw)
                };
                let started_at = now_millis();
                let samples = if prepared.is_wamp() {
                    run_wamp_workload(&http_control, &prepared)
                        .with_context(|| format!("workload \"{}\" failed", workload.name))?
                } else {
                    runtime
                        .block_on(execute_workload(
                            endpoint.clone(),
                            prepared.clone(),
                            workload_timeout,
                        ))
                        .with_context(|| format!("workload \"{}\" failed", workload.name))?
                };
                let completed_at = now_millis();
                if !args.skip_metrics {
                    let raw = http_control.metrics().unwrap_or_else(|err| {
                        eprintln!(
                            "Warning: failed to fetch metrics after workload {}: {err}",
                            workload.name
                        );
                        Value::Object(Default::default())
                    });
                    let (m_after, om_after) = split_metrics_payload(raw);
                    scenario_metrics_after = m_after.clone();
                    scenario_open_metrics_after = om_after.clone();
                }
                let report = WorkloadReport {
                    scenario: scenario.name.clone(),
                    workload: workload.name.clone(),
                    protocol: workload.protocol.clone(),
                    router_workers,
                    native_runtime_threads,
                    iterations: workload.iterations,
                    concurrency: workload.concurrency,
                    started_at_ms: started_at,
                    completed_at_ms: completed_at,
                    metrics_before: metrics_before.clone(),
                    metrics_after: scenario_metrics_after.clone(),
                    open_metrics_before: open_metrics_before.clone(),
                    open_metrics_after: scenario_open_metrics_after.clone(),
                    scenario_metrics_before: Some(scenario_metrics_before.clone()),
                    scenario_metrics_after: Some(scenario_metrics_after.clone()),
                    scenario_open_metrics_before: scenario_open_metrics_before.clone(),
                    scenario_open_metrics_after: scenario_open_metrics_after.clone(),
                    samples,
                };
                print_workload_summary(&report, &prepared);
                results_writer.write(&report)?;
                reports.push(report);
                write_artifact_bundle(reports, results_path, artifact_dir).with_context(|| {
                    format!(
                        "failed to write transformed artifact bundle next to {}",
                        args.results
                    )
                })?;
            }
        }
        Ok(())
    })();

    // attempt graceful stop via HTTP endpoint
    let mut stop_via_stdin = false;
    if let Err(error) = http_control.request_stop() {
        eprintln!(
            "HTTP stop endpoint failed ({}). Falling back to stdin STOP.",
            error
        );
        stop_via_stdin = true;
    } else {
        println!("Issued HTTP stop request");
    }

    if stop_via_stdin {
        if let Some(stdin) = child_stdin.as_mut() {
            stdin
                .write_all(b"STOP\n")
                .context("failed to write STOP to bench_main")?;
        }
    }

    println!("Waiting for bench_main to exit…");
    let status = child_process
        .wait()
        .context("failed to wait for bench_main")?;
    if !status.success() {
        bail!("bench_main exited with status {status}");
    }

    workloads_result?;

    println!("bench_main exited, draining stdout…");
    let stdout_result = stdout_reader
        .join()
        .map_err(|_| anyhow!("bench_main stdout reader panicked"))?;
    stdout_result?;
    Ok(())
}

struct RouterConfigVariant {
    path: String,
    cleanup_path: Option<std::path::PathBuf>,
}

impl RouterConfigVariant {
    fn cleanup(&self) {
        if let Some(path) = &self.cleanup_path {
            let _ = std::fs::remove_file(path);
        }
    }
}

fn resolve_router_worker_counts(spec: Option<&str>, router_config_path: &str) -> Result<Vec<u32>> {
    match spec {
        Some(value) => parse_router_worker_counts(value),
        None => Ok(vec![configured_router_workers(router_config_path)?]),
    }
}

fn resolve_native_runtime_thread_counts(spec: Option<&str>) -> Result<Vec<u32>> {
    match spec {
        Some(value) => parse_native_runtime_thread_counts(value),
        None => Ok(vec![configured_native_runtime_threads()?]),
    }
}

fn parse_router_worker_counts(spec: &str) -> Result<Vec<u32>> {
    let mut values = BTreeSet::new();
    for raw_segment in spec.split(',') {
        let segment = raw_segment.trim();
        if segment.is_empty() {
            continue;
        }
        if let Some((start, end)) = segment.split_once('-') {
            let start = parse_positive_worker_count(start)?;
            let end = parse_positive_worker_count(end)?;
            if start > end {
                bail!("invalid worker range {segment}: start must be <= end");
            }
            for value in start..=end {
                values.insert(value);
            }
            continue;
        }
        values.insert(parse_positive_worker_count(segment)?);
    }
    if values.is_empty() {
        bail!("router_worker_counts must contain at least one value");
    }
    Ok(values.into_iter().collect())
}

fn parse_positive_worker_count(raw: &str) -> Result<u32> {
    let value = raw
        .trim()
        .parse::<u32>()
        .with_context(|| format!("invalid worker count {raw:?}"))?;
    if value == 0 {
        bail!("worker counts must be >= 1");
    }
    Ok(value)
}

fn parse_native_runtime_thread_counts(spec: &str) -> Result<Vec<u32>> {
    let mut values = BTreeSet::new();
    for raw_segment in spec.split(',') {
        let segment = raw_segment.trim();
        if segment.is_empty() {
            continue;
        }
        if segment.eq_ignore_ascii_case("auto") {
            values.insert(0);
            continue;
        }
        if let Some((start, end)) = segment.split_once('-') {
            let start = parse_positive_worker_count(start)?;
            let end = parse_positive_worker_count(end)?;
            if start > end {
                bail!("invalid runtime thread range {segment}: start must be <= end");
            }
            for value in start..=end {
                values.insert(value);
            }
            continue;
        }
        values.insert(parse_positive_worker_count(segment)?);
    }
    if values.is_empty() {
        bail!("native_runtime_thread_counts must contain at least one value");
    }
    Ok(values.into_iter().collect())
}

fn configured_native_runtime_threads() -> Result<u32> {
    let Ok(raw) = std::env::var(NATIVE_RUNTIME_THREADS_ENV) else {
        return Ok(0);
    };
    let trimmed = raw.trim();
    if trimmed.is_empty() || trimmed.eq_ignore_ascii_case("auto") {
        return Ok(0);
    }
    parse_positive_worker_count(trimmed)
}

fn configured_router_workers(router_config_path: &str) -> Result<u32> {
    let value = load_router_config_value(router_config_path)?;
    Ok(extract_router_workers(&value))
}

fn load_router_config_value(router_config_path: &str) -> Result<Value> {
    let contents = std::fs::read_to_string(router_config_path)
        .with_context(|| format!("failed to read router config {router_config_path}"))?;
    serde_json::from_str(&contents)
        .with_context(|| format!("failed to parse router config {router_config_path}"))
}

fn extract_router_workers(value: &Value) -> u32 {
    value
        .get("router")
        .and_then(Value::as_object)
        .and_then(|router| router.get("worker_pool"))
        .and_then(Value::as_object)
        .and_then(|worker_pool| worker_pool.get("min_workers"))
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
        .unwrap_or(1)
}

fn prepare_router_config_variant(
    router_config_path: &str,
    router_workers: u32,
) -> Result<RouterConfigVariant> {
    if configured_router_workers(router_config_path)? == router_workers {
        return Ok(RouterConfigVariant {
            path: router_config_path.to_string(),
            cleanup_path: None,
        });
    }

    let mut value = load_router_config_value(router_config_path)?;
    let router = value
        .get_mut("router")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| anyhow!("router config {router_config_path} missing root router object"))?;
    let worker_pool = router.entry("worker_pool").or_insert_with(|| json!({}));
    let worker_pool = worker_pool.as_object_mut().ok_or_else(|| {
        anyhow!("router config {router_config_path} has non-object worker_pool entry")
    })?;
    worker_pool.insert("min_workers".to_string(), Value::from(router_workers));

    let file_name = format!(
        "connectanum_router_workers_{}_{}.json",
        router_workers,
        now_millis()
    );
    let path = std::env::temp_dir().join(file_name);
    let encoded =
        serde_json::to_vec_pretty(&value).context("failed to encode worker override config")?;
    std::fs::write(&path, encoded)
        .with_context(|| format!("failed to write {}", path.display()))?;
    Ok(RouterConfigVariant {
        path: path.to_string_lossy().into_owned(),
        cleanup_path: Some(path),
    })
}

fn print_router_worker_scaling_summary(reports: &[WorkloadReport]) {
    let workers = reports
        .iter()
        .map(|report| report.router_workers)
        .collect::<BTreeSet<_>>();
    if workers.len() <= 1 {
        return;
    }

    let summaries = reports
        .iter()
        .map(summarize_report)
        .collect::<Vec<WorkloadArtifactSummary>>();
    let mut grouped =
        BTreeMap::<(String, String, String, u32), Vec<WorkloadArtifactSummary>>::new();
    for summary in summaries {
        grouped
            .entry((
                summary.scenario.clone(),
                summary.workload.clone(),
                summary.protocol.clone(),
                summary.native_runtime_threads,
            ))
            .or_default()
            .push(summary);
    }

    let worker_list = workers
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(", ");
    println!("\n=== Router worker scaling summary ({worker_list}) ===");
    for ((scenario, workload, protocol, native_runtime_threads), mut entries) in grouped {
        entries.sort_by_key(|entry| entry.router_workers);
        println!(
            "  {scenario} / {workload} [{protocol}] runtime_threads={}",
            format_native_runtime_threads(native_runtime_threads)
        );
        for entry in entries {
            println!(
                "    workers {:>2}: {:.2} Mbps, p95 {:.2} ms, samples {}",
                entry.router_workers,
                entry.throughput_mbps,
                entry.latency_p95_ms,
                entry.sample_count
            );
        }
    }
}

fn print_native_runtime_thread_scaling_summary(reports: &[WorkloadReport]) {
    let native_runtime_threads = reports
        .iter()
        .map(|report| report.native_runtime_threads)
        .collect::<BTreeSet<_>>();
    if native_runtime_threads.len() <= 1 {
        return;
    }

    let summaries = reports
        .iter()
        .map(summarize_report)
        .collect::<Vec<WorkloadArtifactSummary>>();
    let mut grouped =
        BTreeMap::<(String, String, String, u32), Vec<WorkloadArtifactSummary>>::new();
    for summary in summaries {
        grouped
            .entry((
                summary.scenario.clone(),
                summary.workload.clone(),
                summary.protocol.clone(),
                summary.router_workers,
            ))
            .or_default()
            .push(summary);
    }

    let thread_list = native_runtime_threads
        .iter()
        .map(|value| format_native_runtime_threads(*value))
        .collect::<Vec<_>>()
        .join(", ");
    println!("\n=== Native runtime thread scaling summary ({thread_list}) ===");
    for ((scenario, workload, protocol, router_workers), mut entries) in grouped {
        entries.sort_by_key(|entry| entry.native_runtime_threads);
        println!("  {scenario} / {workload} [{protocol}] router_workers={router_workers}");
        for entry in entries {
            println!(
                "    threads {:>4}: {:.2} Mbps, p95 {:.2} ms, samples {}",
                format_native_runtime_threads(entry.native_runtime_threads),
                entry.throughput_mbps,
                entry.latency_p95_ms,
                entry.sample_count
            );
        }
    }
}

fn format_native_runtime_threads(value: u32) -> String {
    if value == 0 {
        "auto".to_string()
    } else {
        value.to_string()
    }
}

#[derive(Clone)]
struct HttpEndpoint {
    scheme: String,
    host: String,
    port: u16,
    http3_port: Option<u16>,
}

impl HttpEndpoint {
    fn from_control_base(base: &str, http3_port: Option<u16>) -> Result<Self> {
        let url = Url::parse(base).context("invalid control_base URL")?;
        let scheme = url.scheme().to_string();
        if scheme != "http" && scheme != "https" {
            bail!("Only http:// and https:// endpoints are supported (got {scheme})");
        }
        let host = url
            .host_str()
            .ok_or_else(|| anyhow!("control_base missing host"))?
            .to_string();
        let port = url
            .port_or_known_default()
            .ok_or_else(|| anyhow!("control_base missing port for scheme {scheme}"))?;
        Ok(Self {
            scheme,
            host,
            port,
            http3_port,
        })
    }

    fn http3_port(&self) -> u16 {
        self.http3_port.unwrap_or(self.port)
    }
}

#[derive(Debug, Deserialize)]
struct ScenarioFile {
    name: String,
    description: Option<String>,
    #[serde(default)]
    workloads: Vec<WorkloadConfig>,
}

#[derive(Debug, Clone, Deserialize)]
struct WorkloadConfig {
    name: String,
    #[serde(default = "default_protocol")]
    protocol: String,
    #[serde(default = "default_method")]
    method: String,
    #[serde(default = "default_path")]
    path: String,
    #[serde(default = "default_iterations")]
    iterations: u32,
    #[serde(default = "default_concurrency")]
    concurrency: u32,
    #[serde(default = "default_request_bytes")]
    request_bytes: u64,
    #[serde(default = "default_response_bytes")]
    response_bytes: u64,
    #[serde(default = "default_chunk_bytes")]
    request_chunk_bytes: u64,
    #[serde(default)]
    response_chunk_bytes: Option<u64>,
    #[serde(default)]
    warmup_ms: Option<u64>,
    #[serde(default = "default_reuse_connections")]
    reuse_connections: bool,
}

fn default_protocol() -> String {
    "h2".to_string()
}

fn default_method() -> String {
    "POST".to_string()
}

fn default_path() -> String {
    "/bench/stream".to_string()
}

fn default_iterations() -> u32 {
    1
}

fn default_concurrency() -> u32 {
    1
}

fn default_request_bytes() -> u64 {
    64 * 1024
}

fn default_response_bytes() -> u64 {
    64 * 1024
}

fn default_chunk_bytes() -> u64 {
    64 * 1024
}

fn default_reuse_connections() -> bool {
    true
}

fn load_scenario(path: &str) -> Result<ScenarioFile> {
    let contents = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read scenario file {path}"))?;
    let scenario: ScenarioFile =
        toml::from_str(&contents).context("failed to parse scenario TOML")?;
    if scenario.workloads.is_empty() {
        bail!("Scenario {} does not define any workloads", scenario.name);
    }
    Ok(scenario)
}

fn load_scenarios(path: &str) -> Result<Vec<(ScenarioFile, String)>> {
    let metadata =
        std::fs::metadata(path).with_context(|| format!("failed to stat scenario path {path}"))?;
    if metadata.is_dir() {
        let mut files = Vec::new();
        for entry in std::fs::read_dir(path)? {
            let entry = entry?;
            if entry.file_type()?.is_file() {
                let path_buf = entry.path();
                if path_buf
                    .extension()
                    .and_then(|ext| ext.to_str())
                    .map(|ext| ext.eq_ignore_ascii_case("toml"))
                    .unwrap_or(false)
                {
                    files.push(path_buf);
                }
            }
        }
        if files.is_empty() {
            bail!("No *.toml scenarios found in directory {path}");
        }
        files.sort();
        let mut scenarios = Vec::with_capacity(files.len());
        for path_buf in files {
            let path_str = path_buf.to_string_lossy().into_owned();
            scenarios.push((load_scenario(&path_str)?, path_str));
        }
        Ok(scenarios)
    } else {
        Ok(vec![(load_scenario(path)?, path.to_string())])
    }
}

fn infer_h3_port(router_config_path: &str) -> Option<u16> {
    let contents = std::fs::read_to_string(router_config_path).ok()?;
    let value: Value = serde_json::from_str(&contents).ok()?;
    value
        .get("router")?
        .get("listeners")?
        .as_array()?
        .get(0)?
        .get("http")?
        .get("http3")?
        .get("port")?
        .as_u64()
        .and_then(|v| u16::try_from(v).ok())
}

#[derive(Clone)]
struct PreparedWorkload {
    name: String,
    protocol: String,
    method: HyperMethod,
    path: String,
    iterations: u32,
    concurrency: u32,
    request_bytes: u64,
    response_bytes: u64,
    request_chunk_bytes: u64,
    response_chunk_bytes: u64,
    reuse_connections: bool,
}

impl PreparedWorkload {
    fn from_config(config: &WorkloadConfig) -> Result<Self> {
        if config.iterations == 0 {
            bail!("workload {} must have at least one iteration", config.name);
        }
        if config.concurrency == 0 {
            bail!("workload {} must have concurrency >= 1", config.name);
        }
        if config.request_chunk_bytes == 0 {
            bail!("request_chunk_bytes must be > 0");
        }
        let method = config
            .method
            .parse::<HyperMethod>()
            .map_err(|_| anyhow!("invalid HTTP method {}", config.method))?;
        let is_wamp = matches!(
            config.protocol.to_lowercase().as_str(),
            "wamp_pubsub" | "wamp_rpc"
        );
        let path = if is_wamp {
            config.path.clone()
        } else if config.path.starts_with('/') {
            config.path.clone()
        } else {
            format!("/{}", config.path)
        };
        Ok(Self {
            name: config.name.clone(),
            protocol: config.protocol.clone(),
            method,
            path,
            iterations: config.iterations,
            concurrency: config.concurrency,
            request_bytes: config.request_bytes,
            response_bytes: config.response_bytes,
            request_chunk_bytes: config.request_chunk_bytes,
            response_chunk_bytes: config
                .response_chunk_bytes
                .unwrap_or(config.request_chunk_bytes),
            reuse_connections: config.reuse_connections,
        })
    }

    fn is_wamp(&self) -> bool {
        matches!(
            self.protocol.to_lowercase().as_str(),
            "wamp_pubsub" | "wamp_rpc"
        )
    }
}

struct ResultsWriter {
    file: File,
}

impl ResultsWriter {
    fn create(path: &str) -> Result<Self> {
        if let Some(parent) = Path::new(path).parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)
                    .with_context(|| format!("failed to create {}", parent.display()))?;
            }
        }
        let file =
            File::create(Path::new(path)).with_context(|| format!("failed to create {}", path))?;
        Ok(Self { file })
    }

    fn write(&mut self, report: &WorkloadReport) -> Result<()> {
        let line = serde_json::to_string(report)?;
        self.file.write_all(line.as_bytes())?;
        self.file.write_all(b"\n")?;
        self.file.flush()?;
        Ok(())
    }
}

fn print_workload_summary(report: &WorkloadReport, workload: &PreparedWorkload) {
    let total_samples = report.samples.len();
    let total_latency: f64 = report.samples.iter().map(|s| s.latency_ms).sum();
    let total_requests: u64 = report.samples.iter().map(|s| s.request_bytes).sum();
    let total_responses: u64 = report.samples.iter().map(|s| s.response_bytes).sum();
    let total_payload = total_requests + total_responses;
    let avg_latency = if total_samples > 0 {
        total_latency / total_samples as f64
    } else {
        0.0
    };
    let elapsed_ms = (report.completed_at_ms - report.started_at_ms) as f64;
    let response_throughput_mbps = if elapsed_ms > 0.0 {
        (total_responses as f64 * 8.0 / 1_000_000.0) / (elapsed_ms / 1000.0)
    } else {
        0.0
    };
    let payload_throughput_mbps = if elapsed_ms > 0.0 {
        (total_payload as f64 * 8.0 / 1_000_000.0) / (elapsed_ms / 1000.0)
    } else {
        0.0
    };

    println!("  Samples: {total_samples}");
    println!(
        "  Avg latency: {:.2} ms (min {:.2} ms / max {:.2} ms)",
        avg_latency,
        report
            .samples
            .iter()
            .map(|s| s.latency_ms)
            .fold(f64::MAX, f64::min),
        report
            .samples
            .iter()
            .map(|s| s.latency_ms)
            .fold(0.0, f64::max)
    );
    println!(
        "  Bytes uploaded: {} | Bytes downloaded: {}",
        format_bytes(total_requests),
        format_bytes(total_responses)
    );
    println!(
        "  Response throughput: {:.2} Mbps | Total payload throughput: {:.2} Mbps",
        response_throughput_mbps, payload_throughput_mbps
    );
    println!(
        "  Native runtime threads: {}",
        format_native_runtime_threads(report.native_runtime_threads)
    );
    println!("  Router workers: {}", report.router_workers);
    if let Some(delta) = router_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "total_invocations_dispatched",
    ) {
        println!("  Router invocations: Δ{delta}");
    }
    if let Some(delta) = router_counter_delta(
        &report.metrics_before,
        &report.metrics_after,
        "total_publications_routed",
    ) {
        println!("  Router publications: Δ{delta}");
    }
    println!(
        "  Workload payloads: request {} (chunk {}), response {} (chunk {})",
        format_bytes(workload.request_bytes),
        format_bytes(workload.request_chunk_bytes),
        format_bytes(workload.response_bytes),
        format_bytes(workload.response_chunk_bytes)
    );
    println!(
        "  Connection reuse: {}",
        if workload.reuse_connections {
            "enabled"
        } else {
            "disabled"
        }
    );
}

fn format_bytes(bytes: u64) -> String {
    const UNITS: [&str; 4] = ["B", "KiB", "MiB", "GiB"];
    let mut value = bytes as f64;
    let mut unit = 0usize;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    format!("{:.2} {}", value, UNITS[unit])
}

fn now_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

fn split_metrics_payload(mut value: Value) -> (Value, Option<String>) {
    let open_metrics = value
        .as_object_mut()
        .and_then(|map| map.remove("open_metrics"))
        .and_then(|raw| raw.as_str().map(|s| s.to_string()));
    (value, open_metrics)
}

fn run_wamp_workload(
    http_control: &BenchHttpClient,
    workload: &PreparedWorkload,
) -> Result<Vec<WorkloadSample>> {
    let mode = match workload.protocol.to_lowercase().as_str() {
        "wamp_pubsub" => "pubsub",
        "wamp_rpc" => "rpc",
        other => bail!("unsupported WAMP workload {other}"),
    };
    let body = json!({
        "mode": mode,
        "uri": workload.path,
        "iterations": workload.iterations,
        "concurrency": workload.concurrency,
        "payload_bytes": workload.request_bytes,
    });
    let response = http_control.post_json("wamp", &body)?;
    let samples_value = response
        .get("samples")
        .cloned()
        .ok_or_else(|| anyhow!("WAMP response missing samples field"))?;
    let samples: Vec<WorkloadSample> =
        serde_json::from_value(samples_value).context("failed to decode WAMP workload samples")?;
    Ok(samples)
}

async fn execute_workload(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    timeout: Duration,
) -> Result<Vec<WorkloadSample>> {
    match workload.protocol.as_str() {
        "h1" | "http1" | "http" => run_h1_workload(endpoint, workload, timeout).await,
        "h2" | "http2" => run_h2_workload(endpoint, workload, timeout).await,
        "h3" | "http3" => run_h3_workload(endpoint, workload, timeout).await,
        other => bail!("unsupported protocol {other}"),
    }
}

async fn run_h1_workload(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    timeout: Duration,
) -> Result<Vec<WorkloadSample>> {
    let mut join_set = JoinSet::new();
    for worker_id in 0..workload.concurrency {
        let endpoint_clone = endpoint.clone();
        let workload_clone = workload.clone();
        join_set
            .spawn(async move { run_h1_worker(endpoint_clone, workload_clone, worker_id).await });
    }
    let label = format!("{} [HTTP/1.1]", workload.name.as_str());
    collect_worker_samples(join_set, timeout, &label).await
}

async fn run_h1_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<Vec<WorkloadSample>> {
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let request_body = build_payload(
        workload.request_bytes,
        workload.request_chunk_bytes as usize,
    );
    if workload.reuse_connections {
        let mut sender = connect_h1_sender(&endpoint).await?;
        for iteration in 0..workload.iterations {
            let sample = match send_h1_request(
                &mut sender,
                &endpoint,
                &workload,
                request_body.clone(),
                worker_id,
                iteration,
            )
            .await
            {
                Ok(sample) => sample,
                Err(first_error) => {
                    sender = connect_h1_sender(&endpoint).await.with_context(|| {
                        format!(
                            "failed to reconnect HTTP/1.1 worker {} after {}",
                            worker_id, first_error
                        )
                    })?;
                    send_h1_request(
                        &mut sender,
                        &endpoint,
                        &workload,
                        request_body.clone(),
                        worker_id,
                        iteration,
                    )
                    .await
                    .with_context(|| {
                        format!(
                            "HTTP/1.1 worker {} request {} failed after reconnect",
                            worker_id, iteration
                        )
                    })?
                }
            };
            samples.push(sample);
        }
        return Ok(samples);
    }
    for iteration in 0..workload.iterations {
        let sample = run_h1_iteration(
            &endpoint,
            &workload,
            request_body.clone(),
            worker_id,
            iteration,
        )
        .await?;
        samples.push(sample);
    }
    Ok(samples)
}

async fn run_h2_workload(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    timeout: Duration,
) -> Result<Vec<WorkloadSample>> {
    let mut join_set = JoinSet::new();
    for worker_id in 0..workload.concurrency {
        let endpoint_clone = endpoint.clone();
        let workload_clone = workload.clone();
        join_set
            .spawn(async move { run_h2_worker(endpoint_clone, workload_clone, worker_id).await });
    }
    let label = format!("{} [HTTP/2]", workload.name.as_str());
    collect_worker_samples(join_set, timeout, &label).await
}

async fn run_h2_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<Vec<WorkloadSample>> {
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let request_body = build_payload(
        workload.request_bytes,
        workload.request_chunk_bytes as usize,
    );
    if workload.reuse_connections {
        let mut sender = connect_h2_sender(&endpoint).await?;
        for iteration in 0..workload.iterations {
            let sample = match send_h2_request(
                &mut sender,
                &endpoint,
                &workload,
                request_body.clone(),
                worker_id,
                iteration,
            )
            .await
            {
                Ok(sample) => sample,
                Err(first_error) => {
                    sender = connect_h2_sender(&endpoint).await.with_context(|| {
                        format!(
                            "failed to reconnect HTTP/2 worker {} after {}",
                            worker_id, first_error
                        )
                    })?;
                    send_h2_request(
                        &mut sender,
                        &endpoint,
                        &workload,
                        request_body.clone(),
                        worker_id,
                        iteration,
                    )
                    .await
                    .with_context(|| {
                        format!(
                            "HTTP/2 worker {} request {} failed after reconnect",
                            worker_id, iteration
                        )
                    })?
                }
            };
            samples.push(sample);
        }
        return Ok(samples);
    }
    for iteration in 0..workload.iterations {
        let sample = run_h2_iteration(
            &endpoint,
            &workload,
            request_body.clone(),
            worker_id,
            iteration,
        )
        .await?;
        samples.push(sample);
    }
    Ok(samples)
}

async fn run_h3_workload(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    timeout: Duration,
) -> Result<Vec<WorkloadSample>> {
    let mut join_set = JoinSet::new();
    for worker_id in 0..workload.concurrency {
        let endpoint_clone = endpoint.clone();
        let workload_clone = workload.clone();
        join_set
            .spawn(async move { run_h3_worker(endpoint_clone, workload_clone, worker_id).await });
    }
    let label = format!("{} [HTTP/3]", workload.name.as_str());
    collect_worker_samples(join_set, timeout, &label).await
}

async fn run_h3_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<Vec<WorkloadSample>> {
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let request_chunk =
        build_pattern_chunk(std::cmp::max(1, workload.request_chunk_bytes as usize));
    if workload.reuse_connections {
        let (mut quinn_endpoint, mut send_request) = connect_h3_sender(&endpoint).await?;
        for iteration in 0..workload.iterations {
            let sample = match send_h3_request(
                &mut send_request,
                &endpoint,
                &workload,
                &request_chunk,
                worker_id,
                iteration,
            )
            .await
            {
                Ok(sample) => sample,
                Err(first_error) => {
                    quinn_endpoint.close(0u32.into(), b"reconnect");
                    let (new_endpoint, new_send_request) =
                        connect_h3_sender(&endpoint).await.with_context(|| {
                            format!(
                                "failed to reconnect HTTP/3 worker {} after {}",
                                worker_id, first_error
                            )
                        })?;
                    quinn_endpoint = new_endpoint;
                    send_request = new_send_request;
                    send_h3_request(
                        &mut send_request,
                        &endpoint,
                        &workload,
                        &request_chunk,
                        worker_id,
                        iteration,
                    )
                    .await
                    .with_context(|| {
                        format!(
                            "HTTP/3 worker {} request {} failed after reconnect",
                            worker_id, iteration
                        )
                    })?
                }
            };
            samples.push(sample);
        }
        quinn_endpoint.close(0u32.into(), b"done");
        return Ok(samples);
    }
    for iteration in 0..workload.iterations {
        let sample =
            run_h3_iteration(&endpoint, &workload, &request_chunk, worker_id, iteration).await?;
        samples.push(sample);
    }
    Ok(samples)
}

async fn collect_worker_samples(
    mut join_set: JoinSet<Result<Vec<WorkloadSample>>>,
    timeout: Duration,
    label: &str,
) -> Result<Vec<WorkloadSample>> {
    let mut samples = Vec::new();
    let start = Instant::now();
    loop {
        let elapsed = start.elapsed();
        if elapsed >= timeout {
            join_set.shutdown().await;
            bail!("{label} timed out after {:?}", timeout);
        }
        let remaining = timeout - elapsed;
        match tokio::time::timeout(remaining, join_set.join_next()).await {
            Ok(Some(join_result)) => {
                let worker_samples =
                    join_result.map_err(|err| anyhow!("{label} worker failed: {err}"))??;
                samples.extend(worker_samples);
            }
            Ok(None) => break,
            Err(_) => {
                join_set.shutdown().await;
                bail!("{label} timed out after {:?}", timeout);
            }
        }
    }
    Ok(samples)
}

async fn connect_h1_sender(
    endpoint: &HttpEndpoint,
) -> Result<hyper::client::conn::SendRequest<Body>> {
    let addr = format!("{}:{}", endpoint.host, endpoint.port);
    let stream = tokio::net::TcpStream::connect(&addr)
        .await
        .with_context(|| format!("failed to connect to {}", addr))?;
    stream.set_nodelay(true)?;
    let builder = HyperConnBuilder::new();
    if endpoint.scheme == "https" {
        let connector = TlsConnector::from(insecure_rustls_client_config(&[b"http/1.1"]));
        let server_name = ServerName::try_from(endpoint.host.clone())
            .map_err(|_| anyhow!("invalid TLS server name {}", endpoint.host))?;
        let tls_stream = connector
            .connect(server_name, stream)
            .await
            .context("TLS handshake failed")?;
        let (sender, connection) = builder
            .handshake::<_, Body>(tls_stream)
            .await
            .context("HTTP/1.1 handshake failed")?;
        tokio::spawn(async move {
            if let Err(err) = connection.await {
                eprintln!("hyper connection error: {err:?}");
            }
        });
        Ok(sender)
    } else {
        let (sender, connection) = builder
            .handshake::<_, Body>(stream)
            .await
            .context("HTTP/1.1 handshake failed")?;
        tokio::spawn(async move {
            if let Err(err) = connection.await {
                eprintln!("hyper connection error: {err:?}");
            }
        });
        Ok(sender)
    }
}

fn build_http_request(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    absolute_uri: bool,
) -> Result<Request<Body>> {
    let uri = if absolute_uri {
        format!(
            "{}://{}:{}{}",
            endpoint.scheme, endpoint.host, endpoint.port, workload.path
        )
    } else {
        workload.path.clone()
    };
    let mut request_builder = Request::builder().method(workload.method.clone()).uri(uri);
    let headers = request_builder.headers_mut().unwrap();
    if !absolute_uri {
        headers.insert(
            "host",
            HyperHeaderValue::from_str(&endpoint_authority(endpoint))
                .context("invalid host header value")?,
        );
    }
    headers.insert(
        "content-type",
        HyperHeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        "x-bench-response-bytes",
        HyperHeaderValue::from_str(&workload.response_bytes.to_string())
            .unwrap_or_else(|_| HyperHeaderValue::from_static("0")),
    );
    headers.insert(
        "x-bench-response-chunk-bytes",
        HyperHeaderValue::from_str(&workload.response_chunk_bytes.to_string())
            .unwrap_or_else(|_| HyperHeaderValue::from_static("1024")),
    );
    headers.insert(ACCEPT, HyperHeaderValue::from_static("*/*"));
    headers.insert(
        USER_AGENT,
        HyperHeaderValue::from_static("connectanum-bench/0.1"),
    );
    request_builder
        .body(Body::from(request_body))
        .context("failed to build HTTP request")
}

fn endpoint_authority(endpoint: &HttpEndpoint) -> String {
    let default_port = match endpoint.scheme.as_str() {
        "http" => 80,
        "https" => 443,
        _ => endpoint.port,
    };
    if endpoint.port == default_port {
        endpoint.host.clone()
    } else {
        format!("{}:{}", endpoint.host, endpoint.port)
    }
}

async fn connect_h2_sender(
    endpoint: &HttpEndpoint,
) -> Result<hyper::client::conn::SendRequest<Body>> {
    let addr = format!("{}:{}", endpoint.host, endpoint.port);
    let stream = tokio::net::TcpStream::connect(&addr)
        .await
        .with_context(|| format!("failed to connect to {}", addr))?;
    stream.set_nodelay(true)?;
    let mut builder = HyperConnBuilder::new();
    builder.http2_only(true);
    if endpoint.scheme == "https" {
        let connector = TlsConnector::from(insecure_rustls_client_config(&[b"h2"]));
        let server_name = ServerName::try_from(endpoint.host.clone())
            .map_err(|_| anyhow!("invalid TLS server name {}", endpoint.host))?;
        let tls_stream = connector
            .connect(server_name, stream)
            .await
            .context("TLS handshake failed")?;
        let (sender, connection) = builder
            .handshake::<_, Body>(tls_stream)
            .await
            .context("HTTP/2 handshake failed")?;
        tokio::spawn(async move {
            if let Err(err) = connection.await {
                eprintln!("hyper connection error: {err:?}");
            }
        });
        Ok(sender)
    } else {
        let (sender, connection) = builder
            .handshake::<_, Body>(stream)
            .await
            .context("HTTP/2 handshake failed")?;
        tokio::spawn(async move {
            if let Err(err) = connection.await {
                eprintln!("hyper connection error: {err:?}");
            }
        });
        Ok(sender)
    }
}

fn build_h2_request(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
) -> Result<Request<Body>> {
    build_http_request(endpoint, workload, request_body, true)
        .context("failed to build HTTP/2 request")
}

async fn drain_hyper_response(response: hyper::Response<Body>) -> Result<u64> {
    let status = response.status();
    let mut body = response.into_body();
    let mut received = 0u64;
    let mut error_body = Vec::new();
    while let Some(chunk) = body.data().await {
        let bytes = chunk?;
        received += bytes.len() as u64;
        if !status.is_success() && error_body.len() < 256 {
            let remaining = 256 - error_body.len();
            error_body.extend_from_slice(&bytes[..bytes.len().min(remaining)]);
        }
    }
    if !status.is_success() {
        let preview = String::from_utf8_lossy(&error_body);
        bail!("unexpected HTTP status {} with body {}", status, preview);
    }
    Ok(received)
}

async fn send_h1_request(
    sender: &mut hyper::client::conn::SendRequest<Body>,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let request = build_http_request(endpoint, workload, request_body, false)?;
    let start = Instant::now();
    let response = sender
        .send_request(request)
        .await
        .context("failed to send request")?;

    let received = drain_hyper_response(response).await?;
    let latency_ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms,
        request_bytes: workload.request_bytes,
        response_bytes: received,
    })
}

async fn run_h1_iteration(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let mut sender = connect_h1_sender(endpoint).await?;
    send_h1_request(
        &mut sender,
        endpoint,
        workload,
        request_body,
        worker_id,
        iteration,
    )
    .await
}

async fn send_h2_request(
    sender: &mut hyper::client::conn::SendRequest<Body>,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let request = build_h2_request(endpoint, workload, request_body)?;
    let start = Instant::now();
    let response = sender
        .send_request(request)
        .await
        .context("failed to send request")?;

    let received = drain_hyper_response(response).await?;
    let latency_ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms,
        request_bytes: workload.request_bytes,
        response_bytes: received,
    })
}

async fn run_h2_iteration(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let mut sender = connect_h2_sender(endpoint).await?;
    send_h2_request(
        &mut sender,
        endpoint,
        workload,
        request_body,
        worker_id,
        iteration,
    )
    .await
}

async fn connect_h3_sender(endpoint: &HttpEndpoint) -> Result<(QuinnEndpoint, H3RequestSender)> {
    let bind_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 0);
    let mut quinn_endpoint =
        QuinnEndpoint::client(bind_addr).context("failed to bind quic endpoint")?;
    let client_config = quinn_client_config();
    quinn_endpoint.set_default_client_config(client_config);
    let server_port = endpoint.http3_port();
    let mut resolved: Vec<_> = lookup_host((&endpoint.host[..], server_port))
        .await
        .with_context(|| format!("failed to resolve {}", endpoint.host))?
        .collect();
    sort_socket_addrs_prefer_ipv4(&mut resolved);
    let mut connection = None;
    let mut last_error = None;
    for server_addr in resolved {
        let connecting = match quinn_endpoint.connect(server_addr, &endpoint.host) {
            Ok(connecting) => connecting,
            Err(err) => {
                last_error = Some(anyhow!(
                    "failed to start QUIC connect for {}: {}",
                    server_addr,
                    err
                ));
                continue;
            }
        };
        match connecting.await {
            Ok(established) => {
                connection = Some(established);
                break;
            }
            Err(err) => {
                last_error = Some(anyhow!("QUIC connect failed for {}: {}", server_addr, err));
            }
        }
    }
    let connection = connection.ok_or_else(|| {
        last_error.unwrap_or_else(|| anyhow!("no addresses for {}", endpoint.host))
    })?;
    let h3_conn = H3QuinnConnection::new(connection);
    let (driver, send_request) = h3::client::builder()
        .max_field_section_size(64 * 1024)
        .build(h3_conn)
        .await
        .context("failed to create h3 client")?;
    tokio::spawn(async move {
        let mut conn = driver;
        let _ = conn.wait_idle().await;
    });
    Ok((quinn_endpoint, send_request))
}

async fn send_h3_request(
    send_request: &mut H3RequestSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_chunk: &Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let server_port = endpoint.http3_port();
    let uri = format!("https://{}:{}{}", endpoint.host, server_port, workload.path);
    let h3_method = http3::Method::from_bytes(workload.method.as_str().as_bytes())
        .map_err(|_| anyhow!("invalid HTTP/3 method {}", workload.method))?;
    let mut request_builder = http3::Request::builder().method(h3_method).uri(uri);
    let headers = request_builder
        .headers_mut()
        .ok_or_else(|| anyhow!("unable to access request headers"))?;
    headers.insert(
        http3::header::HeaderName::from_static("content-type"),
        http3::header::HeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        http3::header::HeaderName::from_static("x-bench-response-bytes"),
        http3::header::HeaderValue::from_str(&workload.response_bytes.to_string())
            .unwrap_or_else(|_| http3::header::HeaderValue::from_static("0")),
    );
    headers.insert(
        http3::header::HeaderName::from_static("x-bench-response-chunk-bytes"),
        http3::header::HeaderValue::from_str(&workload.response_chunk_bytes.to_string())
            .unwrap_or_else(|_| http3::header::HeaderValue::from_static("1024")),
    );
    headers.insert(
        http3::header::HeaderName::from_static("accept"),
        http3::header::HeaderValue::from_static("*/*"),
    );
    headers.insert(
        http3::header::HeaderName::from_static("user-agent"),
        http3::header::HeaderValue::from_static("connectanum-bench/0.1"),
    );
    let request = request_builder
        .body(())
        .expect("failed to build HTTP/3 request");

    let start = Instant::now();
    let mut req_stream = send_request
        .send_request(request)
        .await
        .context("failed to open HTTP/3 request stream")?;

    let mut sent = 0u64;
    if workload.request_bytes == 0 {
        req_stream
            .finish()
            .await
            .context("failed to finish request")?;
    } else {
        let mut remaining = workload.request_bytes;
        while remaining > 0 {
            let chunk_len = std::cmp::min(remaining, request_chunk.len() as u64) as usize;
            req_stream
                .send_data(request_chunk.slice(..chunk_len))
                .await
                .context("failed to send HTTP/3 request chunk")?;
            remaining -= chunk_len as u64;
            sent += chunk_len as u64;
        }
        req_stream
            .finish()
            .await
            .context("failed to finish request")?;
    }

    let response = req_stream
        .recv_response()
        .await
        .context("failed to receive HTTP/3 response headers")?;
    let mut received = 0u64;
    let mut error_body = Vec::new();
    while let Some(chunk) = req_stream
        .recv_data()
        .await
        .context("failed to read HTTP/3 body")?
    {
        let mut chunk = chunk;
        let chunk_len = chunk.remaining();
        if !response.status().is_success() && error_body.len() < 256 {
            let remaining = 256 - error_body.len();
            error_body.extend_from_slice(&chunk.copy_to_bytes(chunk_len.min(remaining)));
        }
        received += chunk_len as u64;
    }
    if !response.status().is_success() {
        let preview = String::from_utf8_lossy(&error_body);
        bail!(
            "unexpected HTTP/3 status {} with body {}",
            response.status(),
            preview
        );
    }

    let latency_ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms,
        request_bytes: sent,
        response_bytes: received,
    })
}

async fn run_h3_iteration(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_chunk: &Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let (quinn_endpoint, mut send_request) = connect_h3_sender(endpoint).await?;
    let sample = send_h3_request(
        &mut send_request,
        endpoint,
        workload,
        request_chunk,
        worker_id,
        iteration,
    )
    .await;
    quinn_endpoint.close(0u32.into(), b"done");
    sample
}

fn build_payload(total_bytes: u64, chunk_len: usize) -> Bytes {
    if total_bytes == 0 {
        return Bytes::new();
    }
    let mut buffer = vec![0u8; total_bytes as usize];
    let chunk = build_pattern_chunk(std::cmp::max(1, chunk_len));
    for (idx, byte) in buffer.iter_mut().enumerate() {
        *byte = chunk[idx % chunk.len()];
    }
    Bytes::from(buffer)
}

fn build_pattern_chunk(len: usize) -> Bytes {
    let mut bytes = vec![0u8; len];
    for (i, byte) in bytes.iter_mut().enumerate() {
        *byte = ((i * 31) & 0xFF) as u8;
    }
    Bytes::from(bytes)
}

fn sort_socket_addrs_prefer_ipv4(addrs: &mut Vec<SocketAddr>) {
    addrs.sort_by_key(|addr| if addr.is_ipv4() { 0u8 } else { 1u8 });
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };
    use std::time::{SystemTime, UNIX_EPOCH};

    use hyper::service::service_fn;
    use hyper::{server::conn::Http as HyperServerHttp, Response};
    use serde_json::json;
    use tokio::net::TcpListener;

    use super::*;

    fn sample(worker: u32) -> WorkloadSample {
        WorkloadSample {
            worker,
            iteration: 0,
            latency_ms: 0.0,
            request_bytes: 0,
            response_bytes: 0,
        }
    }

    #[tokio::test]
    async fn collect_worker_samples_dries_out_tasks() {
        let mut join_set = JoinSet::new();
        join_set.spawn(async move { Ok(vec![sample(0)]) });
        join_set.spawn(async move { Ok(vec![sample(1)]) });
        let samples = collect_worker_samples(join_set, Duration::from_millis(50), "test")
            .await
            .unwrap();
        assert_eq!(samples.len(), 2);
    }

    #[tokio::test]
    async fn collect_worker_samples_times_out() {
        let mut join_set = JoinSet::new();
        join_set.spawn(async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            Ok(vec![sample(42)])
        });
        let error = collect_worker_samples(join_set, Duration::from_millis(5), "timeout")
            .await
            .unwrap_err();
        assert!(
            error.to_string().contains("timed out"),
            "unexpected error {error}"
        );
    }

    #[test]
    fn split_metrics_payload_extracts_open_metrics_text() {
        let (metrics, open_metrics) = split_metrics_payload(json!({
            "metrics": {
                "total_publications_routed": 5
            },
            "open_metrics": "# TYPE foo counter\nfoo 1\n"
        }));
        assert_eq!(
            metrics["metrics"]["total_publications_routed"].as_i64(),
            Some(5)
        );
        assert_eq!(open_metrics.as_deref(), Some("# TYPE foo counter\nfoo 1\n"));
    }

    #[test]
    fn results_writer_creates_parent_directory_and_writes_jsonl() {
        let temp_dir = unique_temp_dir("results_writer");
        let path = temp_dir.join("nested").join("bench_results.jsonl");
        let report = WorkloadReport {
            scenario: "scenario".to_string(),
            workload: "workload".to_string(),
            protocol: "h2".to_string(),
            router_workers: 2,
            native_runtime_threads: 4,
            iterations: 1,
            concurrency: 1,
            started_at_ms: 1,
            completed_at_ms: 2,
            metrics_before: json!({}),
            metrics_after: json!({}),
            open_metrics_before: None,
            open_metrics_after: None,
            scenario_metrics_before: None,
            scenario_metrics_after: None,
            scenario_open_metrics_before: None,
            scenario_open_metrics_after: None,
            samples: vec![sample(0)],
        };

        let mut writer = ResultsWriter::create(path.to_string_lossy().as_ref()).unwrap();
        writer.write(&report).unwrap();

        let written = fs::read_to_string(&path).unwrap();
        assert!(written.contains("\"scenario\":\"scenario\""));
        assert!(written.ends_with('\n'));

        fs::remove_dir_all(&temp_dir).unwrap();
    }

    #[test]
    fn http_endpoint_accepts_https_control_base() {
        let endpoint =
            HttpEndpoint::from_control_base("https://localhost:8080/bench", Some(8443)).unwrap();
        assert_eq!(endpoint.scheme, "https");
        assert_eq!(endpoint.host, "localhost");
        assert_eq!(endpoint.port, 8080);
        assert_eq!(endpoint.http3_port(), 8443);
    }

    #[test]
    fn prepared_workload_defaults_to_connection_reuse() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: default_protocol(),
            method: default_method(),
            path: default_path(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            request_bytes: default_request_bytes(),
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
        };
        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert!(prepared.reuse_connections);
    }

    #[test]
    fn build_http1_request_uses_origin_form_and_host_header() {
        let endpoint =
            HttpEndpoint::from_control_base("https://localhost:8080/bench", Some(8443)).unwrap();
        let workload = PreparedWorkload {
            name: "h1_test".to_string(),
            protocol: "h1".to_string(),
            method: HyperMethod::POST,
            path: "/bench/stream".to_string(),
            iterations: 1,
            concurrency: 1,
            request_bytes: 0,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections: true,
        };
        let request = build_http_request(&endpoint, &workload, Bytes::new(), false).unwrap();
        assert_eq!(request.uri().path(), "/bench/stream");
        assert_eq!(request.uri().scheme_str(), None);
        assert_eq!(
            request.headers().get("host").unwrap(),
            &HyperHeaderValue::from_static("localhost:8080")
        );
    }

    #[tokio::test]
    async fn drain_hyper_response_rejects_non_success_status() {
        let response = Response::builder()
            .status(404)
            .body(Body::from("not-found"))
            .unwrap();
        let error = drain_hyper_response(response).await.unwrap_err();
        assert!(error.to_string().contains("404"));
        assert!(error.to_string().contains("not-found"));
    }

    #[test]
    fn parse_router_worker_counts_supports_ranges_and_deduplicates() {
        let counts = parse_router_worker_counts("4,1-3,2,6").unwrap();
        assert_eq!(counts, vec![1, 2, 3, 4, 6]);
    }

    #[test]
    fn parse_router_worker_counts_rejects_zero() {
        let error = parse_router_worker_counts("0,1").unwrap_err();
        assert!(error.to_string().contains(">= 1"));
    }

    #[test]
    fn parse_native_runtime_thread_counts_supports_auto_ranges_and_deduplicates() {
        let counts = parse_native_runtime_thread_counts("auto,4,1-3,2").unwrap();
        assert_eq!(counts, vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn parse_native_runtime_thread_counts_rejects_zero() {
        let error = parse_native_runtime_thread_counts("0,1").unwrap_err();
        assert!(error.to_string().contains(">= 1"));
    }

    #[test]
    fn prepare_router_config_variant_overrides_worker_pool() {
        let temp_dir = unique_temp_dir("router_config_override");
        fs::create_dir_all(&temp_dir).unwrap();
        let router_config = temp_dir.join("router.json");
        fs::write(
            &router_config,
            serde_json::to_vec_pretty(&json!({
                "router": {
                    "listeners": [],
                    "realms": []
                }
            }))
            .unwrap(),
        )
        .unwrap();

        let variant =
            prepare_router_config_variant(router_config.to_string_lossy().as_ref(), 4).unwrap();
        let overridden: Value = serde_json::from_slice(&fs::read(&variant.path).unwrap()).unwrap();
        assert_eq!(extract_router_workers(&overridden), 4);
        variant.cleanup();
        fs::remove_dir_all(&temp_dir).unwrap();
    }

    async fn spawn_h2_test_server() -> (
        HttpEndpoint,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        tokio::task::JoinHandle<()>,
    ) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let accept_count = Arc::new(AtomicUsize::new(0));
        let request_count = Arc::new(AtomicUsize::new(0));
        let accept_count_for_task = Arc::clone(&accept_count);
        let request_count_for_task = Arc::clone(&request_count);
        let server = tokio::spawn(async move {
            loop {
                let (stream, _) = match listener.accept().await {
                    Ok(value) => value,
                    Err(_) => break,
                };
                accept_count_for_task.fetch_add(1, Ordering::SeqCst);
                let request_count_for_conn = Arc::clone(&request_count_for_task);
                tokio::spawn(async move {
                    let service = service_fn(move |request: Request<Body>| {
                        let request_count_for_req = Arc::clone(&request_count_for_conn);
                        async move {
                            let mut body = request.into_body();
                            while let Some(chunk) = body.data().await {
                                chunk?;
                            }
                            request_count_for_req.fetch_add(1, Ordering::SeqCst);
                            Ok::<_, hyper::Error>(Response::new(Body::from("ok")))
                        }
                    });
                    let _ = HyperServerHttp::new()
                        .http2_only(true)
                        .serve_connection(stream, service)
                        .await;
                });
            }
        });
        (
            HttpEndpoint {
                scheme: "http".to_string(),
                host: Ipv4Addr::LOCALHOST.to_string(),
                port: addr.port(),
                http3_port: None,
            },
            accept_count,
            request_count,
            server,
        )
    }

    async fn spawn_h1_test_server() -> (
        HttpEndpoint,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        tokio::task::JoinHandle<()>,
    ) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let accept_count = Arc::new(AtomicUsize::new(0));
        let request_count = Arc::new(AtomicUsize::new(0));
        let accept_count_for_task = Arc::clone(&accept_count);
        let request_count_for_task = Arc::clone(&request_count);
        let server = tokio::spawn(async move {
            loop {
                let (stream, _) = match listener.accept().await {
                    Ok(value) => value,
                    Err(_) => break,
                };
                accept_count_for_task.fetch_add(1, Ordering::SeqCst);
                let request_count_for_conn = Arc::clone(&request_count_for_task);
                tokio::spawn(async move {
                    let service = service_fn(move |request: Request<Body>| {
                        let request_count_for_req = Arc::clone(&request_count_for_conn);
                        async move {
                            let mut body = request.into_body();
                            while let Some(chunk) = body.data().await {
                                chunk?;
                            }
                            request_count_for_req.fetch_add(1, Ordering::SeqCst);
                            Ok::<_, hyper::Error>(Response::new(Body::from("ok")))
                        }
                    });
                    let _ = HyperServerHttp::new()
                        .http1_keep_alive(true)
                        .serve_connection(stream, service)
                        .await;
                });
            }
        });
        (
            HttpEndpoint {
                scheme: "http".to_string(),
                host: Ipv4Addr::LOCALHOST.to_string(),
                port: addr.port(),
                http3_port: None,
            },
            accept_count,
            request_count,
            server,
        )
    }

    fn sample_h1_workload(reuse_connections: bool) -> PreparedWorkload {
        PreparedWorkload {
            name: "h1_test".to_string(),
            protocol: "h1".to_string(),
            method: HyperMethod::POST,
            path: "/bench/stream".to_string(),
            iterations: 3,
            concurrency: 1,
            request_bytes: 0,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections,
        }
    }

    fn sample_h2_workload(reuse_connections: bool) -> PreparedWorkload {
        PreparedWorkload {
            name: "h2_test".to_string(),
            protocol: "h2".to_string(),
            method: HyperMethod::POST,
            path: "/bench/stream".to_string(),
            iterations: 3,
            concurrency: 1,
            request_bytes: 0,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections,
        }
    }

    #[tokio::test]
    async fn h1_worker_reuses_single_connection_when_enabled() {
        let (endpoint, accept_count, request_count, server) = spawn_h1_test_server().await;
        let samples = run_h1_worker(endpoint, sample_h1_workload(true), 0)
            .await
            .unwrap();
        assert_eq!(samples.len(), 3);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 1);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        server.abort();
    }

    #[tokio::test]
    async fn h1_worker_reconnects_per_iteration_when_disabled() {
        let (endpoint, accept_count, request_count, server) = spawn_h1_test_server().await;
        let samples = run_h1_worker(endpoint, sample_h1_workload(false), 0)
            .await
            .unwrap();
        assert_eq!(samples.len(), 3);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 3);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        server.abort();
    }

    #[tokio::test]
    async fn h2_worker_reuses_single_connection_when_enabled() {
        let (endpoint, accept_count, request_count, server) = spawn_h2_test_server().await;
        let samples = run_h2_worker(endpoint, sample_h2_workload(true), 0)
            .await
            .unwrap();
        assert_eq!(samples.len(), 3);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 1);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        server.abort();
    }

    #[tokio::test]
    async fn h2_worker_reconnects_per_iteration_when_disabled() {
        let (endpoint, accept_count, request_count, server) = spawn_h2_test_server().await;
        let samples = run_h2_worker(endpoint, sample_h2_workload(false), 0)
            .await
            .unwrap();
        assert_eq!(samples.len(), 3);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 3);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        server.abort();
    }

    #[test]
    fn bench_http_client_builds_https_client() {
        let client = BenchHttpClient::new("https://localhost:8080/bench").unwrap();
        client.build_client().unwrap();
    }

    #[test]
    fn sort_socket_addrs_places_ipv4_first() {
        let mut addrs = vec![
            SocketAddr::new(IpAddr::V6(std::net::Ipv6Addr::LOCALHOST), 8443),
            SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 8443),
        ];
        sort_socket_addrs_prefer_ipv4(&mut addrs);
        assert!(addrs[0].is_ipv4());
        assert!(addrs[1].is_ipv6());
    }

    fn unique_temp_dir(prefix: &str) -> std::path::PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("connectanum_http_stream_{prefix}_{}", unique))
    }
}

fn quinn_client_config() -> QuinnClientConfig {
    let client_crypto = insecure_rustls_client_config(&[b"h3"]);
    let quic_client = QuicClientConfig::try_from(client_crypto).expect("invalid rustls config");
    let mut quinn_config = QuinnClientConfig::new(Arc::new(quic_client));
    let mut transport = TransportConfig::default();
    transport.keep_alive_interval(Some(Duration::from_secs(5)));
    quinn_config.transport_config(Arc::new(transport));
    quinn_config
}

#[derive(Debug)]
struct AcceptAnyCertVerifier(Arc<crypto::CryptoProvider>);

impl AcceptAnyCertVerifier {
    fn new() -> Arc<Self> {
        Arc::new(Self(Arc::new(crypto::ring::default_provider())))
    }
}

impl ServerCertVerifier for AcceptAnyCertVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}
struct BenchHttpClient {
    base: ReqwestUrl,
}

impl BenchHttpClient {
    fn new(raw_base: &str) -> Result<Self> {
        let mut base = ReqwestUrl::parse(raw_base).context("invalid control_base URL")?;
        if !base.path().ends_with('/') {
            base.set_path(&format!("{}/", base.path().trim_end_matches('/')));
        }
        Ok(Self { base })
    }

    fn healthz(&self) -> Result<Value> {
        self.get_json("healthz")
    }

    fn metrics(&self) -> Result<Value> {
        self.get_json("metrics")
    }

    fn request_stop(&self) -> Result<()> {
        let url = self
            .base
            .join("stop")
            .map_err(|err| anyhow!("invalid control_base stop URL: {err}"))?;
        self.build_client()?
            .post(url)
            .header(hyper::http::header::CONNECTION, "close")
            .json(&serde_json::json!({"source":"orchestrator"}))
            .send()
            .and_then(|resp| resp.error_for_status())
            .context("POST /bench/stop failed")?;
        Ok(())
    }

    fn get_json(&self, path: &str) -> Result<Value> {
        let url = self
            .base
            .join(path)
            .map_err(|err| anyhow!("invalid control_base path {path}: {err}"))?;
        let response = self
            .build_client()?
            .get(url)
            .header(hyper::http::header::CONNECTION, "close")
            .send()
            .and_then(|resp| resp.error_for_status())
            .context(format!("GET /bench/{path} failed"))?;
        Ok(response.json().context("failed to decode JSON response")?)
    }

    fn post_json(&self, path: &str, body: &Value) -> Result<Value> {
        let url = self
            .base
            .join(path)
            .map_err(|err| anyhow!("invalid control_base path {path}: {err}"))?;
        let response = self
            .build_client()?
            .post(url)
            .header(hyper::http::header::CONNECTION, "close")
            .json(body)
            .send()
            .and_then(|resp| resp.error_for_status())
            .context(format!("POST /bench/{path} failed"))?;
        Ok(response.json().context("failed to decode JSON response")?)
    }

    fn build_client(&self) -> Result<BlockingHttpClient> {
        build_control_http_client(self.base.scheme())
    }
}

fn build_control_http_client(scheme: &str) -> Result<BlockingHttpClient> {
    let mut builder = BlockingHttpClient::builder()
        .timeout(Duration::from_secs(30))
        .pool_max_idle_per_host(0)
        .pool_idle_timeout(Duration::from_secs(0));
    if scheme.eq_ignore_ascii_case("https") {
        builder = builder.danger_accept_invalid_certs(true);
    }
    builder.build().context("failed to build HTTP client")
}

fn insecure_rustls_client_config(alpn_protocols: &[&[u8]]) -> Arc<rustls::ClientConfig> {
    let verifier = AcceptAnyCertVerifier::new();
    let mut client_crypto = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth();
    client_crypto.alpn_protocols = alpn_protocols.iter().map(|value| value.to_vec()).collect();
    Arc::new(client_crypto)
}
