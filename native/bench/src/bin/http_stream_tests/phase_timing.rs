use super::*;
use serde_json::{json, Map, Value};

struct Metric {
    input: &'static str,
    average: &'static str,
    percentile: &'static str,
    count: Option<&'static str>,
    optional: bool,
}

macro_rules! metric {
    ($name:literal, ms, $optional:literal) => {
        Metric {
            input: concat!($name, "_ms"),
            average: concat!($name, "_avg_ms"),
            percentile: concat!($name, "_p95_ms"),
            count: if $optional {
                Some(concat!($name, "_samples_total"))
            } else {
                None
            },
            optional: $optional,
        }
    };
    ($name:literal, number, $optional:literal) => {
        Metric {
            input: $name,
            average: concat!($name, "_avg"),
            percentile: concat!($name, "_p95"),
            count: if $optional {
                Some(concat!($name, "_samples_total"))
            } else {
                None
            },
            optional: $optional,
        }
    };
}

// Public report schema, with a distinct scale per measurement to catch miswiring.
const METRICS: &[Metric] = &[
    metric!("stream_acquire_wait", ms, false),
    metric!("request_enqueue", ms, false),
    metric!("response_headers_wait", ms, false),
    metric!("response_body_read", ms, false),
    metric!("response_body_first_chunk_wait", ms, false),
    metric!("response_body_tail_read", ms, false),
    metric!("response_body_chunk_count", number, false),
    metric!("response_body_first_chunk_bytes", number, false),
    metric!("request_round_trip", ms, false),
    metric!("response_headers_connection_read_wait", ms, true),
    metric!("response_headers_connection_read_to_headers", ms, true),
    metric!("response_headers_connection_write_wait", ms, true),
    metric!("response_headers_connection_write_span", ms, true),
    metric!("response_headers_last_write_to_first_read", ms, true),
    metric!("response_body_post_header_connection_read_wait", ms, true),
    metric!("response_body_connection_read_to_first_chunk", ms, true),
    metric!("response_body_tail_connection_read_wait", ms, true),
    metric!("response_body_tail_connection_read_to_end", ms, true),
    metric!("response_body_tail_connection_read_count", number, true),
    metric!("response_body_tail_connection_read_span", ms, true),
    metric!("response_body_tail_connection_last_read_to_end", ms, true),
    metric!("response_body_tail_connection_read_bytes", number, true),
    Metric {
        input: "response_body_tail_connection_read_size_avg",
        average: "response_body_tail_connection_read_size_avg",
        percentile: "response_body_tail_connection_read_size_p95",
        count: Some("response_body_tail_connection_read_size_avg_samples_total"),
        optional: true,
    },
    metric!("response_body_tail_connection_read_size_max", number, true),
    Metric {
        input: "response_body_tail_connection_inter_read_gap_avg_ms",
        average: "response_body_tail_connection_inter_read_gap_avg_ms",
        percentile: "response_body_tail_connection_inter_read_gap_p95_ms",
        count: Some("response_body_tail_connection_inter_read_gap_avg_samples_total"),
        optional: true,
    },
    metric!("response_body_tail_connection_inter_read_gap_max", ms, true),
    Metric {
        count: Some("response_body_tail_connection_inter_read_gap_max_position_samples_total"),
        ..metric!(
            "response_body_tail_connection_inter_read_gap_max_read_index",
            number,
            true
        )
    },
    Metric {
        count: None,
        ..metric!(
            "response_body_tail_connection_inter_read_gap_max_bytes_before",
            number,
            true
        )
    },
    Metric {
        count: None,
        ..metric!(
            "response_body_tail_connection_inter_read_gap_max_bytes_after",
            number,
            true
        )
    },
    Metric {
        count: None,
        ..metric!(
            "response_body_tail_connection_inter_read_gap_max_byte_position_ratio",
            number,
            true
        )
    },
];

fn sample(base: u64, optional: bool) -> WorkloadSample {
    let phase: Map<String, Value> = METRICS
        .iter()
        .enumerate()
        .filter(|(_, field)| optional || !field.optional)
        .map(|(index, field)| {
            let value = if field.input.ends_with("_ratio") {
                json!(base as f64 / 100.0)
            } else {
                json!(base * (index + 1) as u64)
            };
            (field.input.to_owned(), value)
        })
        .collect();
    WorkloadSample {
        worker: 0,
        iteration: 0,
        latency_ms: 100.0,
        request_bytes: 7,
        response_bytes: 10000,
        http_fresh_connection_timing: None,
        http_phase_timing: Some(serde_json::from_value(Value::Object(phase)).unwrap()),
    }
}

fn expected_fields(mean: f64, p95: f64, optional: bool, count: u64) -> Map<String, Value> {
    let mut result = Map::new();
    for (index, field) in METRICS.iter().enumerate() {
        let scale = if field.optional && !optional {
            0.0
        } else if field.input.ends_with("_ratio") {
            0.01
        } else {
            (index + 1) as f64
        };
        result.insert(field.average.into(), json!(mean * scale));
        result.insert(field.percentile.into(), json!(p95 * scale));
        if let Some(key) = field.count {
            result.insert(key.into(), json!(if optional { count } else { 0 }));
        }
    }
    result
}

fn add_positions(result: &mut Map<String, Value>, count: u64, pairs: [(f64, f64); 4]) {
    let prefix = "response_body_tail_connection_inter_read_gap_max_response";
    result.insert(format!("{prefix}_position_samples_total"), json!(count));
    for (suffix, (mean, p95)) in [
        "bytes_before",
        "byte_position_ratio",
        "chunk_offset",
        "chunk_boundary_distance",
    ]
    .iter()
    .zip(pairs)
    {
        result.insert(format!("{prefix}_{suffix}_avg"), json!(mean));
        result.insert(format!("{prefix}_{suffix}_p95"), json!(p95));
    }
}

fn assert_summary(samples: &[WorkloadSample], chunk: u64, expected: Map<String, Value>) {
    let actual =
        serde_json::to_value(summarize_http_phase_timing(samples, chunk).unwrap()).unwrap();
    let actual = actual.as_object().unwrap();
    assert_eq!(
        actual.keys().collect::<std::collections::BTreeSet<_>>(),
        expected.keys().collect::<std::collections::BTreeSet<_>>()
    );
    for (key, expected) in expected {
        let expected = expected.as_f64().unwrap();
        let actual = actual[&key].as_f64().unwrap();
        // Counts and integer positions are exact; only fractional means need rounding tolerance.
        let matches = if expected.fract() == 0.0 {
            actual == expected
        } else {
            (actual - expected).abs() <= expected.abs() * f64::EPSILON * 4.0
        };
        assert!(
            actual.is_finite() && matches,
            "assertion failed: {key}: actual={actual}, expected={expected}"
        );
    }
}

#[test]
fn absent_phase_measurements_are_not_invented() {
    assert!(summarize_http_phase_timing(&[], 512).is_none());
    let mut legacy = sample(99, true);
    legacy.http_phase_timing = None;
    assert!(summarize_http_phase_timing(&[legacy], 512).is_none());
}

#[test]
fn all_summary_fields_use_their_own_unsorted_measurements() {
    let mut samples = vec![sample(30, true), sample(10, true), sample(20, true)];
    let mut legacy = sample(99, true);
    legacy.http_phase_timing = None;
    samples.insert(1, legacy);
    let mut expected = expected_fields(20.0, 30.0, true, 3);
    // Response positions are 1080, 360, 720 bytes, with offsets 56, 360, 208.
    add_positions(
        &mut expected,
        3,
        [
            (720.0, 1080.0),
            (0.072, 0.108),
            (208.0, 360.0),
            (416.0 / 3.0, 208.0),
        ],
    );
    assert_summary(&samples, 512, expected);
}

#[test]
fn absent_optional_data_has_zero_counts_not_synthetic_observations() {
    let samples = [sample(30, false), sample(10, false), sample(20, false)];
    let mut expected = expected_fields(20.0, 30.0, false, 0);
    add_positions(&mut expected, 0, [(0.0, 0.0); 4]);
    assert_summary(&samples, 512, expected);
}

#[test]
fn present_zero_observations_keep_their_sample_counts() {
    let samples = [sample(0, true), sample(0, true)];
    let mut expected = expected_fields(0.0, 0.0, true, 2);
    add_positions(&mut expected, 2, [(0.0, 0.0); 4]);
    assert_summary(&samples, 512, expected);
}

#[test]
fn sparse_optional_observations_use_their_own_population() {
    let samples = [sample(10, true), sample(20, false), sample(30, true)];
    let mut expected = expected_fields(20.0, 30.0, true, 2);
    add_positions(
        &mut expected,
        2,
        [
            (720.0, 1080.0),
            (0.072, 0.108),
            (208.0, 360.0),
            (104.0, 152.0),
        ],
    );
    assert_summary(&samples, 512, expected);
}

#[test]
fn one_missing_metric_does_not_discard_the_other_measurements() {
    let mut samples = [sample(10, true), sample(30, true)];
    samples[1]
        .http_phase_timing
        .as_mut()
        .unwrap()
        .response_headers_connection_read_wait_ms = None;
    let mut expected = expected_fields(20.0, 30.0, true, 2);
    expected.insert(
        "response_headers_connection_read_wait_samples_total".into(),
        json!(1),
    );
    expected.insert(
        "response_headers_connection_read_wait_avg_ms".into(),
        json!(100.0),
    );
    expected.insert(
        "response_headers_connection_read_wait_p95_ms".into(),
        json!(100.0),
    );
    add_positions(
        &mut expected,
        2,
        [
            (720.0, 1080.0),
            (0.072, 0.108),
            (208.0, 360.0),
            (104.0, 152.0),
        ],
    );
    assert_summary(&samples, 512, expected);
}

#[test]
fn rounded_index_percentile_is_not_the_maximum_or_the_mean() {
    let samples: Vec<_> = (1..=12).rev().map(|base| sample(base, false)).collect();
    let mut expected = expected_fields(6.5, 11.0, false, 0);
    add_positions(&mut expected, 0, [(0.0, 0.0); 4]);
    assert_summary(&samples, 512, expected);
}

#[test]
fn percentile_clamps_quantiles_and_handles_empty_observations() {
    let sorted = [10.0, 20.0, 30.0];
    for (quantile, expected) in [
        (-1.0, 10.0),
        (0.0, 10.0),
        (0.5, 20.0),
        (1.0, 30.0),
        (2.0, 30.0),
    ] {
        assert_eq!(percentile(&sorted, quantile), expected);
        assert_eq!(percentile(&[], quantile), 0.0);
    }
}

#[test]
fn nonzero_exact_chunk_boundary_keeps_zero_offset_and_distance() {
    let samples = [sample(10, true)];
    let mut expected = expected_fields(10.0, 10.0, true, 1);
    add_positions(
        &mut expected,
        1,
        [(360.0, 360.0), (0.036, 0.036), (0.0, 0.0), (0.0, 0.0)],
    );
    assert_summary(&samples, 36, expected);
}

#[test]
fn zero_response_or_chunk_sizes_do_not_divide_or_take_modulo_by_zero() {
    for (response_bytes, chunk_bytes) in [(0, 512), (10000, 0), (0, 0)] {
        let mut samples = [sample(30, true), sample(10, true), sample(20, true)];
        for sample in &mut samples {
            sample.response_bytes = response_bytes;
        }
        let mut expected = expected_fields(20.0, 30.0, true, 3);
        add_positions(
            &mut expected,
            3,
            [
                (720.0, 1080.0),
                if response_bytes == 0 {
                    (0.0, 0.0)
                } else {
                    (0.072, 0.108)
                },
                if chunk_bytes == 0 {
                    (0.0, 0.0)
                } else {
                    (208.0, 360.0)
                },
                if chunk_bytes == 0 {
                    (0.0, 0.0)
                } else {
                    (416.0 / 3.0, 208.0)
                },
            ],
        );
        assert_summary(&samples, chunk_bytes, expected);
    }
}

#[test]
fn overflow_saturates_response_positions_before_chunk_arithmetic() {
    let mut sample = sample(0, true);
    sample.response_bytes = u64::MAX;
    let timing = sample.http_phase_timing.as_mut().unwrap();
    timing.response_body_first_chunk_bytes = u64::MAX;
    timing.response_body_tail_connection_inter_read_gap_max_bytes_before = Some(7);
    let mut expected = expected_fields(0.0, 0.0, true, 1);
    for suffix in ["avg", "p95"] {
        expected.insert(
            format!("response_body_first_chunk_bytes_{suffix}"),
            json!(u64::MAX as f64),
        );
        expected.insert(
            format!("response_body_tail_connection_inter_read_gap_max_bytes_before_{suffix}"),
            json!(7.0),
        );
    }
    add_positions(
        &mut expected,
        1,
        [
            (u64::MAX as f64, u64::MAX as f64),
            (1.0, 1.0),
            (15.0, 15.0),
            (1.0, 1.0),
        ],
    );
    assert_summary(&[sample], 16, expected);
}
