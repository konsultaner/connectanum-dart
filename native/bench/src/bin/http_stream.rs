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
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::net::lookup_host;
use tokio::runtime::Runtime;
use tokio::task::JoinSet;
use url::Url;

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
    #[arg(long, default_value = "http://127.0.0.1:8080/bench")]
    control_base: String,

    /// Optional HTTP/3 port override (defaults to control port).
    #[arg(long)]
    h3_port: Option<u16>,

    /// Scenario file describing workloads (TOML).
    #[arg(long, default_value = "native/bench/scenarios/h2_smoke.toml")]
    scenario: String,

    /// JSONL results output file.
    #[arg(long, default_value = "bench_results.jsonl")]
    results: String,

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

    println!(
        "Starting bench runner via {} {}",
        args.dart, args.bench_main
    );

    let mut child_process = Command::new(&args.dart)
        .arg("run")
        .arg(&args.bench_main)
        .arg("--router-config")
        .arg(&args.router_config)
        .arg("--native-lib")
        .arg(&args.native_lib)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .context("failed to spawn bench_main")?;

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
            .or_else(|| infer_h3_port(&args.router_config))
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

    let mut results_writer =
        ResultsWriter::create(&args.results).context("failed to open results file")?;
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
                    iterations: workload.iterations,
                    concurrency: workload.concurrency,
                    started_at_ms: started_at,
                    completed_at_ms: completed_at,
                    metrics_before: scenario_metrics_before.clone(),
                    metrics_after: scenario_metrics_after.clone(),
                    open_metrics_before: scenario_open_metrics_before.clone(),
                    open_metrics_after: scenario_open_metrics_after.clone(),
                    samples,
                };
                print_workload_summary(&report, &prepared);
                results_writer.write(&report)?;
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

    println!("Bench run completed successfully");
    Ok(())
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
        if scheme != "http" {
            bail!("Only http:// endpoints are supported for now (got {scheme})");
        }
        let host = url
            .host_str()
            .ok_or_else(|| anyhow!("control_base missing host"))?
            .to_string();
        let port = url.port().unwrap_or(80);
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
        })
    }

    fn is_wamp(&self) -> bool {
        matches!(
            self.protocol.to_lowercase().as_str(),
            "wamp_pubsub" | "wamp_rpc"
        )
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct WorkloadSample {
    worker: u32,
    iteration: u32,
    latency_ms: f64,
    request_bytes: u64,
    response_bytes: u64,
}

#[derive(Serialize)]
struct WorkloadReport {
    scenario: String,
    workload: String,
    protocol: String,
    iterations: u32,
    concurrency: u32,
    started_at_ms: u128,
    completed_at_ms: u128,
    metrics_before: Value,
    metrics_after: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    open_metrics_before: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    open_metrics_after: Option<String>,
    samples: Vec<WorkloadSample>,
}

struct ResultsWriter {
    file: File,
}

impl ResultsWriter {
    fn create(path: &str) -> Result<Self> {
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
    let avg_latency = if total_samples > 0 {
        total_latency / total_samples as f64
    } else {
        0.0
    };
    let elapsed_ms = (report.completed_at_ms - report.started_at_ms) as f64;
    let throughput_mbps = if elapsed_ms > 0.0 {
        (total_responses as f64 * 8.0 / 1_000_000.0) / (elapsed_ms / 1000.0)
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
    println!("  Approx throughput: {:.2} Mbps", throughput_mbps);
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
}

fn router_counter_delta(before: &Value, after: &Value, field: &str) -> Option<i64> {
    let start = before.get("metrics")?.get("router")?.get(field)?.as_i64()?;
    let end = after.get("metrics")?.get("router")?.get(field)?.as_i64()?;
    Some(end - start)
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
        "h2" | "http2" => run_h2_workload(endpoint, workload, timeout).await,
        "h3" | "http3" => run_h3_workload(endpoint, workload, timeout).await,
        other => bail!("unsupported protocol {other}"),
    }
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
    for iteration in 0..workload.iterations {
        let sample = run_h2_iteration(&endpoint, &workload, worker_id, iteration).await?;
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
    for iteration in 0..workload.iterations {
        let sample = run_h3_iteration(&endpoint, &workload, worker_id, iteration).await?;
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

async fn run_h2_iteration(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let addr = format!("{}:{}", endpoint.host, endpoint.port);
    let stream = tokio::net::TcpStream::connect(&addr)
        .await
        .with_context(|| format!("failed to connect to {}", addr))?;
    stream.set_nodelay(true)?;
    let mut builder = HyperConnBuilder::new();
    builder.http2_only(true);
    let (mut sender, connection) = builder
        .handshake::<_, Body>(stream)
        .await
        .context("HTTP/2 handshake failed")?;
    tokio::spawn(async move {
        if let Err(err) = connection.await {
            eprintln!("hyper connection error: {err:?}");
        }
    });

    let uri = format!(
        "{}://{}:{}{}",
        endpoint.scheme, endpoint.host, endpoint.port, workload.path
    );
    let mut request_builder = Request::builder().method(workload.method.clone()).uri(uri);
    let headers = request_builder.headers_mut().unwrap();
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
    let request_body = Body::from(build_payload(
        workload.request_bytes,
        workload.request_chunk_bytes as usize,
    ));
    let request = request_builder
        .body(request_body)
        .expect("failed to build HTTP/2 request");

    let start = Instant::now();
    let response = sender
        .send_request(request)
        .await
        .context("failed to send request")?;

    let mut body = response.into_body();
    let mut received = 0u64;
    while let Some(chunk) = body.data().await {
        let bytes = chunk?;
        received += bytes.len() as u64;
    }

    let latency_ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms,
        request_bytes: workload.request_bytes,
        response_bytes: received,
    })
}

async fn run_h3_iteration(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let bind_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 0);
    let mut quinn_endpoint =
        QuinnEndpoint::client(bind_addr).context("failed to bind quic endpoint")?;
    let client_config = quinn_client_config();
    quinn_endpoint.set_default_client_config(client_config);
    let server_port = endpoint.http3_port();
    let mut resolved = lookup_host((&endpoint.host[..], server_port))
        .await
        .with_context(|| format!("failed to resolve {}", endpoint.host))?;
    let server_addr = resolved
        .next()
        .ok_or_else(|| anyhow!("no addresses for {}", endpoint.host))?;
    let connection = quinn_endpoint
        .connect(server_addr, &endpoint.host)
        .context("failed to start QUIC connect")?
        .await
        .context("QUIC connect failed")?;
    let h3_conn = H3QuinnConnection::new(connection);
    let (driver, mut send_request) = h3::client::builder()
        .max_field_section_size(64 * 1024)
        .build(h3_conn)
        .await
        .context("failed to create h3 client")?;
    tokio::spawn(async move {
        let mut conn = driver;
        let _ = conn.wait_idle().await;
    });

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
        let chunk = build_pattern_chunk(std::cmp::max(1, workload.request_chunk_bytes as usize));
        let mut remaining = workload.request_bytes;
        while remaining > 0 {
            let chunk_len = std::cmp::min(remaining, chunk.len() as u64) as usize;
            req_stream
                .send_data(Bytes::copy_from_slice(&chunk[..chunk_len]))
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

    req_stream
        .recv_response()
        .await
        .context("failed to receive HTTP/3 response headers")?;
    let mut received = 0u64;
    while let Some(chunk) = req_stream
        .recv_data()
        .await
        .context("failed to read HTTP/3 body")?
    {
        received += chunk.remaining() as u64;
    }
    quinn_endpoint.close(0u32.into(), b"done");

    let latency_ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms,
        request_bytes: sent,
        response_bytes: received,
    })
}

fn build_payload(total_bytes: u64, chunk_len: usize) -> Vec<u8> {
    if total_bytes == 0 {
        return Vec::new();
    }
    let mut buffer = vec![0u8; total_bytes as usize];
    let chunk = build_pattern_chunk(std::cmp::max(1, chunk_len));
    for (idx, byte) in buffer.iter_mut().enumerate() {
        *byte = chunk[idx % chunk.len()];
    }
    buffer
}

fn build_pattern_chunk(len: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; len];
    for (i, byte) in bytes.iter_mut().enumerate() {
        *byte = ((i * 31) & 0xFF) as u8;
    }
    bytes
}

#[cfg(test)]
mod tests {
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
}

fn quinn_client_config() -> QuinnClientConfig {
    let verifier = AcceptAnyCertVerifier::new();
    let mut client_crypto = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth();
    client_crypto.alpn_protocols = vec![b"h3".to_vec()];
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
        Self::build_client()?
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
        let response = Self::build_client()?
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
        let response = Self::build_client()?
            .post(url)
            .header(hyper::http::header::CONNECTION, "close")
            .json(body)
            .send()
            .and_then(|resp| resp.error_for_status())
            .context(format!("POST /bench/{path} failed"))?;
        Ok(response.json().context("failed to decode JSON response")?)
    }

    fn build_client() -> Result<BlockingHttpClient> {
        BlockingHttpClient::builder()
            .timeout(Duration::from_secs(30))
            .pool_max_idle_per_host(0)
            .pool_idle_timeout(Duration::from_secs(0))
            .build()
            .context("failed to build HTTP client")
    }
}
