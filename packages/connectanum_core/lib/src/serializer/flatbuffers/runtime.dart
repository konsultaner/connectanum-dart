import '../owned_copy_metrics.dart';
import 'dart:typed_data';
import 'dart:collection';

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

/// Retains the exact logical byte range when reading a FlatBuffer.
/// The caller keeps externally owned storage valid for the reader's lifetime.
fb.BufferContext flatBufferContext(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : OwnedCopyMetrics.copyBytes(bytes);
  return fb.BufferContext(ByteData.sublistView(data));
}

fb.BufferContext bufferContext(List<int> bytes) => flatBufferContext(bytes);

/// Reads a byte vector as an immutable view without copying its contents.
///
/// A view of external storage has the same lifetime as that storage. This
/// reader does not extend a database transaction or native buffer lease.
class FlatBufferUint8ListReader extends fb.Reader<List<int>> {
  const FlatBufferUint8ListReader();

  @override
  int get size => 4;

  @override
  @pragma('vm:prefer-inline')
  Uint8List read(fb.BufferContext context, int offset) {
    final data = context.buffer;
    if (offset < 0 || offset > data.lengthInBytes - 4) {
      throw const FormatException('Invalid FlatBuffers byte-vector reference');
    }
    final relative = data.getUint32(offset, Endian.little);
    final vector = offset + relative;
    if (relative < 4 || vector > data.lengthInBytes - 4) {
      throw const FormatException('Invalid FlatBuffers byte-vector offset');
    }
    final length = data.getUint32(vector, Endian.little);
    if (length > data.lengthInBytes - vector - 4) {
      throw const FormatException('FlatBuffers byte vector exceeds its buffer');
    }
    return Uint8List.sublistView(
      data,
      vector + 4,
      vector + 4 + length,
    ).asUnmodifiableView();
  }
}

/// Internal builder with portable uint64 writes and a replaceable allocator.
class WampFlatBufferBuilder extends fb.Builder
    implements CopyObservedByteVectorBuilder {
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

  @override
  int writeListUint8(List<int> values) => _observeByteVector(
    values.length,
    () =>
        tryWriteFlatBufferByteWords(this, values, () => _storage.current!) ??
        super.writeListUint8(values),
  );

  @override
  int writeListInt8(List<int> values) => _observeByteVector(
    values.length,
    () => super.writeListInt8(values),
  );

  int _observeByteVector(int bytes, int Function() write) {
    try {
      final result = write();
      OwnedCopyMetrics.record(OwnedCopyKind.flatBufferVector, bytes);
      return result;
    } catch (_) {
      OwnedCopyMetrics.recordFailedCopy();
      rethrow;
    }
  }

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
  ByteData resize(ByteData data, int size, int back, int front) {
    try {
      current = delegate.resize(data, size, back, front);
    } catch (_) {
      OwnedCopyMetrics.recordFailedCopy();
      rethrow;
    }
    if (delegate.runtimeType == fb.DefaultAllocator) {
      OwnedCopyMetrics.record(OwnedCopyKind.flatBufferGrowth, back + front);
    } else if (delegate is! CopyObservedAllocator) {
      OwnedCopyMetrics.recordUnmeasuredCopy();
    }
    return current!;
  }
}

/// Writes typed byte vectors through the SDK's word loop instead of byte loop.
/// With an aligned existing tail, both reserve 4 + roundUp(length, 4) bytes;
/// only their length headers differ. Patch that header in the latest allocation.
/// Return null before writes when the ordinary byte writer is required.
int? tryWriteFlatBufferByteWords(
  fb.Builder builder,
  List<int> values,
  ByteData Function() currentStorage,
) {
  if (values is! Uint8List || values.length < 256 || builder.offset % 4 != 0) {
    return null;
  }
  final result = builder.writeListUint32(_LittleEndianByteWords(values));
  final data = currentStorage();
  data.setUint32(data.lengthInBytes - result, values.length, Endian.little);
  return result;
}

class _LittleEndianByteWords extends ListBase<int> {
  _LittleEndianByteWords(Uint8List bytes)
    : _data = ByteData.sublistView(bytes),
      _length = (bytes.length + 3) ~/ 4;
  final ByteData _data;
  final int _length;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Read-only word view');
  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this, null, _length);
    final start = index * 4;
    final remaining = _data.lengthInBytes - start;
    if (remaining >= 4) return _data.getUint32(start, Endian.little);
    var value = 0;
    for (var byte = 0; byte < remaining; byte++) {
      value |= _data.getUint8(start + byte) << (byte * 8);
    }
    return value;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read-only word view');
}
