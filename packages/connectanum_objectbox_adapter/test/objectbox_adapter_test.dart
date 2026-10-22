// ignore_for_file: implementation_imports
import 'dart:io';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';
import 'package:connectanum_objectbox_adapter/connectanum_objectbox_adapter.dart';
import 'package:objectbox/objectbox.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'support/model.dart';

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxFlatBufferAdapter<Sample> adapter;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('connectanum-objectbox-');
    store = Store(fixtureModel(), directory: directory.path);
    adapter = ObjectBoxFlatBufferAdapter<Sample>(store);
    entityReads = entityWrites = 0;
  });
  tearDown(() {
    adapter.close();
    store.close();
    directory.deleteSync(recursive: true);
  });

  ObjectBoxPutResult put(
    Uint8List bytes, {
    Object? owner,
    PutMode mode = PutMode.put,
  }) => adapter.putBytes(
    bytes,
    storageOwner: owner,
    mode: mode,
    schemaFingerprint: adapter.schema.fingerprint,
  );

  (Uint8List, Object) native(Uint8List input, {int offset = 8}) {
    final root = allocateNativeExternalBytes(input.length + 16);
    root.setRange(offset, offset + input.length, input);
    final owner = Object();
    retainNativeExternalBytes(owner, root);
    return (
      Uint8List.sublistView(
        root,
        offset,
        offset + input.length,
      ).asUnmodifiableView(),
      owner,
    );
  }

  test('raw C writes interoperate with the persisted-ID Dart entity model', () {
    final original = Sample(id: 41);
    final bytes = encodeSample(original);
    final writes = entityWrites;
    final result = put(bytes);
    expect(result.id, 41);
    expect(result.copiedBytes, bytes.length);
    expect(entityWrites, writes);
    expect(entityReads, 0);
    final snapshot = adapter.getBytes(41)!;
    expect(snapshot, bytes);
    expect(entityReads, 0);
    final entity = store.box<Sample>().get(41)!;
    expect(entity.text, original.text);
    expect(entity.scores, original.scores);
    expect(entity.blob, original.blob);
    expect(entity.names, original.names);
    expect(entity.flag, original.flag);
    expect(entity.counter, original.counter);
    expect(entity.longs, original.longs);
    expect(adapter.copyMetrics.stagingCopyBytes, bytes.length);
    expect(adapter.copyMetrics.snapshotCopyBytes, bytes.length);
  });

  test(
    'retained native subviews borrow the exact payload without a body copy',
    () {
      final bytes = encodeSample(Sample(id: 42));
      final (view, owner) = native(bytes);
      final result = put(view, owner: owner);
      expect(result.borrowed, isTrue);
      expect(result.copiedBytes, 0);
      expect(adapter.copyMetrics.knownCopyBytes, 0);
      expect(adapter.copyMetrics.borrowedInputBytes, bytes.length);
      expect(adapter.getBytes(42), bytes);
    },
  );

  test(
    'native byte input borrows at a nonzero physical offset without mutation',
    () {
      final bytes = encodeSample(Sample(id: 43));
      final (view, owner) = native(bytes, offset: 1);
      final result = put(view, owner: owner);
      expect(result.copyReasons, isEmpty);
      expect(result.copiedBytes, 0);
      expect(view, bytes);
    },
  );

  test('an unrelated native owner cannot substitute different Dart bytes', () {
    final (_, owner) = native(encodeSample(Sample(id: 44, text: 'wrong')));
    final bytes = encodeSample(Sample(id: 45, text: 'provided'));
    expect(put(bytes, owner: owner).copyReasons, [
      ObjectBoxCopyReason.unavailableNativeLease,
    ]);
    expect(store.box<Sample>().get(45)!.text, 'provided');
    expect(adapter.getBytes(44), isNull);
  });

  test('zero ID assignment mutates only a counted private native copy', () {
    final bytes = encodeSample(Sample());
    final (view, owner) = native(bytes);
    final result = put(view, owner: owner);
    expect(result.id, greaterThan(0));
    expect(result.copyReasons, [ObjectBoxCopyReason.idAssignment]);
    expect(result.copiedBytes, bytes.length);
    expect(view, bytes);
    expect(
      adapter.schema.validate(
        view,
        schemaFingerprint: adapter.schema.fingerprint,
      ),
      0,
    );
    expect(store.box<Sample>().get(result.id)!.id, result.id);
  });

  test('reserve IDs then borrow caller-owned native C memory', () {
    final id = adapter.reserveId();
    final bytes = encodeSample(Sample(id: id));
    final pointer = malloc<Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      final result = adapter.putNative(
        pointer,
        bytes.length,
        lifetimeOwner: bytes,
        schemaFingerprint: adapter.schema.fingerprint,
      );
      expect(result.id, id);
      expect(result.borrowed, isTrue);
      expect(result.copiedBytes, 0);
      expect(pointer.asTypedList(bytes.length), bytes);
      expect(adapter.getBytes(id), bytes);
    } finally {
      malloc.free(pointer);
    }
  });

  test('invalid ranges and explicit IDs fail before allocating or writing', () {
    for (final length in [0, 15, adapter.schema.maximumBytes + 1]) {
      expect(
        () => adapter.putNative(
          nullptr,
          length,
          lifetimeOwner: Object(),
          schemaFingerprint: adapter.schema.fingerprint,
        ),
        throwsArgumentError,
      );
    }
    expect(() => put(Uint8List(15)), throwsFormatException);
    expect(() => adapter.getBytes(0), throwsArgumentError);
    final bytes = encodeSample(Sample());
    for (final mode in [PutMode.put, PutMode.update]) {
      expect(
        () => adapter.putBytes(
          bytes,
          schemaFingerprint: adapter.schema.fingerprint,
          mode: mode,
          assignIdIfZero: mode == PutMode.update,
        ),
        throwsArgumentError,
      );
    }
    expect(adapter.copyMetrics.knownCopyBytes, 0);
    expect(adapter.copyMetrics.successfulWrites, 0);
  });

  test('primitive and record owners safely use the counted fallback', () {
    for (final owner in <Object>[1, 'owner', true, (1, 2)]) {
      final bytes = encodeSample(Sample(id: 51));
      expect(put(bytes, owner: owner).copyReasons, [
        ObjectBoxCopyReason.unavailableNativeLease,
      ]);
    }
  });

  test('read limits also apply to objects written outside the adapter', () {
    store.box<Sample>().put(Sample(id: 52));
    final limited = ObjectBoxFlatBufferAdapter<Sample>(store, maximumBytes: 16);
    try {
      expect(() => limited.getBytes(52), throwsStateError);
      expect(limited.copyMetrics.snapshotCopyBytes, 0);
    } finally {
      limited.close();
    }
  });

  test('PPT metadata is required and encrypted envelopes are rejected', () {
    final bytes = encodeSample(Sample(id: 53));
    final payload = core.LazyMessagePayload.packed(
      encoding: core.LazyPayloadEncoding.flatbuffers,
      packedPayloadBytes: bytes,
      packedPayloadDecoder: (_) => throw StateError('Must stay encoded'),
    );
    core.LazyEventPayload event({
      String? scheme = objectBoxPptScheme,
      String? serializer = 'flatbuffers',
      String? cipher,
      String? key,
      Map<String, dynamic>? details,
    }) => core.LazyEventPayload(
      subscriptionId: 1,
      publicationId: 2,
      payload: payload,
      pptScheme: scheme,
      pptSerializer: serializer,
      pptCipher: cipher,
      pptKeyId: key,
      customDetails: details,
    );
    for (final invalid in [
      event(scheme: null),
      event(serializer: 'cbor'),
      event(cipher: 'cryptobox'),
      event(key: 'secret'),
      event(),
      event(details: {objectBoxSchemaMetadataKey: 7}),
      event(details: {objectBoxSchemaMetadataKey: 'wrong-schema'}),
    ]) {
      expect(() => adapter.putEvent(invalid), throwsFormatException);
    }
    final options = adapter.publishOptions(acknowledge: false);
    expect(options.acknowledge, isFalse);
    expect(options.pptScheme, objectBoxPptScheme);
    expect(options.pptSerializer, 'flatbuffers');
    expect(
      options.custom[objectBoxSchemaMetadataKey],
      adapter.schema.fingerprint,
    );
    expect(adapter.copyMetrics.successfulWrites, 0);
  });

  test('caller padding is initialized and body copying is counted once', () {
    final bytes = encodeSample(Sample(id: 46));
    final extended = Uint8List(bytes.length + 1)
      ..setRange(0, bytes.length, bytes);
    final (view, owner) = native(extended);
    final result = put(view, owner: owner);
    expect(result.copyReasons, [ObjectBoxCopyReason.padding]);
    expect(result.copiedBytes, extended.length);
    expect(adapter.copyMetrics.paddingBytes, 3);
    expect(store.box<Sample>().get(46)!.text, Sample().text);
  });

  test(
    'native insertion/update errors preserve data and original error codes',
    () {
      final bytes = encodeSample(Sample(id: 47));
      put(bytes, mode: PutMode.insert);
      expect(
        () => put(bytes, mode: PutMode.insert),
        throwsA(
          isA<ObjectBoxAdapterException>()
              .having(
                (error) => error.code,
                'C error',
                greaterThan(0),
              )
              .having(
                (error) => error.toString(),
                'description',
                contains('obx_box_put5'),
              ),
        ),
      );
      expect(
        () => put(encodeSample(Sample(id: 999)), mode: PutMode.update),
        throwsA(isA<ObjectBoxAdapterException>()),
      );
      expect(adapter.getBytes(47), bytes);
      expect(adapter.copyMetrics.failedWrites, 2);
    },
  );

  test(
    'normal ObjectBox writes can be read without constructing an entity',
    () {
      final sample = Sample();
      store.box<Sample>().put(sample);
      final reads = entityReads;
      expect(adapter.getBytes(sample.id), isNotEmpty);
      expect(entityReads, reads);
      expect(adapter.getBytes(12345), isNull);
    },
  );

  test(
    'closing an adapter leaves its Store open and rejects later operations',
    () {
      adapter.close();
      expect(store.isClosed(), isFalse);
      expect(() => adapter.getBytes(1), throwsStateError);
      adapter.close();
    },
  );
  test('owned snapshots survive later writes and Store closure', () {
    put(encodeSample(Sample(id: 49, text: 'before')));
    final copy = adapter.getBytes(49)!;
    put(encodeSample(Sample(id: 49, text: 'after')));
    expect(copy, isNot(adapter.getBytes(49)));
    store.close();
    expect(copy, isNotEmpty);
    expect(() => adapter.getBytes(49), throwsStateError);
  });
}
