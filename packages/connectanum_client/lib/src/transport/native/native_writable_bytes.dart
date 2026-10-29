part of '../../../native_buffers.dart';

/// A mutable range available only inside a native builder's fill callback.
///
/// This exposes no raw pointer, typed-data view or backing buffer. Store values
/// directly, or copy existing bytes with [writeBytes]. All word writers created
/// here close with this range, including when a callback throws or returns a
/// Future. Retaining a writer does not extend its writable lifetime.
final class NativeWritableBytes implements ffi.Finalizable {
  NativeWritableBytes._(this._data, this._copyKind);
  final ByteData _data;
  final OwnedCopyKind _copyKind;
  bool _live = true;
  bool _copyFailed = false;
  int _inputCopiedBytes = 0;
  NativeUint32Writer? _firstWords;
  List<NativeUint32Writer>? _otherWords;

  int get length => _data.lengthInBytes;

  void _check() {
    if (!_live || _copyFailed) throw StateError('Native byte writer is closed');
  }

  void _initialize<T>(T Function(NativeWritableBytes) fill) {
    final result = fill(this);
    if (result is Future) {
      throw ArgumentError('Native initialization must be synchronous');
    }
    if (_copyFailed) throw StateError('Native input copy failed');
  }

  void _clear() => _data.buffer
      .asUint8List(_data.offsetInBytes, length)
      .fillRange(0, length, 0);

  void _close() {
    _live = false;
    _firstWords?._close();
    for (final words in _otherWords ?? const <NativeUint32Writer>[]) {
      words._close();
    }
  }

  void setUint8(int offset, int value) {
    _check();
    _data.setUint8(offset, value);
  }

  void setUint32(int offset, int value, [Endian endian = Endian.little]) {
    _check();
    _data.setUint32(offset, value, endian);
  }

  void setUint64(int offset, int value, [Endian endian = Endian.little]) {
    _check();
    _data.setUint64(offset, value, endian);
  }

  /// Copy source bytes into this range and record the completed input copy.
  void writeBytes(int offset, List<int> source) {
    _check();
    try {
      final count = source.length;
      RangeError.checkValidRange(offset, offset + count, length);
      _data.buffer
          .asUint8List(_data.offsetInBytes, length)
          .setRange(offset, offset + count, source);
      _inputCopiedBytes += count;
      OwnedCopyMetrics.record(_copyKind, count);
    } catch (_) {
      _copyFailed = true;
      OwnedCopyMetrics.recordFailedCopy();
      rethrow;
    }
  }

  /// A bounded word writer with the same callback lifetime as this range.
  /// Supports unaligned storage and either byte order without exposing a view.
  NativeUint32Writer uint32Words({
    int offset = 0,
    required int count,
    Endian endian = Endian.little,
  }) {
    _check();
    RangeError.checkValidRange(offset, offset, length);
    RangeError.checkValueInInterval(count, 0, (length - offset) ~/ 4, 'count');
    final absolute = _data.offsetInBytes + offset;
    final NativeUint32Writer writer;
    if (endian == Endian.host && (absolute & 3) == 0) {
      writer = _AlignedNativeUint32Writer(
        _data.buffer.asUint32List(absolute, count),
      );
    } else {
      writer = _UnalignedNativeUint32Writer(
        ByteData.sublistView(_data, offset, offset + count * 4),
        endian,
      );
    }
    if (_firstWords == null) {
      _firstWords = writer;
    } else {
      (_otherWords ??= []).add(writer);
    }
    return writer;
  }
}

/// Indexed uint32 stores confined to their native fill callback.
/// Indexing is in words. This type provides no typed-data or pointer access.
sealed class NativeUint32Writer implements ffi.Finalizable {
  NativeUint32Writer._(this.length);
  final int length;
  bool _live = true;
  void operator []=(int index, int value);
  void _close() => _live = false;
}

final class _AlignedNativeUint32Writer extends NativeUint32Writer {
  _AlignedNativeUint32Writer(this._data) : super._(_data.length);
  final Uint32List _data;

  @override
  @pragma('vm:prefer-inline')
  void operator []=(int index, int value) {
    if (!_live) throw StateError('Native word writer is closed');
    _data[index] = value;
  }
}

final class _UnalignedNativeUint32Writer extends NativeUint32Writer {
  _UnalignedNativeUint32Writer(this._data, this._endian)
    : super._(_data.lengthInBytes ~/ 4);
  final ByteData _data;
  final Endian _endian;

  @override
  void operator []=(int index, int value) {
    if (!_live) throw StateError('Native word writer is closed');
    // Check before multiplication so a large index cannot wrap into this range.
    RangeError.checkValidIndex(index, this, 'index', length);
    _data.setUint32(index * 4, value, _endian);
  }
}
