// Isolated native counters keep other test files from affecting leak assertions.
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'package:connectanum_client/native_buffers.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;

typedef _CountNative = UintPtr Function();
typedef _Count = int Function();

int populate(fb.Builder builder) {
  final offsets = <int>[];
  for (var i = 0; i < 32; i++) {
    offsets.add(
      builder.writeString('field.$i.${List.filled(i + 1, 'x').join()}'),
    );
  }
  builder.startTable(offsets.length);
  for (var i = 0; i < offsets.length; i++) {
    builder.addOffset(i, offsets[i]);
  }
  return builder.endTable();
}

void main() {
  final library = DynamicLibrary.open(
    Platform.environment['CONNECTANUM_NATIVE_LIB']!,
  );
  final allocations = library.lookupFunction<_CountNative, _Count>(
    'ct_test_owned_buffer_live_allocations',
  );
  final handles = library.lookupFunction<_CountNative, _Count>(
    'ct_test_owned_buffer_live_handles',
  );
  final allocator = NativeBufferAllocator(library);
  void balanced(String name) {
    if (allocations() != 0 || handles() != 0) {
      throw StateError('$name leaked native allocations/handles');
    }
  }

  balanced('initial');
  {
    final builder = allocator.flatBuffers(initialSize: 8);
    builder.finish(populate(builder), 'OWNR');
    if (builder.allocationCount < 3) {
      throw StateError('Probe did not exercise repeated growth');
    }
    final owner = builder.freeze();
    builder.dispose();
    if (allocations() != 1 || handles() != 1) {
      throw StateError('Frozen owner lost native storage');
    }
    owner.dispose();
    builder.dispose();
    balanced('repeated growth then freeze');
  }
  {
    final builder = allocator.flatBuffers(initialSize: 8);
    final failure = StateError('input failure after growth');
    try {
      builder.writeListUint8(_ThrowingBytes(failure));
      throw StateError('Input failure was not propagated');
    } catch (error) {
      if (!identical(error, failure)) rethrow;
    }
    if (builder.allocationCount < 2) {
      throw StateError('Probe did not grow before input failure');
    }
    builder.dispose();
    builder.dispose();
    balanced('failed input after growth');
  }
  {
    final builder = allocator.flatBuffers(initialSize: 8);
    populate(builder);
    builder.reset();
    builder.finish(populate(builder), 'OWNR');
    final owner = builder.freeze();
    builder.dispose();
    owner.dispose();
    balanced('reset after repeated growth');
  }
  print(
    'native-allocator-growth: frozen, failed-input and reset paths release all owners',
  );
}

class _ThrowingBytes extends ListBase<int> {
  _ThrowingBytes(this.failure);
  final StateError failure;
  @override
  int get length => 4096;
  @override
  set length(int value) => throw UnsupportedError('Fixed input');
  @override
  int operator [](int index) {
    if (index == 17) throw failure;
    return index & 255;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read only');
}
