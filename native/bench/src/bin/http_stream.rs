use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::Path;
use std::pin::Pin;
use std::process::{Command, Stdio};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    mpsc::{self, RecvTimeoutError},
    Arc, Mutex,
};
use std::task::{Context as TaskContext, Poll};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, bail, Context, Result};
use base64::{engine::general_purpose::STANDARD as Base64Engine, Engine as _};
use bytes::{Buf, Bytes};
use clap::Parser;
use h2::{client as h2_client, RecvStream as H2RecvStream};
use h3_quinn::Connection as H3QuinnConnection;
use hmac::{Hmac, Mac};
use http as http3;
use hyper::body::HttpBody as _;
use hyper::client::conn::Builder as HyperConnBuilder;
use hyper::http::{
    header::{HeaderValue as HyperHeaderValue, ACCEPT, USER_AGENT},
    Method as HyperMethod, StatusCode as HyperStatusCode, Version as HyperVersion,
};
use hyper::{Body, Request};
use pbkdf2::pbkdf2_hmac;
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
use sha2::{Digest, Sha256};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf};
use tokio::net::{lookup_host, TcpStream};
use tokio::runtime::Runtime;
use tokio::task::JoinSet;
use tokio_rustls::TlsConnector;
use url::Url;

use connectanum_bench_orchestrator::artifacts::summarize_report;
use connectanum_bench_orchestrator::artifacts::{write_artifact_bundle, WorkloadArtifactSummary};
use connectanum_bench_orchestrator::report::{
    router_counter_delta, HttpConnectionUsage, HttpPhaseTimingSample, WorkloadReport,
    WorkloadSample,
};

type H3RequestSender = h3::client::SendRequest<h3_quinn::OpenStreams, Bytes>;
const NATIVE_RUNTIME_THREADS_ENV: &str = "CONNECTANUM_NATIVE_RUNTIME_THREADS";
const HTTP2_MAX_CONCURRENT_STREAMS: u32 = 1024;
const HTTP2_INITIAL_STREAM_WINDOW: u32 = 8 * 1024 * 1024;
const HTTP2_INITIAL_CONNECTION_WINDOW: u32 = 64 * 1024 * 1024;
const HTTP2_MAX_FRAME_SIZE: u32 = 1 * 1024 * 1024;
const HTTP2_MAX_HEADER_LIST_SIZE: u32 = 16 * 1024 * 1024;
const HTTP2_MAX_CONCURRENT_RESET_STREAMS: usize = 256;
const HTTP2_MAX_SEND_BUFFER_SIZE: usize = 8 * 1024 * 1024;
const HTTP3_MAX_BIDI_STREAMS: u32 = 1024;
const HTTP3_MAX_UNI_STREAMS: u32 = 256;
const HTTP3_STREAM_RECEIVE_WINDOW: u32 = 8 * 1024 * 1024;
const HTTP3_CONNECTION_RECEIVE_WINDOW: u32 = 64 * 1024 * 1024;
const HTTP3_SEND_WINDOW: u64 = 64 * 1024 * 1024;
const HTTP3_DATAGRAM_BUFFER_BYTES: usize = 8 * 1024 * 1024;
const HTTP3_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, Copy)]
struct H2ResponseDrainStats {
    received_bytes: u64,
    first_chunk_wait_ms: f64,
    tail_read_ms: f64,
    chunk_count: u32,
    first_chunk_bytes: u64,
    post_header_connection_read_wait_ms: Option<f64>,
    connection_read_to_first_chunk_ms: Option<f64>,
    tail_connection_read_wait_ms: Option<f64>,
    tail_connection_read_to_end_ms: Option<f64>,
    tail_connection_read_count: Option<u64>,
    tail_connection_read_span_ms: Option<f64>,
    tail_connection_last_read_to_end_ms: Option<f64>,
}

#[derive(Clone)]
struct H2BenchSender {
    sender: h2_client::SendRequest<Bytes>,
    read_tracker: Arc<H2ClientReadTracker>,
    write_tracker: Arc<H2ClientWriteTracker>,
}

#[derive(Debug, Default)]
struct H2ClientReadTracker {
    probes: Mutex<VecDeque<Arc<H2ClientReadProbeState>>>,
}

#[derive(Clone, Debug)]
struct H2ClientReadProbe {
    state: Arc<H2ClientReadProbeState>,
}

#[derive(Debug)]
struct H2ClientReadProbeState {
    phase_started_at: Instant,
    first_connection_read_at: Mutex<Option<Instant>>,
    last_connection_read_at: Mutex<Option<Instant>>,
    connection_read_count: Mutex<u64>,
    finished: AtomicBool,
}

#[derive(Debug, Clone, Copy, Default)]
struct H2ClientPhaseReadStats {
    connection_read_wait_ms: Option<f64>,
    connection_read_to_phase_end_ms: Option<f64>,
    connection_read_span_ms: Option<f64>,
    last_connection_read_to_phase_end_ms: Option<f64>,
    first_connection_read_at: Option<Instant>,
    connection_read_count: u64,
}

#[derive(Debug, Default)]
struct H2ClientWriteTracker {
    probes: Mutex<VecDeque<Arc<H2ClientWriteProbeState>>>,
}

#[derive(Clone, Debug)]
struct H2ClientWriteProbe {
    state: Arc<H2ClientWriteProbeState>,
}

#[derive(Debug)]
struct H2ClientWriteProbeState {
    phase_started_at: Instant,
    first_connection_write_at: Mutex<Option<Instant>>,
    last_connection_write_at: Mutex<Option<Instant>>,
    finished: AtomicBool,
}

#[derive(Debug, Clone, Copy, Default)]
struct H2ClientPhaseWriteStats {
    connection_write_wait_ms: Option<f64>,
    connection_write_span_ms: Option<f64>,
    last_connection_write_at: Option<Instant>,
}

struct InstrumentedH2ClientIo<T> {
    inner: T,
    read_tracker: Arc<H2ClientReadTracker>,
    write_tracker: Arc<H2ClientWriteTracker>,
}

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
    #[arg(long, default_value = "https://127.0.0.1:8080/bench")]
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
    let startup_timeout = Duration::from_millis(args.workload_timeout_ms);
    let (stdout_event_tx, stdout_event_rx) = mpsc::channel();
    let stdout_reader = thread::spawn(move || -> Result<()> {
        let mut reader = BufReader::new(stdout);
        let mut line = String::new();
        loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => {
                    let _ = stdout_event_tx.send(BenchMainStdoutEvent::Eof);
                    break;
                }
                Ok(_) => {
                    let trimmed = line.trim();
                    if trimmed == "READY" {
                        let _ = stdout_event_tx.send(BenchMainStdoutEvent::Ready);
                        continue;
                    }
                    if !trimmed.is_empty() {
                        println!("[bench_main] {trimmed}");
                    }
                }
                Err(error) => {
                    let _ = stdout_event_tx.send(BenchMainStdoutEvent::Error(error.to_string()));
                    return Err(error).context("failed to read bench_main stdout");
                }
            }
        }
        Ok(())
    });
    wait_for_bench_ready(&stdout_event_rx, startup_timeout)?;

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
                let execution = if prepared.is_wamp() {
                    WorkloadExecution::samples_only(
                        run_wamp_workload(&http_control, &prepared)
                            .with_context(|| format!("workload \"{}\" failed", workload.name))?,
                    )
                } else if prepared.is_rawsocket_auth_frames() {
                    WorkloadExecution::samples_only(
                        runtime
                            .block_on(run_rawsocket_auth_frame_workload(
                                router_config_path,
                                prepared.clone(),
                                workload_timeout,
                            ))
                            .with_context(|| format!("workload \"{}\" failed", workload.name))?,
                    )
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
                    client_impl: prepared.client_impl.clone(),
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
                    http_connection_usage: execution.http_connection_usage.clone(),
                    http_phase_timing: summarize_http_phase_timing(&execution.samples),
                    samples: execution.samples,
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

enum BenchMainStdoutEvent {
    Ready,
    Eof,
    Error(String),
}

fn wait_for_bench_ready(
    receiver: &mpsc::Receiver<BenchMainStdoutEvent>,
    timeout: Duration,
) -> Result<()> {
    match receiver.recv_timeout(timeout) {
        Ok(BenchMainStdoutEvent::Ready) => {
            println!("bench_main reported READY");
            Ok(())
        }
        Ok(BenchMainStdoutEvent::Eof) => bail!("bench_main exited before signaling READY"),
        Ok(BenchMainStdoutEvent::Error(message)) => {
            bail!("failed to read bench_main stdout before READY: {message}")
        }
        Err(RecvTimeoutError::Timeout) => {
            bail!("bench_main did not signal READY within {:?}", timeout)
        }
        Err(RecvTimeoutError::Disconnected) => {
            bail!("bench_main stdout reader stopped before READY")
        }
    }
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
        BTreeMap::<(String, String, String, String, u32), Vec<WorkloadArtifactSummary>>::new();
    for summary in summaries {
        grouped
            .entry((
                summary.scenario.clone(),
                summary.workload.clone(),
                summary.protocol.clone(),
                summary.client_impl.clone(),
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
    for ((scenario, workload, protocol, client_impl, native_runtime_threads), mut entries) in
        grouped
    {
        entries.sort_by_key(|entry| entry.router_workers);
        println!(
            "  {scenario} / {workload} [{protocol}] client_impl={client_impl} runtime_threads={}",
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
        BTreeMap::<(String, String, String, String, u32), Vec<WorkloadArtifactSummary>>::new();
    for summary in summaries {
        grouped
            .entry((
                summary.scenario.clone(),
                summary.workload.clone(),
                summary.protocol.clone(),
                summary.client_impl.clone(),
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
    for ((scenario, workload, protocol, client_impl, router_workers), mut entries) in grouped {
        entries.sort_by_key(|entry| entry.native_runtime_threads);
        println!(
            "  {scenario} / {workload} [{protocol}] client_impl={client_impl} router_workers={router_workers}"
        );
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

impl H2ClientReadTracker {
    fn note_phase_started(&self) -> H2ClientReadProbe {
        let probe = Arc::new(H2ClientReadProbeState {
            phase_started_at: Instant::now(),
            first_connection_read_at: Mutex::new(None),
            last_connection_read_at: Mutex::new(None),
            connection_read_count: Mutex::new(0),
            finished: AtomicBool::new(false),
        });
        let mut guard = self
            .probes
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        guard.retain(|state| !state.finished.load(Ordering::SeqCst));
        guard.push_back(probe.clone());
        H2ClientReadProbe { state: probe }
    }

    fn record_connection_read(&self, read_at: Instant) {
        let mut guard = self
            .probes
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        guard.retain(|state| !state.finished.load(Ordering::SeqCst));
        for state in guard.iter() {
            if state.finished.load(Ordering::SeqCst) {
                continue;
            }
            let mut first_connection_read_at = state
                .first_connection_read_at
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            if first_connection_read_at.is_none() {
                *first_connection_read_at = Some(read_at);
            }
            drop(first_connection_read_at);
            let mut last_connection_read_at = state
                .last_connection_read_at
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            *last_connection_read_at = Some(read_at);
            drop(last_connection_read_at);
            let mut connection_read_count = state
                .connection_read_count
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            *connection_read_count = connection_read_count.saturating_add(1);
        }
    }
}

impl H2ClientReadProbe {
    fn finish(&self, phase_finished_at: Option<Instant>) -> H2ClientPhaseReadStats {
        self.state.finished.store(true, Ordering::SeqCst);
        let first_connection_read_at = *self
            .state
            .first_connection_read_at
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let last_connection_read_at = *self
            .state
            .last_connection_read_at
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let connection_read_count = *self
            .state
            .connection_read_count
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let connection_read_wait_ms = first_connection_read_at.map(|read_at| {
            read_at
                .saturating_duration_since(self.state.phase_started_at)
                .as_secs_f64()
                * 1000.0
        });
        let connection_read_to_phase_end_ms = match (first_connection_read_at, phase_finished_at) {
            (Some(read_at), Some(phase_end_at)) if phase_end_at >= read_at => Some(
                phase_end_at
                    .saturating_duration_since(read_at)
                    .as_secs_f64()
                    * 1000.0,
            ),
            _ => None,
        };
        let connection_read_span_ms = match (first_connection_read_at, last_connection_read_at) {
            (Some(first_read_at), Some(last_read_at)) if last_read_at >= first_read_at => Some(
                last_read_at
                    .saturating_duration_since(first_read_at)
                    .as_secs_f64()
                    * 1000.0,
            ),
            _ => None,
        };
        let last_connection_read_to_phase_end_ms =
            match (last_connection_read_at, phase_finished_at) {
                (Some(last_read_at), Some(phase_end_at)) if phase_end_at >= last_read_at => Some(
                    phase_end_at
                        .saturating_duration_since(last_read_at)
                        .as_secs_f64()
                        * 1000.0,
                ),
                _ => None,
            };
        H2ClientPhaseReadStats {
            connection_read_wait_ms,
            connection_read_to_phase_end_ms,
            connection_read_span_ms,
            last_connection_read_to_phase_end_ms,
            first_connection_read_at,
            connection_read_count,
        }
    }
}

impl H2ClientWriteTracker {
    fn note_phase_started(&self) -> H2ClientWriteProbe {
        let probe = Arc::new(H2ClientWriteProbeState {
            phase_started_at: Instant::now(),
            first_connection_write_at: Mutex::new(None),
            last_connection_write_at: Mutex::new(None),
            finished: AtomicBool::new(false),
        });
        let mut guard = self
            .probes
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        guard.retain(|state| !state.finished.load(Ordering::SeqCst));
        guard.push_back(probe.clone());
        H2ClientWriteProbe { state: probe }
    }

    fn record_connection_write(&self, write_at: Instant) {
        let mut guard = self
            .probes
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        guard.retain(|state| !state.finished.load(Ordering::SeqCst));
        for state in guard.iter() {
            if state.finished.load(Ordering::SeqCst) {
                continue;
            }
            let mut first_connection_write_at = state
                .first_connection_write_at
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            if first_connection_write_at.is_none() {
                *first_connection_write_at = Some(write_at);
            }
            drop(first_connection_write_at);
            let mut last_connection_write_at = state
                .last_connection_write_at
                .lock()
                .unwrap_or_else(|poison| poison.into_inner());
            *last_connection_write_at = Some(write_at);
        }
    }
}

impl H2ClientWriteProbe {
    fn finish(&self) -> H2ClientPhaseWriteStats {
        self.state.finished.store(true, Ordering::SeqCst);
        let first_connection_write_at = *self
            .state
            .first_connection_write_at
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let last_connection_write_at = *self
            .state
            .last_connection_write_at
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        let connection_write_wait_ms = first_connection_write_at.map(|write_at| {
            write_at
                .saturating_duration_since(self.state.phase_started_at)
                .as_secs_f64()
                * 1000.0
        });
        let connection_write_span_ms = match (first_connection_write_at, last_connection_write_at) {
            (Some(first_write_at), Some(last_write_at)) if last_write_at >= first_write_at => Some(
                last_write_at
                    .saturating_duration_since(first_write_at)
                    .as_secs_f64()
                    * 1000.0,
            ),
            _ => None,
        };
        H2ClientPhaseWriteStats {
            connection_write_wait_ms,
            connection_write_span_ms,
            last_connection_write_at,
        }
    }
}

fn h2_last_write_to_first_read_ms(
    write_stats: &H2ClientPhaseWriteStats,
    read_stats: &H2ClientPhaseReadStats,
) -> Option<f64> {
    match (
        write_stats.last_connection_write_at,
        read_stats.first_connection_read_at,
    ) {
        (Some(last_write_at), Some(first_read_at)) if first_read_at >= last_write_at => Some(
            first_read_at
                .saturating_duration_since(last_write_at)
                .as_secs_f64()
                * 1000.0,
        ),
        _ => None,
    }
}

impl<T: AsyncRead + Unpin> AsyncRead for InstrumentedH2ClientIo<T> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let me = self.get_mut();
        let filled_before = buf.filled().len();
        match Pin::new(&mut me.inner).poll_read(cx, buf) {
            Poll::Ready(Ok(())) => {
                if buf.filled().len() > filled_before {
                    me.read_tracker.record_connection_read(Instant::now());
                }
                Poll::Ready(Ok(()))
            }
            other => other,
        }
    }
}

impl<T: AsyncWrite + Unpin> AsyncWrite for InstrumentedH2ClientIo<T> {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let me = self.get_mut();
        match Pin::new(&mut me.inner).poll_write(cx, buf) {
            Poll::Ready(Ok(written)) => {
                if written > 0 {
                    me.write_tracker.record_connection_write(Instant::now());
                }
                Poll::Ready(Ok(written))
            }
            other => other,
        }
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<std::io::Result<()>> {
        let me = self.get_mut();
        Pin::new(&mut me.inner).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<std::io::Result<()>> {
        let me = self.get_mut();
        Pin::new(&mut me.inner).poll_shutdown(cx)
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
    #[serde(default = "default_wamp_client_impl")]
    client_impl: String,
    #[serde(default = "default_wamp_serializer")]
    serializer: String,
    #[serde(default = "default_method")]
    method: String,
    #[serde(default = "default_path")]
    path: String,
    #[serde(default = "default_iterations")]
    iterations: u32,
    #[serde(default = "default_concurrency")]
    concurrency: u32,
    #[serde(default = "default_in_flight_per_session")]
    in_flight_per_session: u32,
    #[serde(default = "default_peer_count")]
    peer_count: u32,
    #[serde(default = "default_request_bytes")]
    request_bytes: u64,
    #[serde(default)]
    websocket_fragment_size: Option<u32>,
    #[serde(default)]
    secure_transport: bool,
    #[serde(default)]
    ppt_scheme: Option<String>,
    #[serde(default)]
    ppt_serializer: Option<String>,
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
    #[serde(default = "default_streams_per_connection")]
    streams_per_connection: u32,
    #[serde(default)]
    auth_flow: Option<String>,
    #[serde(default)]
    auth_path: Option<String>,
    #[serde(default)]
    auth_realm: Option<String>,
    #[serde(default)]
    auth_method: Option<String>,
    #[serde(default)]
    auth_id: Option<String>,
    #[serde(default)]
    auth_secret: Option<String>,
    #[serde(default)]
    auth_bearer_token: Option<String>,
    #[serde(default)]
    frame_case: Option<String>,
}

fn default_protocol() -> String {
    "h2".to_string()
}

fn default_method() -> String {
    "POST".to_string()
}

fn default_wamp_serializer() -> String {
    "json".to_string()
}

fn default_wamp_client_impl() -> String {
    "dart".to_string()
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

fn default_in_flight_per_session() -> u32 {
    1
}

fn default_peer_count() -> u32 {
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

fn default_streams_per_connection() -> u32 {
    1
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum BenchWampTransport {
    RawSocket,
    WebSocket,
}

impl BenchWampTransport {
    fn as_str(self) -> &'static str {
        match self {
            Self::RawSocket => "rawsocket",
            Self::WebSocket => "websocket",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum BenchWampMode {
    Authenticate,
    PubSub,
    Rpc,
    PublishAck,
    SubscribeCycle,
    RegisterCycle,
    CancelCycle,
}

impl BenchWampMode {
    fn as_str(self) -> &'static str {
        match self {
            Self::Authenticate => "authenticate",
            Self::PubSub => "pubsub",
            Self::Rpc => "rpc",
            Self::PublishAck => "publish_ack",
            Self::SubscribeCycle => "subscribe_cycle",
            Self::RegisterCycle => "register_cycle",
            Self::CancelCycle => "cancel_cycle",
        }
    }
}

fn parse_wamp_protocol(protocol: &str) -> Option<(BenchWampTransport, BenchWampMode)> {
    match protocol.to_ascii_lowercase().as_str() {
        "wamp_auth" | "wamp_rawsocket_auth" => {
            Some((BenchWampTransport::RawSocket, BenchWampMode::Authenticate))
        }
        "wamp_pubsub" | "wamp_rawsocket_pubsub" => {
            Some((BenchWampTransport::RawSocket, BenchWampMode::PubSub))
        }
        "wamp_rpc" | "wamp_rawsocket_rpc" => {
            Some((BenchWampTransport::RawSocket, BenchWampMode::Rpc))
        }
        "wamp_publish_ack" | "wamp_rawsocket_publish_ack" => {
            Some((BenchWampTransport::RawSocket, BenchWampMode::PublishAck))
        }
        "wamp_subscribe_cycle" | "wamp_rawsocket_subscribe_cycle" => {
            Some((BenchWampTransport::RawSocket, BenchWampMode::SubscribeCycle))
        }
        "wamp_register_cycle" | "wamp_rawsocket_register_cycle" => {
            Some((BenchWampTransport::RawSocket, BenchWampMode::RegisterCycle))
        }
        "wamp_cancel_cycle" | "wamp_rawsocket_cancel_cycle" => {
            Some((BenchWampTransport::RawSocket, BenchWampMode::CancelCycle))
        }
        "wamp_websocket_pubsub" => Some((BenchWampTransport::WebSocket, BenchWampMode::PubSub)),
        "wamp_websocket_auth" => Some((BenchWampTransport::WebSocket, BenchWampMode::Authenticate)),
        "wamp_websocket_rpc" => Some((BenchWampTransport::WebSocket, BenchWampMode::Rpc)),
        "wamp_websocket_publish_ack" => {
            Some((BenchWampTransport::WebSocket, BenchWampMode::PublishAck))
        }
        "wamp_websocket_subscribe_cycle" => {
            Some((BenchWampTransport::WebSocket, BenchWampMode::SubscribeCycle))
        }
        "wamp_websocket_register_cycle" => {
            Some((BenchWampTransport::WebSocket, BenchWampMode::RegisterCycle))
        }
        "wamp_websocket_cancel_cycle" => {
            Some((BenchWampTransport::WebSocket, BenchWampMode::CancelCycle))
        }
        _ => None,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RawSocketFrameProtocol {
    RemoteAuth,
}

fn parse_rawsocket_frame_protocol(protocol: &str) -> Option<RawSocketFrameProtocol> {
    match protocol.to_ascii_lowercase().as_str() {
        "rawsocket_auth_frames" | "wamp_rawsocket_auth_frames" => {
            Some(RawSocketFrameProtocol::RemoteAuth)
        }
        _ => None,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RawSocketAuthFrameCase {
    Success,
    InvalidTicket,
    MissingAuthId,
    DisconnectAfterChallenge,
}

impl RawSocketAuthFrameCase {
    fn parse(raw: Option<&str>) -> Result<Self> {
        match raw
            .map(|value| value.trim().to_ascii_lowercase())
            .as_deref()
            .unwrap_or("success")
        {
            "success" => Ok(Self::Success),
            "invalid_ticket" | "bad_ticket" => Ok(Self::InvalidTicket),
            "missing_authid" | "hello_missing_authid" => Ok(Self::MissingAuthId),
            "disconnect_after_challenge" | "drop_after_challenge" => {
                Ok(Self::DisconnectAfterChallenge)
            }
            other => bail!("unsupported rawsocket auth frame case {other}"),
        }
    }
}

#[derive(Clone, Debug)]
struct RawSocketEndpoint {
    host: String,
    port: u16,
}

#[derive(Clone)]
struct PreparedWorkload {
    name: String,
    protocol: String,
    client_impl: String,
    serializer: String,
    method: HyperMethod,
    path: String,
    iterations: u32,
    concurrency: u32,
    in_flight_per_session: u32,
    peer_count: u32,
    request_bytes: u64,
    websocket_fragment_size: Option<u32>,
    secure_transport: bool,
    ppt_scheme: Option<String>,
    ppt_serializer: Option<String>,
    response_bytes: u64,
    request_chunk_bytes: u64,
    response_chunk_bytes: u64,
    reuse_connections: bool,
    streams_per_connection: u32,
    auth_flow: Option<HttpAuthFlow>,
    auth_path: String,
    auth_realm: String,
    auth_method: String,
    auth_id: String,
    auth_secret: String,
    auth_bearer_token: Option<String>,
    frame_case: Option<String>,
}

impl PreparedWorkload {
    fn from_config(config: &WorkloadConfig) -> Result<Self> {
        if config.iterations == 0 {
            bail!("workload {} must have at least one iteration", config.name);
        }
        if config.concurrency == 0 {
            bail!("workload {} must have concurrency >= 1", config.name);
        }
        if config.in_flight_per_session == 0 {
            bail!(
                "workload {} must have in_flight_per_session >= 1",
                config.name
            );
        }
        if config.request_chunk_bytes == 0 {
            bail!("request_chunk_bytes must be > 0");
        }
        if config.streams_per_connection == 0 {
            bail!("streams_per_connection must be >= 1");
        }
        let method = config
            .method
            .parse::<HyperMethod>()
            .map_err(|_| anyhow!("invalid HTTP method {}", config.method))?;
        if config.streams_per_connection > 1 && !config.reuse_connections {
            if config.protocol.eq_ignore_ascii_case("h2")
                || config.protocol.eq_ignore_ascii_case("h3")
            {
                bail!(
                    "{} streams_per_connection > 1 requires reuse_connections = true",
                    config.protocol.to_uppercase()
                );
            }
        }
        if config.streams_per_connection > 1 && config.protocol.eq_ignore_ascii_case("h1") {
            bail!("HTTP/1.1 does not support streams_per_connection > 1");
        }
        let is_wamp = parse_wamp_protocol(&config.protocol).is_some();
        let is_rawsocket_frame = parse_rawsocket_frame_protocol(&config.protocol).is_some();
        let path = if is_wamp || is_rawsocket_frame {
            config.path.clone()
        } else if config.path.starts_with('/') {
            config.path.clone()
        } else {
            format!("/{}", config.path)
        };
        let client_impl = if is_wamp {
            normalize_wamp_client_impl(&config.client_impl)?
        } else {
            "n/a".to_string()
        };
        let auth_flow = parse_http_auth_flow(config.auth_flow.as_deref())?;
        if auth_flow.is_some() && (is_wamp || is_rawsocket_frame) {
            bail!("HTTP auth workloads are not valid for WAMP protocols");
        }
        let auth_path = config
            .auth_path
            .clone()
            .unwrap_or_else(|| "/bench/auth".to_string());
        let auth_realm = config.auth_realm.clone().unwrap_or_else(|| {
            if is_rawsocket_frame {
                "bench.remote_auth".to_string()
            } else if is_wamp {
                "bench.control".to_string()
            } else {
                "bench.secure".to_string()
            }
        });
        let auth_method = config.auth_method.clone().unwrap_or_else(|| {
            if is_rawsocket_frame {
                "ticket".to_string()
            } else if is_wamp {
                "anonymous".to_string()
            } else {
                "ticket".to_string()
            }
        });
        let auth_id = config.auth_id.clone().unwrap_or_else(|| {
            if is_rawsocket_frame {
                "ticket-user".to_string()
            } else if is_wamp && auth_method.eq_ignore_ascii_case("anonymous") {
                "".to_string()
            } else {
                "bench-user".to_string()
            }
        });
        let auth_secret = config.auth_secret.clone().unwrap_or_else(|| {
            if is_rawsocket_frame {
                "ticket-secret".to_string()
            } else if is_wamp && auth_method.eq_ignore_ascii_case("anonymous") {
                "".to_string()
            } else {
                "bench-ticket".to_string()
            }
        });
        let auth_bearer_token = config.auth_bearer_token.clone();
        if is_rawsocket_frame && !config.serializer.eq_ignore_ascii_case("json") {
            bail!("rawsocket auth frame workloads currently support json only");
        }
        if auth_flow.is_some()
            && auth_bearer_token.is_none()
            && !matches!(
                auth_method.to_ascii_lowercase().as_str(),
                "ticket" | "wampcra" | "scram"
            )
        {
            bail!(
                "HTTP auth bench currently supports interactive login for ticket, wampcra, and scram only"
            );
        }
        if is_rawsocket_frame {
            RawSocketAuthFrameCase::parse(config.frame_case.as_deref())?;
        }
        Ok(Self {
            name: config.name.clone(),
            protocol: config.protocol.clone(),
            client_impl,
            serializer: config.serializer.clone(),
            method,
            path,
            iterations: config.iterations,
            concurrency: config.concurrency,
            in_flight_per_session: config.in_flight_per_session,
            peer_count: config.peer_count,
            request_bytes: config.request_bytes,
            websocket_fragment_size: config.websocket_fragment_size,
            secure_transport: config.secure_transport,
            ppt_scheme: config.ppt_scheme.clone(),
            ppt_serializer: config.ppt_serializer.clone(),
            response_bytes: config.response_bytes,
            request_chunk_bytes: config.request_chunk_bytes,
            response_chunk_bytes: config
                .response_chunk_bytes
                .unwrap_or(config.request_chunk_bytes),
            reuse_connections: config.reuse_connections,
            streams_per_connection: config.streams_per_connection,
            auth_flow,
            auth_path,
            auth_realm,
            auth_method,
            auth_id,
            auth_secret,
            auth_bearer_token,
            frame_case: config.frame_case.clone(),
        })
    }

    fn is_wamp(&self) -> bool {
        parse_wamp_protocol(&self.protocol).is_some()
    }

    fn is_rawsocket_auth_frames(&self) -> bool {
        matches!(
            parse_rawsocket_frame_protocol(&self.protocol),
            Some(RawSocketFrameProtocol::RemoteAuth)
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum HttpAuthFlow {
    Login,
    Protected,
    Refresh,
}

fn parse_http_auth_flow(raw: Option<&str>) -> Result<Option<HttpAuthFlow>> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    let flow = match raw.to_ascii_lowercase().as_str() {
        "login" | "challenge" | "challenge_login" => HttpAuthFlow::Login,
        "protected" | "protected_route" | "bearer" => HttpAuthFlow::Protected,
        "refresh" | "refresh_token" => HttpAuthFlow::Refresh,
        other => bail!("unsupported http auth flow {other}"),
    };
    Ok(Some(flow))
}

#[derive(Clone, Debug)]
struct HttpAuthSession {
    access_token: String,
    refresh_token: String,
}

#[derive(Clone, Debug)]
struct HttpAuthChallenge {
    state: String,
    challenge: Value,
}

#[derive(Clone, Debug)]
enum HttpAuthClientState {
    Ticket,
    WampCra,
    Scram { hello_nonce: String },
}

struct HttpBodyResponse {
    status: HyperStatusCode,
    body: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq)]
struct HttpWorkerExecution {
    samples: Vec<WorkloadSample>,
    connections_opened: u32,
}

#[derive(Clone, Debug, PartialEq)]
struct WorkloadExecution {
    samples: Vec<WorkloadSample>,
    http_connection_usage: Option<HttpConnectionUsage>,
}

impl WorkloadExecution {
    fn samples_only(samples: Vec<WorkloadSample>) -> Self {
        Self {
            samples,
            http_connection_usage: None,
        }
    }

    fn with_http_usage(
        workload: &PreparedWorkload,
        samples: Vec<WorkloadSample>,
        connections_opened: u32,
    ) -> Self {
        Self {
            samples,
            http_connection_usage: Some(HttpConnectionUsage {
                reuse_connections: workload.reuse_connections,
                streams_per_connection: workload.streams_per_connection,
                connections_opened,
            }),
        }
    }
}

fn normalize_wamp_client_impl(raw: &str) -> Result<String> {
    match raw.to_ascii_lowercase().as_str() {
        "dart" | "vm" => Ok("dart".to_string()),
        "native" | "rust" => Ok("native".to_string()),
        other => bail!("unsupported WAMP client implementation {other}"),
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
    if report.client_impl != "n/a" {
        println!("  Client implementation: {}", report.client_impl);
    }
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
    if workload.is_wamp() {
        println!(
            "  In-flight operations per session: {}",
            workload.in_flight_per_session
        );
    } else {
        println!(
            "  Streams per connection: {}",
            workload.streams_per_connection
        );
        if let Some(connection_usage) = &report.http_connection_usage {
            println!(
                "  HTTP connections opened: {}",
                connection_usage.connections_opened
            );
            let samples_per_connection = if connection_usage.connections_opened == 0 {
                0.0
            } else {
                total_samples as f64 / connection_usage.connections_opened as f64
            };
            println!(
                "  Samples per opened connection: {:.2}",
                samples_per_connection
            );
        }
        if let Some(phase_timing) = &report.http_phase_timing {
            println!(
                "  HTTP stream acquire wait avg/p95: {:.2} / {:.2} ms",
                phase_timing.stream_acquire_wait_avg_ms, phase_timing.stream_acquire_wait_p95_ms
            );
            println!(
                "  HTTP request enqueue avg/p95: {:.2} / {:.2} ms",
                phase_timing.request_enqueue_avg_ms, phase_timing.request_enqueue_p95_ms
            );
            println!(
                "  HTTP response headers wait avg/p95: {:.2} / {:.2} ms",
                phase_timing.response_headers_wait_avg_ms,
                phase_timing.response_headers_wait_p95_ms
            );
            if phase_timing.response_headers_connection_read_wait_samples_total > 0 {
                println!(
                    "  HTTP response-header connection read wait avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_headers_connection_read_wait_avg_ms,
                    phase_timing.response_headers_connection_read_wait_p95_ms,
                    phase_timing.response_headers_connection_read_wait_samples_total
                );
            }
            if phase_timing.response_headers_connection_read_to_headers_samples_total > 0 {
                println!(
                    "  HTTP response-header connection read to headers avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_headers_connection_read_to_headers_avg_ms,
                    phase_timing.response_headers_connection_read_to_headers_p95_ms,
                    phase_timing.response_headers_connection_read_to_headers_samples_total
                );
            }
            if phase_timing.response_headers_connection_write_wait_samples_total > 0 {
                println!(
                    "  HTTP response-header connection write wait avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_headers_connection_write_wait_avg_ms,
                    phase_timing.response_headers_connection_write_wait_p95_ms,
                    phase_timing.response_headers_connection_write_wait_samples_total
                );
            }
            if phase_timing.response_headers_connection_write_span_samples_total > 0 {
                println!(
                    "  HTTP response-header connection write span avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_headers_connection_write_span_avg_ms,
                    phase_timing.response_headers_connection_write_span_p95_ms,
                    phase_timing.response_headers_connection_write_span_samples_total
                );
            }
            if phase_timing.response_headers_last_write_to_first_read_samples_total > 0 {
                println!(
                    "  HTTP response-header last write to first read avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_headers_last_write_to_first_read_avg_ms,
                    phase_timing.response_headers_last_write_to_first_read_p95_ms,
                    phase_timing.response_headers_last_write_to_first_read_samples_total
                );
            }
            println!(
                "  HTTP response body read avg/p95: {:.2} / {:.2} ms",
                phase_timing.response_body_read_avg_ms, phase_timing.response_body_read_p95_ms
            );
            println!(
                "  HTTP response body first chunk wait avg/p95: {:.2} / {:.2} ms",
                phase_timing.response_body_first_chunk_wait_avg_ms,
                phase_timing.response_body_first_chunk_wait_p95_ms
            );
            println!(
                "  HTTP response body tail read avg/p95: {:.2} / {:.2} ms",
                phase_timing.response_body_tail_read_avg_ms,
                phase_timing.response_body_tail_read_p95_ms
            );
            println!(
                "  HTTP response body chunks avg/p95: {:.2} / {:.2}",
                phase_timing.response_body_chunk_count_avg,
                phase_timing.response_body_chunk_count_p95
            );
            println!(
                "  HTTP response body first chunk bytes avg/p95: {:.0} / {:.0} B",
                phase_timing.response_body_first_chunk_bytes_avg,
                phase_timing.response_body_first_chunk_bytes_p95
            );
            if phase_timing.response_body_post_header_connection_read_wait_samples_total > 0 {
                println!(
                    "  HTTP post-header connection read wait avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_body_post_header_connection_read_wait_avg_ms,
                    phase_timing.response_body_post_header_connection_read_wait_p95_ms,
                    phase_timing.response_body_post_header_connection_read_wait_samples_total
                );
            }
            if phase_timing.response_body_connection_read_to_first_chunk_samples_total > 0 {
                println!(
                    "  HTTP connection read to first chunk avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_body_connection_read_to_first_chunk_avg_ms,
                    phase_timing.response_body_connection_read_to_first_chunk_p95_ms,
                    phase_timing.response_body_connection_read_to_first_chunk_samples_total
                );
            }
            if phase_timing.response_body_tail_connection_read_wait_samples_total > 0 {
                println!(
                    "  HTTP tail connection read wait avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_body_tail_connection_read_wait_avg_ms,
                    phase_timing.response_body_tail_connection_read_wait_p95_ms,
                    phase_timing.response_body_tail_connection_read_wait_samples_total
                );
            }
            if phase_timing.response_body_tail_connection_read_to_end_samples_total > 0 {
                println!(
                    "  HTTP tail connection read to end avg/p95: {:.2} / {:.2} ms (samples {})",
                    phase_timing.response_body_tail_connection_read_to_end_avg_ms,
                    phase_timing.response_body_tail_connection_read_to_end_p95_ms,
                    phase_timing.response_body_tail_connection_read_to_end_samples_total
                );
            }
            println!(
                "  HTTP request round trip avg/p95: {:.2} / {:.2} ms",
                phase_timing.request_round_trip_avg_ms, phase_timing.request_round_trip_p95_ms
            );
        }
    }
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

fn summarize_http_phase_timing(
    samples: &[WorkloadSample],
) -> Option<connectanum_bench_orchestrator::report::HttpPhaseTimingSummary> {
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
    let mut response_body_tail_connection_read_counts = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_body_tail_connection_read_count)
        .map(|count| count as f64)
        .collect::<Vec<_>>();
    let mut response_body_tail_connection_read_spans = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_body_tail_connection_read_span_ms)
        .collect::<Vec<_>>();
    let mut response_body_tail_connection_last_read_to_ends = samples
        .iter()
        .filter_map(|sample| sample.http_phase_timing.as_ref())
        .filter_map(|timing| timing.response_body_tail_connection_last_read_to_end_ms)
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
    response_body_tail_connection_read_counts.sort_by(|left, right| left.total_cmp(right));
    response_body_tail_connection_read_spans.sort_by(|left, right| left.total_cmp(right));
    response_body_tail_connection_last_read_to_ends.sort_by(|left, right| left.total_cmp(right));
    request_round_trips.sort_by(|left, right| left.total_cmp(right));

    Some(
        connectanum_bench_orchestrator::report::HttpPhaseTimingSummary {
            stream_acquire_wait_avg_ms: stream_acquire_waits.iter().sum::<f64>()
                / stream_acquire_waits.len() as f64,
            stream_acquire_wait_p95_ms: percentile(&stream_acquire_waits, 0.95),
            request_enqueue_avg_ms: request_enqueue_times.iter().sum::<f64>()
                / request_enqueue_times.len() as f64,
            request_enqueue_p95_ms: percentile(&request_enqueue_times, 0.95),
            response_headers_wait_avg_ms: response_headers_waits.iter().sum::<f64>()
                / response_headers_waits.len() as f64,
            response_headers_wait_p95_ms: percentile(&response_headers_waits, 0.95),
            response_headers_connection_read_wait_samples_total:
                response_headers_connection_read_waits.len() as u64,
            response_headers_connection_read_wait_avg_ms: if response_headers_connection_read_waits
                .is_empty()
            {
                0.0
            } else {
                response_headers_connection_read_waits.iter().sum::<f64>()
                    / response_headers_connection_read_waits.len() as f64
            },
            response_headers_connection_read_wait_p95_ms: if response_headers_connection_read_waits
                .is_empty()
            {
                0.0
            } else {
                percentile(&response_headers_connection_read_waits, 0.95)
            },
            response_headers_connection_read_to_headers_samples_total:
                response_headers_connection_read_to_headers.len() as u64,
            response_headers_connection_read_to_headers_avg_ms:
                if response_headers_connection_read_to_headers.is_empty() {
                    0.0
                } else {
                    response_headers_connection_read_to_headers
                        .iter()
                        .sum::<f64>()
                        / response_headers_connection_read_to_headers.len() as f64
                },
            response_headers_connection_read_to_headers_p95_ms:
                if response_headers_connection_read_to_headers.is_empty() {
                    0.0
                } else {
                    percentile(&response_headers_connection_read_to_headers, 0.95)
                },
            response_headers_connection_write_wait_samples_total:
                response_headers_connection_write_waits.len() as u64,
            response_headers_connection_write_wait_avg_ms:
                if response_headers_connection_write_waits.is_empty() {
                    0.0
                } else {
                    response_headers_connection_write_waits.iter().sum::<f64>()
                        / response_headers_connection_write_waits.len() as f64
                },
            response_headers_connection_write_wait_p95_ms:
                if response_headers_connection_write_waits.is_empty() {
                    0.0
                } else {
                    percentile(&response_headers_connection_write_waits, 0.95)
                },
            response_headers_connection_write_span_samples_total:
                response_headers_connection_write_spans.len() as u64,
            response_headers_connection_write_span_avg_ms:
                if response_headers_connection_write_spans.is_empty() {
                    0.0
                } else {
                    response_headers_connection_write_spans.iter().sum::<f64>()
                        / response_headers_connection_write_spans.len() as f64
                },
            response_headers_connection_write_span_p95_ms:
                if response_headers_connection_write_spans.is_empty() {
                    0.0
                } else {
                    percentile(&response_headers_connection_write_spans, 0.95)
                },
            response_headers_last_write_to_first_read_samples_total:
                response_headers_last_write_to_first_reads.len() as u64,
            response_headers_last_write_to_first_read_avg_ms:
                if response_headers_last_write_to_first_reads.is_empty() {
                    0.0
                } else {
                    response_headers_last_write_to_first_reads
                        .iter()
                        .sum::<f64>()
                        / response_headers_last_write_to_first_reads.len() as f64
                },
            response_headers_last_write_to_first_read_p95_ms:
                if response_headers_last_write_to_first_reads.is_empty() {
                    0.0
                } else {
                    percentile(&response_headers_last_write_to_first_reads, 0.95)
                },
            response_body_read_avg_ms: response_body_reads.iter().sum::<f64>()
                / response_body_reads.len() as f64,
            response_body_read_p95_ms: percentile(&response_body_reads, 0.95),
            response_body_first_chunk_wait_avg_ms: response_body_first_chunk_waits
                .iter()
                .sum::<f64>()
                / response_body_first_chunk_waits.len() as f64,
            response_body_first_chunk_wait_p95_ms: percentile(
                &response_body_first_chunk_waits,
                0.95,
            ),
            response_body_tail_read_avg_ms: response_body_tail_reads.iter().sum::<f64>()
                / response_body_tail_reads.len() as f64,
            response_body_tail_read_p95_ms: percentile(&response_body_tail_reads, 0.95),
            response_body_chunk_count_avg: response_body_chunk_counts.iter().sum::<f64>()
                / response_body_chunk_counts.len() as f64,
            response_body_chunk_count_p95: percentile(&response_body_chunk_counts, 0.95),
            response_body_first_chunk_bytes_avg: response_body_first_chunk_bytes
                .iter()
                .sum::<f64>()
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
            response_body_tail_connection_read_wait_avg_ms:
                if response_body_tail_connection_read_waits.is_empty() {
                    0.0
                } else {
                    response_body_tail_connection_read_waits.iter().sum::<f64>()
                        / response_body_tail_connection_read_waits.len() as f64
                },
            response_body_tail_connection_read_wait_p95_ms:
                if response_body_tail_connection_read_waits.is_empty() {
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
            response_body_tail_connection_read_count_samples_total:
                response_body_tail_connection_read_counts.len() as u64,
            response_body_tail_connection_read_count_avg:
                if response_body_tail_connection_read_counts.is_empty() {
                    0.0
                } else {
                    response_body_tail_connection_read_counts
                        .iter()
                        .sum::<f64>()
                        / response_body_tail_connection_read_counts.len() as f64
                },
            response_body_tail_connection_read_count_p95:
                if response_body_tail_connection_read_counts.is_empty() {
                    0.0
                } else {
                    percentile(&response_body_tail_connection_read_counts, 0.95)
                },
            response_body_tail_connection_read_span_samples_total:
                response_body_tail_connection_read_spans.len() as u64,
            response_body_tail_connection_read_span_avg_ms:
                if response_body_tail_connection_read_spans.is_empty() {
                    0.0
                } else {
                    response_body_tail_connection_read_spans.iter().sum::<f64>()
                        / response_body_tail_connection_read_spans.len() as f64
                },
            response_body_tail_connection_read_span_p95_ms:
                if response_body_tail_connection_read_spans.is_empty() {
                    0.0
                } else {
                    percentile(&response_body_tail_connection_read_spans, 0.95)
                },
            response_body_tail_connection_last_read_to_end_samples_total:
                response_body_tail_connection_last_read_to_ends.len() as u64,
            response_body_tail_connection_last_read_to_end_avg_ms:
                if response_body_tail_connection_last_read_to_ends.is_empty() {
                    0.0
                } else {
                    response_body_tail_connection_last_read_to_ends
                        .iter()
                        .sum::<f64>()
                        / response_body_tail_connection_last_read_to_ends.len() as f64
                },
            response_body_tail_connection_last_read_to_end_p95_ms:
                if response_body_tail_connection_last_read_to_ends.is_empty() {
                    0.0
                } else {
                    percentile(&response_body_tail_connection_last_read_to_ends, 0.95)
                },
            request_round_trip_avg_ms: request_round_trips.iter().sum::<f64>()
                / request_round_trips.len() as f64,
            request_round_trip_p95_ms: percentile(&request_round_trips, 0.95),
        },
    )
}

fn percentile(values: &[f64], quantile: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let quantile = quantile.clamp(0.0, 1.0);
    let index = ((values.len() - 1) as f64 * quantile).round() as usize;
    values[index]
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
    let (transport, mode) = parse_wamp_protocol(&workload.protocol)
        .ok_or_else(|| anyhow!("unsupported WAMP workload {}", workload.protocol))?;
    let body = json!({
        "realm": workload.auth_realm,
        "auth_method": workload.auth_method,
        "auth_id": if workload.auth_id.is_empty() {
            Value::Null
        } else {
            Value::String(workload.auth_id.clone())
        },
        "auth_secret": if workload.auth_secret.is_empty() {
            Value::Null
        } else {
            Value::String(workload.auth_secret.clone())
        },
        "transport": transport.as_str(),
        "client_impl": workload.client_impl,
        "serializer": workload.serializer,
        "mode": mode.as_str(),
        "uri": workload.path,
        "iterations": workload.iterations,
        "concurrency": workload.concurrency,
        "in_flight_per_session": workload.in_flight_per_session,
        "peer_count": workload.peer_count,
        "payload_bytes": workload.request_bytes,
        "websocket_fragment_size": workload.websocket_fragment_size,
        "secure_transport": workload.secure_transport,
        "ppt_scheme": workload.ppt_scheme.clone(),
        "ppt_serializer": workload.ppt_serializer.clone(),
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

async fn run_rawsocket_auth_frame_workload(
    router_config_path: &str,
    workload: PreparedWorkload,
    timeout: Duration,
) -> Result<Vec<WorkloadSample>> {
    let endpoint = infer_rawsocket_endpoint(router_config_path)?;
    let case = RawSocketAuthFrameCase::parse(workload.frame_case.as_deref())?;
    let mut join_set = JoinSet::new();
    for worker_id in 0..workload.concurrency {
        let endpoint_clone = endpoint.clone();
        let workload_clone = workload.clone();
        join_set.spawn(async move {
            run_rawsocket_auth_frame_worker(endpoint_clone, workload_clone, worker_id, case).await
        });
    }
    let label = format!("{} [RawSocket auth frames]", workload.name.as_str());
    collect_worker_samples(join_set, timeout, &label).await
}

async fn run_rawsocket_auth_frame_worker(
    endpoint: RawSocketEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
    case: RawSocketAuthFrameCase,
) -> Result<Vec<WorkloadSample>> {
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    for iteration in 0..workload.iterations {
        samples.push(
            run_rawsocket_auth_frame_iteration(&endpoint, &workload, case, worker_id, iteration)
                .await?,
        );
    }
    Ok(samples)
}

async fn run_rawsocket_auth_frame_iteration(
    endpoint: &RawSocketEndpoint,
    workload: &PreparedWorkload,
    case: RawSocketAuthFrameCase,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let start = Instant::now();
    let mut request_bytes = 0u64;
    let mut response_bytes = 0u64;
    let mut stream = TcpStream::connect((&endpoint.host[..], endpoint.port))
        .await
        .with_context(|| format!("failed to connect to {}:{}", endpoint.host, endpoint.port))?;

    rawsocket_handshake(&mut stream).await?;

    let hello = build_hello_payload(workload, case)?;
    request_bytes += hello.len() as u64;
    write_rawsocket_message(&mut stream, &hello).await?;

    let challenge = read_rawsocket_message(&mut stream).await?;
    response_bytes += challenge.len() as u64;
    let challenge_message = parse_json_message(&challenge)?;
    let challenge_type = message_type(&challenge_message)?;
    match case {
        RawSocketAuthFrameCase::Success => {
            if challenge_type != 4 {
                bail!("CHALLENGE frame had unexpected code {challenge_type}");
            }
        }
        RawSocketAuthFrameCase::DisconnectAfterChallenge => {
            if challenge_type == 3 {
                return Ok(WorkloadSample {
                    worker: worker_id,
                    iteration,
                    latency_ms: start.elapsed().as_secs_f64() * 1000.0,
                    request_bytes,
                    response_bytes,
                    http_phase_timing: None,
                });
            }
            if challenge_type != 4 {
                bail!("CHALLENGE frame had unexpected code {challenge_type}");
            }
        }
        RawSocketAuthFrameCase::InvalidTicket | RawSocketAuthFrameCase::MissingAuthId => {
            if challenge_type == 3 {
                return Ok(WorkloadSample {
                    worker: worker_id,
                    iteration,
                    latency_ms: start.elapsed().as_secs_f64() * 1000.0,
                    request_bytes,
                    response_bytes,
                    http_phase_timing: None,
                });
            }
            if challenge_type != 4 {
                bail!("CHALLENGE frame had unexpected code {challenge_type}");
            }
        }
    }

    if case == RawSocketAuthFrameCase::DisconnectAfterChallenge {
        stream.shutdown().await?;
        tokio::time::sleep(Duration::from_millis(10)).await;
        return Ok(WorkloadSample {
            worker: worker_id,
            iteration,
            latency_ms: start.elapsed().as_secs_f64() * 1000.0,
            request_bytes,
            response_bytes,
            http_phase_timing: None,
        });
    }

    let authenticate = build_authenticate_payload(workload, case)?;
    request_bytes += authenticate.len() as u64;
    write_rawsocket_message(&mut stream, &authenticate).await?;

    let final_message = read_rawsocket_message(&mut stream).await?;
    response_bytes += final_message.len() as u64;
    let decoded_final = parse_json_message(&final_message)?;
    match case {
        RawSocketAuthFrameCase::Success => {
            ensure_message_type(&decoded_final, 2, "WELCOME")?;
        }
        RawSocketAuthFrameCase::InvalidTicket | RawSocketAuthFrameCase::MissingAuthId => {
            ensure_message_type(&decoded_final, 3, "ABORT")?;
        }
        RawSocketAuthFrameCase::DisconnectAfterChallenge => {}
    }

    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms: start.elapsed().as_secs_f64() * 1000.0,
        request_bytes,
        response_bytes,
        http_phase_timing: None,
    })
}

fn infer_rawsocket_endpoint(router_config_path: &str) -> Result<RawSocketEndpoint> {
    let contents = std::fs::read_to_string(router_config_path)
        .with_context(|| format!("failed to read router config {router_config_path}"))?;
    let value: Value = serde_json::from_str(&contents)
        .with_context(|| format!("failed to parse router config {router_config_path}"))?;
    let listeners = value
        .get("router")
        .and_then(|node| node.get("listeners"))
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("router config missing listeners array"))?;
    for listener in listeners {
        let protocols = listener
            .get("protocols")
            .and_then(Value::as_array)
            .ok_or_else(|| anyhow!("listener missing protocols array"))?;
        let has_rawsocket = protocols.iter().any(|value| {
            value
                .as_str()
                .map(|protocol| protocol.eq_ignore_ascii_case("rawsocket"))
                .unwrap_or(false)
        });
        if !has_rawsocket {
            continue;
        }
        let endpoint = listener
            .get("endpoint")
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow!("rawsocket listener missing endpoint"))?;
        let socket_addr: SocketAddr = endpoint
            .parse()
            .with_context(|| format!("invalid rawsocket listener endpoint {endpoint}"))?;
        let host = match socket_addr.ip() {
            IpAddr::V4(ip) if ip == Ipv4Addr::UNSPECIFIED => "127.0.0.1".to_string(),
            IpAddr::V6(ip) if ip.is_unspecified() => "::1".to_string(),
            other => other.to_string(),
        };
        return Ok(RawSocketEndpoint {
            host,
            port: socket_addr.port(),
        });
    }
    bail!("router config does not define a rawsocket listener")
}

async fn rawsocket_handshake(stream: &mut TcpStream) -> Result<()> {
    let request = [0x7F, ((18u8 - 9) << 4) | 0x01, 0, 0];
    stream
        .write_all(&request)
        .await
        .context("failed to send rawsocket handshake")?;
    let mut response = [0u8; 4];
    stream
        .read_exact(&mut response)
        .await
        .context("failed to read rawsocket handshake response")?;
    if response[0] != 0x7F || response[2] != 0 || response[3] != 0 {
        bail!("invalid rawsocket handshake response");
    }
    if (response[1] & 0x0F) != 0x01 {
        bail!("rawsocket handshake negotiated unexpected serializer");
    }
    Ok(())
}

async fn write_rawsocket_message(stream: &mut TcpStream, payload: &[u8]) -> Result<()> {
    if payload.len() > 0x00FF_FFFF {
        bail!("rawsocket payload too large");
    }
    let header = [
        0u8,
        ((payload.len() >> 16) & 0xFF) as u8,
        ((payload.len() >> 8) & 0xFF) as u8,
        (payload.len() & 0xFF) as u8,
    ];
    stream
        .write_all(&header)
        .await
        .context("failed to send rawsocket frame header")?;
    stream
        .write_all(payload)
        .await
        .context("failed to send rawsocket frame payload")?;
    Ok(())
}

async fn read_rawsocket_message(stream: &mut TcpStream) -> Result<Vec<u8>> {
    let mut header = [0u8; 4];
    stream
        .read_exact(&mut header)
        .await
        .context("failed to read rawsocket frame header")?;
    if header[0] != 0 {
        bail!("unexpected rawsocket frame type {}", header[0]);
    }
    let payload_len =
        ((header[1] as usize) << 16) | ((header[2] as usize) << 8) | header[3] as usize;
    let mut payload = vec![0u8; payload_len];
    stream
        .read_exact(&mut payload)
        .await
        .context("failed to read rawsocket frame payload")?;
    Ok(payload)
}

fn build_hello_payload(
    workload: &PreparedWorkload,
    case: RawSocketAuthFrameCase,
) -> Result<Vec<u8>> {
    let mut details = serde_json::Map::new();
    details.insert(
        "roles".to_string(),
        json!({
            "caller": {},
            "subscriber": {},
            "publisher": {},
        }),
    );
    details.insert(
        "authmethods".to_string(),
        Value::Array(vec![Value::String(workload.auth_method.clone())]),
    );
    if case != RawSocketAuthFrameCase::MissingAuthId && !workload.auth_id.is_empty() {
        details.insert(
            "authid".to_string(),
            Value::String(workload.auth_id.clone()),
        );
    }
    serde_json::to_vec(&json!([1, workload.auth_realm, Value::Object(details)]))
        .context("failed to serialize HELLO payload")
}

fn build_authenticate_payload(
    workload: &PreparedWorkload,
    case: RawSocketAuthFrameCase,
) -> Result<Vec<u8>> {
    let signature = match case {
        RawSocketAuthFrameCase::InvalidTicket => "invalid-ticket".to_string(),
        _ => workload.auth_secret.clone(),
    };
    serde_json::to_vec(&json!([5, signature, {}]))
        .context("failed to serialize AUTHENTICATE payload")
}

fn parse_json_message(payload: &[u8]) -> Result<Vec<Value>> {
    let value: Value =
        serde_json::from_slice(payload).context("failed to decode JSON WAMP frame")?;
    value
        .as_array()
        .cloned()
        .ok_or_else(|| anyhow!("expected JSON array WAMP frame"))
}

fn ensure_message_type(message: &[Value], expected: u64, label: &str) -> Result<()> {
    let actual = message_type(message)?;
    if actual != expected {
        bail!("{label} frame had unexpected code {actual}");
    }
    Ok(())
}

fn message_type(message: &[Value]) -> Result<u64> {
    message
        .first()
        .and_then(Value::as_u64)
        .ok_or_else(|| anyhow!("WAMP frame missing message code"))
}

async fn execute_workload(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    timeout: Duration,
) -> Result<WorkloadExecution> {
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
) -> Result<WorkloadExecution> {
    let mut join_set = JoinSet::new();
    for worker_id in 0..workload.concurrency {
        let endpoint_clone = endpoint.clone();
        let workload_clone = workload.clone();
        join_set
            .spawn(async move { run_h1_worker(endpoint_clone, workload_clone, worker_id).await });
    }
    let label = format!("{} [HTTP/1.1]", workload.name.as_str());
    collect_http_worker_executions(join_set, &workload, timeout, &label).await
}

async fn run_h1_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<HttpWorkerExecution> {
    if workload.auth_flow.is_some() {
        return run_h1_auth_worker(endpoint, workload, worker_id).await;
    }
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let mut connections_opened = 0u32;
    let request_body = build_payload(
        workload.request_bytes,
        workload.request_chunk_bytes as usize,
    );
    if workload.reuse_connections {
        let mut sender = connect_h1_sender(&endpoint).await?;
        connections_opened += 1;
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
                    connections_opened += 1;
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
        return Ok(HttpWorkerExecution {
            samples,
            connections_opened,
        });
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
        connections_opened += 1;
    }
    Ok(HttpWorkerExecution {
        samples,
        connections_opened,
    })
}

async fn run_h2_workload(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    timeout: Duration,
) -> Result<WorkloadExecution> {
    let mut join_set = JoinSet::new();
    for worker_id in 0..workload.concurrency {
        let endpoint_clone = endpoint.clone();
        let workload_clone = workload.clone();
        join_set
            .spawn(async move { run_h2_worker(endpoint_clone, workload_clone, worker_id).await });
    }
    let label = format!("{} [HTTP/2]", workload.name.as_str());
    collect_http_worker_executions(join_set, &workload, timeout, &label).await
}

async fn run_h2_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<HttpWorkerExecution> {
    if workload.auth_flow.is_some() {
        return run_h2_auth_worker(endpoint, workload, worker_id).await;
    }
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let mut connections_opened = 0u32;
    let request_body = build_payload(
        workload.request_bytes,
        workload.request_chunk_bytes as usize,
    );
    if workload.reuse_connections {
        let mut sender = connect_h2_sender(&endpoint).await?;
        connections_opened += 1;
        if workload.streams_per_connection > 1 {
            return run_h2_multiplexed_worker(
                sender,
                endpoint,
                workload,
                request_body,
                worker_id,
                connections_opened,
            )
            .await;
        }
        for iteration in 0..workload.iterations {
            let sample = match send_h2_request(
                sender.clone(),
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
                    connections_opened += 1;
                    send_h2_request(
                        sender.clone(),
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
        return Ok(HttpWorkerExecution {
            samples,
            connections_opened,
        });
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
        connections_opened += 1;
    }
    Ok(HttpWorkerExecution {
        samples,
        connections_opened,
    })
}

async fn run_h2_multiplexed_worker(
    sender: H2BenchSender,
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    request_body: Bytes,
    worker_id: u32,
    connections_opened: u32,
) -> Result<HttpWorkerExecution> {
    let mut join_set = JoinSet::new();
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let mut next_iteration = 0u32;
    let max_in_flight = workload
        .streams_per_connection
        .min(workload.iterations)
        .max(1);

    while next_iteration < workload.iterations || !join_set.is_empty() {
        while next_iteration < workload.iterations && join_set.len() < max_in_flight as usize {
            let sender_clone = sender.clone();
            let endpoint_clone = endpoint.clone();
            let workload_clone = workload.clone();
            let request_body_clone = request_body.clone();
            let iteration = next_iteration;
            join_set.spawn(async move {
                send_h2_request(
                    sender_clone,
                    &endpoint_clone,
                    &workload_clone,
                    request_body_clone,
                    worker_id,
                    iteration,
                )
                .await
            });
            next_iteration += 1;
        }
        let sample = join_set
            .join_next()
            .await
            .expect("join_set should contain inflight HTTP/2 streams")
            .map_err(|err| anyhow!("HTTP/2 multiplexed worker failed: {err}"))??;
        samples.push(sample);
    }

    Ok(HttpWorkerExecution {
        samples,
        connections_opened,
    })
}

async fn run_h3_workload(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    timeout: Duration,
) -> Result<WorkloadExecution> {
    let mut join_set = JoinSet::new();
    for worker_id in 0..workload.concurrency {
        let endpoint_clone = endpoint.clone();
        let workload_clone = workload.clone();
        join_set
            .spawn(async move { run_h3_worker(endpoint_clone, workload_clone, worker_id).await });
    }
    let label = format!("{} [HTTP/3]", workload.name.as_str());
    collect_http_worker_executions(join_set, &workload, timeout, &label).await
}

async fn run_h3_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<HttpWorkerExecution> {
    if workload.auth_flow.is_some() {
        return run_h3_auth_worker(endpoint, workload, worker_id).await;
    }
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let mut connections_opened = 0u32;
    let request_chunk =
        build_pattern_chunk(std::cmp::max(1, workload.request_chunk_bytes as usize));
    if workload.reuse_connections {
        let (mut quinn_endpoint, mut send_request) = connect_h3_sender(&endpoint).await?;
        connections_opened += 1;
        if workload.streams_per_connection > 1 {
            return run_h3_multiplexed_worker(
                quinn_endpoint,
                send_request,
                endpoint,
                workload,
                request_chunk,
                worker_id,
                connections_opened,
            )
            .await;
        }
        for iteration in 0..workload.iterations {
            let sample = match send_h3_request(
                send_request.clone(),
                &endpoint,
                &workload,
                request_chunk.clone(),
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
                    connections_opened += 1;
                    send_h3_request(
                        send_request.clone(),
                        &endpoint,
                        &workload,
                        request_chunk.clone(),
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
        return Ok(HttpWorkerExecution {
            samples,
            connections_opened,
        });
    }
    for iteration in 0..workload.iterations {
        let sample = run_h3_iteration(
            &endpoint,
            &workload,
            request_chunk.clone(),
            worker_id,
            iteration,
        )
        .await?;
        samples.push(sample);
        connections_opened += 1;
    }
    Ok(HttpWorkerExecution {
        samples,
        connections_opened,
    })
}

async fn run_h3_multiplexed_worker(
    quinn_endpoint: QuinnEndpoint,
    send_request: H3RequestSender,
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    request_chunk: Bytes,
    worker_id: u32,
    connections_opened: u32,
) -> Result<HttpWorkerExecution> {
    let mut join_set = JoinSet::new();
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let mut next_iteration = 0u32;
    let max_in_flight = workload
        .streams_per_connection
        .min(workload.iterations)
        .max(1);

    while next_iteration < workload.iterations || !join_set.is_empty() {
        while next_iteration < workload.iterations && join_set.len() < max_in_flight as usize {
            let sender_clone = send_request.clone();
            let endpoint_clone = endpoint.clone();
            let workload_clone = workload.clone();
            let request_chunk_clone = request_chunk.clone();
            let iteration = next_iteration;
            join_set.spawn(async move {
                send_h3_request(
                    sender_clone,
                    &endpoint_clone,
                    &workload_clone,
                    request_chunk_clone,
                    worker_id,
                    iteration,
                )
                .await
            });
            next_iteration += 1;
        }
        let sample = join_set
            .join_next()
            .await
            .expect("join_set should contain inflight HTTP/3 streams")
            .map_err(|err| anyhow!("HTTP/3 multiplexed worker failed: {err}"))??;
        samples.push(sample);
    }

    quinn_endpoint.close(0u32.into(), b"done");
    Ok(HttpWorkerExecution {
        samples,
        connections_opened,
    })
}

async fn run_h1_auth_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<HttpWorkerExecution> {
    let mut sender = connect_h1_sender(&endpoint).await?;
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let request_body = build_payload(
        workload.request_bytes,
        workload.request_chunk_bytes as usize,
    );
    let flow = workload
        .auth_flow
        .ok_or_else(|| anyhow!("missing http auth flow"))?;
    let mut auth_session = match flow {
        HttpAuthFlow::Protected if workload.auth_bearer_token.is_some() => Some(HttpAuthSession {
            access_token: workload.auth_bearer_token.clone().unwrap(),
            refresh_token: String::new(),
        }),
        HttpAuthFlow::Protected | HttpAuthFlow::Refresh => {
            Some(h1_authenticate(&mut sender, &endpoint, &workload).await?)
        }
        HttpAuthFlow::Login => None,
    };

    for iteration in 0..workload.iterations {
        let sample = match flow {
            HttpAuthFlow::Login => {
                h1_login_iteration(&mut sender, &endpoint, &workload, worker_id, iteration).await?
            }
            HttpAuthFlow::Protected => {
                let session = auth_session
                    .as_ref()
                    .ok_or_else(|| anyhow!("missing bearer token for protected auth workload"))?;
                send_h1_protected_request(
                    &mut sender,
                    &endpoint,
                    &workload,
                    request_body.clone(),
                    &session.access_token,
                    worker_id,
                    iteration,
                )
                .await?
            }
            HttpAuthFlow::Refresh => {
                let session = auth_session
                    .as_ref()
                    .ok_or_else(|| anyhow!("missing refresh token for auth workload"))?;
                let start = Instant::now();
                let (next_session, request_bytes, response_bytes) =
                    h1_refresh(&mut sender, &endpoint, &workload, &session.refresh_token).await?;
                auth_session = Some(next_session);
                WorkloadSample {
                    worker: worker_id,
                    iteration,
                    latency_ms: start.elapsed().as_secs_f64() * 1000.0,
                    request_bytes,
                    response_bytes,
                    http_phase_timing: None,
                }
            }
        };
        samples.push(sample);
    }

    Ok(HttpWorkerExecution {
        samples,
        connections_opened: 1,
    })
}

async fn run_h2_auth_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<HttpWorkerExecution> {
    let sender = connect_h2_sender(&endpoint).await?;
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let request_body = build_payload(
        workload.request_bytes,
        workload.request_chunk_bytes as usize,
    );
    let flow = workload
        .auth_flow
        .ok_or_else(|| anyhow!("missing http auth flow"))?;
    let mut auth_session = match flow {
        HttpAuthFlow::Protected if workload.auth_bearer_token.is_some() => Some(HttpAuthSession {
            access_token: workload.auth_bearer_token.clone().unwrap(),
            refresh_token: String::new(),
        }),
        HttpAuthFlow::Protected | HttpAuthFlow::Refresh => {
            Some(h2_authenticate(sender.clone(), &endpoint, &workload).await?)
        }
        HttpAuthFlow::Login => None,
    };

    for iteration in 0..workload.iterations {
        let sample = match flow {
            HttpAuthFlow::Login => {
                h2_login_iteration(sender.clone(), &endpoint, &workload, worker_id, iteration)
                    .await?
            }
            HttpAuthFlow::Protected => {
                let session = auth_session
                    .as_ref()
                    .ok_or_else(|| anyhow!("missing bearer token for protected auth workload"))?;
                send_h2_protected_request(
                    sender.clone(),
                    &endpoint,
                    &workload,
                    request_body.clone(),
                    &session.access_token,
                    worker_id,
                    iteration,
                )
                .await?
            }
            HttpAuthFlow::Refresh => {
                let session = auth_session
                    .as_ref()
                    .ok_or_else(|| anyhow!("missing refresh token for auth workload"))?;
                let start = Instant::now();
                let (next_session, request_bytes, response_bytes) =
                    h2_refresh(sender.clone(), &endpoint, &workload, &session.refresh_token)
                        .await?;
                auth_session = Some(next_session);
                WorkloadSample {
                    worker: worker_id,
                    iteration,
                    latency_ms: start.elapsed().as_secs_f64() * 1000.0,
                    request_bytes,
                    response_bytes,
                    http_phase_timing: None,
                }
            }
        };
        samples.push(sample);
    }

    Ok(HttpWorkerExecution {
        samples,
        connections_opened: 1,
    })
}

async fn run_h3_auth_worker(
    endpoint: HttpEndpoint,
    workload: PreparedWorkload,
    worker_id: u32,
) -> Result<HttpWorkerExecution> {
    let (quinn_endpoint, send_request) = connect_h3_sender(&endpoint).await?;
    let mut samples = Vec::with_capacity(workload.iterations as usize);
    let request_chunk =
        build_pattern_chunk(std::cmp::max(1, workload.request_chunk_bytes as usize));
    let flow = workload
        .auth_flow
        .ok_or_else(|| anyhow!("missing http auth flow"))?;
    let mut auth_session = match flow {
        HttpAuthFlow::Protected if workload.auth_bearer_token.is_some() => Some(HttpAuthSession {
            access_token: workload.auth_bearer_token.clone().unwrap(),
            refresh_token: String::new(),
        }),
        HttpAuthFlow::Protected | HttpAuthFlow::Refresh => {
            Some(h3_authenticate(send_request.clone(), &endpoint, &workload).await?)
        }
        HttpAuthFlow::Login => None,
    };

    for iteration in 0..workload.iterations {
        let sample = match flow {
            HttpAuthFlow::Login => {
                h3_login_iteration(
                    send_request.clone(),
                    &endpoint,
                    &workload,
                    worker_id,
                    iteration,
                )
                .await?
            }
            HttpAuthFlow::Protected => {
                let session = auth_session
                    .as_ref()
                    .ok_or_else(|| anyhow!("missing bearer token for protected auth workload"))?;
                send_h3_protected_request(
                    send_request.clone(),
                    &endpoint,
                    &workload,
                    request_chunk.clone(),
                    &session.access_token,
                    worker_id,
                    iteration,
                )
                .await?
            }
            HttpAuthFlow::Refresh => {
                let session = auth_session
                    .as_ref()
                    .ok_or_else(|| anyhow!("missing refresh token for auth workload"))?;
                let start = Instant::now();
                let (next_session, request_bytes, response_bytes) = h3_refresh(
                    send_request.clone(),
                    &endpoint,
                    &workload,
                    &session.refresh_token,
                )
                .await?;
                auth_session = Some(next_session);
                WorkloadSample {
                    worker: worker_id,
                    iteration,
                    latency_ms: start.elapsed().as_secs_f64() * 1000.0,
                    request_bytes,
                    response_bytes,
                    http_phase_timing: None,
                }
            }
        };
        samples.push(sample);
    }

    quinn_endpoint.close(0u32.into(), b"done");
    Ok(HttpWorkerExecution {
        samples,
        connections_opened: 1,
    })
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

async fn collect_http_worker_executions(
    mut join_set: JoinSet<Result<HttpWorkerExecution>>,
    workload: &PreparedWorkload,
    timeout: Duration,
    label: &str,
) -> Result<WorkloadExecution> {
    let mut samples = Vec::new();
    let mut connections_opened = 0u32;
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
                let worker_execution =
                    join_result.map_err(|err| anyhow!("{label} worker failed: {err}"))??;
                samples.extend(worker_execution.samples);
                connections_opened += worker_execution.connections_opened;
            }
            Ok(None) => break,
            Err(_) => {
                join_set.shutdown().await;
                bail!("{label} timed out after {:?}", timeout);
            }
        }
    }
    Ok(WorkloadExecution::with_http_usage(
        workload,
        samples,
        connections_opened,
    ))
}

fn build_auth_start_body(workload: &PreparedWorkload) -> Result<(Value, HttpAuthClientState)> {
    let method = workload.auth_method.to_ascii_lowercase();
    match method.as_str() {
        "ticket" => Ok((
            json!({
                "realm": workload.auth_realm,
                "authmethod": workload.auth_method,
                "authid": workload.auth_id,
            }),
            HttpAuthClientState::Ticket,
        )),
        "wampcra" => Ok((
            json!({
                "realm": workload.auth_realm,
                "authmethod": workload.auth_method,
                "authid": workload.auth_id,
            }),
            HttpAuthClientState::WampCra,
        )),
        "scram" => {
            let hello_nonce = Base64Engine.encode(format!(
                "bench-http-scram:{}:{}",
                workload.auth_realm, workload.auth_id
            ));
            Ok((
                json!({
                    "realm": workload.auth_realm,
                    "authmethod": workload.auth_method,
                    "authid": workload.auth_id,
                    "authextra": {
                        "nonce": hello_nonce,
                        "channel_binding": Value::Null,
                    },
                }),
                HttpAuthClientState::Scram { hello_nonce },
            ))
        }
        other => bail!("unsupported HTTP auth method {other}"),
    }
}

fn build_auth_complete_body(
    workload: &PreparedWorkload,
    client_state: &HttpAuthClientState,
    challenge: &HttpAuthChallenge,
) -> Result<Value> {
    let method = workload.auth_method.to_ascii_lowercase();
    match method.as_str() {
        "ticket" => Ok(json!({
            "state": challenge.state,
            "signature": workload.auth_secret,
            "extra": {},
        })),
        "wampcra" => {
            let challenge_fields = challenge
                .challenge
                .as_object()
                .ok_or_else(|| anyhow!("WAMP-CRA challenge payload must be an object"))?;
            let challenge_text = challenge_fields
                .get("challenge")
                .and_then(Value::as_str)
                .ok_or_else(|| anyhow!("WAMP-CRA challenge missing challenge text"))?;
            let iterations = json_u32(challenge_fields.get("iterations"))
                .unwrap_or(1000)
                .max(1);
            let key_len = json_usize(challenge_fields.get("keylen"))
                .unwrap_or(32)
                .max(1);
            let secret_key =
                if let Some(salt) = challenge_fields.get("salt").and_then(Value::as_str) {
                    let mut derived = vec![0u8; key_len];
                    pbkdf2_hmac::<Sha256>(
                        workload.auth_secret.as_bytes(),
                        salt.as_bytes(),
                        iterations,
                        &mut derived,
                    );
                    derived
                } else {
                    workload.auth_secret.as_bytes().to_vec()
                };
            let signature = hmac_base64(
                Base64Engine.encode(secret_key).as_bytes(),
                challenge_text.as_bytes(),
                key_len,
            )?;
            Ok(json!({
                "state": challenge.state,
                "signature": signature,
                "extra": {},
            }))
        }
        "scram" => {
            let hello_nonce = match client_state {
                HttpAuthClientState::Scram { hello_nonce } => hello_nonce.as_str(),
                _ => bail!("SCRAM auth completion requires SCRAM client state"),
            };
            let challenge_fields = challenge
                .challenge
                .as_object()
                .ok_or_else(|| anyhow!("SCRAM challenge payload must be an object"))?;
            let combined_nonce = challenge_fields
                .get("nonce")
                .and_then(Value::as_str)
                .ok_or_else(|| anyhow!("SCRAM challenge missing nonce"))?;
            let salt = challenge_fields
                .get("salt")
                .and_then(Value::as_str)
                .ok_or_else(|| anyhow!("SCRAM challenge missing salt"))?;
            let iterations = json_u32(challenge_fields.get("iterations"))
                .unwrap_or(4096)
                .max(1);
            let kdf = challenge_fields
                .get("kdf")
                .and_then(Value::as_str)
                .unwrap_or("pbkdf2");
            if !kdf.eq_ignore_ascii_case("pbkdf2") {
                bail!("SCRAM challenge uses unsupported kdf {kdf}");
            }
            let salted_password = {
                let salt_bytes = Base64Engine
                    .decode(salt)
                    .with_context(|| format!("invalid SCRAM salt {salt}"))?;
                let mut output = vec![0u8; 32];
                pbkdf2_hmac::<Sha256>(
                    workload.auth_secret.as_bytes(),
                    &salt_bytes,
                    iterations,
                    &mut output,
                );
                output
            };
            let client_key = hmac_bytes(&salted_password, b"Client Key")?;
            let stored_key = Sha256::digest(&client_key);
            let auth_message = format!(
                "n={},r={},r={},s={},i={},c=biws,r={}",
                workload.auth_id, hello_nonce, combined_nonce, salt, iterations, combined_nonce
            );
            let client_signature = hmac_bytes(&stored_key, auth_message.as_bytes())?;
            let proof: Vec<u8> = client_key
                .iter()
                .zip(client_signature.iter())
                .map(|(lhs, rhs)| lhs ^ rhs)
                .collect();
            Ok(json!({
                "state": challenge.state,
                "signature": Base64Engine.encode(proof),
                "extra": {
                    "nonce": combined_nonce,
                    "channel_binding": Value::Null,
                    "cbind_data": Value::Null,
                },
            }))
        }
        other => bail!("unsupported HTTP auth method {other}"),
    }
}

fn build_auth_refresh_body(refresh_token: &str) -> Value {
    json!({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
    })
}

fn parse_json_response(response: &HttpBodyResponse) -> Result<Value> {
    serde_json::from_slice(&response.body).context("failed to decode JSON response")
}

fn parse_auth_challenge(response: &HttpBodyResponse) -> Result<HttpAuthChallenge> {
    if response.status != HyperStatusCode::UNAUTHORIZED {
        bail!("expected 401 challenge, got {}", response.status);
    }
    let body = parse_json_response(response)?;
    let state = body
        .get("state")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("challenge response missing state"))?;
    Ok(HttpAuthChallenge {
        state: state.to_string(),
        challenge: body.get("challenge").cloned().unwrap_or(Value::Null),
    })
}

fn json_u32(value: Option<&Value>) -> Option<u32> {
    value
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
}

fn json_usize(value: Option<&Value>) -> Option<usize> {
    value
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
}

fn hmac_base64(key: &[u8], message: &[u8], key_len: usize) -> Result<String> {
    Ok(Base64Engine.encode(hmac_bytes(key, message)?[..std::cmp::min(key_len, 32)].to_vec()))
}

fn hmac_bytes(key: &[u8], message: &[u8]) -> Result<Vec<u8>> {
    let mut mac =
        Hmac::<Sha256>::new_from_slice(key).map_err(|_| anyhow!("invalid HMAC key length"))?;
    mac.update(message);
    Ok(mac.finalize().into_bytes().to_vec())
}

fn parse_auth_success(response: &HttpBodyResponse) -> Result<HttpAuthSession> {
    if response.status != HyperStatusCode::OK {
        bail!("expected 200 success, got {}", response.status);
    }
    let body = parse_json_response(response)?;
    let access_token = body
        .get("access_token")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("auth response missing access_token"))?;
    let refresh_token = body
        .get("refresh_token")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("auth response missing refresh_token"))?;
    Ok(HttpAuthSession {
        access_token: access_token.to_string(),
        refresh_token: refresh_token.to_string(),
    })
}

fn json_request_bytes(body: &Value) -> Result<Bytes> {
    let encoded = serde_json::to_vec(body).context("failed to encode JSON body")?;
    Ok(Bytes::from(encoded))
}

fn build_h1_json_request(
    endpoint: &HttpEndpoint,
    method: &HyperMethod,
    path: &str,
    request_body: Body,
    request_bytes: u64,
    bearer: Option<&str>,
) -> Result<Request<Body>> {
    let uri = path.to_string();
    let mut request_builder = Request::builder().method(method.clone()).uri(uri);
    let headers = request_builder.headers_mut().unwrap();
    headers.insert(
        "host",
        HyperHeaderValue::from_str(&endpoint_authority(endpoint))
            .context("invalid host header value")?,
    );
    headers.insert(
        "content-type",
        HyperHeaderValue::from_static("application/json"),
    );
    headers.insert(
        "content-length",
        HyperHeaderValue::from_str(&request_bytes.to_string())
            .unwrap_or_else(|_| HyperHeaderValue::from_static("0")),
    );
    headers.insert(ACCEPT, HyperHeaderValue::from_static("application/json"));
    headers.insert(
        USER_AGENT,
        HyperHeaderValue::from_static("connectanum-bench/0.1"),
    );
    if let Some(token) = bearer {
        headers.insert(
            "authorization",
            HyperHeaderValue::from_str(&format!("Bearer {token}"))
                .context("invalid authorization header")?,
        );
    }
    request_builder
        .body(request_body)
        .context("failed to build HTTP/1.1 JSON request")
}

fn build_h2_json_request(
    endpoint: &HttpEndpoint,
    method: &HyperMethod,
    path: &str,
    request_bytes: u64,
    bearer: Option<&str>,
) -> Result<Request<()>> {
    let uri = format!(
        "{}://{}:{}{}",
        endpoint.scheme, endpoint.host, endpoint.port, path
    );
    let mut request_builder = Request::builder()
        .method(method.clone())
        .uri(uri)
        .version(HyperVersion::HTTP_2);
    let headers = request_builder.headers_mut().unwrap();
    headers.insert(
        "content-type",
        HyperHeaderValue::from_static("application/json"),
    );
    headers.insert(
        "content-length",
        HyperHeaderValue::from_str(&request_bytes.to_string())
            .unwrap_or_else(|_| HyperHeaderValue::from_static("0")),
    );
    headers.insert(ACCEPT, HyperHeaderValue::from_static("application/json"));
    headers.insert(
        USER_AGENT,
        HyperHeaderValue::from_static("connectanum-bench/0.1"),
    );
    if let Some(token) = bearer {
        headers.insert(
            "authorization",
            HyperHeaderValue::from_str(&format!("Bearer {token}"))
                .context("invalid authorization header")?,
        );
    }
    request_builder
        .body(())
        .context("failed to build HTTP/2 JSON request")
}

fn build_h3_json_request(
    endpoint: &HttpEndpoint,
    method: &HyperMethod,
    path: &str,
    request_bytes: u64,
    bearer: Option<&str>,
) -> Result<http3::Request<()>> {
    let server_port = endpoint.http3_port();
    let uri = format!("https://{}:{}{}", endpoint.host, server_port, path);
    let h3_method = http3::Method::from_bytes(method.as_str().as_bytes())
        .map_err(|_| anyhow!("invalid HTTP/3 method {}", method.as_str()))?;
    let mut request_builder = http3::Request::builder().method(h3_method).uri(uri);
    let headers = request_builder
        .headers_mut()
        .ok_or_else(|| anyhow!("unable to access HTTP/3 request headers"))?;
    headers.insert(
        http3::header::HeaderName::from_static("content-type"),
        http3::header::HeaderValue::from_static("application/json"),
    );
    headers.insert(
        http3::header::HeaderName::from_static("content-length"),
        http3::header::HeaderValue::from_str(&request_bytes.to_string())
            .unwrap_or_else(|_| http3::header::HeaderValue::from_static("0")),
    );
    headers.insert(
        http3::header::HeaderName::from_static("accept"),
        http3::header::HeaderValue::from_static("application/json"),
    );
    headers.insert(
        http3::header::HeaderName::from_static("user-agent"),
        http3::header::HeaderValue::from_static("connectanum-bench/0.1"),
    );
    if let Some(token) = bearer {
        headers.insert(
            http3::header::HeaderName::from_static("authorization"),
            http3::header::HeaderValue::from_str(&format!("Bearer {token}"))
                .context("invalid authorization header")?,
        );
    }
    request_builder
        .body(())
        .context("failed to build HTTP/3 JSON request")
}

async fn drain_hyper_response_bytes(response: hyper::Response<Body>) -> Result<HttpBodyResponse> {
    let status = response.status();
    let mut body = response.into_body();
    let mut received = Vec::new();
    while let Some(chunk) = body.data().await {
        received.extend_from_slice(&chunk?);
    }
    Ok(HttpBodyResponse {
        status,
        body: received,
    })
}

async fn drain_h2_response_bytes(
    response: hyper::http::Response<H2RecvStream>,
) -> Result<HttpBodyResponse> {
    let status = response.status();
    let mut body = response.into_body();
    let mut received = Vec::new();
    while let Some(chunk) = body.data().await {
        let bytes = chunk?;
        body.flow_control()
            .release_capacity(bytes.len())
            .context("failed to release HTTP/2 flow-control capacity")?;
        received.extend_from_slice(&bytes);
    }
    Ok(HttpBodyResponse {
        status,
        body: received,
    })
}

async fn send_h1_json_request(
    sender: &mut hyper::client::conn::SendRequest<Body>,
    endpoint: &HttpEndpoint,
    method: &HyperMethod,
    path: &str,
    body: &Value,
    bearer: Option<&str>,
) -> Result<(HttpBodyResponse, u64)> {
    let payload = json_request_bytes(body)?;
    let request = build_h1_json_request(
        endpoint,
        method,
        path,
        Body::from(payload.clone()),
        payload.len() as u64,
        bearer,
    )?;
    let response = sender
        .send_request(request)
        .await
        .context("failed to send HTTP/1.1 JSON request")?;
    Ok((
        drain_hyper_response_bytes(response).await?,
        payload.len() as u64,
    ))
}

async fn send_h2_json_request(
    sender: H2BenchSender,
    endpoint: &HttpEndpoint,
    method: &HyperMethod,
    path: &str,
    body: &Value,
    bearer: Option<&str>,
) -> Result<(HttpBodyResponse, u64)> {
    let payload = json_request_bytes(body)?;
    let mut sender = sender
        .sender
        .ready()
        .await
        .context("HTTP/2 sender not ready for JSON request")?;
    let request = build_h2_json_request(endpoint, method, path, payload.len() as u64, bearer)?;
    let end_stream = payload.is_empty();
    let (response, mut send_stream) = sender
        .send_request(request, end_stream)
        .context("failed to send HTTP/2 JSON request")?;
    if !end_stream {
        send_stream
            .send_data(payload.clone(), true)
            .context("failed to send HTTP/2 JSON body")?;
    }
    Ok((
        drain_h2_response_bytes(
            response
                .await
                .context("failed to receive HTTP/2 JSON response")?,
        )
        .await?,
        payload.len() as u64,
    ))
}

async fn send_h3_json_request(
    mut send_request: H3RequestSender,
    endpoint: &HttpEndpoint,
    method: &HyperMethod,
    path: &str,
    body: &Value,
    bearer: Option<&str>,
) -> Result<(HttpBodyResponse, u64)> {
    let payload = json_request_bytes(body)?;
    let request = build_h3_json_request(endpoint, method, path, payload.len() as u64, bearer)?;
    let mut req_stream = send_request
        .send_request(request)
        .await
        .context("failed to open HTTP/3 JSON request stream")?;
    if payload.is_empty() {
        req_stream
            .finish()
            .await
            .context("failed to finish HTTP/3 JSON request")?;
    } else {
        req_stream
            .send_data(payload.clone())
            .await
            .context("failed to send HTTP/3 JSON body")?;
        req_stream
            .finish()
            .await
            .context("failed to finish HTTP/3 JSON request")?;
    }
    let response = req_stream
        .recv_response()
        .await
        .context("failed to receive HTTP/3 JSON response headers")?;
    let mut received = Vec::new();
    while let Some(chunk) = req_stream
        .recv_data()
        .await
        .context("failed to read HTTP/3 JSON body")?
    {
        let mut chunk = chunk;
        received.extend_from_slice(&chunk.copy_to_bytes(chunk.remaining()));
    }
    Ok((
        HttpBodyResponse {
            status: HyperStatusCode::from_u16(response.status().as_u16())
                .map_err(|_| anyhow!("invalid HTTP/3 status {}", response.status()))?,
            body: received,
        },
        payload.len() as u64,
    ))
}

async fn h1_authenticate(
    sender: &mut hyper::client::conn::SendRequest<Body>,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
) -> Result<HttpAuthSession> {
    let (start_body, client_state) = build_auth_start_body(workload)?;
    let (challenge, _) = send_h1_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &start_body,
        None,
    )
    .await?;
    let challenge = parse_auth_challenge(&challenge)?;
    let complete_body = build_auth_complete_body(workload, &client_state, &challenge)?;
    let (success, _) = send_h1_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &complete_body,
        None,
    )
    .await?;
    parse_auth_success(&success)
}

async fn h2_authenticate(
    sender: H2BenchSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
) -> Result<HttpAuthSession> {
    let (start_body, client_state) = build_auth_start_body(workload)?;
    let (challenge, _) = send_h2_json_request(
        sender.clone(),
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &start_body,
        None,
    )
    .await?;
    let challenge = parse_auth_challenge(&challenge)?;
    let complete_body = build_auth_complete_body(workload, &client_state, &challenge)?;
    let (success, _) = send_h2_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &complete_body,
        None,
    )
    .await?;
    parse_auth_success(&success)
}

async fn h3_authenticate(
    sender: H3RequestSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
) -> Result<HttpAuthSession> {
    let (start_body, client_state) = build_auth_start_body(workload)?;
    let (challenge, _) = send_h3_json_request(
        sender.clone(),
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &start_body,
        None,
    )
    .await?;
    let challenge = parse_auth_challenge(&challenge)?;
    let complete_body = build_auth_complete_body(workload, &client_state, &challenge)?;
    let (success, _) = send_h3_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &complete_body,
        None,
    )
    .await?;
    parse_auth_success(&success)
}

async fn h1_login_iteration(
    sender: &mut hyper::client::conn::SendRequest<Body>,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let start = Instant::now();
    let (start_body, client_state) = build_auth_start_body(workload)?;
    let (challenge, request1) = send_h1_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &start_body,
        None,
    )
    .await?;
    let challenge_bytes = challenge.body.len() as u64;
    let challenge = parse_auth_challenge(&challenge)?;
    let complete_body = build_auth_complete_body(workload, &client_state, &challenge)?;
    let (success, request2) = send_h1_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &complete_body,
        None,
    )
    .await?;
    let success_bytes = success.body.len() as u64;
    let _ = parse_auth_success(&success)?;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms: start.elapsed().as_secs_f64() * 1000.0,
        request_bytes: request1 + request2,
        response_bytes: challenge_bytes + success_bytes,
        http_phase_timing: None,
    })
}

async fn h2_login_iteration(
    sender: H2BenchSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let start = Instant::now();
    let (start_body, client_state) = build_auth_start_body(workload)?;
    let (challenge, request1) = send_h2_json_request(
        sender.clone(),
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &start_body,
        None,
    )
    .await?;
    let challenge_bytes = challenge.body.len() as u64;
    let challenge = parse_auth_challenge(&challenge)?;
    let complete_body = build_auth_complete_body(workload, &client_state, &challenge)?;
    let (success, request2) = send_h2_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &complete_body,
        None,
    )
    .await?;
    let success_bytes = success.body.len() as u64;
    let _ = parse_auth_success(&success)?;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms: start.elapsed().as_secs_f64() * 1000.0,
        request_bytes: request1 + request2,
        response_bytes: challenge_bytes + success_bytes,
        http_phase_timing: None,
    })
}

async fn h3_login_iteration(
    sender: H3RequestSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let start = Instant::now();
    let (start_body, client_state) = build_auth_start_body(workload)?;
    let (challenge, request1) = send_h3_json_request(
        sender.clone(),
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &start_body,
        None,
    )
    .await?;
    let challenge_bytes = challenge.body.len() as u64;
    let challenge = parse_auth_challenge(&challenge)?;
    let complete_body = build_auth_complete_body(workload, &client_state, &challenge)?;
    let (success, request2) = send_h3_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &complete_body,
        None,
    )
    .await?;
    let success_bytes = success.body.len() as u64;
    let _ = parse_auth_success(&success)?;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms: start.elapsed().as_secs_f64() * 1000.0,
        request_bytes: request1 + request2,
        response_bytes: challenge_bytes + success_bytes,
        http_phase_timing: None,
    })
}

async fn h1_refresh(
    sender: &mut hyper::client::conn::SendRequest<Body>,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    refresh_token: &str,
) -> Result<(HttpAuthSession, u64, u64)> {
    let body = build_auth_refresh_body(refresh_token);
    let (response, request_bytes) = send_h1_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &body,
        None,
    )
    .await?;
    let response_bytes = response.body.len() as u64;
    Ok((
        parse_auth_success(&response)?,
        request_bytes,
        response_bytes,
    ))
}

async fn h2_refresh(
    sender: H2BenchSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    refresh_token: &str,
) -> Result<(HttpAuthSession, u64, u64)> {
    let body = build_auth_refresh_body(refresh_token);
    let (response, request_bytes) = send_h2_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &body,
        None,
    )
    .await?;
    let response_bytes = response.body.len() as u64;
    Ok((
        parse_auth_success(&response)?,
        request_bytes,
        response_bytes,
    ))
}

async fn h3_refresh(
    sender: H3RequestSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    refresh_token: &str,
) -> Result<(HttpAuthSession, u64, u64)> {
    let body = build_auth_refresh_body(refresh_token);
    let (response, request_bytes) = send_h3_json_request(
        sender,
        endpoint,
        &HyperMethod::POST,
        &workload.auth_path,
        &body,
        None,
    )
    .await?;
    let response_bytes = response.body.len() as u64;
    Ok((
        parse_auth_success(&response)?,
        request_bytes,
        response_bytes,
    ))
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

fn split_request_body_chunks(payload: &Bytes, chunk_len: usize) -> Vec<Bytes> {
    if payload.is_empty() {
        return Vec::new();
    }
    let chunk_len = std::cmp::max(1, chunk_len);
    let mut chunks = Vec::with_capacity((payload.len() + chunk_len - 1) / chunk_len);
    let mut offset = 0usize;
    while offset < payload.len() {
        let end = std::cmp::min(offset + chunk_len, payload.len());
        chunks.push(payload.slice(offset..end));
        offset = end;
    }
    chunks
}

fn build_h1_body(payload: Bytes, chunk_len: usize) -> (Body, tokio::task::JoinHandle<Result<u64>>) {
    if payload.is_empty() {
        return (Body::empty(), tokio::spawn(async { Ok(0) }));
    }
    let chunks = split_request_body_chunks(&payload, chunk_len);
    let total_bytes: u64 = chunks.iter().map(|chunk| chunk.len() as u64).sum();
    let (mut sender, body) = Body::channel();
    let writer = tokio::spawn(async move {
        for chunk in chunks {
            sender
                .send_data(chunk)
                .await
                .context("failed to send HTTP/1.1 request chunk")?;
        }
        Ok(total_bytes)
    });
    (body, writer)
}

fn build_http_request(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Body,
    request_bytes: u64,
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
        "content-length",
        HyperHeaderValue::from_str(&request_bytes.to_string())
            .unwrap_or_else(|_| HyperHeaderValue::from_static("0")),
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
        .body(request_body)
        .context("failed to build HTTP request")
}

fn build_h1_protected_request(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Body,
    request_bytes: u64,
    bearer: &str,
) -> Result<Request<Body>> {
    let mut request_builder = Request::builder()
        .method(workload.method.clone())
        .uri(workload.path.clone());
    let headers = request_builder.headers_mut().unwrap();
    headers.insert(
        "host",
        HyperHeaderValue::from_str(&endpoint_authority(endpoint))
            .context("invalid host header value")?,
    );
    headers.insert(
        "authorization",
        HyperHeaderValue::from_str(&format!("Bearer {bearer}"))
            .context("invalid authorization header")?,
    );
    headers.insert(
        "content-type",
        HyperHeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        "content-length",
        HyperHeaderValue::from_str(&request_bytes.to_string())
            .unwrap_or_else(|_| HyperHeaderValue::from_static("0")),
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
        .body(request_body)
        .context("failed to build protected HTTP/1.1 request")
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

fn apply_http2_transport_tuning(builder: &mut h2_client::Builder) {
    builder
        .max_concurrent_streams(HTTP2_MAX_CONCURRENT_STREAMS)
        .initial_window_size(HTTP2_INITIAL_STREAM_WINDOW)
        .initial_connection_window_size(HTTP2_INITIAL_CONNECTION_WINDOW)
        .max_frame_size(HTTP2_MAX_FRAME_SIZE)
        .max_header_list_size(HTTP2_MAX_HEADER_LIST_SIZE)
        .max_concurrent_reset_streams(HTTP2_MAX_CONCURRENT_RESET_STREAMS)
        .max_send_buffer_size(HTTP2_MAX_SEND_BUFFER_SIZE);
}

async fn connect_h2_sender(endpoint: &HttpEndpoint) -> Result<H2BenchSender> {
    let addr = format!("{}:{}", endpoint.host, endpoint.port);
    let stream = tokio::net::TcpStream::connect(&addr)
        .await
        .with_context(|| format!("failed to connect to {}", addr))?;
    stream.set_nodelay(true)?;
    let mut builder = h2_client::Builder::new();
    apply_http2_transport_tuning(&mut builder);
    let read_tracker = Arc::new(H2ClientReadTracker::default());
    let write_tracker = Arc::new(H2ClientWriteTracker::default());
    if endpoint.scheme == "https" {
        let connector = TlsConnector::from(insecure_rustls_client_config(&[b"h2"]));
        let server_name = ServerName::try_from(endpoint.host.clone())
            .map_err(|_| anyhow!("invalid TLS server name {}", endpoint.host))?;
        let tls_stream = connector
            .connect(server_name, stream)
            .await
            .context("TLS handshake failed")?;
        let instrumented_stream = InstrumentedH2ClientIo {
            inner: tls_stream,
            read_tracker: read_tracker.clone(),
            write_tracker: write_tracker.clone(),
        };
        let (sender, connection) = builder
            .handshake(instrumented_stream)
            .await
            .context("HTTP/2 handshake failed")?;
        tokio::spawn(async move {
            if let Err(err) = connection.await {
                eprintln!("h2 connection error: {err:?}");
            }
        });
        Ok(H2BenchSender {
            sender,
            read_tracker,
            write_tracker,
        })
    } else {
        let instrumented_stream = InstrumentedH2ClientIo {
            inner: stream,
            read_tracker: read_tracker.clone(),
            write_tracker: write_tracker.clone(),
        };
        let (sender, connection) = builder
            .handshake(instrumented_stream)
            .await
            .context("HTTP/2 handshake failed")?;
        tokio::spawn(async move {
            if let Err(err) = connection.await {
                eprintln!("h2 connection error: {err:?}");
            }
        });
        Ok(H2BenchSender {
            sender,
            read_tracker,
            write_tracker,
        })
    }
}

fn build_h2_request(endpoint: &HttpEndpoint, workload: &PreparedWorkload) -> Result<Request<()>> {
    let uri = format!(
        "{}://{}:{}{}",
        endpoint.scheme, endpoint.host, endpoint.port, workload.path
    );
    let mut request_builder = Request::builder()
        .method(workload.method.clone())
        .uri(uri)
        .version(HyperVersion::HTTP_2);
    let headers = request_builder.headers_mut().unwrap();
    headers.insert(
        "content-type",
        HyperHeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        "content-length",
        HyperHeaderValue::from_str(&workload.request_bytes.to_string())
            .unwrap_or_else(|_| HyperHeaderValue::from_static("0")),
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
        .body(())
        .context("failed to build HTTP/2 request")
}

fn build_h2_protected_request(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    bearer: &str,
) -> Result<Request<()>> {
    let uri = format!(
        "{}://{}:{}{}",
        endpoint.scheme, endpoint.host, endpoint.port, workload.path
    );
    let mut request_builder = Request::builder()
        .method(workload.method.clone())
        .uri(uri)
        .version(HyperVersion::HTTP_2);
    let headers = request_builder.headers_mut().unwrap();
    headers.insert(
        "authorization",
        HyperHeaderValue::from_str(&format!("Bearer {bearer}"))
            .context("invalid authorization header")?,
    );
    headers.insert(
        "content-type",
        HyperHeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        "content-length",
        HyperHeaderValue::from_str(&workload.request_bytes.to_string())
            .unwrap_or_else(|_| HyperHeaderValue::from_static("0")),
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
        .body(())
        .context("failed to build protected HTTP/2 request")
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

async fn drain_h2_response(
    response: hyper::http::Response<H2RecvStream>,
    read_probe: H2ClientReadProbe,
    read_tracker: Arc<H2ClientReadTracker>,
) -> Result<H2ResponseDrainStats> {
    let status = response.status();
    let mut body = response.into_body();
    let mut received = 0u64;
    let mut error_body = Vec::new();
    let drain_start = Instant::now();
    let mut first_chunk_wait_ms = None;
    let mut first_chunk_at = None;
    let mut first_chunk_bytes = 0u64;
    let mut chunk_count = 0u32;
    let mut tail_read_probe = None;
    while let Some(chunk) = body.data().await {
        let bytes = chunk?;
        let chunk_len = bytes.len() as u64;
        if first_chunk_wait_ms.is_none() {
            first_chunk_wait_ms = Some(drain_start.elapsed().as_secs_f64() * 1000.0);
            first_chunk_at = Some(Instant::now());
            first_chunk_bytes = chunk_len;
            tail_read_probe = Some(read_tracker.note_phase_started());
        }
        body.flow_control()
            .release_capacity(bytes.len())
            .context("failed to release HTTP/2 flow-control capacity")?;
        chunk_count = chunk_count.saturating_add(1);
        received += chunk_len;
        if !status.is_success() && error_body.len() < 256 {
            let remaining = 256 - error_body.len();
            error_body.extend_from_slice(&bytes[..bytes.len().min(remaining)]);
        }
    }
    if !status.is_success() {
        let preview = String::from_utf8_lossy(&error_body);
        bail!("unexpected HTTP/2 status {} with body {}", status, preview);
    }
    let body_finished_at = Instant::now();
    let connection_read_stats = read_probe.finish(first_chunk_at);
    let tail_connection_read_stats = tail_read_probe
        .as_ref()
        .map(|probe| probe.finish(Some(body_finished_at)));
    Ok(H2ResponseDrainStats {
        received_bytes: received,
        first_chunk_wait_ms: first_chunk_wait_ms
            .unwrap_or_else(|| drain_start.elapsed().as_secs_f64() * 1000.0),
        tail_read_ms: first_chunk_at
            .map(|instant: Instant| {
                body_finished_at
                    .saturating_duration_since(instant)
                    .as_secs_f64()
                    * 1000.0
            })
            .unwrap_or(0.0),
        chunk_count,
        first_chunk_bytes,
        post_header_connection_read_wait_ms: connection_read_stats.connection_read_wait_ms,
        connection_read_to_first_chunk_ms: connection_read_stats.connection_read_to_phase_end_ms,
        tail_connection_read_wait_ms: tail_connection_read_stats
            .and_then(|stats| stats.connection_read_wait_ms),
        tail_connection_read_to_end_ms: tail_connection_read_stats
            .and_then(|stats| stats.connection_read_to_phase_end_ms),
        tail_connection_read_count: tail_connection_read_stats
            .map(|stats| stats.connection_read_count),
        tail_connection_read_span_ms: tail_connection_read_stats
            .and_then(|stats| stats.connection_read_span_ms),
        tail_connection_last_read_to_end_ms: tail_connection_read_stats
            .and_then(|stats| stats.last_connection_read_to_phase_end_ms),
    })
}

async fn send_h1_request(
    sender: &mut hyper::client::conn::SendRequest<Body>,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let (body, body_writer) = build_h1_body(request_body, workload.request_chunk_bytes as usize);
    let request = build_http_request(endpoint, workload, body, workload.request_bytes, false)?;
    let start = Instant::now();
    let response = sender
        .send_request(request)
        .await
        .context("failed to send request")?;
    let sent = body_writer
        .await
        .map_err(|err| anyhow!("HTTP/1.1 body writer failed: {err}"))??;

    let received = drain_hyper_response(response).await?;
    let latency_ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms,
        request_bytes: sent,
        response_bytes: received,
        http_phase_timing: None,
    })
}

async fn send_h1_protected_request(
    sender: &mut hyper::client::conn::SendRequest<Body>,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    bearer: &str,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let (body, body_writer) = build_h1_body(request_body, workload.request_chunk_bytes as usize);
    let request =
        build_h1_protected_request(endpoint, workload, body, workload.request_bytes, bearer)?;
    let start = Instant::now();
    let response = sender
        .send_request(request)
        .await
        .context("failed to send protected HTTP/1.1 request")?;
    let sent = body_writer
        .await
        .map_err(|err| anyhow!("HTTP/1.1 protected body writer failed: {err}"))??;
    let response = drain_hyper_response_bytes(response).await?;
    if !response.status.is_success() {
        let preview = String::from_utf8_lossy(&response.body);
        bail!(
            "unexpected protected HTTP/1.1 status {} with body {}",
            response.status,
            preview
        );
    }
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms: start.elapsed().as_secs_f64() * 1000.0,
        request_bytes: sent,
        response_bytes: response.body.len() as u64,
        http_phase_timing: None,
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
    sender: H2BenchSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let ready_start = Instant::now();
    let read_tracker = sender.read_tracker.clone();
    let write_tracker = sender.write_tracker.clone();
    let mut sender = sender
        .sender
        .ready()
        .await
        .context("HTTP/2 sender not ready for a new stream")?;
    let stream_acquire_wait_ms = ready_start.elapsed().as_secs_f64() * 1000.0;
    let request = build_h2_request(endpoint, workload)?;
    let start = Instant::now();
    let request_enqueue_start = Instant::now();
    let end_stream = request_body.is_empty();
    let (response, mut send_stream) = sender
        .send_request(request, end_stream)
        .context("failed to send request")?;
    if !end_stream {
        let request_chunks =
            split_request_body_chunks(&request_body, workload.request_chunk_bytes as usize);
        let last_index = request_chunks.len().saturating_sub(1);
        for (index, chunk) in request_chunks.into_iter().enumerate() {
            let is_last = index == last_index;
            send_stream
                .send_data(chunk, is_last)
                .context("failed to send HTTP/2 request body")?;
        }
    }
    let request_enqueue_ms = request_enqueue_start.elapsed().as_secs_f64() * 1000.0;

    let response_headers_start = Instant::now();
    let response_headers_read_probe = read_tracker.note_phase_started();
    let response_headers_write_probe = write_tracker.note_phase_started();
    let response = response.await.context("failed to receive response")?;
    let response_headers_wait_ms = response_headers_start.elapsed().as_secs_f64() * 1000.0;
    let response_headers_read_stats = response_headers_read_probe.finish(Some(Instant::now()));
    let response_headers_write_stats = response_headers_write_probe.finish();
    let response_headers_last_write_to_first_read_ms =
        h2_last_write_to_first_read_ms(&response_headers_write_stats, &response_headers_read_stats);
    let read_probe = read_tracker.note_phase_started();
    let response_body_start = Instant::now();
    let response_body = drain_h2_response(response, read_probe, read_tracker).await?;
    let response_body_read_ms = response_body_start.elapsed().as_secs_f64() * 1000.0;
    let latency_ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms,
        request_bytes: workload.request_bytes,
        response_bytes: response_body.received_bytes,
        http_phase_timing: Some(HttpPhaseTimingSample {
            stream_acquire_wait_ms,
            request_enqueue_ms,
            response_headers_wait_ms,
            response_headers_connection_read_wait_ms: response_headers_read_stats
                .connection_read_wait_ms,
            response_headers_connection_read_to_headers_ms: response_headers_read_stats
                .connection_read_to_phase_end_ms,
            response_headers_connection_write_wait_ms: response_headers_write_stats
                .connection_write_wait_ms,
            response_headers_connection_write_span_ms: response_headers_write_stats
                .connection_write_span_ms,
            response_headers_last_write_to_first_read_ms,
            response_body_read_ms,
            response_body_first_chunk_wait_ms: response_body.first_chunk_wait_ms,
            response_body_tail_read_ms: response_body.tail_read_ms,
            response_body_chunk_count: response_body.chunk_count,
            response_body_first_chunk_bytes: response_body.first_chunk_bytes,
            response_body_post_header_connection_read_wait_ms: response_body
                .post_header_connection_read_wait_ms,
            response_body_connection_read_to_first_chunk_ms: response_body
                .connection_read_to_first_chunk_ms,
            response_body_tail_connection_read_wait_ms: response_body.tail_connection_read_wait_ms,
            response_body_tail_connection_read_to_end_ms: response_body
                .tail_connection_read_to_end_ms,
            response_body_tail_connection_read_count: response_body.tail_connection_read_count,
            response_body_tail_connection_read_span_ms: response_body.tail_connection_read_span_ms,
            response_body_tail_connection_last_read_to_end_ms: response_body
                .tail_connection_last_read_to_end_ms,
            request_round_trip_ms: latency_ms,
        }),
    })
}

async fn send_h2_protected_request(
    sender: H2BenchSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    bearer: &str,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let mut sender = sender
        .sender
        .ready()
        .await
        .context("HTTP/2 sender not ready for protected request")?;
    let request = build_h2_protected_request(endpoint, workload, bearer)?;
    let start = Instant::now();
    let end_stream = request_body.is_empty();
    let (response, mut send_stream) = sender
        .send_request(request, end_stream)
        .context("failed to send protected HTTP/2 request")?;
    if !end_stream {
        let request_chunks =
            split_request_body_chunks(&request_body, workload.request_chunk_bytes as usize);
        let last_index = request_chunks.len().saturating_sub(1);
        for (index, chunk) in request_chunks.into_iter().enumerate() {
            let is_last = index == last_index;
            send_stream
                .send_data(chunk, is_last)
                .context("failed to send protected HTTP/2 request body")?;
        }
    }
    let response = drain_h2_response_bytes(
        response
            .await
            .context("failed to receive protected HTTP/2 response")?,
    )
    .await?;
    if !response.status.is_success() {
        let preview = String::from_utf8_lossy(&response.body);
        bail!(
            "unexpected protected HTTP/2 status {} with body {}",
            response.status,
            preview
        );
    }
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms: start.elapsed().as_secs_f64() * 1000.0,
        request_bytes: workload.request_bytes,
        response_bytes: response.body.len() as u64,
        http_phase_timing: None,
    })
}

async fn run_h2_iteration(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_body: Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let sender = connect_h2_sender(endpoint).await?;
    send_h2_request(
        sender,
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
    mut send_request: H3RequestSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_chunk: Bytes,
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
        http3::header::HeaderName::from_static("content-length"),
        http3::header::HeaderValue::from_str(&workload.request_bytes.to_string())
            .unwrap_or_else(|_| http3::header::HeaderValue::from_static("0")),
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
        http_phase_timing: None,
    })
}

async fn send_h3_protected_request(
    mut send_request: H3RequestSender,
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_chunk: Bytes,
    bearer: &str,
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
        .ok_or_else(|| anyhow!("unable to access protected HTTP/3 headers"))?;
    headers.insert(
        http3::header::HeaderName::from_static("authorization"),
        http3::header::HeaderValue::from_str(&format!("Bearer {bearer}"))
            .context("invalid authorization header")?,
    );
    headers.insert(
        http3::header::HeaderName::from_static("content-type"),
        http3::header::HeaderValue::from_static("application/octet-stream"),
    );
    headers.insert(
        http3::header::HeaderName::from_static("content-length"),
        http3::header::HeaderValue::from_str(&workload.request_bytes.to_string())
            .unwrap_or_else(|_| http3::header::HeaderValue::from_static("0")),
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
        .expect("failed to build protected HTTP/3 request");

    let start = Instant::now();
    let mut req_stream = send_request
        .send_request(request)
        .await
        .context("failed to open protected HTTP/3 request stream")?;
    let mut sent = 0u64;
    if workload.request_bytes == 0 {
        req_stream
            .finish()
            .await
            .context("failed to finish protected HTTP/3 request")?;
    } else {
        let mut remaining = workload.request_bytes;
        while remaining > 0 {
            let chunk_len = std::cmp::min(remaining, request_chunk.len() as u64) as usize;
            req_stream
                .send_data(request_chunk.slice(..chunk_len))
                .await
                .context("failed to send protected HTTP/3 request chunk")?;
            remaining -= chunk_len as u64;
            sent += chunk_len as u64;
        }
        req_stream
            .finish()
            .await
            .context("failed to finish protected HTTP/3 request")?;
    }
    let response = req_stream
        .recv_response()
        .await
        .context("failed to receive protected HTTP/3 response headers")?;
    let mut received = Vec::new();
    while let Some(chunk) = req_stream
        .recv_data()
        .await
        .context("failed to read protected HTTP/3 body")?
    {
        let mut chunk = chunk;
        received.extend_from_slice(&chunk.copy_to_bytes(chunk.remaining()));
    }
    if !response.status().is_success() {
        let preview = String::from_utf8_lossy(&received);
        bail!(
            "unexpected protected HTTP/3 status {} with body {}",
            response.status(),
            preview
        );
    }
    Ok(WorkloadSample {
        worker: worker_id,
        iteration,
        latency_ms: start.elapsed().as_secs_f64() * 1000.0,
        request_bytes: sent,
        response_bytes: received.len() as u64,
        http_phase_timing: None,
    })
}

async fn run_h3_iteration(
    endpoint: &HttpEndpoint,
    workload: &PreparedWorkload,
    request_chunk: Bytes,
    worker_id: u32,
    iteration: u32,
) -> Result<WorkloadSample> {
    let (quinn_endpoint, send_request) = connect_h3_sender(endpoint).await?;
    let sample = send_h3_request(
        send_request.clone(),
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
    use std::net::UdpSocket;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };
    use std::time::{SystemTime, UNIX_EPOCH};

    use h3::server;
    use hyper::service::service_fn;
    use hyper::{server::conn::Http as HyperServerHttp, Response};
    use quinn::ServerConfig as QuinnServerConfig;
    use quinn_proto::crypto::rustls::QuicServerConfig as QuinnRustlsServerConfig;
    use rcgen::generate_simple_self_signed;
    use rustls::pki_types::{PrivateKeyDer, PrivatePkcs8KeyDer};
    use rustls::ServerConfig as RustlsServerConfig;
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
            http_phase_timing: None,
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
    fn wait_for_bench_ready_accepts_ready_signal() {
        let (tx, rx) = mpsc::channel();
        tx.send(BenchMainStdoutEvent::Ready).unwrap();
        wait_for_bench_ready(&rx, Duration::from_millis(10)).unwrap();
    }

    #[test]
    fn wait_for_bench_ready_times_out_without_ready() {
        let (_tx, rx) = mpsc::channel::<BenchMainStdoutEvent>();
        let error = wait_for_bench_ready(&rx, Duration::from_millis(5)).unwrap_err();
        assert!(
            error.to_string().contains("did not signal READY"),
            "unexpected error {error}"
        );
    }

    #[test]
    fn h2_client_read_probe_records_connection_read_split() {
        let tracker = H2ClientReadTracker::default();
        let probe = tracker.note_phase_started();
        std::thread::sleep(Duration::from_millis(1));
        tracker.record_connection_read(Instant::now());
        std::thread::sleep(Duration::from_millis(1));
        let stats = probe.finish(Some(Instant::now()));
        assert!(stats.connection_read_wait_ms.is_some());
        assert!(stats.connection_read_to_phase_end_ms.is_some());
    }

    #[test]
    fn h2_client_write_probe_records_connection_write_span() {
        let tracker = H2ClientWriteTracker::default();
        let probe = tracker.note_phase_started();
        std::thread::sleep(Duration::from_millis(1));
        tracker.record_connection_write(Instant::now());
        std::thread::sleep(Duration::from_millis(1));
        tracker.record_connection_write(Instant::now());
        let stats = probe.finish();
        assert!(stats.connection_write_wait_ms.is_some());
        assert!(stats.connection_write_span_ms.is_some());
    }

    #[test]
    fn h2_last_write_to_first_read_gap_uses_last_write_boundary() {
        let read_tracker = H2ClientReadTracker::default();
        let write_tracker = H2ClientWriteTracker::default();
        let read_probe = read_tracker.note_phase_started();
        let write_probe = write_tracker.note_phase_started();
        write_tracker.record_connection_write(Instant::now());
        std::thread::sleep(Duration::from_millis(1));
        write_tracker.record_connection_write(Instant::now());
        std::thread::sleep(Duration::from_millis(1));
        read_tracker.record_connection_read(Instant::now());
        let write_stats = write_probe.finish();
        let read_stats = read_probe.finish(Some(Instant::now()));
        assert!(h2_last_write_to_first_read_ms(&write_stats, &read_stats)
            .is_some_and(|value| value >= 1.0));
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
            client_impl: "n/a".to_string(),
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
            http_connection_usage: None,
            http_phase_timing: None,
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
            HttpEndpoint::from_control_base("https://127.0.0.1:8080/bench", Some(8443)).unwrap();
        assert_eq!(endpoint.scheme, "https");
        assert_eq!(endpoint.host, "127.0.0.1");
        assert_eq!(endpoint.port, 8080);
        assert_eq!(endpoint.http3_port(), 8443);
    }

    #[test]
    fn prepared_workload_defaults_to_connection_reuse() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: default_protocol(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: default_path(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };
        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert!(prepared.reuse_connections);
        assert_eq!(prepared.client_impl, "n/a");
        assert_eq!(prepared.streams_per_connection, 1);
    }

    #[test]
    fn prepared_workload_rejects_invalid_wamp_client_impl() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "wamp_rawsocket_rpc".to_string(),
            client_impl: "fast".to_string(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "bench.rpc.echo".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };

        let error = PreparedWorkload::from_config(&config).err().unwrap();
        assert!(error
            .to_string()
            .contains("unsupported WAMP client implementation"));
    }

    #[test]
    fn parse_wamp_protocol_supports_transport_specific_labels() {
        assert_eq!(
            parse_wamp_protocol("wamp_rawsocket_auth"),
            Some((BenchWampTransport::RawSocket, BenchWampMode::Authenticate))
        );
        assert_eq!(
            parse_wamp_protocol("wamp_rawsocket_pubsub"),
            Some((BenchWampTransport::RawSocket, BenchWampMode::PubSub))
        );
        assert_eq!(
            parse_wamp_protocol("wamp_websocket_auth"),
            Some((BenchWampTransport::WebSocket, BenchWampMode::Authenticate))
        );
        assert_eq!(
            parse_wamp_protocol("wamp_websocket_rpc"),
            Some((BenchWampTransport::WebSocket, BenchWampMode::Rpc))
        );
        assert_eq!(
            parse_wamp_protocol("wamp_pubsub"),
            Some((BenchWampTransport::RawSocket, BenchWampMode::PubSub))
        );
        assert_eq!(
            parse_wamp_protocol("wamp_websocket_publish_ack"),
            Some((BenchWampTransport::WebSocket, BenchWampMode::PublishAck))
        );
        assert_eq!(
            parse_wamp_protocol("wamp_rawsocket_subscribe_cycle"),
            Some((BenchWampTransport::RawSocket, BenchWampMode::SubscribeCycle))
        );
        assert_eq!(
            parse_wamp_protocol("wamp_register_cycle"),
            Some((BenchWampTransport::RawSocket, BenchWampMode::RegisterCycle))
        );
        assert_eq!(
            parse_wamp_protocol("wamp_websocket_cancel_cycle"),
            Some((BenchWampTransport::WebSocket, BenchWampMode::CancelCycle))
        );
        assert_eq!(parse_wamp_protocol("h2"), None);
    }

    #[test]
    fn parse_rawsocket_frame_protocol_supports_auth_frame_labels() {
        assert_eq!(
            parse_rawsocket_frame_protocol("rawsocket_auth_frames"),
            Some(RawSocketFrameProtocol::RemoteAuth)
        );
        assert_eq!(
            parse_rawsocket_frame_protocol("wamp_rawsocket_auth_frames"),
            Some(RawSocketFrameProtocol::RemoteAuth)
        );
        assert_eq!(parse_rawsocket_frame_protocol("wamp_rawsocket_auth"), None);
    }

    #[test]
    fn prepared_workload_defaults_wamp_auth_to_anonymous_control_realm() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "wamp_rawsocket_rpc".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "bench.rpc.echo".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };

        let prepared = PreparedWorkload::from_config(&config).unwrap();

        assert_eq!(prepared.auth_realm, "bench.control");
        assert_eq!(prepared.auth_method, "anonymous");
        assert!(prepared.auth_id.is_empty());
        assert!(prepared.auth_secret.is_empty());
    }

    #[test]
    fn prepared_workload_defaults_rawsocket_auth_frames_to_remote_auth_ticket() {
        let config = WorkloadConfig {
            name: "remote_auth".to_string(),
            protocol: "wamp_rawsocket_auth_frames".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: default_path(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };

        let prepared = PreparedWorkload::from_config(&config).unwrap();

        assert!(prepared.is_rawsocket_auth_frames());
        assert_eq!(prepared.auth_realm, "bench.remote_auth");
        assert_eq!(prepared.auth_method, "ticket");
        assert_eq!(prepared.auth_id, "ticket-user");
        assert_eq!(prepared.auth_secret, "ticket-secret");
    }

    #[test]
    fn prepared_workload_accepts_transport_specific_wamp_protocols() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "wamp_websocket_pubsub".to_string(),
            client_impl: "native".to_string(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "bench.topic".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };
        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert!(prepared.is_wamp());
        assert_eq!(prepared.client_impl, "native");
        assert_eq!(prepared.path, "bench.topic");
    }

    #[test]
    fn prepared_workload_preserves_secure_wamp_transport_flag() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "wamp_websocket_rpc".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "bench.rpc.echo".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: true,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: Some("bench.secure".to_string()),
            auth_method: Some("ticket".to_string()),
            auth_id: Some("bench-user".to_string()),
            auth_secret: Some("bench-ticket".to_string()),
            auth_bearer_token: None,
            frame_case: None,
        };

        let prepared = PreparedWorkload::from_config(&config).unwrap();

        assert!(prepared.secure_transport);
        assert_eq!(prepared.auth_realm, "bench.secure");
        assert_eq!(prepared.auth_method, "ticket");
    }

    #[test]
    fn prepared_workload_preserves_wamp_serializer() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "wamp_rawsocket_rpc".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: "msgpack".to_string(),
            method: default_method(),
            path: "bench.rpc.echo".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };
        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert_eq!(prepared.serializer, "msgpack");
    }

    #[test]
    fn prepared_workload_preserves_wamp_in_flight_setting() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "wamp_websocket_rpc".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "bench.rpc.echo".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: 4,
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };
        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert_eq!(prepared.in_flight_per_session, 4);
    }

    #[test]
    fn prepared_workload_preserves_wamp_peer_count() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "wamp_websocket_pubsub".to_string(),
            client_impl: "native".to_string(),
            serializer: "msgpack".to_string(),
            method: default_method(),
            path: "bench.topic".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: 8,
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };
        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert_eq!(prepared.peer_count, 8);
    }

    #[test]
    fn prepared_workload_rejects_invalid_h2_stream_multiplexing_config() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "h2".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: default_path(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: false,
            streams_per_connection: 2,
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };
        let error = PreparedWorkload::from_config(&config).err().unwrap();
        assert!(error
            .to_string()
            .contains("streams_per_connection > 1 requires reuse_connections = true"));
    }

    #[test]
    fn prepared_workload_rejects_invalid_h3_stream_multiplexing_config() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "h3".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: default_path(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: false,
            streams_per_connection: 2,
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };
        let error = PreparedWorkload::from_config(&config).err().unwrap();
        assert!(error
            .to_string()
            .contains("streams_per_connection > 1 requires reuse_connections = true"));
    }

    #[test]
    fn prepared_workload_rejects_invalid_h1_stream_multiplexing_config() {
        let config = WorkloadConfig {
            name: "load".to_string(),
            protocol: "h1".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: default_path(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: true,
            streams_per_connection: 2,
            auth_flow: None,
            auth_path: None,
            auth_realm: None,
            auth_method: None,
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: None,
            frame_case: None,
        };
        let error = PreparedWorkload::from_config(&config).err().unwrap();
        assert!(error
            .to_string()
            .contains("HTTP/1.1 does not support streams_per_connection > 1"));
    }

    #[test]
    fn build_http1_request_uses_origin_form_and_host_header() {
        let endpoint =
            HttpEndpoint::from_control_base("https://127.0.0.1:8080/bench", Some(8443)).unwrap();
        let workload = PreparedWorkload {
            name: "h1_test".to_string(),
            protocol: "h1".to_string(),
            client_impl: "n/a".to_string(),
            serializer: default_wamp_serializer(),
            method: HyperMethod::POST,
            path: "/bench/stream".to_string(),
            iterations: 1,
            concurrency: 1,
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections: true,
            streams_per_connection: 1,
            auth_flow: None,
            auth_path: "/bench/auth".to_string(),
            auth_realm: "bench.secure".to_string(),
            auth_method: "ticket".to_string(),
            auth_id: "bench-user".to_string(),
            auth_secret: "bench-ticket".to_string(),
            auth_bearer_token: None,
            frame_case: None,
        };
        let request = build_http_request(&endpoint, &workload, Body::empty(), 0, false).unwrap();
        assert_eq!(request.uri().path(), "/bench/stream");
        assert_eq!(request.uri().scheme_str(), None);
        assert_eq!(
            request.headers().get("host").unwrap(),
            &HyperHeaderValue::from_static("127.0.0.1:8080")
        );
    }

    #[test]
    fn prepared_workload_allows_static_bearer_auth_for_protected_routes() {
        let config = WorkloadConfig {
            name: "jwt_protected".to_string(),
            protocol: "h2".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "/bench/secure-jwt".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: Some("protected".to_string()),
            auth_path: None,
            auth_realm: None,
            auth_method: Some("jwt".to_string()),
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: Some("static-bearer".to_string()),
            frame_case: None,
        };

        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert_eq!(prepared.auth_flow, Some(HttpAuthFlow::Protected));
        assert_eq!(prepared.auth_method, "jwt");
        assert_eq!(prepared.auth_bearer_token.as_deref(), Some("static-bearer"));
    }

    #[test]
    fn prepared_workload_allows_oauth_protected_routes_with_static_bearer_token() {
        let config = WorkloadConfig {
            name: "oauth_protected".to_string(),
            protocol: "h3".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "/bench/secure-oauth".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: Some("protected".to_string()),
            auth_path: None,
            auth_realm: None,
            auth_method: Some("oauth".to_string()),
            auth_id: None,
            auth_secret: None,
            auth_bearer_token: Some("bench-oauth-token".to_string()),
            frame_case: None,
        };

        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert_eq!(prepared.auth_flow, Some(HttpAuthFlow::Protected));
        assert_eq!(prepared.auth_method, "oauth");
        assert_eq!(
            prepared.auth_bearer_token.as_deref(),
            Some("bench-oauth-token")
        );
    }

    #[test]
    fn prepared_workload_allows_wampcra_http_auth_bridge_flows() {
        let config = WorkloadConfig {
            name: "wampcra_protected".to_string(),
            protocol: "h2".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "/bench/secure".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: Some("protected".to_string()),
            auth_path: Some("/bench/auth".to_string()),
            auth_realm: Some("bench.secure".to_string()),
            auth_method: Some("wampcra".to_string()),
            auth_id: Some("bench-user".to_string()),
            auth_secret: Some("bench-cra-secret".to_string()),
            auth_bearer_token: None,
            frame_case: None,
        };

        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert_eq!(prepared.auth_flow, Some(HttpAuthFlow::Protected));
        assert_eq!(prepared.auth_method, "wampcra");
        assert_eq!(prepared.auth_secret, "bench-cra-secret");
    }

    #[test]
    fn prepared_workload_allows_scram_http_auth_bridge_flows() {
        let config = WorkloadConfig {
            name: "scram_refresh".to_string(),
            protocol: "h3".to_string(),
            client_impl: default_wamp_client_impl(),
            serializer: default_wamp_serializer(),
            method: default_method(),
            path: "/bench/auth".to_string(),
            iterations: default_iterations(),
            concurrency: default_concurrency(),
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: default_request_bytes(),
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: default_response_bytes(),
            request_chunk_bytes: default_chunk_bytes(),
            response_chunk_bytes: None,
            warmup_ms: None,
            reuse_connections: default_reuse_connections(),
            streams_per_connection: default_streams_per_connection(),
            auth_flow: Some("refresh".to_string()),
            auth_path: Some("/bench/auth".to_string()),
            auth_realm: Some("bench.secure".to_string()),
            auth_method: Some("scram".to_string()),
            auth_id: Some("bench-user".to_string()),
            auth_secret: Some("bench-scram-secret".to_string()),
            auth_bearer_token: None,
            frame_case: None,
        };

        let prepared = PreparedWorkload::from_config(&config).unwrap();
        assert_eq!(prepared.auth_flow, Some(HttpAuthFlow::Refresh));
        assert_eq!(prepared.auth_method, "scram");
        assert_eq!(prepared.auth_secret, "bench-scram-secret");
    }

    #[test]
    fn build_auth_start_body_adds_scram_authextra() {
        let workload = PreparedWorkload {
            name: "scram_login".to_string(),
            protocol: "h1".to_string(),
            client_impl: "n/a".to_string(),
            serializer: default_wamp_serializer(),
            method: HyperMethod::POST,
            path: "/bench/auth".to_string(),
            iterations: 1,
            concurrency: 1,
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections: true,
            streams_per_connection: 1,
            auth_flow: Some(HttpAuthFlow::Login),
            auth_path: "/bench/auth".to_string(),
            auth_realm: "bench.secure".to_string(),
            auth_method: "scram".to_string(),
            auth_id: "bench-user".to_string(),
            auth_secret: "bench-scram-secret".to_string(),
            auth_bearer_token: None,
            frame_case: None,
        };

        let (body, client_state) = build_auth_start_body(&workload).unwrap();
        assert_eq!(body["authmethod"], "scram");
        assert_eq!(body["authid"], "bench-user");
        assert!(body["authextra"]["nonce"].as_str().is_some());
        assert!(matches!(client_state, HttpAuthClientState::Scram { .. }));
    }

    #[test]
    fn build_auth_complete_body_signs_wampcra_challenge() {
        let workload = PreparedWorkload {
            name: "cra_login".to_string(),
            protocol: "h1".to_string(),
            client_impl: "n/a".to_string(),
            serializer: default_wamp_serializer(),
            method: HyperMethod::POST,
            path: "/bench/auth".to_string(),
            iterations: 1,
            concurrency: 1,
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections: true,
            streams_per_connection: 1,
            auth_flow: Some(HttpAuthFlow::Login),
            auth_path: "/bench/auth".to_string(),
            auth_realm: "bench.secure".to_string(),
            auth_method: "wampcra".to_string(),
            auth_id: "bench-user".to_string(),
            auth_secret: "bench-cra-secret".to_string(),
            auth_bearer_token: None,
            frame_case: None,
        };
        let challenge = HttpAuthChallenge {
            state: "auth-state".to_string(),
            challenge: json!({
                "challenge": "{\"authid\":\"bench-user\",\"realm\":\"bench.secure\",\"nonce\":\"fixed\"}",
                "salt": "bench-cra-salt",
                "iterations": 1000,
                "keylen": 32,
            }),
        };

        let body =
            build_auth_complete_body(&workload, &HttpAuthClientState::WampCra, &challenge).unwrap();
        assert_eq!(body["state"], "auth-state");
        assert_eq!(
            body["signature"],
            "yYd61sRkvHj6Heqz4yjRxcb72u68tNQltpLCAiAP7EE="
        );
        assert_eq!(body["extra"], json!({}));
    }

    #[test]
    fn build_auth_complete_body_signs_scram_challenge() {
        let workload = PreparedWorkload {
            name: "scram_login".to_string(),
            protocol: "h1".to_string(),
            client_impl: "n/a".to_string(),
            serializer: default_wamp_serializer(),
            method: HyperMethod::POST,
            path: "/bench/auth".to_string(),
            iterations: 1,
            concurrency: 1,
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections: true,
            streams_per_connection: 1,
            auth_flow: Some(HttpAuthFlow::Login),
            auth_path: "/bench/auth".to_string(),
            auth_realm: "bench.secure".to_string(),
            auth_method: "scram".to_string(),
            auth_id: "bench-user".to_string(),
            auth_secret: "bench-scram-secret".to_string(),
            auth_bearer_token: None,
            frame_case: None,
        };
        let challenge = HttpAuthChallenge {
            state: "auth-state".to_string(),
            challenge: json!({
                "nonce": "YmVuY2gtaHR0cC1zY3JhbS1ub25jZQ==c2VydmVyLW5vbmNl",
                "salt": "CgsMDQ4PEBESExQVFhcYGQ==",
                "iterations": 4096,
                "kdf": "pbkdf2",
            }),
        };

        let body = build_auth_complete_body(
            &workload,
            &HttpAuthClientState::Scram {
                hello_nonce: "YmVuY2gtaHR0cC1zY3JhbS1ub25jZQ==".to_string(),
            },
            &challenge,
        )
        .unwrap();
        assert_eq!(body["state"], "auth-state");
        assert_eq!(
            body["signature"],
            "7RoGYFXvNOdJIrYZ7JO7MwQ5h7SpTgptDpShviU5lWo="
        );
        assert_eq!(
            body["extra"],
            json!({
                "nonce": "YmVuY2gtaHR0cC1zY3JhbS1ub25jZQ==c2VydmVyLW5vbmNl",
                "channel_binding": Value::Null,
                "cbind_data": Value::Null,
            })
        );
    }

    #[test]
    fn split_request_body_chunks_slices_payload_by_chunk_size() {
        let payload = Bytes::from_static(b"abcdefghi");
        let chunks = split_request_body_chunks(&payload, 4);
        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks[0], Bytes::from_static(b"abcd"));
        assert_eq!(chunks[1], Bytes::from_static(b"efgh"));
        assert_eq!(chunks[2], Bytes::from_static(b"i"));
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
        Arc<AtomicUsize>,
        tokio::task::JoinHandle<()>,
    ) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let accept_count = Arc::new(AtomicUsize::new(0));
        let request_count = Arc::new(AtomicUsize::new(0));
        let max_request_chunks = Arc::new(AtomicUsize::new(0));
        let accept_count_for_task = Arc::clone(&accept_count);
        let request_count_for_task = Arc::clone(&request_count);
        let max_request_chunks_for_task = Arc::clone(&max_request_chunks);
        let server = tokio::spawn(async move {
            loop {
                let (stream, _) = match listener.accept().await {
                    Ok(value) => value,
                    Err(_) => break,
                };
                accept_count_for_task.fetch_add(1, Ordering::SeqCst);
                let request_count_for_conn = Arc::clone(&request_count_for_task);
                let max_request_chunks_for_conn = Arc::clone(&max_request_chunks_for_task);
                tokio::spawn(async move {
                    let service = service_fn(move |request: Request<Body>| {
                        let request_count_for_req = Arc::clone(&request_count_for_conn);
                        let max_request_chunks_for_req = Arc::clone(&max_request_chunks_for_conn);
                        async move {
                            let mut body = request.into_body();
                            let mut chunk_count = 0usize;
                            while let Some(chunk) = body.data().await {
                                chunk?;
                                chunk_count += 1;
                            }
                            let _ = max_request_chunks_for_req.fetch_update(
                                Ordering::SeqCst,
                                Ordering::SeqCst,
                                |current| {
                                    if chunk_count > current {
                                        Some(chunk_count)
                                    } else {
                                        None
                                    }
                                },
                            );
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
            max_request_chunks,
            server,
        )
    }

    async fn spawn_h1_test_server() -> (
        HttpEndpoint,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        tokio::task::JoinHandle<()>,
    ) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let accept_count = Arc::new(AtomicUsize::new(0));
        let request_count = Arc::new(AtomicUsize::new(0));
        let max_request_chunks = Arc::new(AtomicUsize::new(0));
        let accept_count_for_task = Arc::clone(&accept_count);
        let request_count_for_task = Arc::clone(&request_count);
        let max_request_chunks_for_task = Arc::clone(&max_request_chunks);
        let server = tokio::spawn(async move {
            loop {
                let (stream, _) = match listener.accept().await {
                    Ok(value) => value,
                    Err(_) => break,
                };
                accept_count_for_task.fetch_add(1, Ordering::SeqCst);
                let request_count_for_conn = Arc::clone(&request_count_for_task);
                let max_request_chunks_for_conn = Arc::clone(&max_request_chunks_for_task);
                tokio::spawn(async move {
                    let service = service_fn(move |request: Request<Body>| {
                        let request_count_for_req = Arc::clone(&request_count_for_conn);
                        let max_request_chunks_for_req = Arc::clone(&max_request_chunks_for_conn);
                        async move {
                            let mut body = request.into_body();
                            let mut chunk_count = 0usize;
                            while let Some(chunk) = body.data().await {
                                chunk?;
                                chunk_count += 1;
                            }
                            let _ = max_request_chunks_for_req.fetch_update(
                                Ordering::SeqCst,
                                Ordering::SeqCst,
                                |current| {
                                    if chunk_count > current {
                                        Some(chunk_count)
                                    } else {
                                        None
                                    }
                                },
                            );
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
            max_request_chunks,
            server,
        )
    }

    async fn spawn_h2_overlap_test_server() -> (
        HttpEndpoint,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        tokio::task::JoinHandle<()>,
    ) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let accept_count = Arc::new(AtomicUsize::new(0));
        let request_count = Arc::new(AtomicUsize::new(0));
        let current_in_flight = Arc::new(AtomicUsize::new(0));
        let max_in_flight = Arc::new(AtomicUsize::new(0));
        let accept_count_for_task = Arc::clone(&accept_count);
        let request_count_for_task = Arc::clone(&request_count);
        let current_in_flight_for_task = Arc::clone(&current_in_flight);
        let max_in_flight_for_task = Arc::clone(&max_in_flight);
        let server = tokio::spawn(async move {
            loop {
                let (stream, _) = match listener.accept().await {
                    Ok(value) => value,
                    Err(_) => break,
                };
                accept_count_for_task.fetch_add(1, Ordering::SeqCst);
                let request_count_for_conn = Arc::clone(&request_count_for_task);
                let current_for_conn = Arc::clone(&current_in_flight_for_task);
                let max_for_conn = Arc::clone(&max_in_flight_for_task);
                tokio::spawn(async move {
                    let service = service_fn(move |request: Request<Body>| {
                        let request_count_for_req = Arc::clone(&request_count_for_conn);
                        let current_for_req = Arc::clone(&current_for_conn);
                        let max_for_req = Arc::clone(&max_for_conn);
                        async move {
                            let in_flight = current_for_req.fetch_add(1, Ordering::SeqCst) + 1;
                            let _ = max_for_req.fetch_update(
                                Ordering::SeqCst,
                                Ordering::SeqCst,
                                |current| {
                                    if in_flight > current {
                                        Some(in_flight)
                                    } else {
                                        None
                                    }
                                },
                            );
                            let mut body = request.into_body();
                            while let Some(chunk) = body.data().await {
                                chunk?;
                            }
                            tokio::time::sleep(Duration::from_millis(50)).await;
                            current_for_req.fetch_sub(1, Ordering::SeqCst);
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
            max_in_flight,
            server,
        )
    }

    async fn spawn_h3_overlap_test_server() -> (
        HttpEndpoint,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        Arc<AtomicUsize>,
        tokio::task::JoinHandle<()>,
    ) {
        let certified = generate_simple_self_signed(vec!["localhost".to_string()]).unwrap();
        let mut server_crypto = RustlsServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(
                vec![certified.cert.der().clone()],
                PrivateKeyDer::from(PrivatePkcs8KeyDer::from(certified.key_pair.serialize_der())),
            )
            .unwrap();
        server_crypto.alpn_protocols = vec![b"h3".to_vec()];
        let mut server_config = QuinnServerConfig::with_crypto(Arc::new(
            QuinnRustlsServerConfig::try_from(server_crypto).unwrap(),
        ));
        let transport = Arc::get_mut(&mut server_config.transport).unwrap();
        apply_http3_transport_tuning(transport);

        let bind_socket = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let server_addr = bind_socket.local_addr().unwrap();
        let server_endpoint = quinn::Endpoint::new(
            quinn::EndpointConfig::default(),
            Some(server_config),
            bind_socket,
            Arc::new(quinn::TokioRuntime),
        )
        .unwrap();

        let accept_count = Arc::new(AtomicUsize::new(0));
        let request_count = Arc::new(AtomicUsize::new(0));
        let current_in_flight = Arc::new(AtomicUsize::new(0));
        let max_in_flight = Arc::new(AtomicUsize::new(0));
        let accept_count_for_task = Arc::clone(&accept_count);
        let request_count_for_task = Arc::clone(&request_count);
        let current_in_flight_for_task = Arc::clone(&current_in_flight);
        let max_in_flight_for_task = Arc::clone(&max_in_flight);

        let server = tokio::spawn(async move {
            while let Some(connecting) = server_endpoint.accept().await {
                accept_count_for_task.fetch_add(1, Ordering::SeqCst);
                let request_count_for_conn = Arc::clone(&request_count_for_task);
                let current_for_conn = Arc::clone(&current_in_flight_for_task);
                let max_for_conn = Arc::clone(&max_in_flight_for_task);
                tokio::spawn(async move {
                    let connection = match connecting.await {
                        Ok(connection) => connection,
                        Err(_) => return,
                    };
                    let mut incoming = match server::builder()
                        .build(H3QuinnConnection::new(connection))
                        .await
                    {
                        Ok(connection) => connection,
                        Err(_) => return,
                    };
                    loop {
                        let resolver = match incoming.accept().await {
                            Ok(Some(resolver)) => resolver,
                            Ok(None) | Err(_) => break,
                        };
                        let request_count_for_req = Arc::clone(&request_count_for_conn);
                        let current_for_req = Arc::clone(&current_for_conn);
                        let max_for_req = Arc::clone(&max_for_conn);
                        tokio::spawn(async move {
                            let (_, mut stream) = match resolver.resolve_request().await {
                                Ok(value) => value,
                                Err(_) => return,
                            };
                            let in_flight = current_for_req.fetch_add(1, Ordering::SeqCst) + 1;
                            let _ = max_for_req.fetch_update(
                                Ordering::SeqCst,
                                Ordering::SeqCst,
                                |current| {
                                    if in_flight > current {
                                        Some(in_flight)
                                    } else {
                                        None
                                    }
                                },
                            );
                            while let Ok(Some(_)) = stream.recv_data().await {}
                            tokio::time::sleep(Duration::from_millis(50)).await;
                            current_for_req.fetch_sub(1, Ordering::SeqCst);
                            request_count_for_req.fetch_add(1, Ordering::SeqCst);
                            let response = http3::Response::builder()
                                .status(http3::StatusCode::OK)
                                .body(())
                                .unwrap();
                            if stream.send_response(response).await.is_err() {
                                return;
                            }
                            if stream.send_data(Bytes::from_static(b"ok")).await.is_err() {
                                return;
                            }
                            let _ = stream.finish().await;
                        });
                    }
                });
            }
        });

        (
            HttpEndpoint {
                scheme: "https".to_string(),
                host: "localhost".to_string(),
                port: server_addr.port(),
                http3_port: Some(server_addr.port()),
            },
            accept_count,
            request_count,
            max_in_flight,
            server,
        )
    }

    fn sample_rawsocket_auth_frame_workload(case: &str) -> PreparedWorkload {
        PreparedWorkload {
            name: "rawsocket_auth_frame_test".to_string(),
            protocol: "wamp_rawsocket_auth_frames".to_string(),
            client_impl: "n/a".to_string(),
            serializer: "json".to_string(),
            method: HyperMethod::POST,
            path: default_path(),
            iterations: 1,
            concurrency: 1,
            in_flight_per_session: 1,
            peer_count: 1,
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections: true,
            streams_per_connection: 1,
            auth_flow: None,
            auth_path: "/bench/auth".to_string(),
            auth_realm: "bench.remote_auth".to_string(),
            auth_method: "ticket".to_string(),
            auth_id: "ticket-user".to_string(),
            auth_secret: "ticket-secret".to_string(),
            auth_bearer_token: None,
            frame_case: Some(case.to_string()),
        }
    }

    #[tokio::test]
    async fn rawsocket_auth_frame_iteration_completes_success_flow() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = RawSocketEndpoint {
            host: "127.0.0.1".to_string(),
            port: listener.local_addr().unwrap().port(),
        };
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut handshake = [0u8; 4];
            socket.read_exact(&mut handshake).await.unwrap();
            assert_eq!(handshake, [0x7F, ((18u8 - 9) << 4) | 0x01, 0, 0]);
            socket.write_all(&handshake).await.unwrap();

            let hello = read_rawsocket_message(&mut socket).await.unwrap();
            let hello_message = parse_json_message(&hello).unwrap();
            assert_eq!(hello_message[0].as_u64(), Some(1));
            assert_eq!(hello_message[1].as_str(), Some("bench.remote_auth"));

            let challenge = serde_json::to_vec(&json!([4, "ticket", {}])).unwrap();
            write_rawsocket_message(&mut socket, &challenge)
                .await
                .unwrap();

            let authenticate = read_rawsocket_message(&mut socket).await.unwrap();
            let authenticate_message = parse_json_message(&authenticate).unwrap();
            assert_eq!(authenticate_message[0].as_u64(), Some(5));
            assert_eq!(authenticate_message[1].as_str(), Some("ticket-secret"));

            let welcome = serde_json::to_vec(&json!([
                2,
                123,
                {
                    "realm": "bench.remote_auth",
                    "authid": "ticket-user",
                    "authrole": "member",
                    "authmethod": "ticket",
                    "authprovider": "bench-remote-auth-server"
                }
            ]))
            .unwrap();
            write_rawsocket_message(&mut socket, &welcome)
                .await
                .unwrap();
        });

        let sample = run_rawsocket_auth_frame_iteration(
            &endpoint,
            &sample_rawsocket_auth_frame_workload("success"),
            RawSocketAuthFrameCase::Success,
            0,
            0,
        )
        .await
        .unwrap();

        assert!(sample.request_bytes > 0);
        assert!(sample.response_bytes > 0);
        server.await.unwrap();
    }

    fn sample_h1_workload(reuse_connections: bool) -> PreparedWorkload {
        PreparedWorkload {
            name: "h1_test".to_string(),
            protocol: "h1".to_string(),
            client_impl: "n/a".to_string(),
            serializer: default_wamp_serializer(),
            method: HyperMethod::POST,
            path: "/bench/stream".to_string(),
            iterations: 3,
            concurrency: 1,
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections,
            streams_per_connection: 1,
            auth_flow: None,
            auth_path: "/bench/auth".to_string(),
            auth_realm: "bench.secure".to_string(),
            auth_method: "ticket".to_string(),
            auth_id: "bench-user".to_string(),
            auth_secret: "bench-ticket".to_string(),
            auth_bearer_token: None,
            frame_case: None,
        }
    }

    fn sample_h2_workload(
        reuse_connections: bool,
        streams_per_connection: u32,
    ) -> PreparedWorkload {
        PreparedWorkload {
            name: "h2_test".to_string(),
            protocol: "h2".to_string(),
            client_impl: "n/a".to_string(),
            serializer: default_wamp_serializer(),
            method: HyperMethod::POST,
            path: "/bench/stream".to_string(),
            iterations: 3,
            concurrency: 1,
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections,
            streams_per_connection,
            auth_flow: None,
            auth_path: "/bench/auth".to_string(),
            auth_realm: "bench.secure".to_string(),
            auth_method: "ticket".to_string(),
            auth_id: "bench-user".to_string(),
            auth_secret: "bench-ticket".to_string(),
            auth_bearer_token: None,
            frame_case: None,
        }
    }

    fn sample_h3_workload(
        reuse_connections: bool,
        streams_per_connection: u32,
    ) -> PreparedWorkload {
        PreparedWorkload {
            name: "h3_test".to_string(),
            protocol: "h3".to_string(),
            client_impl: "n/a".to_string(),
            serializer: default_wamp_serializer(),
            method: HyperMethod::POST,
            path: "/bench/stream".to_string(),
            iterations: 3,
            concurrency: 1,
            in_flight_per_session: default_in_flight_per_session(),
            peer_count: default_peer_count(),
            request_bytes: 0,
            websocket_fragment_size: None,
            ppt_scheme: None,
            ppt_serializer: None,
            secure_transport: false,
            response_bytes: 0,
            request_chunk_bytes: 1024,
            response_chunk_bytes: 1024,
            reuse_connections,
            streams_per_connection,
            auth_flow: None,
            auth_path: "/bench/auth".to_string(),
            auth_realm: "bench.secure".to_string(),
            auth_method: "ticket".to_string(),
            auth_id: "bench-user".to_string(),
            auth_secret: "bench-ticket".to_string(),
            auth_bearer_token: None,
            frame_case: None,
        }
    }

    #[tokio::test]
    async fn h1_worker_reuses_single_connection_when_enabled() {
        let (endpoint, accept_count, request_count, _, server) = spawn_h1_test_server().await;
        let execution = run_h1_worker(endpoint, sample_h1_workload(true), 0)
            .await
            .unwrap();
        assert_eq!(execution.samples.len(), 3);
        assert_eq!(execution.connections_opened, 1);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 1);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        server.abort();
    }

    #[tokio::test]
    async fn h1_worker_reconnects_per_iteration_when_disabled() {
        let (endpoint, accept_count, request_count, _, server) = spawn_h1_test_server().await;
        let execution = run_h1_worker(endpoint, sample_h1_workload(false), 0)
            .await
            .unwrap();
        assert_eq!(execution.samples.len(), 3);
        assert_eq!(execution.connections_opened, 3);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 3);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        server.abort();
    }

    #[tokio::test]
    async fn build_h1_body_streams_request_chunks() {
        let (body, writer) = build_h1_body(Bytes::from_static(b"abcdef"), 2);
        let mut body = body;
        let mut chunks = Vec::new();
        while let Some(chunk) = body.data().await {
            chunks.push(chunk.unwrap());
        }
        let sent = writer.await.unwrap().unwrap();
        assert_eq!(sent, 6);
        assert_eq!(
            chunks,
            vec![
                Bytes::from_static(b"ab"),
                Bytes::from_static(b"cd"),
                Bytes::from_static(b"ef"),
            ]
        );
    }

    #[tokio::test]
    async fn h2_worker_reuses_single_connection_when_enabled() {
        let (endpoint, accept_count, request_count, _, server) = spawn_h2_test_server().await;
        let execution = run_h2_worker(endpoint, sample_h2_workload(true, 1), 0)
            .await
            .unwrap();
        assert_eq!(execution.samples.len(), 3);
        assert_eq!(execution.connections_opened, 1);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 1);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        server.abort();
    }

    #[tokio::test]
    async fn h2_worker_reconnects_per_iteration_when_disabled() {
        let (endpoint, accept_count, request_count, _, server) = spawn_h2_test_server().await;
        let execution = run_h2_worker(endpoint, sample_h2_workload(false, 1), 0)
            .await
            .unwrap();
        assert_eq!(execution.samples.len(), 3);
        assert_eq!(execution.connections_opened, 3);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 3);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        server.abort();
    }

    #[tokio::test]
    async fn h2_worker_honors_request_chunk_size() {
        let (endpoint, _, request_count, max_request_chunks, server) = spawn_h2_test_server().await;
        let mut workload = sample_h2_workload(true, 1);
        workload.iterations = 1;
        workload.request_bytes = 4096;
        workload.request_chunk_bytes = 1024;
        let execution = run_h2_worker(endpoint, workload, 0).await.unwrap();
        assert_eq!(execution.samples.len(), 1);
        assert_eq!(execution.connections_opened, 1);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(request_count.load(Ordering::SeqCst), 1);
        assert!(max_request_chunks.load(Ordering::SeqCst) > 1);
        server.abort();
    }

    #[tokio::test]
    async fn h2_worker_multiplexes_streams_on_single_connection() {
        let (endpoint, accept_count, request_count, max_in_flight, server) =
            spawn_h2_overlap_test_server().await;
        let execution = run_h2_worker(endpoint, sample_h2_workload(true, 3), 0)
            .await
            .unwrap();
        assert_eq!(execution.samples.len(), 3);
        assert_eq!(execution.connections_opened, 1);
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 1);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        assert!(max_in_flight.load(Ordering::SeqCst) > 1);
        server.abort();
    }

    #[tokio::test]
    async fn h3_worker_multiplexes_streams_on_single_connection() {
        let _ = ring::default_provider().install_default();
        let (endpoint, accept_count, request_count, max_in_flight, server) =
            spawn_h3_overlap_test_server().await;
        let execution = run_h3_worker(endpoint, sample_h3_workload(true, 3), 0)
            .await
            .unwrap();
        assert_eq!(execution.samples.len(), 3);
        assert_eq!(execution.connections_opened, 1);
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert_eq!(accept_count.load(Ordering::SeqCst), 1);
        assert_eq!(request_count.load(Ordering::SeqCst), 3);
        assert!(max_in_flight.load(Ordering::SeqCst) > 1);
        server.abort();
    }

    #[test]
    fn bench_http_client_builds_https_client() {
        let client = BenchHttpClient::new("https://127.0.0.1:8080/bench").unwrap();
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

    #[test]
    fn quinn_client_config_applies_transport_tuning() {
        let _ = ring::default_provider().install_default();
        let config = quinn_client_config();
        let debug = format!("{config:?}");
        assert!(debug.contains("max_concurrent_bidi_streams: 1024"));
        assert!(debug.contains("max_concurrent_uni_streams: 256"));
        assert!(debug.contains("stream_receive_window: 8388608"));
        assert!(debug.contains("receive_window: 67108864"));
        assert!(debug.contains("send_window: 67108864"));
        assert!(debug.contains("keep_alive_interval: Some(5s)"));
        assert!(debug.contains("datagram_receive_buffer_size: Some(8388608)"));
        assert!(debug.contains("datagram_send_buffer_size: 8388608"));
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
    apply_http3_transport_tuning(&mut transport);
    quinn_config.transport_config(Arc::new(transport));
    quinn_config
}

fn apply_http3_transport_tuning(transport: &mut TransportConfig) {
    transport
        .max_concurrent_bidi_streams(HTTP3_MAX_BIDI_STREAMS.into())
        .max_concurrent_uni_streams(HTTP3_MAX_UNI_STREAMS.into())
        .stream_receive_window(HTTP3_STREAM_RECEIVE_WINDOW.into())
        .receive_window(HTTP3_CONNECTION_RECEIVE_WINDOW.into())
        .send_window(HTTP3_SEND_WINDOW)
        .datagram_receive_buffer_size(Some(HTTP3_DATAGRAM_BUFFER_BYTES))
        .datagram_send_buffer_size(HTTP3_DATAGRAM_BUFFER_BYTES)
        .keep_alive_interval(Some(HTTP3_KEEP_ALIVE_INTERVAL));
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
        // Keep benchmark control traffic off HTTP/2 so control-plane TLS
        // shutdown noise cannot pollute workload transport-alert deltas.
        .http1_only()
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
