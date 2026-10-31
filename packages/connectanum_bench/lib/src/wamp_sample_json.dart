import 'dart:collection';
import 'dart:convert';

import 'wamp_workload_runner.dart';

/// Retain every model through routing and project named JSON only at encoding.
/// Public [WampSample.toJson] snapshots keep their existing behavior.
Object wampSamplesForJsonEncoding(List<WampSample> samples) =>
    _Samples(samples);

/// Encode the unchanged positional_v1 fields without allocating a row list.
/// Public [WampSample.toWorkerRecord] still returns an independent mutable list.
List<Object?> wampSampleWorkerRecordForJsonEncoding(WampSample sample) =>
    _SampleRecord(sample);

/// Encode the unchanged worker JSON without staging a JSON string.
/// The process writer appends the line terminator and flushes the response.
List<int> wampWorkerResponseJsonBytes(
  Map<String, Object?> response, {
  bool compactSamples = false,
}) => JsonUtf8Encoder(
  null,
  compactSamples
      ? (object) => wampSampleWorkerRecordForJsonEncoding(object as WampSample)
      : null,
).convert(response);

/// Encode the complete report before sending, without joining its UTF-8 chunks.
/// This keeps encoder failures atomic and retains every sample. The ordinary
/// sink adapter owns each slice; encoder buffers must not be retained by view.
/// 64 KiB batches avoid one transport write per 256-byte SDK default chunk.
List<List<int>> wampResponseJsonChunks(
  Map<String, Object?> response, {
  bool compactSamples = false,
}) {
  final output = _JsonChunks();
  final encoder = JsonUtf8Encoder(
    null,
    compactSamples
        ? (object) =>
              wampSampleWorkerRecordForJsonEncoding(object as WampSample)
        : null,
    65536,
  ).startChunkedConversion(output);
  encoder.add(response);
  encoder.close();
  return output.chunks;
}

class _JsonChunks implements Sink<List<int>> {
  final chunks = <List<int>>[];

  @override
  void add(List<int> bytes) => chunks.add(bytes);

  @override
  void close() {}
}

// Shared named/positional order. Boundary tests compare both projections with
// the existing public snapshots, including all optional null/zero combinations.
const _fieldNames = [
  'worker',
  'iteration',
  'latency_ms',
  'request_bytes',
  'response_bytes',
  'payload_preparation_us',
  'native_builder_input_copied_bytes',
  'native_builder_growth_copied_bytes',
  'native_ppt_frame_submissions',
  'native_ppt_payload_bytes',
  'native_ppt_payload_reused_bytes',
  'started_at_us',
  'completed_at_us',
];

Object? _field(WampSample sample, int index) => switch (index) {
  0 => sample.worker,
  1 => sample.iteration,
  2 => sample.latencyMs,
  3 => sample.requestBytes,
  4 => sample.responseBytes,
  5 => sample.payloadPreparationUs,
  6 => sample.nativeBuilderInputCopiedBytes,
  7 => sample.nativeBuilderGrowthCopiedBytes,
  8 => sample.nativePptFrameSubmissions,
  9 => sample.nativePptPayloadBytes,
  10 => sample.nativePptPayloadReusedBytes,
  11 => sample.startedAtUs,
  12 => sample.completedAtUs,
  _ => throw RangeError.range(index, 0, _fieldNames.length - 1, 'index'),
};

class _Samples {
  const _Samples(this.samples);
  final List<WampSample> samples;
  Object toJson() => _SampleList(samples);
}

class _SampleList extends ListBase<Object> {
  _SampleList(this.samples);
  final List<WampSample> samples;

  @override
  int get length => samples.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only sample JSON');
  @override
  Object operator [](int index) => _SampleMap(samples[index]);
  @override
  void operator []=(int index, Object value) =>
      throw UnsupportedError('Read-only sample JSON');
}

class _SampleRecord extends ListBase<Object?> {
  _SampleRecord(this.sample);
  final WampSample sample;

  @override
  int get length => _fieldNames.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only sample JSON');
  @override
  Object? operator [](int index) => _field(sample, index);
  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('Read-only sample JSON');
}

class _SampleMap extends MapBase<String, Object?> {
  _SampleMap(this.sample);
  final WampSample sample;

  @override
  Object? operator [](Object? key) {
    if (key is! String) {
      return null;
    }
    final index = _fieldNames.indexOf(key);
    return index < 0 ? null : _field(sample, index);
  }

  @override
  Iterable<String> get keys => _fieldNames.where((key) => this[key] != null);
  @override
  bool get isEmpty => false;
  @override
  void forEach(void Function(String, Object?) action) {
    for (var index = 0; index < _fieldNames.length; index++) {
      final value = _field(sample, index);
      if (value != null) {
        action(_fieldNames[index], value);
      }
    }
  }

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Read-only sample JSON');
  @override
  void clear() => throw UnsupportedError('Read-only sample JSON');
  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('Read-only sample JSON');
}
