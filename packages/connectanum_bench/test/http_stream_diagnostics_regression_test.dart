import 'dart:async';

import 'package:connectanum_bench/src/http_stream_handler.dart';
import 'package:test/test.dart';

const _timings = <String>[
  'request_body_drain',
  'request_body_drain_first_chunk_wait',
  'request_body_drain_tail_read',
  'request_body_drain_second_chunk_wait',
  'request_body_drain_remaining_tail_read',
  'stream_open',
  'first_chunk_queued',
  'first_body_write',
  'first_body_write_completed',
  'headers_to_first_body_write',
  'headers_to_first_body_write_completed',
  'queue_to_first_body_write',
  'queue_to_first_body_write_completed',
  'first_body_write_call',
  'direct_stream_open_round_trip',
  'direct_stream_request_queue_delay',
  'direct_stream_descriptor_open_call',
  'direct_stream_reply_delivery_delay',
  'handler',
];

Map<String, Object?> _emptyDiagnostics() => {
  'requests_total': 0,
  'synthetic_responses_total': 0,
  'native_forwarded_responses_total': 0,
  'buffered_responses_total': 0,
  'request_body_drain_chunk_count_samples_total': 0,
  'request_body_drain_chunk_count_total': 0,
  for (final name in _timings) '${name}_samples_total': 0,
  for (final name in _timings) '${name}_us_total': 0,
};

void _sample(Map<String, Object?> expected, String name, int? value) {
  if (value == null) return;
  expected['${name}_samples_total'] = 1;
  expected['${name}_us_total'] = value;
}

Duration? _duration(int? value) =>
    value == null ? null : Duration(microseconds: value);

BenchHttpStreamResponseStats _response({
  BenchHttpStreamResponseMode mode = BenchHttpStreamResponseMode.buffered,
  int? queued,
  int? firstDrain,
  int? tailDrain,
  int? secondDrain,
  int? remainingDrain,
}) => BenchHttpStreamResponseStats(
  responseMode: mode,
  requestBodyDrain: const Duration(microseconds: 101),
  requestBodyDrainFirstChunkWait: _duration(firstDrain),
  requestBodyDrainTailRead: _duration(tailDrain),
  requestBodyDrainSecondChunkWait: _duration(secondDrain),
  requestBodyDrainRemainingTailRead: _duration(remainingDrain),
  requestBodyDrainChunkCount: 7,
  firstChunkQueued: _duration(queued),
  emittedChunkCount: 3,
  firstChunkBytes: 11,
  handlerElapsed: const Duration(microseconds: 137),
);

void main() {
  group('HTTP diagnostic accounting', () {
    test('empty snapshots contain every counter and are independent', () {
      final diagnostics = BenchHttpStreamDiagnostics();
      final first = diagnostics.toJson();
      expect(first, _emptyDiagnostics());
      first['requests_total'] = 999;
      first.remove('handler_us_total');
      expect(diagnostics.toJson(), _emptyDiagnostics());
    });

    const responseCounters = {
      BenchHttpStreamResponseMode.synthetic: 'synthetic_responses_total',
      BenchHttpStreamResponseMode.nativeForwarded:
          'native_forwarded_responses_total',
      BenchHttpStreamResponseMode.buffered: 'buffered_responses_total',
    };
    for (final mode in BenchHttpStreamResponseMode.values) {
      for (var mask = 0; mask < 16; mask++) {
        test('$mode drain presence mask $mask', () {
          final first = mask & 1 == 0 ? null : 11;
          final tail = mask & 2 == 0 ? null : 23;
          final second = mask & 4 == 0 ? null : 31;
          final remaining = mask & 8 == 0 ? null : 47;
          final diagnostics = BenchHttpStreamDiagnostics();
          diagnostics.record(
            response: _response(
              mode: mode,
              firstDrain: first,
              tailDrain: tail,
              secondDrain: second,
              remainingDrain: remaining,
            ),
          );
          final expected = _emptyDiagnostics()
            ..['requests_total'] = 1
            ..[responseCounters[mode]!] = 1;
          _sample(expected, 'handler', 137);
          if (mode == BenchHttpStreamResponseMode.synthetic) {
            _sample(expected, 'request_body_drain', 101);
            _sample(expected, 'request_body_drain_first_chunk_wait', first);
            _sample(expected, 'request_body_drain_tail_read', tail);
            _sample(expected, 'request_body_drain_second_chunk_wait', second);
            _sample(
              expected,
              'request_body_drain_remaining_tail_read',
              remaining,
            );
            expected['request_body_drain_chunk_count_samples_total'] = 1;
            expected['request_body_drain_chunk_count_total'] = 7;
          }
          expect(diagnostics.toJson(), expected);
        });
      }
    }

    // Exhaust all presence/order/equality boundaries without wall-clock timing.
    for (final opened in <int?>[null, 0, 3, 7]) {
      for (final queued in <int?>[null, 0, 3, 7]) {
        for (final write in <int?>[null, 0, 3, 7]) {
          for (final completed in <int?>[null, 0, 3, 7]) {
            test('timestamps $opened/$queued/$write/$completed', () {
              final diagnostics = BenchHttpStreamDiagnostics();
              diagnostics.record(
                response: _response(queued: queued),
                streamOpened: _duration(opened),
                firstBodyWrite: _duration(write),
                firstBodyWriteCompleted: _duration(completed),
              );
              final expected = _emptyDiagnostics()
                ..['requests_total'] = 1
                ..['buffered_responses_total'] = 1;
              _sample(expected, 'handler', 137);
              _sample(expected, 'stream_open', opened);
              _sample(expected, 'first_chunk_queued', queued);
              _sample(expected, 'first_body_write', write);
              _sample(expected, 'first_body_write_completed', completed);
              for (final pair in [
                ('headers_to_first_body_write', opened, write),
                ('headers_to_first_body_write_completed', opened, completed),
                ('queue_to_first_body_write', queued, write),
                ('queue_to_first_body_write_completed', queued, completed),
                ('first_body_write_call', write, completed),
              ]) {
                final start = pair.$2;
                final end = pair.$3;
                if (start != null && end != null) {
                  final difference = end - start;
                  if (!difference.isNegative) {
                    _sample(expected, pair.$1, difference);
                  }
                }
              }
              expect(diagnostics.toJson(), expected);
            });
          }
        }
      }
    }

    for (var mask = 0; mask < 16; mask++) {
      test('direct stream timing presence mask $mask', () {
        final diagnostics = BenchHttpStreamDiagnostics();
        final values = <int?>[
          mask & 1 == 0 ? null : 0,
          mask & 2 == 0 ? null : 17,
          mask & 4 == 0 ? null : 29,
          mask & 8 == 0 ? null : 43,
        ];
        diagnostics.record(
          response: _response(),
          directStreamOpenRoundTrip: _duration(values[0]),
          directStreamRequestQueueDelay: _duration(values[1]),
          directStreamDescriptorOpenCall: _duration(values[2]),
          directStreamReplyDeliveryDelay: _duration(values[3]),
        );
        final expected = _emptyDiagnostics()
          ..['requests_total'] = 1
          ..['buffered_responses_total'] = 1;
        _sample(expected, 'handler', 137);
        const names = [
          'direct_stream_open_round_trip',
          'direct_stream_request_queue_delay',
          'direct_stream_descriptor_open_call',
          'direct_stream_reply_delivery_delay',
        ];
        for (var i = 0; i < names.length; i++) {
          _sample(expected, names[i], values[i]);
        }
        expect(diagnostics.toJson(), expected);
      });
    }

    test(
      'adds all counters across requests without mutating old snapshots',
      () {
        final diagnostics = BenchHttpStreamDiagnostics();
        final before = diagnostics.toJson();
        void record() => diagnostics.record(
          response: _response(
            mode: BenchHttpStreamResponseMode.synthetic,
            queued: 17,
            firstDrain: 11,
            tailDrain: 23,
            secondDrain: 31,
            remainingDrain: 47,
          ),
          streamOpened: _duration(7),
          firstBodyWrite: _duration(29),
          firstBodyWriteCompleted: _duration(43),
          directStreamOpenRoundTrip: _duration(53),
          directStreamRequestQueueDelay: _duration(61),
          directStreamDescriptorOpenCall: _duration(73),
          directStreamReplyDeliveryDelay: _duration(89),
        );
        record();
        final once = diagnostics.toJson();
        record();
        final twice = _emptyDiagnostics()
          ..['requests_total'] = 2
          ..['synthetic_responses_total'] = 2
          ..['request_body_drain_chunk_count_samples_total'] = 2
          ..['request_body_drain_chunk_count_total'] = 14;
        const sums = <String, int>{
          'request_body_drain': 202,
          'request_body_drain_first_chunk_wait': 22,
          'request_body_drain_tail_read': 46,
          'request_body_drain_second_chunk_wait': 62,
          'request_body_drain_remaining_tail_read': 94,
          'stream_open': 14,
          'first_chunk_queued': 34,
          'first_body_write': 58,
          'first_body_write_completed': 86,
          'headers_to_first_body_write': 44,
          'headers_to_first_body_write_completed': 72,
          'queue_to_first_body_write': 24,
          'queue_to_first_body_write_completed': 52,
          'first_body_write_call': 28,
          'direct_stream_open_round_trip': 106,
          'direct_stream_request_queue_delay': 122,
          'direct_stream_descriptor_open_call': 146,
          'direct_stream_reply_delivery_delay': 178,
          'handler': 274,
        };
        for (final entry in sums.entries) {
          twice['${entry.key}_samples_total'] = 2;
          twice['${entry.key}_us_total'] = entry.value;
        }
        expect(diagnostics.toJson(), twice);
        expect(before, _emptyDiagnostics());
        expect(
          once,
          twice.map((key, value) => MapEntry(key, (value! as int) ~/ 2)),
        );
      },
    );
  });

  group('HTTP write tracker', () {
    test('records each first event once on a common monotonic clock', () async {
      final outer = Stopwatch()..start();
      final tracker = BenchHttpStreamWriteTracker();
      expect(tracker.streamOpened, isNull);
      expect(tracker.firstBodyWrite, isNull);
      expect(tracker.firstBodyWriteCompleted, isNull);
      final inner = Stopwatch()..start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final lowerBound = inner.elapsed;
      tracker.markStreamOpened();
      final opened = tracker.streamOpened!;
      tracker.markFirstBodyWrite();
      final write = tracker.firstBodyWrite!;
      tracker.markFirstBodyWriteCompleted();
      final completed = tracker.firstBodyWriteCompleted!;
      expect(opened, greaterThanOrEqualTo(lowerBound));
      expect(write, greaterThanOrEqualTo(opened));
      expect(completed, greaterThanOrEqualTo(write));
      expect(completed, lessThanOrEqualTo(outer.elapsed));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      tracker.markStreamOpened();
      tracker.markFirstBodyWrite();
      tracker.markFirstBodyWriteCompleted();
      expect(tracker.streamOpened, opened);
      expect(tracker.firstBodyWrite, write);
      expect(tracker.firstBodyWriteCompleted, completed);
    });

    test('direct timings remain independent and keep the first zero value', () {
      final tracker = BenchHttpStreamWriteTracker();
      expect(tracker.directStreamOpenRoundTrip, isNull);
      expect(tracker.directStreamRequestQueueDelay, isNull);
      expect(tracker.directStreamDescriptorOpenCall, isNull);
      expect(tracker.directStreamReplyDeliveryDelay, isNull);
      tracker.markDirectStreamOpenRoundTrip(Duration.zero);
      tracker.markDirectStreamRequestQueueDelay(
        const Duration(microseconds: 3),
      );
      tracker.markDirectStreamDescriptorOpenCall(
        const Duration(microseconds: 7),
      );
      tracker.markDirectStreamReplyDeliveryDelay(
        const Duration(microseconds: 11),
      );
      tracker.markDirectStreamOpenRoundTrip(const Duration(days: 1));
      tracker.markDirectStreamRequestQueueDelay(const Duration(days: 1));
      tracker.markDirectStreamDescriptorOpenCall(const Duration(days: 1));
      tracker.markDirectStreamReplyDeliveryDelay(const Duration(days: 1));
      expect(tracker.directStreamOpenRoundTrip, Duration.zero);
      expect(tracker.directStreamRequestQueueDelay, _duration(3));
      expect(tracker.directStreamDescriptorOpenCall, _duration(7));
      expect(tracker.directStreamReplyDeliveryDelay, _duration(11));
      expect(tracker.streamOpened, isNull);
      expect(tracker.firstBodyWrite, isNull);
      expect(tracker.firstBodyWriteCompleted, isNull);
    });
  });
}
