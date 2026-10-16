// Derived from flat_buffers 25.9.23, dart/lib/flat_buffers.dart.
// Upstream Git blob: 7590bdba690c594fe095273d0f1ab110a7960475.
// Apache-2.0 license: upstream/flat_buffers.LICENSE.
// The standard Builder interface is preserved. Changes bulk-copy byte vectors,
// encode bools directly, and observe explicit UTF8 staging. Keep the provenance
// and SDK wire/allocation parity checks when updating this implementation.
// ignore_for_file: annotate_overrides

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:flat_buffers/flat_buffers.dart'
    show Allocator, DefaultAllocator, ObjectBuilder;
import '../owned_copy_metrics.dart';

const int _sizeofUint8 = 1;
const int _sizeofUint16 = 2;
const int _sizeofUint32 = 4;
const int _sizeofUint64 = 8;
const int _sizeofInt8 = 1;
const int _sizeofInt16 = 2;
const int _sizeofInt32 = 4;
const int _sizeofInt64 = 8;
const int _sizeofFloat32 = 4;
const int _sizeofFloat64 = 8;

class ByteViewFlatBufferBuilder implements fb.Builder {
  bool _finished = false;

  final int initialSize;

  /// The list of existing VTable(s).
  final List<int> _vTables;

  final bool deduplicateTables;

  ByteData _buf;

  final Allocator _allocator;

  /// The maximum alignment that has been seen so far.  If [_buf] has to be
  /// reallocated in the future (to insert room at its start for more bytes) the
  /// reallocation will need to be a multiple of this many bytes.
  int _maxAlign = 1;

  /// The number of bytes that have been written to the buffer so far.  The
  /// most recently written byte is this many bytes from the end of [_buf].
  int _tail = 0;

  /// The location of the end of the current table, measured in bytes from the
  /// end of [_buf].
  int _currentTableEndTail = 0;

  _VTable? _currentVTable;

  /// Map containing all strings that have been written so far.  This allows us
  /// to avoid duplicating strings.
  ///
  /// Allocated only if `internStrings` is set to true on the constructor.
  Map<String, int>? _strings;

  /// Creates a new FlatBuffers ByteViewFlatBufferBuilder.
  ///
  /// `initialSize` is the initial array size in bytes.  The [ByteViewFlatBufferBuilder] will
  /// automatically grow the array if/as needed.  `internStrings`, if set to
  /// true, will cause [writeString] to pool strings in the buffer so that
  /// identical strings will always use the same offset in tables.
  ByteViewFlatBufferBuilder({
    this.initialSize = 1024,
    bool internStrings = false,
    Allocator allocator = const DefaultAllocator(),
    this.deduplicateTables = true,
  }) : _allocator = allocator,
       _buf = allocator.allocate(initialSize),
       _vTables = deduplicateTables ? [] : const [] {
    if (internStrings) {
      _strings = <String, int>{};
    }
  }

  /// Calculate the finished buffer size (aligned).
  @pragma('vm:prefer-inline')
  int size() => _tail + ((-_tail) & (_maxAlign - 1));

  /// Add the [field] with the given boolean [value].  The field is not added if
  /// the [value] is equal to [def].  Booleans are stored as 8-bit fields with
  /// `0` for `false` and `1` for `true`.
  void addBool(int field, bool? value, [bool? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofUint8, 1);
      _trackField(field);
      _buf.setInt8(_buf.lengthInBytes - _tail, value ? 1 : 0);
    }
  }

  /// Add the [field] with the given 32-bit signed integer [value].  The field is
  /// not added if the [value] is equal to [def].
  void addInt32(int field, int? value, [int? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofInt32, 1);
      _trackField(field);
      _setInt32AtTail(_tail, value);
    }
  }

  /// Add the [field] with the given 32-bit signed integer [value].  The field is
  /// not added if the [value] is equal to [def].
  void addInt16(int field, int? value, [int? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofInt16, 1);
      _trackField(field);
      _setInt16AtTail(_tail, value);
    }
  }

  /// Add the [field] with the given 8-bit signed integer [value].  The field is
  /// not added if the [value] is equal to [def].
  void addInt8(int field, int? value, [int? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofInt8, 1);
      _trackField(field);
      _setInt8AtTail(_tail, value);
    }
  }

  void addStruct(int field, int offset) {
    assert(_inVTable);
    _trackField(field);
    _currentVTable!.addField(field, offset);
  }

  /// Add the [field] referencing an object with the given [offset].
  void addOffset(int field, int? offset) {
    assert(_inVTable);
    if (offset != null) {
      _prepare(_sizeofUint32, 1);
      _trackField(field);
      _setUint32AtTail(_tail, _tail - offset);
    }
  }

  /// Add the [field] with the given 32-bit unsigned integer [value].  The field
  /// is not added if the [value] is equal to [def].
  void addUint32(int field, int? value, [int? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofUint32, 1);
      _trackField(field);
      _setUint32AtTail(_tail, value);
    }
  }

  /// Add the [field] with the given 32-bit unsigned integer [value].  The field
  /// is not added if the [value] is equal to [def].
  void addUint16(int field, int? value, [int? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofUint16, 1);
      _trackField(field);
      _setUint16AtTail(_tail, value);
    }
  }

  /// Add the [field] with the given 8-bit unsigned integer [value].  The field
  /// is not added if the [value] is equal to [def].
  void addUint8(int field, int? value, [int? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofUint8, 1);
      _trackField(field);
      _setUint8AtTail(_tail, value);
    }
  }

  /// Add the [field] with the given 32-bit float [value].  The field
  /// is not added if the [value] is equal to [def].
  void addFloat32(int field, double? value, [double? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofFloat32, 1);
      _trackField(field);
      _setFloat32AtTail(_tail, value);
    }
  }

  /// Add the [field] with the given 64-bit double [value].  The field
  /// is not added if the [value] is equal to [def].
  void addFloat64(int field, double? value, [double? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofFloat64, 1);
      _trackField(field);
      _setFloat64AtTail(_tail, value);
    }
  }

  /// Add the [field] with the given 64-bit unsigned integer [value].  The field
  /// is not added if the [value] is equal to [def].
  void addUint64(int field, int? value, [double? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofUint64, 1);
      _trackField(field);
      _setUint64AtTail(_tail, value);
    }
  }

  /// Add the [field] with the given 64-bit unsigned integer [value].  The field
  /// is not added if the [value] is equal to [def].
  void addInt64(int field, int? value, [double? def]) {
    assert(_inVTable);
    if (value != null && value != def) {
      _prepare(_sizeofInt64, 1);
      _trackField(field);
      _setInt64AtTail(_tail, value);
    }
  }

  /// End the current table and return its offset.
  int endTable() {
    assert(_inVTable);
    // Prepare for writing the VTable.
    _prepare(_sizeofInt32, 1);
    final tableTail = _tail;
    // Prepare the size of the current table.
    final currentVTable = _currentVTable!;
    currentVTable.tableSize = tableTail - _currentTableEndTail;
    // Prepare the VTable to use for the current table.
    int? vTableTail;
    {
      currentVTable.computeFieldOffsets(tableTail);

      // Try to find an existing compatible VTable.
      if (deduplicateTables) {
        // Search backward - more likely to have recently used one
        for (var i = _vTables.length - 1; i >= 0; i--) {
          final vt2Offset = _vTables[i];
          final vt2Start = _buf.lengthInBytes - vt2Offset;
          final vt2Size = _buf.getUint16(vt2Start, Endian.little);

          if (currentVTable._vTableSize == vt2Size &&
              currentVTable._offsetsMatch(vt2Start, _buf)) {
            vTableTail = vt2Offset;
            break;
          }
        }
      }

      // Write a new VTable.
      if (vTableTail == null) {
        _prepare(_sizeofUint16, _currentVTable!.numOfUint16);
        vTableTail = _tail;
        currentVTable.tail = vTableTail;
        currentVTable.output(_buf, _buf.lengthInBytes - _tail);
        if (deduplicateTables) _vTables.add(currentVTable.tail);
      }
    }
    // Set the VTable offset.
    _setInt32AtTail(tableTail, vTableTail - tableTail);
    // Done with this table.
    _currentVTable = null;
    return tableTail;
  }

  /// Returns the finished buffer. You must call [finish] before accessing this.
  @pragma('vm:prefer-inline')
  Uint8List get buffer {
    assert(_finished);
    final finishedSize = size();
    return _buf.buffer.asUint8List(
      _buf.lengthInBytes - finishedSize,
      finishedSize,
    );
  }

  /// Finish off the creation of the buffer.  The given [offset] is used as the
  /// root object offset, and usually references directly or indirectly every
  /// written object.  If [fileIdentifier] is specified (and not `null`), it is
  /// interpreted as a 4-byte Latin-1 encoded string that should be placed at
  /// bytes 4-7 of the file.
  void finish(int offset, [String? fileIdentifier]) {
    final sizeBeforePadding = size();
    final requiredBytes = _sizeofUint32 * (fileIdentifier == null ? 1 : 2);
    _prepare(max(requiredBytes, _maxAlign), 1);
    final finishedSize = size();
    _setUint32AtTail(finishedSize, finishedSize - offset);
    if (fileIdentifier != null) {
      for (var i = 0; i < 4; i++) {
        _setUint8AtTail(
          finishedSize - _sizeofUint32 - i,
          fileIdentifier.codeUnitAt(i),
        );
      }
    }

    // zero out the added padding
    for (
      var i = sizeBeforePadding + 1;
      i <= finishedSize - requiredBytes;
      i++
    ) {
      _setUint8AtTail(i, 0);
    }
    _finished = true;
  }

  /// Writes a Float64 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putFloat64(double value) {
    _prepare(_sizeofFloat64, 1);
    _setFloat64AtTail(_tail, value);
  }

  /// Writes a Float32 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putFloat32(double value) {
    _prepare(_sizeofFloat32, 1);
    _setFloat32AtTail(_tail, value);
  }

  /// Writes a bool to the tail of the buffer after preparing space for it.
  /// Bools are represented as a Uint8, with the value set to '1' for true, and '0' for false
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putBool(bool value) {
    _prepare(_sizeofUint8, 1);
    _buf.setInt8(_buf.lengthInBytes - _tail, value ? 1 : 0);
  }

  /// Writes a Int64 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putInt64(int value) {
    _prepare(_sizeofInt64, 1);
    _setInt64AtTail(_tail, value);
  }

  /// Writes a Uint32 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putInt32(int value) {
    _prepare(_sizeofInt32, 1);
    _setInt32AtTail(_tail, value);
  }

  /// Writes a Uint16 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putInt16(int value) {
    _prepare(_sizeofInt16, 1);
    _setInt16AtTail(_tail, value);
  }

  /// Writes a Uint8 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putInt8(int value) {
    _prepare(_sizeofInt8, 1);
    _buf.setInt8(_buf.lengthInBytes - _tail, value);
  }

  /// Writes a Uint64 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putUint64(int value) {
    _prepare(_sizeofUint64, 1);
    _setUint64AtTail(_tail, value);
  }

  /// Writes a Uint32 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putUint32(int value) {
    _prepare(_sizeofUint32, 1);
    _setUint32AtTail(_tail, value);
  }

  /// Writes a Uint16 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putUint16(int value) {
    _prepare(_sizeofUint16, 1);
    _setUint16AtTail(_tail, value);
  }

  /// Writes a Uint8 to the tail of the buffer after preparing space for it.
  ///
  /// Updates the [offset] pointer.  This method is intended for use when writing structs to the buffer.
  void putUint8(int value) {
    _prepare(_sizeofUint8, 1);
    _buf.setUint8(_buf.lengthInBytes - _tail, value);
  }

  /// Reset the builder and make it ready for filling a new buffer.
  void reset() {
    _finished = false;
    _maxAlign = 1;
    _tail = 0;
    _currentVTable = null;
    if (deduplicateTables) _vTables.clear();
    if (_strings != null) {
      _strings = <String, int>{};
    }
  }

  /// Start a new table. Must be finished with [endTable] invocation.
  void startTable(int numFields) {
    assert(!_inVTable); // Inline tables are not supported.
    _currentVTable = _VTable(numFields);
    _currentTableEndTail = _tail;
  }

  /// Finish a Struct vector.  Most callers should preferto use [writeListOfStructs].
  ///
  /// Most callers should prefer [writeListOfStructs].
  int endStructVector(int count) {
    putUint32(count);
    return _tail;
  }

  /// Writes a list of Structs to the buffer, returning the offset
  int writeListOfStructs(List<ObjectBuilder> structBuilders) {
    assert(!_inVTable);
    for (var i = structBuilders.length - 1; i >= 0; i--) {
      structBuilders[i].finish(this);
    }
    return endStructVector(structBuilders.length);
  }

  /// Write the given list of [values].
  int writeList(List<int> values) {
    assert(!_inVTable);
    _prepare(_sizeofUint32, 1 + values.length);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setUint32AtTail(tail, tail - value);
      tail -= _sizeofUint32;
    }
    return result;
  }

  /// Write the given list of 64-bit float [values].
  int writeListFloat64(List<double> values) {
    assert(!_inVTable);
    _prepare(_sizeofFloat64, values.length, additionalBytes: _sizeofUint32);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setFloat64AtTail(tail, value);
      tail -= _sizeofFloat64;
    }
    return result;
  }

  /// Write the given list of 32-bit float [values].
  int writeListFloat32(List<double> values) {
    assert(!_inVTable);
    _prepare(_sizeofFloat32, 1 + values.length);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setFloat32AtTail(tail, value);
      tail -= _sizeofFloat32;
    }
    return result;
  }

  /// Write the given list of signed 64-bit integer [values].
  int writeListInt64(List<int> values) {
    assert(!_inVTable);
    _prepare(_sizeofInt64, values.length, additionalBytes: _sizeofUint32);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setInt64AtTail(tail, value);
      tail -= _sizeofInt64;
    }
    return result;
  }

  /// Write the given list of signed 64-bit integer [values].
  int writeListUint64(List<int> values) {
    assert(!_inVTable);
    _prepare(_sizeofUint64, values.length, additionalBytes: _sizeofUint32);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setUint64AtTail(tail, value);
      tail -= _sizeofUint64;
    }
    return result;
  }

  /// Write the given list of signed 32-bit integer [values].
  int writeListInt32(List<int> values) {
    assert(!_inVTable);
    _prepare(_sizeofUint32, 1 + values.length);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setInt32AtTail(tail, value);
      tail -= _sizeofInt32;
    }
    return result;
  }

  /// Write the given list of unsigned 32-bit integer [values].
  int writeListUint32(List<int> values) {
    assert(!_inVTable);
    _prepare(_sizeofUint32, 1 + values.length);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setUint32AtTail(tail, value);
      tail -= _sizeofUint32;
    }
    return result;
  }

  /// Write the given list of signed 16-bit integer [values].
  int writeListInt16(List<int> values) {
    assert(!_inVTable);
    _prepare(_sizeofUint32, 1, additionalBytes: 2 * values.length);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setInt16AtTail(tail, value);
      tail -= _sizeofInt16;
    }
    return result;
  }

  /// Write the given list of unsigned 16-bit integer [values].
  int writeListUint16(List<int> values) {
    assert(!_inVTable);
    _prepare(_sizeofUint32, 1, additionalBytes: 2 * values.length);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setUint16AtTail(tail, value);
      tail -= _sizeofUint16;
    }
    return result;
  }

  /// Write the given list of bools as unsigend 8-bit integer [values].
  int writeListBool(List<bool> values) {
    assert(!_inVTable);
    _prepare(_sizeofUint32, 1, additionalBytes: values.length);
    final result = _tail;
    _setUint32AtTail(result, values.length);
    var tail = result - _sizeofUint32;
    for (final value in values) {
      _setUint8AtTail(tail, value ? 1 : 0);
      tail -= _sizeofUint8;
    }
    return result;
  }

  /// Write the given list of signed 8-bit integer [values].
  int writeListInt8(List<int> values) {
    assert(!_inVTable);
    _prepare(_sizeofUint32, 1, additionalBytes: values.length);
    final result = _tail;
    var tail = _tail;
    _setUint32AtTail(tail, values.length);
    tail -= _sizeofUint32;
    for (final value in values) {
      _setInt8AtTail(tail, value);
      tail -= _sizeofUint8;
    }
    return result;
  }

  /// Write the given list of unsigned 8-bit integer [values].
  int writeListUint8(List<int> values) {
    assert(!_inVTable);
    final bulk =
        values is Uint8List &&
        values.length >= 256 &&
        values.buffer != _buf.buffer;
    _prepare(_sizeofUint32, 1, additionalBytes: values.length);
    final result = _tail;
    _setUint32AtTail(result, values.length);
    if (bulk) {
      _buf.buffer
          .asUint8List(
            _buf.offsetInBytes + _buf.lengthInBytes - result + 4,
            values.length,
          )
          .setAll(0, values);
    } else {
      var tail = result - _sizeofUint32;
      for (final value in values) {
        _setUint8AtTail(tail, value);
        tail -= _sizeofUint8;
      }
    }
    return result;
  }

  /// Write the given string [value] and return its offset.
  ///
  /// Dart strings are UTF-16 but must be stored as UTF-8 in FlatBuffers.
  /// If the given string consists only of ASCII characters, you can indicate
  /// enable [asciiOptimization]. In this mode, [writeString()] first tries to
  /// copy the ASCII string directly to the output buffer and if that fails
  /// (because there are no-ASCII characters in the string) it falls back and to
  /// the default UTF-16 -> UTF-8 conversion (with slight performance penalty).
  int writeString(String value, {bool asciiOptimization = false}) {
    assert(!_inVTable);
    if (_strings != null) {
      return _strings!.putIfAbsent(
        value,
        () => _writeString(value, asciiOptimization),
      );
    } else {
      return _writeString(value, asciiOptimization);
    }
  }

  int _writeString(String value, bool asciiOptimization) {
    if (asciiOptimization) {
      // [utf8.encode()] is slow (up to at least Dart SDK 2.13). If the given
      // string is ASCII we can just write it directly, without any conversion.
      final originalTail = _tail;
      if (_tryWriteASCIIString(value)) return _tail;
      // if non-ASCII: reset the output buffer position for [_writeUTFString()]
      _tail = originalTail;
    }
    _writeUTFString(value);
    return _tail;
  }

  // Try to write the string as ASCII, return false if there's a non-ascii char.
  @pragma('vm:prefer-inline')
  bool _tryWriteASCIIString(String value) {
    _prepare(4, 1, additionalBytes: value.length + 1);
    final length = value.length;
    var offset = _buf.lengthInBytes - _tail + 4;
    for (var i = 0; i < length; i++) {
      // utf16 code unit, e.g. for '†' it's [0x20 0x20], which is 8224 decimal.
      // ASCII characters go from 0x00 to 0x7F (which is 0 to 127 decimal).
      final char = value.codeUnitAt(i);
      if ((char & ~0x7F) != 0) {
        return false;
      }
      _buf.setUint8(offset++, char);
    }
    _buf.setUint8(offset, 0); // trailing zero
    _setUint32AtTail(_tail, value.length);
    return true;
  }

  @pragma('vm:prefer-inline')
  void _writeUTFString(String value) {
    final bytes = utf8.encode(value);
    final length = bytes.length;
    try {
      _prepare(4, 1, additionalBytes: length + 1);
      _setUint32AtTail(_tail, length);
      var offset = _buf.lengthInBytes - _tail + 4;
      for (var i = 0; i < length; i++) {
        _buf.setUint8(offset++, bytes[i]);
      }
      _buf.setUint8(offset, 0); // trailing zero
    } catch (_) {
      OwnedCopyMetrics.recordDedicatedFailure();
      rethrow;
    }
    // This encoded-byte staging is distinct from an enclosing PPT wrapper's
    // source copies and remains observable inside its synchronous scope.
    OwnedCopyMetrics.recordDedicated(OwnedCopyKind.framing, length);
  }

  /// Used to assert whether a "Table" is currently being built.
  ///
  /// If you hit `assert(!_inVTable())`, you're trying to add table fields
  /// without starting a table with [ByteViewFlatBufferBuilder.startTable()].
  ///
  /// If you hit `assert(_inVTable())`, you're trying to construct a
  /// Table/Vector/String during the construction of its parent table,
  /// between the MyTableBuilder and [ByteViewFlatBufferBuilder.endTable()].
  /// Move the creation of these sub-objects to before the MyTableBuilder to
  /// not get this assert.
  @pragma('vm:prefer-inline')
  bool get _inVTable => _currentVTable != null;

  /// The number of bytes that have been written to the buffer so far.  The
  /// most recently written byte is this many bytes from the end of the buffer.
  @pragma('vm:prefer-inline')
  int get offset => _tail;

  /// Zero-pads the buffer, which may be required for some struct layouts.
  @pragma('vm:prefer-inline')
  void pad(int howManyBytes) {
    for (var i = 0; i < howManyBytes; i++) {
      putUint8(0);
    }
  }

  /// Prepare for writing the given `count` of scalars of the given `size`.
  /// Additionally allocate the specified `additionalBytes`. Update the current
  /// tail pointer to point at the allocated space.
  @pragma('vm:prefer-inline')
  void _prepare(int size, int count, {int additionalBytes = 0}) {
    assert(!_finished);
    // Update the alignment.
    if (_maxAlign < size) {
      _maxAlign = size;
    }
    // Prepare amount of required space.
    final dataSize = size * count + additionalBytes;
    final alignDelta = (-(_tail + dataSize)) & (size - 1);
    final bufSize = alignDelta + dataSize;
    // Ensure that we have the required amount of space.
    {
      final oldCapacity = _buf.lengthInBytes;
      if (_tail + bufSize > oldCapacity) {
        final desiredNewCapacity = (oldCapacity + bufSize) * 2;
        var deltaCapacity = desiredNewCapacity - oldCapacity;
        deltaCapacity += (-deltaCapacity) & (_maxAlign - 1);
        final newCapacity = oldCapacity + deltaCapacity;
        _buf = _allocator.resize(_buf, newCapacity, _tail, 0);
      }
    }

    // zero out the added padding
    for (var i = _tail + 1; i <= _tail + alignDelta; i++) {
      _setUint8AtTail(i, 0);
    }

    // Update the tail pointer.
    _tail += bufSize;
  }

  /// Record the offset of the given [field].
  @pragma('vm:prefer-inline')
  void _trackField(int field) => _currentVTable!.addField(field, _tail);

  @pragma('vm:prefer-inline')
  void _setFloat64AtTail(int tail, double x) =>
      _buf.setFloat64(_buf.lengthInBytes - tail, x, Endian.little);

  @pragma('vm:prefer-inline')
  void _setFloat32AtTail(int tail, double x) =>
      _buf.setFloat32(_buf.lengthInBytes - tail, x, Endian.little);

  @pragma('vm:prefer-inline')
  void _setUint64AtTail(int tail, int x) =>
      _buf.setUint64(_buf.lengthInBytes - tail, x, Endian.little);

  @pragma('vm:prefer-inline')
  void _setInt64AtTail(int tail, int x) =>
      _buf.setInt64(_buf.lengthInBytes - tail, x, Endian.little);

  @pragma('vm:prefer-inline')
  void _setInt32AtTail(int tail, int x) =>
      _buf.setInt32(_buf.lengthInBytes - tail, x, Endian.little);

  @pragma('vm:prefer-inline')
  void _setUint32AtTail(int tail, int x) =>
      _buf.setUint32(_buf.lengthInBytes - tail, x, Endian.little);

  @pragma('vm:prefer-inline')
  void _setInt16AtTail(int tail, int x) =>
      _buf.setInt16(_buf.lengthInBytes - tail, x, Endian.little);

  @pragma('vm:prefer-inline')
  void _setUint16AtTail(int tail, int x) =>
      _buf.setUint16(_buf.lengthInBytes - tail, x, Endian.little);

  @pragma('vm:prefer-inline')
  void _setInt8AtTail(int tail, int x) =>
      _buf.setInt8(_buf.lengthInBytes - tail, x);

  @pragma('vm:prefer-inline')
  void _setUint8AtTail(int tail, int x) =>
      _buf.setUint8(_buf.lengthInBytes - tail, x);
}

class _VTable {
  static const int _metadataLength = 4;

  final int numFields;

  // Note: fieldOffsets start as "tail offsets" and are then transformed by
  // [computeFieldOffsets()] to actual offsets when a table is finished.
  final Uint32List fieldOffsets;
  bool offsetsComputed = false;

  _VTable(this.numFields) : fieldOffsets = Uint32List(numFields);

  /// The size of the table that uses this VTable.
  int tableSize = 0;

  /// The tail of this VTable. It is used to share the same VTable between
  /// multiple tables of identical structure.
  int tail = 0;

  int get _vTableSize => numOfUint16 * _sizeofUint16;

  int get numOfUint16 => 1 + 1 + numFields;

  @pragma('vm:prefer-inline')
  void addField(int field, int offset) {
    assert(!offsetsComputed);
    assert(offset > 0); // it's impossible for field to start at the buffer end
    assert(offset <= 4294967295); // uint32 max
    fieldOffsets[field] = offset;
  }

  @pragma('vm:prefer-inline')
  bool _offsetsMatch(int vt2Start, ByteData buf) {
    assert(offsetsComputed);
    for (var i = 0; i < numFields; i++) {
      if (fieldOffsets[i] !=
          buf.getUint16(vt2Start + _metadataLength + (2 * i), Endian.little)) {
        return false;
      }
    }
    return true;
  }

  /// Fill the [fieldOffsets] field.
  @pragma('vm:prefer-inline')
  void computeFieldOffsets(int tableTail) {
    assert(!offsetsComputed);
    offsetsComputed = true;
    for (var i = 0; i < numFields; i++) {
      if (fieldOffsets[i] != 0) {
        fieldOffsets[i] = tableTail - fieldOffsets[i];
      }
    }
  }

  /// Outputs this VTable to [buf], which is is expected to be aligned to 16-bit
  /// and have at least [numOfUint16] 16-bit words available.
  @pragma('vm:prefer-inline')
  void output(ByteData buf, int bufOffset) {
    assert(offsetsComputed);
    // VTable size.
    buf.setUint16(bufOffset, numOfUint16 * 2, Endian.little);
    bufOffset += 2;
    // Table size.
    buf.setUint16(bufOffset, tableSize, Endian.little);
    bufOffset += 2;
    // Field offsets.
    for (var i = 0; i < numFields; i++) {
      buf.setUint16(bufOffset, fieldOffsets[i], Endian.little);
      bufOffset += 2;
    }
  }
}
