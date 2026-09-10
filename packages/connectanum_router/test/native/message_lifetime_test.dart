@TestOn('vm')
library;

import 'dart:convert';
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/native/runtime.dart' as client;
import 'package:connectanum_client/src/transport/native/message_binding.dart'
    show materializeSessionMessage;
import 'package:connectanum_client/native_message_bytes.dart';
import 'package:connectanum_core/connectanum_core.dart' show Call, Result;
import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_router/src/native/ffi_bindings.dart'
    show CtMessageInfo, CtMessagePeekDart, CtMessagePeekNative;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:ffi/ffi.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

import '../support/native_lib.dart';

void main() {
  final path = resolveOrBuildNativeLib();
  final legacy =
      Platform.environment['CONNECTANUM_TEST_LEGACY_MESSAGE_BYTES'] == '1';
  final expectedNativeOwner = legacy ? 0 : 1;
  test('native byte ownership capability matches the tested ABI', () {
    expect(
      NativeMessageBytes(ffi.DynamicLibrary.open(path!)).supportsZeroCopy,
      !legacy,
    );
  }, skip: path == null ? 'Native library unavailable' : null);

  for (final throws in [false, true]) {
    test('metadata copy holds a temporary owner and releases it '
        '${throws ? 'on callback failure' : 'on return'}', () {
      final runtime = NativeTransportRuntime(libraryPath: path);
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });
      runtime.start();
      final library = ffi.DynamicLibrary.open(path!);
      final handle = runtime.enqueueTestMessage(
        connectionId: 9716,
        serializer: NativeMessageSerializer.json,
        frame: Uint8List.fromList(
          utf8.encode(
            '[48,123,{"trace_label":"metadata survives"},'
            '"com.example.metadata"]',
          ),
        ),
      );
      final observer = _MessageObserver(library);
      final token = observer.watch(handle);
      addTearDown(() => observer.free(token));
      final info = calloc<CtMessageInfo>();
      addTearDown(() => calloc.free(info));
      final peek = library
          .lookupFunction<CtMessagePeekNative, CtMessagePeekDart>(
            'ct_message_peek',
          );
      expect(peek(handle, info), 0);
      final bytes = NativeMessageBytes(library);
      late Uint8List copy;
      String run() => bytes.withCopiedBytes(
        handle,
        NativeMessageBytePart.details,
        borrowed: info.ref.detailsPtr,
        length: info.ref.detailsLen,
        consume: (owned) {
          copy = owned;
          NativeMessageHandleDecoder(libraryPath: path).release(handle);
          runtime.shutdown();
          // Check the weak witness before touching the borrowed string.
          expect(observer.alive(token), 1);
          final procedure = utf8.decode(
            info.ref.stringAPtr.asTypedList(info.ref.stringALen),
          );
          if (throws) throw StateError('Test callback failure');
          return procedure;
        },
      );
      if (throws) {
        expect(run, throwsStateError);
      } else {
        expect(run(), 'com.example.metadata');
      }
      expect(observer.alive(token), 0);
      expect(jsonDecode(utf8.decode(copy)), {
        'trace_label': 'metadata survives',
      });
    }, skip: path == null || legacy ? 'Requires the native owner ABI' : null);
  }

  test('metadata copy rejects stale and inconsistent info without leaking', () {
    final runtime = NativeTransportRuntime(libraryPath: path);
    addTearDown(() {
      runtime.shutdown();
      runtime.dispose();
    });
    runtime.start();
    final library = ffi.DynamicLibrary.open(path!);
    final handle = runtime.enqueueTestMessage(
      connectionId: 9717,
      serializer: NativeMessageSerializer.json,
      frame: Uint8List.fromList(
        utf8.encode('[48,123,{},"com.example.metadata"]'),
      ),
    );
    final observer = _MessageObserver(library);
    final token = observer.watch(handle);
    addTearDown(() => observer.free(token));
    final info = calloc<CtMessageInfo>();
    addTearDown(() => calloc.free(info));
    final peek = library.lookupFunction<CtMessagePeekNative, CtMessagePeekDart>(
      'ct_message_peek',
    );
    expect(peek(handle, info), 0);
    final bytes = NativeMessageBytes(library);
    var called = false;
    void read(int length, ffi.Pointer<ffi.Uint8> pointer) =>
        bytes.withCopiedBytes(
          handle,
          NativeMessageBytePart.details,
          borrowed: pointer,
          length: length,
          consume: (_) {
            called = true;
          },
        );
    expect(
      () => read(info.ref.detailsLen + 1, info.ref.detailsPtr),
      throwsStateError,
    );
    expect(
      () => read(info.ref.detailsLen, info.ref.stringAPtr),
      throwsStateError,
    );
    expect(() => read(-1, info.ref.detailsPtr), throwsArgumentError);
    expect(() => read(info.ref.detailsLen, ffi.nullptr), throwsArgumentError);
    expect(called, isFalse);
    NativeMessageHandleDecoder(libraryPath: path).release(handle);
    expect(observer.alive(token), 0);
    expect(
      () => read(info.ref.detailsLen, info.ref.detailsPtr),
      throwsStateError,
    );
    expect(called, isFalse);
  }, skip: path == null || legacy ? 'Requires the native owner ABI' : null);

  for (final isClient in [false, true]) {
    for (final serializer in [
      NativeMessageSerializer.json,
      NativeMessageSerializer.messagePack,
      NativeMessageSerializer.cbor,
    ]) {
      test('${isClient ? 'client' : 'router'} ${serializer.name} lazy metadata '
          'does not retain native message storage', () {
        final runtime = NativeTransportRuntime(libraryPath: path);
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });
        runtime.start();
        final wire = <Object?>[
          isClient ? 50 : 48,
          123,
          <String, Object?>{'trace_label': 'metadata survives'},
          if (!isClient) 'com.example.metadata',
        ];
        final frame = switch (serializer) {
          NativeMessageSerializer.json => Uint8List.fromList(
            utf8.encode(jsonEncode(wire)),
          ),
          NativeMessageSerializer.messagePack => msgpack.serialize(wire),
          NativeMessageSerializer.cbor => Uint8List.fromList(
            cbor.cbor.encode(cbor.CborValue(wire)),
          ),
          _ => throw StateError('Unsupported test serializer'),
        };
        final handle = runtime.enqueueTestMessage(
          connectionId: 9715,
          serializer: serializer,
          frame: frame,
        );
        final observer = _MessageObserver(ffi.DynamicLibrary.open(path!));
        final token = observer.watch(handle);
        addTearDown(() => observer.free(token));
        late String? Function() readMetadata;
        if (isClient) {
          final consumer = client.NativeClientRuntime.instance(
            libraryPath: path,
          );
          addTearDown(consumer.shutdown);
          final incoming = consumer.materialize(handle);
          final details =
              (materializeSessionMessage(incoming.message) as Result).details;
          readMetadata = () => details.custom['trace_label'] as String?;
          incoming.release();
        } else {
          final incoming = NativeMessageHandleDecoder(
            libraryPath: path,
          ).materialize(handle);
          final options = (incoming.message as Call).options!;
          readMetadata = () => options.custom['trace_label'] as String?;
          incoming.dispose();
        }
        runtime.shutdown();
        expect(
          observer.alive(token),
          0,
          reason: 'Metadata must not keep an unrelated native frame alive',
        );
        expect(readMetadata(), 'metadata survives');
      }, skip: path == null ? 'Native library unavailable' : null);

      test('${isClient ? 'client' : 'router'} ${serializer.name} views survive '
          'explicit handle release', () {
        final runtime = NativeTransportRuntime(libraryPath: path);
        addTearDown(() {
          runtime.shutdown();
          runtime.dispose();
        });
        runtime.start();
        final observer = _MessageObserver(ffi.DynamicLibrary.open(path!));
        final wire = <Object?>[
          isClient ? 50 : 48,
          123,
          <String, Object?>{},
          if (!isClient) 'com.example.lifetime',
          ['alpha'],
          {'flag': true},
        ];
        final frame = switch (serializer) {
          NativeMessageSerializer.json => Uint8List.fromList(
            utf8.encode(jsonEncode(wire)),
          ),
          NativeMessageSerializer.messagePack => msgpack.serialize(wire),
          NativeMessageSerializer.cbor => Uint8List.fromList(
            cbor.cbor.encode(cbor.CborValue(wire)),
          ),
          _ => throw StateError('Unsupported test serializer'),
        };
        final handle = runtime.enqueueTestMessage(
          connectionId: 9711,
          serializer: serializer,
          frame: frame,
        );
        final token = observer.watch(handle);
        expect(token, isNot(ffi.nullptr));
        addTearDown(() => observer.free(token));
        late Uint8List args;
        late Uint8List kwargs;
        late void Function() release;
        if (isClient) {
          final consumer = client.NativeClientRuntime.instance(
            libraryPath: path,
          );
          addTearDown(consumer.shutdown);
          final incoming = consumer.materialize(handle);
          args = incoming.argumentsBytes!;
          kwargs = incoming.argumentsKeywordsBytes!;
          release = incoming.release;
        } else {
          final incoming = NativeMessageHandleDecoder(
            libraryPath: path,
          ).materialize(handle);
          args = incoming.argumentsBytes!;
          kwargs = incoming.argumentsKeywordsBytes!;
          release = incoming.dispose;
        }
        final subview = Uint8List.sublistView(args, 1);
        final expectedArgs = List<int>.of(subview);
        final expectedKwargs = List<int>.of(kwargs);
        expect(observer.alive(token), 1);
        release();
        release();
        // Stop before dereferencing any byte if native ownership was lost.
        expect(
          observer.alive(token),
          expectedNativeOwner,
          reason:
              'Views must retain native storage or use an owned legacy copy',
        );
        expect(subview, expectedArgs);
        expect(kwargs, expectedKwargs);
        runtime.shutdown();
        expect(observer.alive(token), expectedNativeOwner);
        expect(subview, expectedArgs);
        expect(kwargs, expectedKwargs);
      }, skip: path == null ? 'Native library unavailable' : null);
    }
  }

  test('receiver acquires its own handle and rejects expired transfers', () {
    final runtime = NativeTransportRuntime(libraryPath: path)..start();
    addTearDown(() {
      runtime.shutdown();
      runtime.dispose();
    });
    final decoder = NativeMessageHandleDecoder(libraryPath: path);
    final handle = runtime.enqueueTestMessage(
      connectionId: 9712,
      serializer: NativeMessageSerializer.json,
      frame: Uint8List.fromList(
        utf8.encode('[48,123,{},"com.example.lifetime",["alpha"]]'),
      ),
    );
    final observer = _MessageObserver(ffi.DynamicLibrary.open(path!));
    final token = observer.watch(handle);
    addTearDown(() => observer.free(token));
    final incoming = decoder.materializeRetained(handle);
    final args = incoming.argumentsBytes!;
    final expected = List<int>.of(args);
    decoder.release(handle);
    expect(
      () => decoder.materializeRetained(handle),
      throwsA(isA<NativeTransportException>()),
    );
    incoming.dispose();
    expect(observer.alive(token), expectedNativeOwner);
    expect(args, expected);
    expect(
      () => decoder.materializeRetained(0),
      throwsA(isA<NativeTransportException>()),
    );
    expect(
      () => decoder.materializeRetained(-1),
      throwsA(isA<NativeTransportException>()),
    );
  }, skip: path == null ? 'Native library unavailable' : null);

  for (final serializer in [
    NativeMessageSerializer.messagePack,
    NativeMessageSerializer.cbor,
  ]) {
    test('client ${serializer.name} sole binary argument retains storage', () {
      final runtime = NativeTransportRuntime(libraryPath: path)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });
      final expected = Uint8List.fromList([0, 1, 127, 255]);
      final wire = [
        68,
        123,
        456,
        <String, Object?>{},
        [expected],
      ];
      final frame = serializer == NativeMessageSerializer.messagePack
          ? msgpack.serialize(wire)
          : Uint8List.fromList(
              cbor.cbor.encode(
                cbor.CborList([
                  cbor.CborSmallInt(68),
                  cbor.CborSmallInt(123),
                  cbor.CborSmallInt(456),
                  cbor.CborMap({}),
                  cbor.CborList([cbor.CborBytes(expected)]),
                ]),
              ),
            );
      final handle = runtime.enqueueTestMessage(
        connectionId: 9713,
        serializer: serializer,
        frame: frame,
      );
      final observer = _MessageObserver(ffi.DynamicLibrary.open(path!));
      final token = observer.watch(handle);
      addTearDown(() => observer.free(token));
      final consumer = client.NativeClientRuntime.instance(libraryPath: path);
      addTearDown(consumer.shutdown);
      final incoming = consumer.materialize(handle);
      final bytes = incoming.singleBinaryArgumentBytes!;
      incoming.release();
      runtime.shutdown();
      expect(observer.alive(token), expectedNativeOwner);
      expect(bytes, expected);
    }, skip: path == null ? 'Native library unavailable' : null);
  }

  test(
    'subview owns storage across groups and frees it when its group exits',
    () async {
      final runtime = NativeTransportRuntime(libraryPath: path)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });
      final handle = runtime.enqueueTestMessage(
        connectionId: 9714,
        serializer: NativeMessageSerializer.json,
        frame: Uint8List.fromList(
          utf8.encode('[48,123,{},"com.example.lifetime",["alpha"]]'),
        ),
      );
      final observer = _MessageObserver(ffi.DynamicLibrary.open(path!));
      final token = observer.watch(handle);
      addTearDown(() => observer.free(token));
      final messages = ReceivePort();
      final iterator = StreamIterator<dynamic>(messages);
      addTearDown(() async {
        messages.close();
        await iterator.cancel();
      });
      final exits = ReceivePort();
      final exited = exits.first;
      addTearDown(exits.close);
      var script = File('test/support/native_message_owner_isolate.dart');
      if (!script.existsSync()) {
        script = File(
          'packages/connectanum_router/test/support/native_message_owner_isolate.dart',
        );
      }
      final child = await Isolate.spawnUri(
        script.absolute.uri,
        [path, '$handle'],
        messages.sendPort,
        packageConfig: await Isolate.packageConfig,
        onExit: exits.sendPort,
      );
      addTearDown(() => child.kill(priority: Isolate.immediate));
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 15)),
        isTrue,
      );
      final commands = iterator.current as SendPort;
      NativeMessageHandleDecoder(libraryPath: path).release(handle);
      runtime.shutdown();
      expect(observer.alive(token), expectedNativeOwner);
      commands.send('read');
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 15)),
        isTrue,
      );
      expect(iterator.current, utf8.encode('"alpha"]'));
      commands.send('finish');
      await exited.timeout(const Duration(seconds: 15));
      expect(
        observer.alive(token),
        0,
        reason: 'Normal group exit must release all native byte owners',
      );
    },
    skip: path == null ? 'Native library unavailable' : null,
  );
}

class _MessageObserver {
  _MessageObserver(ffi.DynamicLibrary library)
    : watch = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Int32),
            ffi.Pointer<ffi.Void> Function(int)
          >('ct_test_message_observer_new'),
      alive = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('ct_test_message_observer_alive'),
      free = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('ct_test_message_observer_free');

  final ffi.Pointer<ffi.Void> Function(int) watch;
  final int Function(ffi.Pointer<ffi.Void>) alive;
  final void Function(ffi.Pointer<ffi.Void>) free;
}
