import 'dart:typed_data';

import 'package:flat_buffers/flat_buffers.dart' as fb;

const _wordBase = 4294967296;
// WAMP IDs include 2^53 itself, which is exactly representable in JavaScript.
const _maximumWampInteger = 9007199254740992;

/// Preserve uint64 wire bits using operations supported by dart2js.
class WampUint64Reader extends fb.Reader<int> {
  const WampUint64Reader();

  @override
  int get size => 8;

  @override
  int read(fb.BufferContext context, int offset) {
    final low = context.buffer.getUint32(offset, Endian.little);
    final high = context.buffer.getUint32(offset + 4, Endian.little);
    if (high > 0x200000 || (high == 0x200000 && low != 0)) {
      throw const FormatException(
        'FlatBuffers integer exceeds the WAMP ID range',
      );
    }
    return high * _wordBase + low;
  }
}

fb.BufferContext bufferContext(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  return fb.BufferContext(ByteData.sublistView(data));
}

/// Internal builder with portable uint64 writes and a replaceable allocator.
class WampFlatBufferBuilder extends fb.Builder {
  factory WampFlatBufferBuilder({
    int initialSize = 1024,
    bool internStrings = false,
    fb.Allocator allocator = const fb.DefaultAllocator(),
    bool deduplicateTables = true,
  }) => WampFlatBufferBuilder._(
    _TrackingAllocator(allocator),
    initialSize,
    internStrings,
    deduplicateTables,
  );

  WampFlatBufferBuilder._(
    this._storage,
    int initialSize,
    bool internStrings,
    bool deduplicateTables,
  ) : super(
        initialSize: initialSize,
        internStrings: internStrings,
        allocator: _storage,
        deduplicateTables: deduplicateTables,
      );

  final _TrackingAllocator _storage;

  static void _validate(int value) {
    if (value < 0 || value > _maximumWampInteger) {
      throw ArgumentError.value(
        value,
        'value',
        'Outside the WAMP ID range',
      );
    }
  }

  @override
  void putUint64(int value) {
    _validate(value);
    // Reserve exactly eight bytes with eight-byte alignment. Store integer
    // bits with two Uint32 writes; a Float64 numeric value is never the wire ID.
    super.putFloat64(0);
    final data = _storage.current!;
    final position = data.lengthInBytes - offset;
    data.setUint32(position, value % _wordBase, Endian.little);
    data.setUint32(position + 4, value ~/ _wordBase, Endian.little);
  }

  @override
  void addUint64(int field, int? value, [double? def]) {
    if (value != null && value != def) {
      putUint64(value);
      addStruct(field, offset);
    }
  }

  @override
  int writeListUint64(List<int> values) {
    // Validate first so an invalid input does not leave a half-written vector.
    for (final value in values) {
      _validate(value);
    }
    if (values.isEmpty) {
      // Establish uint64 vector alignment even when no elements are present.
      super.putFloat64(0);
    } else {
      for (var i = values.length - 1; i >= 0; i--) {
        putUint64(values[i]);
      }
    }
    putUint32(values.length);
    return offset;
  }
}

class _TrackingAllocator extends fb.Allocator {
  _TrackingAllocator(this.delegate);

  final fb.Allocator delegate;
  ByteData? current;

  @override
  ByteData allocate(int size) => current = delegate.allocate(size);

  @override
  void deallocate(ByteData data) {
    delegate.deallocate(data);
    if (identical(current, data)) current = null;
  }

  @override
  ByteData resize(ByteData data, int size, int back, int front) =>
      current = delegate.resize(data, size, back, front);
}
