use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct WorkloadSample {
    pub worker: u32,
    pub iteration: u32,
    pub latency_ms: f64,
    pub request_bytes: u64,
    pub response_bytes: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct WorkloadReport {
    pub scenario: String,
    pub workload: String,
    pub protocol: String,
    #[serde(default = "default_router_workers")]
    pub router_workers: u32,
    #[serde(default = "default_native_runtime_threads")]
    pub native_runtime_threads: u32,
    pub iterations: u32,
    pub concurrency: u32,
    pub started_at_ms: u128,
    pub completed_at_ms: u128,
    pub metrics_before: Value,
    pub metrics_after: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub open_metrics_before: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub open_metrics_after: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scenario_metrics_before: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scenario_metrics_after: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scenario_open_metrics_before: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scenario_open_metrics_after: Option<String>,
    pub samples: Vec<WorkloadSample>,
}

fn default_router_workers() -> u32 {
    1
}

fn default_native_runtime_threads() -> u32 {
    0
}

pub fn metric_root(value: &Value) -> Option<&Value> {
    value.get("metrics").unwrap_or(value).as_object()?;
    Some(value.get("metrics").unwrap_or(value))
}

pub fn extract_i64(root: &Value, path: &[&str]) -> Option<i64> {
    let mut current = metric_root(root)?;
    for segment in path {
        current = current.get(*segment)?;
    }
    current.as_i64()
}

pub fn extract_u64(root: &Value, path: &[&str]) -> Option<u64> {
    let mut current = metric_root(root)?;
    for segment in path {
        current = current.get(*segment)?;
    }
    current.as_u64()
}

pub fn counter_delta(before: &Value, after: &Value, path: &[&str]) -> Option<i64> {
    let start = extract_i64(before, path)?;
    let end = extract_i64(after, path)?;
    Some(end - start)
}

pub fn router_counter_delta(before: &Value, after: &Value, field: &str) -> Option<i64> {
    counter_delta(before, after, &[field])
}

pub fn transport_counter_delta(before: &Value, after: &Value, field: &str) -> Option<i64> {
    counter_delta(before, after, &["transport", field])
}

pub fn transport_counter_after(after: &Value, field: &str) -> Option<u64> {
    extract_u64(after, &["transport", field])
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn metric_helpers_handle_wrapped_and_flat_payloads() {
        let wrapped = json!({
            "metrics": {
                "total_invocations_dispatched": 5,
                "transport": {
                    "goaway_events": 2,
                    "active_throttles": 1,
                }
            }
        });
        let flat = json!({
            "total_publications_routed": 8,
            "transport": {
                "goaway_events": 4,
                "active_throttles": 3,
            }
        });

        assert_eq!(
            extract_i64(&wrapped, &["total_invocations_dispatched"]),
            Some(5)
        );
        assert_eq!(extract_i64(&flat, &["total_publications_routed"]), Some(8));
        assert_eq!(
            transport_counter_delta(
                &wrapped,
                &json!({
                    "metrics": {
                        "transport": {
                            "goaway_events": 6,
                        }
                    }
                }),
                "goaway_events",
            ),
            Some(4)
        );
        assert_eq!(transport_counter_after(&flat, "active_throttles"), Some(3));
    }

    #[test]
    fn router_counter_delta_reads_metric_roots() {
        let before = json!({
            "metrics": {
                "total_publications_routed": 10
            }
        });
        let after = json!({
            "metrics": {
                "total_publications_routed": 17
            }
        });
        assert_eq!(
            router_counter_delta(&before, &after, "total_publications_routed"),
            Some(7)
        );
    }

    #[test]
    fn workload_report_defaults_router_workers_for_legacy_rows() {
        let report: WorkloadReport = serde_json::from_value(json!({
            "scenario": "legacy",
            "workload": "load",
            "protocol": "h2",
            "iterations": 1,
            "concurrency": 1,
            "started_at_ms": 1,
            "completed_at_ms": 2,
            "metrics_before": {},
            "metrics_after": {},
            "samples": []
        }))
        .unwrap();
        assert_eq!(report.router_workers, 1);
        assert_eq!(report.native_runtime_threads, 0);
    }
}
