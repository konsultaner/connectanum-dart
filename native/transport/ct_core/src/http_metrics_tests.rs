use super::*;

#[test]
fn response_count_and_header_timings_accumulate_without_wrapping() {
    let metrics = HttpResponseStreamMetrics::default();
    let base = Instant::now();
    assert_eq!(metrics.snapshot().streaming_responses_total, 0);
    metrics.record_streaming_response();
    metrics.record_streaming_response();
    metrics.record_headers_sent(
        base,
        base + Duration::from_micros(30),
        base + Duration::from_micros(70),
    );
    metrics.record_headers_sent(
        base + Duration::from_micros(100),
        base + Duration::from_micros(80),
        base + Duration::from_micros(20),
    );
    let snapshot = metrics.snapshot();
    assert_eq!(snapshot.streaming_responses_total, 2);
    assert_eq!(snapshot.stream_open_to_headers_send_samples_total, 2);
    assert_eq!(snapshot.stream_open_to_headers_send_us_total, 70);
    assert_eq!(snapshot.headers_send_call_samples_total, 2);
    assert_eq!(snapshot.headers_send_call_us_total, 40);
    assert_eq!(snapshot.first_chunk_channel_wait_samples_total, 0);
    assert_eq!(snapshot.tail_chunk_channel_wait_samples_total, 0);
}

#[test]
fn response_first_chunk_uses_each_phase_clock_origin() {
    let metrics = HttpResponseStreamMetrics::default();
    let base = Instant::now();
    metrics.record_first_chunk(
        base + Duration::from_micros(2),
        base + Duration::from_micros(5),
        base + Duration::from_micros(11),
        base + Duration::from_micros(13),
        base + Duration::from_micros(20),
    );
    let snapshot = metrics.snapshot();
    assert_eq!(snapshot.first_chunk_channel_wait_samples_total, 1);
    assert_eq!(snapshot.first_chunk_channel_wait_us_total, 9);
    assert_eq!(snapshot.headers_to_first_chunk_dequeue_samples_total, 1);
    assert_eq!(snapshot.headers_to_first_chunk_dequeue_us_total, 6);
    assert_eq!(snapshot.first_chunk_send_call_samples_total, 1);
    assert_eq!(snapshot.first_chunk_send_call_us_total, 7);
    assert_eq!(snapshot.headers_to_first_chunk_send_call_samples_total, 1);
    assert_eq!(snapshot.headers_to_first_chunk_send_call_us_total, 15);
    assert_eq!(snapshot.streaming_responses_total, 0);
    assert_eq!(snapshot.tail_chunk_send_call_samples_total, 0);
}

#[test]
fn response_latency_buckets_include_exact_thresholds_and_saturate_reversed_time() {
    let metrics = HttpResponseStreamMetrics::default();
    let base = Instant::now();
    for micros in [0, 999, 1000, 4999, 5000, 9999, 10000] {
        let end = base + Duration::from_micros(micros);
        metrics.record_headers_to_first_connection_write(base, end);
        metrics.record_first_chunk(base, base, end, base, end);
        metrics.record_tail_chunk(base, end, base, end);
        metrics.record_first_to_last_chunk_send(base, end);
    }
    let future = base + Duration::from_secs(1);
    metrics.record_headers_to_first_connection_write(future, base);
    metrics.record_first_chunk(future, future, base, future, base);
    metrics.record_tail_chunk(future, base, future, base);
    metrics.record_first_to_last_chunk_send(future, base);

    let s = metrics.snapshot();
    let groups = [
        (
            s.headers_to_first_connection_write_samples_total,
            s.headers_to_first_connection_write_us_total,
            s.headers_to_first_connection_write_ge_1ms_total,
            s.headers_to_first_connection_write_ge_5ms_total,
            s.headers_to_first_connection_write_ge_10ms_total,
        ),
        (
            s.first_chunk_channel_wait_samples_total,
            s.first_chunk_channel_wait_us_total,
            s.first_chunk_channel_wait_ge_1ms_total,
            s.first_chunk_channel_wait_ge_5ms_total,
            s.first_chunk_channel_wait_ge_10ms_total,
        ),
        (
            s.headers_to_first_chunk_dequeue_samples_total,
            s.headers_to_first_chunk_dequeue_us_total,
            s.headers_to_first_chunk_dequeue_ge_1ms_total,
            s.headers_to_first_chunk_dequeue_ge_5ms_total,
            s.headers_to_first_chunk_dequeue_ge_10ms_total,
        ),
        (
            s.first_chunk_send_call_samples_total,
            s.first_chunk_send_call_us_total,
            s.first_chunk_send_call_ge_1ms_total,
            s.first_chunk_send_call_ge_5ms_total,
            s.first_chunk_send_call_ge_10ms_total,
        ),
        (
            s.tail_chunk_channel_wait_samples_total,
            s.tail_chunk_channel_wait_us_total,
            s.tail_chunk_channel_wait_ge_1ms_total,
            s.tail_chunk_channel_wait_ge_5ms_total,
            s.tail_chunk_channel_wait_ge_10ms_total,
        ),
        (
            s.tail_chunk_send_call_samples_total,
            s.tail_chunk_send_call_us_total,
            s.tail_chunk_send_call_ge_1ms_total,
            s.tail_chunk_send_call_ge_5ms_total,
            s.tail_chunk_send_call_ge_10ms_total,
        ),
        (
            s.first_to_last_chunk_send_samples_total,
            s.first_to_last_chunk_send_us_total,
            s.first_to_last_chunk_send_ge_1ms_total,
            s.first_to_last_chunk_send_ge_5ms_total,
            s.first_to_last_chunk_send_ge_10ms_total,
        ),
    ];
    for group in groups {
        assert_eq!(group, (8, 31_997, 5, 3, 1));
    }
    assert_eq!(s.headers_to_first_chunk_send_call_samples_total, 8);
    assert_eq!(s.headers_to_first_chunk_send_call_us_total, 31_997);
    assert_eq!(s.streaming_responses_total, 0);
    assert_eq!(s.headers_send_call_samples_total, 0);
}

#[test]
fn response_counts_preserve_concurrent_updates() {
    let metrics = Arc::new(HttpResponseStreamMetrics::default());
    let workers: Vec<_> = (0..4)
        .map(|_| {
            let metrics = metrics.clone();
            std::thread::spawn(move || {
                for _ in 0..17 {
                    metrics.record_streaming_response();
                }
            })
        })
        .collect();
    for worker in workers {
        assert!(worker.join().is_ok());
    }
    assert_eq!(metrics.snapshot().streaming_responses_total, 68);
    assert_eq!(metrics.snapshot().headers_send_call_samples_total, 0);
}

#[test]
fn tail_wait_max_retains_smaller_samples_and_replaces_ties_with_all_metadata() {
    let mut sample = HttpRequestBodyTailDataWaitMax::default();
    for (wait, tag, expected_wait, expected_tag) in [
        (0, 1, 0, 1),
        (100, 2, 100, 2),
        (99, 3, 100, 2),
        (100, 4, 100, 4),
        (u64::MAX, 5, u64::MAX, 5),
        (0, 6, u64::MAX, 5),
    ] {
        sample.observe(
            wait,
            tag,
            tag * 10,
            tag * 10 + 7,
            tag % 2 == 0,
            HttpRequestBodyFlowControlSample {
                available_capacity: -(tag as i64),
                used_capacity: tag + 11,
            },
            HttpRequestBodyFlowControlSample {
                available_capacity: -(tag as i64) - 20,
                used_capacity: tag + 31,
            },
            HttpRequestBodyFlowControlSample {
                available_capacity: tag as i64 + 40,
                used_capacity: tag + 51,
            },
        );
        assert_eq!(sample.wait_us, expected_wait);
        assert_eq!(sample.event_index, expected_tag);
        assert_eq!(sample.bytes_before, expected_tag * 10);
        assert_eq!(sample.bytes_after, expected_tag * 10 + 7);
        assert_eq!(sample.eof, expected_tag % 2 == 0);
        assert_eq!(
            sample.flow_before_wait.available_capacity,
            -(expected_tag as i64)
        );
        assert_eq!(sample.flow_before_wait.used_capacity, expected_tag + 11);
        assert_eq!(
            sample.flow_after_data.available_capacity,
            -(expected_tag as i64) - 20
        );
        assert_eq!(sample.flow_after_data.used_capacity, expected_tag + 31);
        assert_eq!(
            sample.flow_after_release.available_capacity,
            expected_tag as i64 + 40
        );
        assert_eq!(sample.flow_after_release.used_capacity, expected_tag + 51);
    }
}
