use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

struct Fixture(PathBuf);

impl Fixture {
    fn new() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "connectanum-artifact-cli-{}-{stamp}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn path(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }

    fn write(&self, name: &str, text: &str) -> PathBuf {
        let path = self.path(name);
        fs::write(&path, text).unwrap();
        path
    }

    fn reports(&self, name: &str, threads: u32, alerts: u32) -> PathBuf {
        let report = json!({
            "scenario": "cli-proof", "workload": "upload", "protocol": "h2",
            "client_impl": "rust", "router_workers": 2,
            "native_runtime_threads": threads,
            "iterations": 2, "concurrency": 1,
            "started_at_ms": 1000, "completed_at_ms": 2000,
            "data_window_elapsed_ms": 500,
            "metrics_before": {"metrics": {"transport": {"protocol_error_alerts": 7}}},
            "metrics_after": {"metrics": {"transport": {"protocol_error_alerts": 7 + alerts}}},
            "samples": [
                {"worker": 0, "iteration": 0, "latency_ms": 10,
                 "request_bytes": 500000, "response_bytes": 64},
                {"worker": 0, "iteration": 1, "latency_ms": 30,
                 "request_bytes": 500000, "response_bytes": 64}
            ]
        });
        self.write(name, &format!("\n{report}\n\n"))
    }

    fn summary(&self, threads: u32, alerts: u32) -> PathBuf {
        let input = self.reports("run.jsonl", threads, alerts);
        let output = transform(&input, None);
        assert_success(&output);
        self.path("run.summary.json")
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn transform(input: &Path, directory: Option<&Path>) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_transform_results"));
    command.arg("--input").arg(input);
    if let Some(directory) = directory {
        command.arg("--output-dir").arg(directory);
    }
    command.output().unwrap()
}

fn gate(summary: &Path) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_check_artifact_gate"));
    command.arg("--summary").arg(summary);
    command
}

fn assert_success(output: &Output) {
    assert!(
        output.status.success(),
        "stdout: {}\nstderr: {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn assert_failure(output: &Output, message: &str) {
    assert_eq!(output.status.code(), Some(1), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stderr).contains(message),
        "{output:?}"
    );
}

fn read_json(path: &Path) -> Value {
    serde_json::from_slice(&fs::read(path).unwrap()).unwrap()
}

#[test]
fn transform_preserves_independent_sample_accounting_and_prometheus_output() {
    let fixture = Fixture::new();
    let input = fixture.reports("measurements.jsonl", 4, 0);
    let directory = fixture.path("nested/artifacts");
    let output = transform(&input, Some(&directory));
    assert_success(&output);
    let bundle = read_json(&directory.join("measurements.summary.json"));
    assert_eq!(bundle["source_results"], input.to_string_lossy().as_ref());
    assert_eq!(bundle["workloads"].as_array().unwrap().len(), 1);
    let result = &bundle["workloads"][0];
    assert_eq!(result["scenario"], "cli-proof");
    assert_eq!(result["native_runtime_threads"], 4);
    assert_eq!(result["sample_count"], 2);
    assert_eq!(result["request_bytes_total"], 1000000);
    assert_eq!(result["response_bytes_total"], 128);
    assert_eq!(result["throughput_mbps"], 16.0);
    assert_eq!(result["lifecycle_throughput_mbps"], 8.0);
    assert_eq!(result["latency_avg_ms"], 20.0);
    assert_eq!(result["latency_p95_ms"], 30.0);
    assert_eq!(result["transport"]["protocol_error_alerts"], 0);
    let prometheus = fs::read_to_string(directory.join("measurements.prom")).unwrap();
    assert!(prometheus.contains("scenario=\"cli-proof\""));
    assert!(prometheus.contains("native_runtime_threads=\"4\""));
    assert!(!fixture.path("measurements.summary.json").exists());
}

#[test]
fn default_gate_succeeds_and_writes_sibling_reports_for_all_suffixes() {
    let fixture = Fixture::new();
    let original = fixture.summary(0, 0);
    for (name, stem) in [
        ("run.summary.json", "run"),
        ("plain.json", "plain"),
        ("bare", "bare"),
    ] {
        let summary = fixture.path(name);
        if summary != original {
            fs::copy(&original, &summary).unwrap();
        }
        let output = gate(&summary).output().unwrap();
        assert_success(&output);
        assert!(String::from_utf8_lossy(&output.stdout).contains("passed for 1 workload(s)"));
        let report = read_json(&fixture.path(&format!("{stem}.gate.json")));
        assert_eq!(report["source_summary"], summary.to_string_lossy().as_ref());
        assert_eq!(report["workload_count"], 1);
        assert_eq!(report["findings"], json!([]));
        assert_eq!(report["metric_findings"], json!([]));
        let markdown = fs::read_to_string(fixture.path(&format!("{stem}.gate.md"))).unwrap();
        assert!(markdown.contains("Workloads checked: 1"));
        assert!(markdown.contains("Gate passed."));
    }
}

#[test]
fn failing_gate_emits_counter_and_metric_evidence_before_nonzero_exit() {
    for threads in [0, 4] {
        let fixture = Fixture::new();
        let summary = fixture.summary(threads, 2);
        let policy = fixture.write(
            "policy.json",
            r#"{"metrics":[{"kind":"throughput_mbps_min","threshold":17}]}"#,
        );
        let report_json = fixture.path("reports/json/result.json");
        let report_md = fixture.path("reports/md/result.md");
        let output = gate(&summary)
            .arg("--policy")
            .arg(policy)
            .arg("--report-json")
            .arg(&report_json)
            .arg("--report-md")
            .arg(&report_md)
            .output()
            .unwrap();
        assert_failure(&output, "gate failed with 2 finding(s)");
        let report = read_json(&report_json);
        assert_eq!(report["findings"].as_array().unwrap().len(), 1);
        assert_eq!(report["findings"][0]["kind"], "protocol_error_alerts");
        assert_eq!(report["findings"][0]["observed"], 2);
        assert_eq!(report["findings"][0]["threshold"], 0);
        assert_eq!(report["metric_findings"].as_array().unwrap().len(), 1);
        assert_eq!(report["metric_findings"][0]["observed"], 16.0);
        assert_eq!(report["metric_findings"][0]["threshold"], 17.0);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let label = if threads == 0 { "auto" } else { "4" };
        assert!(stdout.contains(&format!("native_runtime_threads={label}")));
        assert!(stdout.contains("kind=protocol_error_alerts observed=2 threshold=0"));
        assert!(stdout.contains("metric=throughput_mbps_min observed=16.000 threshold=17.000"));
        let markdown = fs::read_to_string(report_md).unwrap();
        assert!(markdown.contains("protocol_error_alerts"));
        assert!(markdown.contains("throughput_mbps_min"));
        assert!(!fixture.path("run.gate.json").exists());
    }
}

#[test]
fn scoped_policy_accepts_exact_boundaries_but_not_another_workload() {
    let fixture = Fixture::new();
    let summary = fixture.summary(4, 2);
    let policy = fixture.write("policy.json", r#"{
        "thresholds":[{"kind":"protocol_error_alerts","threshold":2,"workload":"upload"}],
        "metrics":[{"kind":"throughput_mbps_min","threshold":16},{"kind":"latency_p95_ms_max","threshold":30}]
    }"#);
    assert_success(
        &gate(&summary)
            .arg("--policy")
            .arg(&policy)
            .output()
            .unwrap(),
    );
    let mut bundle = read_json(&summary);
    bundle["workloads"][0]["workload"] = json!("different");
    fs::write(&summary, bundle.to_string()).unwrap();
    let output = gate(&summary).arg("--policy").arg(policy).output().unwrap();
    assert_failure(&output, "gate failed with 1 finding(s)");
    let report = read_json(&fixture.path("run.gate.json"));
    assert_eq!(report["findings"][0]["workload"], "different");
    assert_eq!(report["metric_findings"], json!([]));
}

#[test]
fn invalid_jsonl_never_emits_a_partial_success_bundle() {
    let fixture = Fixture::new();
    let input = fixture.reports("broken.jsonl", 0, 0);
    let valid = fs::read_to_string(&input).unwrap();
    fs::write(&input, format!("{valid}{{bad-json\n")).unwrap();
    let output = transform(&input, None);
    assert_failure(&output, "failed to parse");
    assert!(!fixture.path("broken.summary.json").exists());
    assert!(!fixture.path("broken.prom").exists());
}

#[test]
fn missing_input_and_malformed_summary_or_policy_fail_closed() {
    let fixture = Fixture::new();
    let missing = fixture.path("absent.jsonl");
    assert_failure(&transform(&missing, None), "failed to open");
    assert_failure(&gate(&missing).output().unwrap(), "failed to read");
    let malformed = fixture.write("bad.json", "{}");
    assert_failure(&gate(&malformed).output().unwrap(), "failed to parse");
    assert!(!fixture.path("bad.gate.json").exists());
    let summary = fixture.summary(0, 0);
    let policy = fixture.write("bad-policy.json", "{");
    assert_failure(
        &gate(&summary).arg("--policy").arg(policy).output().unwrap(),
        "failed to parse",
    );
    assert!(!fixture.path("run.gate.json").exists());
}

#[test]
fn filesystem_failures_cannot_report_gate_success() {
    let fixture = Fixture::new();
    let summary = fixture.summary(0, 0);
    let blocked = fixture.write("not-directory", "do not overwrite");
    for flag in ["--report-json", "--report-md"] {
        let output = gate(&summary)
            .arg(flag)
            .arg(blocked.join("report"))
            .output()
            .unwrap();
        assert_failure(&output, "failed to create");
        assert!(!String::from_utf8_lossy(&output.stdout).contains("gate passed"));
    }
    let directory = fixture.path("directory");
    fs::create_dir(&directory).unwrap();
    for flag in ["--report-json", "--report-md"] {
        let output = gate(&summary).arg(flag).arg(&directory).output().unwrap();
        assert_failure(&output, "failed to write");
        assert!(!String::from_utf8_lossy(&output.stdout).contains("gate passed"));
    }
    assert_eq!(fs::read_to_string(blocked).unwrap(), "do not overwrite");
}

#[test]
fn transform_output_directory_failure_preserves_the_input() {
    let fixture = Fixture::new();
    let input = fixture.reports("run.jsonl", 0, 0);
    let original = fs::read(&input).unwrap();
    let blocked = fixture.write("output", "not a directory");
    assert_failure(&transform(&input, Some(&blocked)), "failed to create");
    assert_eq!(fs::read(input).unwrap(), original);
    assert_eq!(fs::read_to_string(blocked).unwrap(), "not a directory");
}
