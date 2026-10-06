import 'dart:typed_data';

import 'package:connectanum_client/native_buffers.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;

import 'generated/workload_payload_connectanum.bench_generated.dart' as schema;

/// The application fixture used by typed-payload benchmark rows.
///
/// Its worker and iteration fields let the receiver reject stale, duplicated,
/// or cross-worker payloads. The body is deterministic across codec variants.
abstract final class BenchPayloadCodec {
  static const fileIdentifier = 'CBEN';

  static Map<String, Object?> dynamicValue({
    required int worker,
    required int iteration,
    required int bodyBytes,
  }) => {
    'worker': worker,
    'iteration': iteration,
    'body': body(worker: worker, iteration: iteration, length: bodyBytes),
  };

  static Uint8List body({
    required int worker,
    required int iteration,
    required int length,
  }) {
    _checkIdentity(worker, iteration);
    RangeError.checkValueInInterval(length, 0, 64 * 1024 * 1024, 'length');
    return Uint8List.fromList(
      List<int>.generate(
        length,
        (index) => (index * 31 + worker * 17 + iteration * 29) & 0xff,
        growable: false,
      ),
    );
  }

  static Uint8List encodeDart({
    required int worker,
    required int iteration,
    required int bodyBytes,
  }) {
    final builder = fb.Builder(deduplicateTables: false);
    builder.finish(
      schema.WorkloadPayloadObjectBuilder(
        worker: worker,
        iteration: iteration,
        body: body(worker: worker, iteration: iteration, length: bodyBytes),
      ).finish(builder),
      fileIdentifier,
    );
    return builder.buffer;
  }

  static NativeOwnedBuffer encodeNative(
    NativeBufferAllocator allocator, {
    required int worker,
    required int iteration,
    required int bodyBytes,
    int initialSize = 1024,
  }) {
    final builder = allocator.flatBuffers(initialSize: initialSize);
    try {
      builder.finish(
        schema.WorkloadPayloadObjectBuilder(
          worker: worker,
          iteration: iteration,
          body: body(worker: worker, iteration: iteration, length: bodyBytes),
        ).finish(builder),
        fileIdentifier,
      );
      return builder.freeze();
    } finally {
      builder.dispose();
    }
  }

  static int _uintWidth(int value, bool cbor) => value <= (cbor ? 23 : 127)
      ? 1
      : value <= 0xff
      ? 2
      : value <= 0xffff
      ? 3
      : 5;
  static int _binaryWidth(int length, bool cbor) => cbor
      ? _uintWidth(length, true)
      : length <= 0xff
      ? 2
      : length <= 0xffff
      ? 3
      : 5;

  /// Encodes the fixed CBOR/MessagePack benchmark PPT model in native storage.
  /// Header/scalar fields are written directly; only the body input is copied.
  /// Other serializers continue to use their regular public codecs.
  static NativeOwnedBuffer encodeNativePpt(
    NativeBufferAllocator allocator, {
    required String serializer,
    required int worker,
    required int iteration,
    required int bodyBytes,
  }) {
    final cbor = switch (serializer) {
      'cbor' => true,
      'msgpack' => false,
      _ => throw ArgumentError.value(serializer, 'serializer'),
    };
    final data = body(
      worker: worker,
      iteration: iteration,
      length: bodyBytes,
    );
    // Two maps, one array, five short ASCII keys, and the null keyword value.
    final length =
        38 +
        _uintWidth(worker, cbor) +
        _uintWidth(iteration, cbor) +
        _binaryWidth(bodyBytes, cbor) +
        bodyBytes;
    final builder = allocator.allocate(length);
    var offset = 0;
    void byte(int value) => builder.setUint8(offset++, value);
    void key(String value) {
      byte((cbor ? 0x60 : 0xa0) | value.length);
      for (final unit in value.codeUnits) {
        byte(unit);
      }
    }

    void unsigned(int value, {bool binary = false}) {
      final width = binary
          ? _binaryWidth(value, cbor)
          : _uintWidth(value, cbor);
      if (width == 1) {
        byte((binary ? 0x40 : 0) | value);
        return;
      }
      final extension = width == 2
          ? 0
          : width == 3
          ? 1
          : 2;
      byte(
        cbor
            ? (binary ? 0x40 : 0) | (24 + extension)
            : (binary ? 0xc4 : 0xcc) + extension,
      );
      if (width == 2) {
        byte(value);
      } else if (width == 3) {
        byte(value >> 8);
        byte(value & 0xff);
      } else {
        builder.setUint32(offset, value, Endian.big);
        offset += 4;
      }
    }

    try {
      byte(cbor ? 0xa2 : 0x82);
      key('args');
      byte(cbor ? 0x81 : 0x91);
      byte(cbor ? 0xa3 : 0x83);
      key('worker');
      unsigned(worker);
      key('iteration');
      unsigned(iteration);
      key('body');
      unsigned(bodyBytes, binary: true);
      builder.writeBytes(offset, data);
      offset += data.length;
      key('kwargs');
      byte(cbor ? 0xf6 : 0xc0);
      if (offset != length) throw StateError('Invalid native PPT fixture size');
      return builder.freeze();
    } finally {
      builder.dispose();
    }
  }

  static schema.WorkloadPayload decode(List<int> bytes) {
    _checkFileIdentifier(bytes);
    return schema.WorkloadPayload(bytes);
  }

  static void verify({
    required List<int> bytes,
    required int worker,
    required int iteration,
    required int bodyBytes,
  }) {
    final decoded = decode(bytes);
    if (decoded.worker != worker || decoded.iteration != iteration) {
      throw FormatException(
        'Benchmark payload identity mismatch: '
        'expected $worker/$iteration, got ${decoded.worker}/${decoded.iteration}',
      );
    }
    final actual = decoded.body;
    if (actual == null || actual.length != bodyBytes) {
      throw const FormatException('Benchmark payload body length mismatch');
    }
    for (var index = 0; index < bodyBytes; index += 1) {
      final expected = (index * 31 + worker * 17 + iteration * 29) & 0xff;
      if (actual[index] != expected) {
        throw FormatException('Benchmark payload body mismatch at byte $index');
      }
    }
  }

  static bool matchesIdentity(
    Object? value, {
    required String serializer,
    required int worker,
    required int iteration,
  }) {
    if (serializer == 'flatbuffers') {
      if (value is! List<int>) return false;
      try {
        final decoded = decode(value);
        return decoded.worker == worker && decoded.iteration == iteration;
      } on FormatException {
        return false;
      } on RangeError {
        return false;
      }
    }
    if (value is! Map) return false;
    return value['worker'] == worker && value['iteration'] == iteration;
  }

  static void verifyDynamic({
    required Object? value,
    required int worker,
    required int iteration,
    required int bodyBytes,
  }) {
    if (value is! Map ||
        value['worker'] != worker ||
        value['iteration'] != iteration) {
      throw const FormatException('Benchmark payload identity mismatch');
    }
    final actual = value['body'];
    if (actual is! List<int> || actual.length != bodyBytes) {
      throw const FormatException('Benchmark payload body length mismatch');
    }
    for (var index = 0; index < bodyBytes; index += 1) {
      final expected = (index * 31 + worker * 17 + iteration * 29) & 0xff;
      if (actual[index] != expected) {
        throw FormatException('Benchmark payload body mismatch at byte $index');
      }
    }
  }

  static void _checkIdentity(int worker, int iteration) {
    RangeError.checkValueInInterval(worker, 0, 0xffffffff, 'worker');
    RangeError.checkValueInInterval(iteration, 0, 0xffffffff, 'iteration');
  }

  static void _checkFileIdentifier(List<int> bytes) {
    if (bytes.length < 8 ||
        bytes[4] != 0x43 ||
        bytes[5] != 0x42 ||
        bytes[6] != 0x45 ||
        bytes[7] != 0x4e) {
      throw const FormatException('Invalid benchmark FlatBuffers identifier');
    }
  }
}
