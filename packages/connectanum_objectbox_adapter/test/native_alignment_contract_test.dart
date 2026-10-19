// Probe the actual C reader independently of the adapter's staging decision.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_objectbox_adapter/src/native_compat.dart';
import 'package:ffi/ffi.dart';
import 'package:objectbox/objectbox.dart';
import 'package:test/test.dart';

import 'support/model.dart';

void main() {
  test(
    'ObjectBox C reader accepts entity bytes at every physical offset mod8',
    () {
      final directory = Directory.systemTemp.createTempSync(
        'objectbox-c-alignment-',
      );
      final store = Store(fixtureModel(), directory: directory.path);
      try {
        final access = NativeObjectBoxAccess<Sample>(store);
        for (var offset = 0; offset < 8; offset++) {
          final sample = Sample(id: 100 + offset);
          final bytes = encodeSample(sample);
          final longField = fieldPosition(bytes, 13);
          final vector =
              longField +
              ByteData.sublistView(bytes).getUint32(longField, Endian.little);
          expect(
            (vector + 4) % 8,
            4,
            reason: 'Exercise the Dart builder layout',
          );
          final allocation = malloc<Uint8>(bytes.length + 8);
          try {
            final pointer = allocation + offset;
            pointer.asTypedList(bytes.length).setAll(0, bytes);
            access.write(
              () => access.put(pointer, bytes.length, sample.id, PutMode.put),
            );
            expect(pointer.asTypedList(bytes.length), bytes);
            final read = store.box<Sample>().get(sample.id)!;
            expect(read.text, sample.text);
            expect(read.counter, sample.counter);
            expect(read.blob, sample.blob);
            expect(read.scores, sample.scores);
            expect(read.names, sample.names);
            expect(read.longs, sample.longs);
          } finally {
            malloc.free(allocation);
          }
        }
      } finally {
        store.close();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
