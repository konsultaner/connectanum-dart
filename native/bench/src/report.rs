use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct WorkloadSample {
    pub worker: u32,
    pub iteration: u32,
    pub latency_ms: f64,
    pub request_bytes: u64,
    pub response_bytes: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub http_phase_timing: Option<HttpPhaseTimingSample>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct HttpConnectionUsage {
    pub reuse_connections: bool,
    pub streams_per_connection: u32,
    pub connections_opened: u32,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct HttpPhaseTimingSample {
    pub stream_acquire_wait_ms: f64,
    pub request_enqueue_ms: f64,
    pub response_headers_wait_ms: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_headers_connection_read_wait_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_headers_connection_read_to_headers_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_headers_connection_write_wait_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_headers_connection_write_span_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_headers_last_write_to_first_read_ms: Option<f64>,
    pub response_body_read_ms: f64,
    pub response_body_first_chunk_wait_ms: f64,
    pub response_body_tail_read_ms: f64,
    pub response_body_chunk_count: u32,
    pub response_body_first_chunk_bytes: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_post_header_connection_read_wait_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_connection_read_to_first_chunk_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_read_wait_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_read_to_end_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_read_count: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_read_span_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_last_read_to_end_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_read_bytes: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_read_size_avg: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_read_size_max: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_inter_read_gap_avg_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_inter_read_gap_max_ms: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_inter_read_gap_max_read_index: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_inter_read_gap_max_bytes_before: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_inter_read_gap_max_bytes_after: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_body_tail_connection_inter_read_gap_max_byte_position_ratio: Option<f64>,
    pub request_round_trip_ms: f64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct HttpPhaseTimingSummary {
    pub stream_acquire_wait_avg_ms: f64,
    pub stream_acquire_wait_p95_ms: f64,
    pub request_enqueue_avg_ms: f64,
    pub request_enqueue_p95_ms: f64,
    pub response_headers_wait_avg_ms: f64,
    pub response_headers_wait_p95_ms: f64,
    pub response_headers_connection_read_wait_samples_total: u64,
    pub response_headers_connection_read_wait_avg_ms: f64,
    pub response_headers_connection_read_wait_p95_ms: f64,
    pub response_headers_connection_read_to_headers_samples_total: u64,
    pub response_headers_connection_read_to_headers_avg_ms: f64,
    pub response_headers_connection_read_to_headers_p95_ms: f64,
    pub response_headers_connection_write_wait_samples_total: u64,
    pub response_headers_connection_write_wait_avg_ms: f64,
    pub response_headers_connection_write_wait_p95_ms: f64,
    pub response_headers_connection_write_span_samples_total: u64,
    pub response_headers_connection_write_span_avg_ms: f64,
    pub response_headers_connection_write_span_p95_ms: f64,
    pub response_headers_last_write_to_first_read_samples_total: u64,
    pub response_headers_last_write_to_first_read_avg_ms: f64,
    pub response_headers_last_write_to_first_read_p95_ms: f64,
    pub response_body_read_avg_ms: f64,
    pub response_body_read_p95_ms: f64,
    pub response_body_first_chunk_wait_avg_ms: f64,
    pub response_body_first_chunk_wait_p95_ms: f64,
    pub response_body_tail_read_avg_ms: f64,
    pub response_body_tail_read_p95_ms: f64,
    pub response_body_chunk_count_avg: f64,
    pub response_body_chunk_count_p95: f64,
    pub response_body_first_chunk_bytes_avg: f64,
    pub response_body_first_chunk_bytes_p95: f64,
    pub response_body_post_header_connection_read_wait_samples_total: u64,
    pub response_body_post_header_connection_read_wait_avg_ms: f64,
    pub response_body_post_header_connection_read_wait_p95_ms: f64,
    pub response_body_connection_read_to_first_chunk_samples_total: u64,
    pub response_body_connection_read_to_first_chunk_avg_ms: f64,
    pub response_body_connection_read_to_first_chunk_p95_ms: f64,
    pub response_body_tail_connection_read_wait_samples_total: u64,
    pub response_body_tail_connection_read_wait_avg_ms: f64,
    pub response_body_tail_connection_read_wait_p95_ms: f64,
    pub response_body_tail_connection_read_to_end_samples_total: u64,
    pub response_body_tail_connection_read_to_end_avg_ms: f64,
    pub response_body_tail_connection_read_to_end_p95_ms: f64,
    pub response_body_tail_connection_read_count_samples_total: u64,
    pub response_body_tail_connection_read_count_avg: f64,
    pub response_body_tail_connection_read_count_p95: f64,
    pub response_body_tail_connection_read_span_samples_total: u64,
    pub response_body_tail_connection_read_span_avg_ms: f64,
    pub response_body_tail_connection_read_span_p95_ms: f64,
    pub response_body_tail_connection_last_read_to_end_samples_total: u64,
    pub response_body_tail_connection_last_read_to_end_avg_ms: f64,
    pub response_body_tail_connection_last_read_to_end_p95_ms: f64,
    pub response_body_tail_connection_read_bytes_samples_total: u64,
    pub response_body_tail_connection_read_bytes_avg: f64,
    pub response_body_tail_connection_read_bytes_p95: f64,
    pub response_body_tail_connection_read_size_avg_samples_total: u64,
    pub response_body_tail_connection_read_size_avg: f64,
    pub response_body_tail_connection_read_size_p95: f64,
    pub response_body_tail_connection_read_size_max_samples_total: u64,
    pub response_body_tail_connection_read_size_max_avg: f64,
    pub response_body_tail_connection_read_size_max_p95: f64,
    pub response_body_tail_connection_inter_read_gap_avg_samples_total: u64,
    pub response_body_tail_connection_inter_read_gap_avg_ms: f64,
    pub response_body_tail_connection_inter_read_gap_p95_ms: f64,
    pub response_body_tail_connection_inter_read_gap_max_samples_total: u64,
    pub response_body_tail_connection_inter_read_gap_max_avg_ms: f64,
    pub response_body_tail_connection_inter_read_gap_max_p95_ms: f64,
    pub response_body_tail_connection_inter_read_gap_max_position_samples_total: u64,
    pub response_body_tail_connection_inter_read_gap_max_read_index_avg: f64,
    pub response_body_tail_connection_inter_read_gap_max_read_index_p95: f64,
    pub response_body_tail_connection_inter_read_gap_max_bytes_before_avg: f64,
    pub response_body_tail_connection_inter_read_gap_max_bytes_before_p95: f64,
    pub response_body_tail_connection_inter_read_gap_max_bytes_after_avg: f64,
    pub response_body_tail_connection_inter_read_gap_max_bytes_after_p95: f64,
    pub response_body_tail_connection_inter_read_gap_max_byte_position_ratio_avg: f64,
    pub response_body_tail_connection_inter_read_gap_max_byte_position_ratio_p95: f64,
    pub response_body_tail_connection_inter_read_gap_max_response_position_samples_total: u64,
    pub response_body_tail_connection_inter_read_gap_max_response_bytes_before_avg: f64,
    pub response_body_tail_connection_inter_read_gap_max_response_bytes_before_p95: f64,
    pub response_body_tail_connection_inter_read_gap_max_response_byte_position_ratio_avg: f64,
    pub response_body_tail_connection_inter_read_gap_max_response_byte_position_ratio_p95: f64,
    pub response_body_tail_connection_inter_read_gap_max_response_chunk_offset_avg: f64,
    pub response_body_tail_connection_inter_read_gap_max_response_chunk_offset_p95: f64,
    pub response_body_tail_connection_inter_read_gap_max_response_chunk_boundary_distance_avg: f64,
    pub response_body_tail_connection_inter_read_gap_max_response_chunk_boundary_distance_p95: f64,
    pub request_round_trip_avg_ms: f64,
    pub request_round_trip_p95_ms: f64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct HttpServerEmissionTimingSummary {
    pub requests_total: u64,
    pub synthetic_responses_total: u64,
    pub native_forwarded_responses_total: u64,
    pub buffered_responses_total: u64,
    pub request_body_drain_avg_ms: f64,
    pub request_body_drain_first_chunk_wait_avg_ms: f64,
    pub request_body_drain_tail_read_avg_ms: f64,
    pub request_body_drain_second_chunk_wait_avg_ms: f64,
    pub request_body_drain_remaining_tail_read_avg_ms: f64,
    pub request_body_drain_chunk_count_avg: f64,
    pub native_request_body_reader_total_avg_ms: f64,
    pub native_request_body_reader_first_chunk_wait_avg_ms: f64,
    pub native_request_body_reader_second_chunk_wait_avg_ms: f64,
    pub native_request_body_reader_remaining_tail_read_avg_ms: f64,
    pub native_request_body_reader_remaining_tail_data_wait_avg_ms: f64,
    pub native_request_body_reader_remaining_tail_data_wait_max_avg_ms: f64,
    #[serde(default)]
    pub native_request_body_reader_remaining_tail_data_wait_max_event_index_avg: f64,
    #[serde(default)]
    pub native_request_body_reader_remaining_tail_data_wait_max_bytes_before_avg: f64,
    #[serde(default)]
    pub native_request_body_reader_remaining_tail_data_wait_max_bytes_after_avg: f64,
    #[serde(default)]
    pub native_request_body_reader_remaining_tail_data_wait_max_eof_ratio: f64,
    pub native_request_body_reader_data_chunk_wait_avg_ms: f64,
    pub native_request_body_reader_chunk_count_avg: f64,
    pub stream_open_avg_ms: f64,
    pub first_chunk_queued_avg_ms: f64,
    pub first_body_write_avg_ms: f64,
    pub first_body_write_completed_avg_ms: f64,
    pub headers_to_first_body_write_avg_ms: f64,
    pub headers_to_first_body_write_completed_avg_ms: f64,
    pub queue_to_first_body_write_avg_ms: f64,
    pub queue_to_first_body_write_completed_avg_ms: f64,
    pub first_body_write_call_avg_ms: f64,
    pub direct_stream_open_round_trip_avg_ms: f64,
    pub direct_stream_request_queue_delay_avg_ms: f64,
    pub direct_stream_descriptor_open_call_avg_ms: f64,
    pub direct_stream_reply_delivery_delay_avg_ms: f64,
    pub handler_avg_ms: f64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct HttpNativeResponseStreamTimingSummary {
    pub streaming_responses_total: u64,
    pub stream_open_to_headers_send_avg_ms: f64,
    pub headers_send_call_avg_ms: f64,
    pub headers_to_first_connection_write_avg_ms: f64,
    pub first_chunk_channel_wait_avg_ms: f64,
    pub headers_to_first_chunk_dequeue_avg_ms: f64,
    pub first_chunk_send_call_avg_ms: f64,
    pub headers_to_first_chunk_send_call_avg_ms: f64,
    pub tail_chunk_channel_wait_avg_ms: f64,
    pub tail_chunk_send_call_avg_ms: f64,
    pub first_to_last_chunk_send_avg_ms: f64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct HttpNativeResponseStreamSlowPathSummary {
    pub streaming_responses_total: u64,
    pub headers_to_first_connection_write_ge_1ms_total: u64,
    pub headers_to_first_connection_write_ge_5ms_total: u64,
    pub headers_to_first_connection_write_ge_10ms_total: u64,
    pub first_chunk_channel_wait_ge_1ms_total: u64,
    pub first_chunk_channel_wait_ge_5ms_total: u64,
    pub first_chunk_channel_wait_ge_10ms_total: u64,
    pub headers_to_first_chunk_dequeue_ge_1ms_total: u64,
    pub headers_to_first_chunk_dequeue_ge_5ms_total: u64,
    pub headers_to_first_chunk_dequeue_ge_10ms_total: u64,
    pub first_chunk_send_call_ge_1ms_total: u64,
    pub first_chunk_send_call_ge_5ms_total: u64,
    pub first_chunk_send_call_ge_10ms_total: u64,
    pub tail_chunk_channel_wait_ge_1ms_total: u64,
    pub tail_chunk_channel_wait_ge_5ms_total: u64,
    pub tail_chunk_channel_wait_ge_10ms_total: u64,
    pub tail_chunk_send_call_ge_1ms_total: u64,
    pub tail_chunk_send_call_ge_5ms_total: u64,
    pub tail_chunk_send_call_ge_10ms_total: u64,
    pub first_to_last_chunk_send_ge_1ms_total: u64,
    pub first_to_last_chunk_send_ge_5ms_total: u64,
    pub first_to_last_chunk_send_ge_10ms_total: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct WorkloadReport {
    pub scenario: String,
    pub workload: String,
    pub protocol: String,
    #[serde(default = "default_client_impl")]
    pub client_impl: String,
    #[serde(default = "default_router_workers")]
    pub router_workers: u32,
    #[serde(default = "default_native_runtime_threads")]
    pub native_runtime_threads: u32,
    pub iterations: u32,
    pub concurrency: u32,
    #[serde(default)]
    pub request_chunk_bytes: u64,
    #[serde(default)]
    pub response_chunk_bytes: u64,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub http_connection_usage: Option<HttpConnectionUsage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub http_phase_timing: Option<HttpPhaseTimingSummary>,
    pub samples: Vec<WorkloadSample>,
}

fn default_router_workers() -> u32 {
    1
}

fn default_client_impl() -> String {
    "n/a".to_string()
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

pub fn transport_http_response_stream_counter_delta(
    before: &Value,
    after: &Value,
    field: &str,
) -> Option<i64> {
    let path = &["transport", "http_response_stream", field];
    let end = extract_i64(after, path)?;
    let start = extract_i64(before, path).unwrap_or(0);
    Some(end - start)
}

pub fn transport_http_response_stream_counter_after(after: &Value, field: &str) -> Option<u64> {
    extract_u64(after, &["transport", "http_response_stream", field])
}

pub fn transport_http_request_body_stream_counter_delta(
    before: &Value,
    after: &Value,
    field: &str,
) -> Option<i64> {
    let path = &["transport", "http_request_body_stream", field];
    let end = extract_i64(after, path)?;
    let start = extract_i64(before, path).unwrap_or(0);
    Some(end - start)
}

pub fn bench_http_stream_counter_delta(before: &Value, after: &Value, field: &str) -> Option<i64> {
    counter_delta(before, after, &["bench_http_stream", field])
}

pub fn bench_http_stream_counter_after(after: &Value, field: &str) -> Option<u64> {
    extract_u64(after, &["bench_http_stream", field])
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
        let response_stream_before = json!({
            "metrics": {
                "transport": {
                    "http_response_stream": {
                        "streaming_responses_total": 2,
                    }
                }
            }
        });
        let response_stream_after = json!({
            "transport": {
                "http_response_stream": {
                    "streaming_responses_total": 7,
                }
            }
        });
        assert_eq!(
            transport_http_response_stream_counter_delta(
                &response_stream_before,
                &response_stream_after,
                "streaming_responses_total",
            ),
            Some(5)
        );
        assert_eq!(
            transport_http_response_stream_counter_after(
                &response_stream_after,
                "streaming_responses_total",
            ),
            Some(7)
        );
        assert_eq!(
            transport_http_response_stream_counter_delta(
                &json!({"metrics": {"transport": {}}}),
                &response_stream_after,
                "streaming_responses_total",
            ),
            Some(7)
        );
        let before = json!({
            "metrics": {
                "bench_http_stream": {
                    "requests_total": 4,
                }
            }
        });
        let after = json!({
            "metrics": {
                "bench_http_stream": {
                    "requests_total": 9,
                }
            }
        });
        assert_eq!(
            bench_http_stream_counter_delta(&before, &after, "requests_total"),
            Some(5)
        );
        assert_eq!(
            bench_http_stream_counter_after(&after, "requests_total"),
            Some(9)
        );
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
        assert_eq!(report.client_impl, "n/a");
        assert_eq!(report.router_workers, 1);
        assert_eq!(report.native_runtime_threads, 0);
        assert_eq!(report.http_connection_usage, None);
    }
}
