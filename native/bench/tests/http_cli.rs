use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Arc, Mutex,
};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

struct ScratchDirectory(PathBuf);

impl Drop for ScratchDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

struct Peer {
    root: PathBuf,
    address: String,
    stop: Arc<AtomicBool>,
    requests: Arc<Mutex<Vec<(String, Vec<u8>)>>>,
    server: Option<thread::JoinHandle<()>>,
    worker: PathBuf,
    _directory: ScratchDirectory,
}

impl Peer {
    fn new(mode: &str) -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "connectanum-http-cli-{}-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&root).unwrap();
        let directory = ScratchDirectory(root.clone());
        let worker = root.join(format!("stdio-peer{}", std::env::consts::EXE_SUFFIX));
        let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/bench_peer.rs");
        let compiled = Command::new("rustc")
            .arg("--edition=2021")
            .arg(source)
            .arg("-o")
            .arg(&worker)
            .output()
            .unwrap();
        assert!(compiled.status.success(), "{compiled:?}");
        fs::write(
            root.join("router.json"),
            r#"{"router":{"worker_pool":{"min_workers":1}}}"#,
        )
        .unwrap();
        fs::write(
            root.join("scenario.toml"),
            r#"
name = "cli-proof"
description = "Controlled HTTP CLI boundary"
[[workloads]]
name = "transfer"
protocol = "h1"
iterations = 2
concurrency = 1
request_bytes = 8
response_bytes = 16
request_chunk_bytes = 4
response_chunk_bytes = 8
reuse_connections = false
warmup_ms = 0
"#,
        )
        .unwrap();
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        listener.set_nonblocking(true).unwrap();
        let address = format!("http://{}/bench", listener.local_addr().unwrap());
        let stop = Arc::new(AtomicBool::new(false));
        let requests = Arc::new(Mutex::new(Vec::new()));
        let stopping = stop.clone();
        let recorded = requests.clone();
        let stop_path = root.join("stop");
        let mode = mode.to_string();
        let server = thread::spawn(move || {
            while !stopping.load(Ordering::SeqCst) {
                match listener.accept() {
                    Ok((stream, _)) => serve(stream, &mode, &recorded, &stop_path),
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(2));
                    }
                    Err(error) => panic!("accept failed: {error}"),
                }
            }
        });
        Self {
            root,
            address,
            stop,
            requests,
            server: Some(server),
            worker,
            _directory: directory,
        }
    }

    fn command(&self, mode: &str) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_http_stream"));
        command
            .current_dir(&self.root)
            .arg("--dart")
            .arg(&self.worker)
            .arg("--bench-main")
            .arg("controlled-peer")
            .arg("--skip-wamp-worker-aot")
            .arg("--native-lib")
            .arg("fixture-native-library")
            .arg("--router-config")
            .arg(self.root.join("router.json"))
            .arg("--scenario")
            .arg(self.root.join("scenario.toml"))
            .arg("--results")
            .arg(self.root.join("results.jsonl"))
            .arg("--artifact-dir")
            .arg(self.root.join("artifacts"))
            .arg("--control-base")
            .arg(&self.address)
            .arg("--workload-timeout-ms")
            .arg("2000")
            .env("BENCH_CLI_TEST_ROOT", &self.root)
            .env("BENCH_CLI_TEST_MODE", mode)
            .env("CONNECTANUM_NATIVE_RUNTIME_THREADS", "99");
        command
    }

    fn run(&self, mut command: Command) -> Output {
        let stdout = self.root.join("stdout");
        let stderr = self.root.join("stderr");
        let mut child = command
            .stdout(Stdio::from(fs::File::create(&stdout).unwrap()))
            .stderr(Stdio::from(fs::File::create(&stderr).unwrap()))
            .spawn()
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(30);
        loop {
            if let Some(status) = child.try_wait().unwrap() {
                return Output {
                    status,
                    stdout: fs::read(&stdout).unwrap(),
                    stderr: fs::read(&stderr).unwrap(),
                };
            }
            if Instant::now() >= deadline {
                fs::write(self.root.join("stop"), "stop fixture").unwrap();
                let _ = child.kill();
                let _ = child.wait();
                panic!(
                    "CLI exceeded test deadline: {}",
                    fs::read_to_string(stderr).unwrap()
                );
            }
            thread::sleep(Duration::from_millis(5));
        }
    }

    fn reports(&self) -> Vec<Value> {
        fs::read_to_string(self.root.join("results.jsonl"))
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect()
    }

    fn stopped(&self, expected: &str) {
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            if let Ok(reason) = fs::read_to_string(self.root.join("child-stopped")) {
                assert_eq!(reason, expected);
                return;
            }
            assert!(Instant::now() < deadline, "worker did not stop");
            thread::sleep(Duration::from_millis(5));
        }
    }
}

impl Drop for Peer {
    fn drop(&mut self) {
        let _ = fs::write(self.root.join("stop"), "stop fixture");
        self.stop.store(true, Ordering::SeqCst);
        if let Some(server) = self.server.take() {
            let _ = server.join();
        }
    }
}

fn serve(stream: TcpStream, mode: &str, recorded: &Mutex<Vec<(String, Vec<u8>)>>, stop: &Path) {
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    let mut reader = BufReader::new(stream);
    let mut first = String::new();
    reader.read_line(&mut first).unwrap();
    let path = first.split_whitespace().nth(1).unwrap().to_string();
    let mut length = 0;
    loop {
        let mut line = String::new();
        assert!(
            reader.read_line(&mut line).unwrap() > 0,
            "truncated request headers"
        );
        if line == "\r\n" {
            break;
        }
        if let Some((key, value)) = line.split_once(':') {
            if key.eq_ignore_ascii_case("content-length") {
                length = value.trim().parse().unwrap();
            }
        }
    }
    assert!(length <= 1024, "unexpected oversized fixture request");
    let mut body = vec![0; length];
    reader.read_exact(&mut body).unwrap();
    {
        let mut requests = recorded.lock().unwrap();
        assert!(requests.len() < 64, "unexpected fixture retry loop");
        requests.push((path.clone(), body));
    }
    let (status, response) = match path.as_str() {
        "/bench/healthz" => (200, br#"{"status":"ok"}"#.to_vec()),
        "/bench/metrics" if mode == "metrics-error" => (500, b"metrics unavailable".to_vec()),
        "/bench/metrics" => (
            200,
            br##"{"metrics":{"transport":{}},"open_metrics":"# fixture\n"}"##.to_vec(),
        ),
        "/bench/stream" if mode == "stream-error" => (500, b"failed".to_vec()),
        "/bench/stream" => (200, vec![7; 16]),
        "/bench/stop" if mode == "stop-error" => (500, b"use stdin".to_vec()),
        "/bench/stop" => {
            fs::write(stop, "stop fixture").unwrap();
            (200, b"{}".to_vec())
        }
        _ => panic!("unexpected request: {first}"),
    };
    let stream = reader.get_mut();
    let mut wire = format!("HTTP/1.1 {status} Fixture\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", response.len()).into_bytes();
    wire.extend_from_slice(&response);
    stream.write_all(&wire).unwrap();
    stream.flush().unwrap();
}

fn success(output: &Output) {
    assert!(
        output.status.success(),
        "stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn cli_sweeps_workers_and_runtime_threads_with_real_http_samples() {
    let peer = Peer::new("normal");
    let mut command = peer.command("normal");
    command
        .arg("--router-worker-counts")
        .arg("1,2")
        .arg("--native-runtime-thread-counts")
        .arg("auto,2");
    let output = peer.run(command);
    success(&output);
    peer.stopped("HTTP");
    let reports = peer.reports();
    assert_eq!(reports.len(), 4);
    for (report, (workers, threads)) in reports.iter().zip([(1, 0), (2, 0), (1, 2), (2, 2)]) {
        assert_eq!(report["router_workers"], workers);
        assert_eq!(report["native_runtime_threads"], threads);
        assert_eq!(report["scenario"], "cli-proof");
        assert_eq!(report["protocol"], "h1");
        let samples = report["samples"].as_array().unwrap();
        assert_eq!(samples.len(), 2);
        for sample in samples {
            assert_eq!(sample["request_bytes"], 8);
            assert_eq!(sample["response_bytes"], 16);
            assert!(sample["latency_ms"].as_f64().unwrap() >= 0.0);
        }
        assert_eq!(report["open_metrics_after"], "# fixture\n");
    }
    let requests = peer.requests.lock().unwrap();
    for (path, expected) in [
        ("/bench/healthz", 4),
        ("/bench/metrics", 12),
        ("/bench/stream", 8),
        ("/bench/stop", 4),
    ] {
        assert_eq!(
            requests.iter().filter(|(p, _)| p == path).count(),
            expected,
            "{path}"
        );
    }
    for (_, body) in requests.iter().filter(|(p, _)| p == "/bench/stream") {
        assert_eq!(body.len(), 8);
    }
    let summary: Value = serde_json::from_slice(
        &fs::read(peer.root.join("artifacts/results.summary.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(summary["workloads"].as_array().unwrap().len(), 4);
    let args = fs::read_to_string(peer.root.join("child-arguments")).unwrap();
    assert!(args.contains("library=fixture-native-library\nthreads=2\n"));
    assert!(args.contains("arg=run\narg=controlled-peer\n"));
    let mut arguments = args.lines();
    arguments
        .find(|line| *line == "arg=--router-config")
        .unwrap();
    let generated_config = arguments.next().unwrap().strip_prefix("arg=").unwrap();
    assert!(
        !Path::new(generated_config).exists(),
        "worker override config was not removed"
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("Bench run completed successfully"));
    assert!(stdout.contains("router worker count 2"));
    assert!(peer.root.join("artifacts/results.prom").is_file());
}

#[test]
fn metrics_failure_is_visible_but_does_not_invent_measurements() {
    let peer = Peer::new("metrics-error");
    let mut command = peer.command("normal");
    command.arg("--native-runtime-thread-counts").arg("auto");
    let output = peer.run(command);
    success(&output);
    assert!(String::from_utf8_lossy(&output.stderr).contains("Warning: failed to fetch metrics"));
    let reports = peer.reports();
    assert_eq!(reports.len(), 1);
    assert_eq!(reports[0]["metrics_before"], json!({}));
    assert_eq!(reports[0]["metrics_after"], json!({}));
    assert!(reports[0]["open_metrics_after"].is_null());
    assert_eq!(reports[0]["samples"].as_array().unwrap().len(), 2);
    assert!(fs::read_to_string(peer.root.join("child-arguments"))
        .unwrap()
        .contains("threads=auto\n"));
    peer.stopped("HTTP");
}

#[test]
fn failed_stop_endpoint_falls_back_to_stdin_and_waits_for_worker_exit() {
    let peer = Peer::new("stop-error");
    let mut command = peer.command("normal");
    command.arg("--skip-metrics");
    let output = peer.run(command);
    success(&output);
    peer.stopped("STOP");
    assert!(String::from_utf8_lossy(&output.stderr).contains("Falling back to stdin STOP"));
    assert_eq!(peer.reports().len(), 1);
    assert!(!peer
        .requests
        .lock()
        .unwrap()
        .iter()
        .any(|(path, _)| path == "/bench/metrics"));
}

#[test]
fn workload_failure_stops_worker_without_success_report_or_partial_sample() {
    let peer = Peer::new("stream-error");
    let output = peer.run(peer.command("normal"));
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("workload \"transfer\" failed"));
    assert!(!String::from_utf8_lossy(&output.stdout).contains("Bench run completed successfully"));
    peer.stopped("HTTP");
    assert!(peer.reports().is_empty());
    assert!(!peer.root.join("artifacts/results.summary.json").exists());
}

#[test]
fn worker_eof_and_readiness_timeout_do_not_start_workloads() {
    for mode in ["eof", "timeout"] {
        let peer = Peer::new("normal");
        let output = peer.run(peer.command(mode));
        assert_eq!(output.status.code(), Some(1));
        let message = if mode == "eof" {
            "exited before signaling READY"
        } else {
            "did not signal READY"
        };
        assert!(String::from_utf8_lossy(&output.stderr).contains(message));
        assert!(peer.requests.lock().unwrap().is_empty());
        assert!(peer.reports().is_empty());
        if mode == "timeout" {
            peer.stopped("EOF");
        }
    }
}

#[test]
fn invalid_worker_counts_fail_before_launching_a_child_or_creating_results() {
    let peer = Peer::new("normal");
    let mut command = peer.command("normal");
    command.arg("--router-worker-counts").arg("0");
    let output = peer.run(command);
    assert_eq!(output.status.code(), Some(1));
    assert!(!peer.root.join("child-arguments").exists());
    assert!(!peer.root.join("results.jsonl").exists());
    assert!(peer.requests.lock().unwrap().is_empty());
}
