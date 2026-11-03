import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Process-local RSS sampler; setup, active load and quiescence are separate.
final class GatewayMemoryMeter {
  GatewayMemoryMeter({
    int Function()? readRss,
    int Function()? readPeakRss,
    Duration interval = const Duration(milliseconds: 20),
  }) : _readRss = readRss ?? _currentRss,
       _readPeakRss = readPeakRss ?? (readRss ?? _maxRss) {
    _timer = Timer.periodic(interval, (_) => sample());
  }

  static int _currentRss() => ProcessInfo.currentRss;
  static int _maxRss() => ProcessInfo.maxRss;
  final int Function() _readRss;
  final int Function() _readPeakRss;
  late final Timer _timer;
  int _warm = 0;
  int _peak = 0;

  void begin() {
    _warm = _readRss();
    _peak = _warm;
  }

  int sample() {
    final rss = _readRss();
    if (rss > _peak) _peak = rss;
    final highWater = _readPeakRss();
    if (highWater > _peak) _peak = highWater;
    return rss;
  }

  Map<String, int> snapshot() {
    final current = sample();
    return {
      'warm_rss_bytes': _warm,
      'peak_rss_bytes': _peak,
      'drained_rss_bytes': current,
    };
  }

  void close() => _timer.cancel();
}

Uint8List gatewayBenchmarkPayload(
  int length,
  int phase,
  int sequence,
  int sentUs,
) {
  if (length < 24) throw ArgumentError.value(length, 'length');
  final payload = Uint8List(length);
  final header = ByteData.sublistView(payload);
  header.setUint32(0, 0x43544757);
  header.setUint32(4, phase);
  header.setUint64(8, sequence);
  header.setUint64(16, sentUs);
  for (var i = 24; i < length; i++) {
    payload[i] = (i * 31 + phase + sequence) & 255;
  }
  return payload;
}

/// Exact-byte validation and an exact, compact latency histogram.
final class GatewayDeliveryMeasurement {
  GatewayDeliveryMeasurement({
    required this.payloadBytes,
    required this.requireOrder,
  });

  final int payloadBytes;
  final bool requireOrder;
  int _phase = 0;
  int _expected = 0;
  int _received = 0;
  int _firstSentUs = 0;
  int _lastReceivedUs = 0;
  int _orderErrors = 0;
  Uint8List _seen = Uint8List(0);
  final Map<int, int> _latencies = {};

  int get received => _received;
  bool get complete => _expected > 0 && _received == _expected;

  void begin(int phase, int expected) {
    if (phase < 0 || expected <= 0 || expected > 1000000) {
      throw ArgumentError('Invalid measurement phase/count');
    }
    _phase = phase;
    _expected = expected;
    _received = 0;
    _firstSentUs = 0;
    _lastReceivedUs = 0;
    _orderErrors = 0;
    _seen = Uint8List(expected);
    _latencies.clear();
  }

  void accept(Uint8List payload, int receivedUs) {
    if (payload.length != payloadBytes || payload.length < 24) {
      throw const FormatException('Wrong payload length');
    }
    final header = ByteData.sublistView(payload);
    final phase = header.getUint32(4);
    final sequence = header.getUint64(8);
    final sentUs = header.getUint64(16);
    if (header.getUint32(0) != 0x43544757 ||
        phase != _phase ||
        sequence >= _expected) {
      throw const FormatException('Wrong payload identity');
    }
    if (_seen[sequence] != 0) throw const FormatException('Duplicate delivery');
    for (var i = 24; i < payload.length; i++) {
      if (payload[i] != (i * 31 + phase + sequence) & 255) {
        throw const FormatException('Payload byte mismatch');
      }
    }
    if (receivedUs < sentUs) {
      throw const FormatException('Measurement clock regressed');
    }
    if (sequence != _received) {
      _orderErrors++;
      if (requireOrder) throw const FormatException('Delivery order mismatch');
    }
    _seen[sequence] = 1;
    _received++;
    if (_firstSentUs == 0 || sentUs < _firstSentUs) _firstSentUs = sentUs;
    _lastReceivedUs = receivedUs;
    final latency = receivedUs - sentUs;
    _latencies.update(latency, (value) => value + 1, ifAbsent: () => 1);
  }

  Map<String, Object> summary() {
    if (!complete || _lastReceivedUs <= _firstSentUs) {
      throw StateError('Incomplete or invalid delivery measurement');
    }
    final histogram = _latencies.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {
      'received': _received,
      'duplicates': 0,
      'order_errors': _orderErrors,
      'ordered': requireOrder,
      'payload_bytes': payloadBytes,
      'first_sent_us': _firstSentUs,
      'last_received_us': _lastReceivedUs,
      'latency_histogram_us': [
        for (final entry in histogram) [entry.key, entry.value],
      ],
    };
  }
}
