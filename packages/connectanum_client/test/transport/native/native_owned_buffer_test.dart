@TestOn('vm')
library;

import 'dart:collection';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:test/test.dart';

void main() {
  late NativeBufferAllocator allocator;
  setUpAll(() {
    allocator = NativeBufferAllocator.instance();
  });

  test('complete native ownership ABI is available', () {
    expect(
      allocator.isSupported,
      isTrue,
      reason: 'Tests require the owned-buffer native ABI',
    );
  });

  test('older native libraries reject the complete optional ABI', () {
    // process() sees ct_ffi symbols already loaded by build hooks. Use a
    // separate library handle with no Connectanum ownership entry points.
    final library = DynamicLibrary.open(
      Platform.isMacOS
          ? '/usr/lib/libSystem.B.dylib'
          : Platform.isWindows
          ? 'kernel32.dll'
          : 'libc.so.6',
    );
    final old = NativeBufferAllocator(library);
    expect(old.isSupported, isFalse);
    expect(() => old.allocate(0), throwsUnsupportedError);
    expect(old.flatBuffers, throwsUnsupportedError);
  });

  test(
    'version mismatch and foreign library reject before ownership transfer',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_client/native_buffers.dart'),
      );
      final fixture = source!
          .resolve(
            '../test/transport/native/support/owned_buffer_abi_fixture.c',
          )
          .toFilePath();
      final directory = await Directory.systemTemp.createTemp(
        'connectanum-owned-abi-',
      );
      addTearDown(() => directory.delete(recursive: true));
      Future<NativeBufferAllocator> load(int version) async {
        final output =
            '${directory.path}/owned-$version.${Platform.isMacOS ? 'dylib' : 'so'}';
        final result = await Process.run('cc', [
          Platform.isMacOS ? '-dynamiclib' : '-shared',
          '-fPIC',
          '-DOWNED_BUFFER_VERSION=$version',
          '-o',
          output,
          fixture,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        return NativeBufferAllocator(DynamicLibrary.open(output));
      }

      final differentVersion = await load(2);
      expect(differentVersion.isSupported, isFalse);
      expect(() => differentVersion.allocate(8), throwsUnsupportedError);
      final foreign = await load(1);
      expect(foreign.isSupported, isTrue);
      final buffer = allocator.allocate(8).freeze();
      expect(
        () => foreign.send(42, buffer, transfer: true),
        throwsArgumentError,
      );
      expect(buffer.isDisposed, isFalse);
      expect(buffer.bytes, hasLength(8));
      buffer.dispose();
    },
    skip: Platform.isWindows
        ? 'Native verification uses Unix C toolchains'
        : false,
  );

  test(
    'native finalizers preserve derived views and release abandoned owners',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_client/native_buffers.dart'),
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--enable-vm-service=0',
          '--disable-service-auth-codes',
          'run',
          source!
              .resolve(
                '../test/transport/native/support/owned_buffer_gc_probe.dart',
              )
              .toFilePath(),
        ],
        environment: {
          'CONNECTANUM_NATIVE_LIB': NativeClientRuntime.instance().libraryPath,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains(
          'owned-buffer-gc: derived view retained then released storage',
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test('zero-filled native storage freezes a backward subrange', () {
    final builder = allocator.allocate(64);
    builder.setUint32(60, 0x04030201);
    final buffer = builder.freeze(offset: 56, length: 8);
    addTearDown(buffer.dispose);
    expect(buffer.bytes, [0, 0, 0, 0, 1, 2, 3, 4]);
    expect(buffer.growthCopiedBytes, 0);
    expect(buffer.inputCopiedBytes, 0);
    expect(() => builder.setUint8(0, 7), throwsStateError);
    expect(() => builder.freeze(), throwsStateError);
    builder.dispose();
    expect(buffer.bytes, hasLength(8));
  });

  test('invalid ranges preserve mutable ownership and explicit disposal', () {
    final builder = allocator.allocate(8);
    expect(() => builder.freeze(offset: 7, length: 2), throwsRangeError);
    builder.writeBytes(0, [1, 2, 3]);
    final buffer = builder.freeze();
    expect(buffer.inputCopiedBytes, 3);
    buffer.dispose();
    buffer.dispose();
    expect(() => buffer.bytes, throwsStateError);
    expect(() => builder.setUint32(0, 1), throwsStateError);
    final other = allocator.allocate(0);
    other.dispose();
    expect(() => other.freeze(), throwsStateError);
  });

  test('read-only exported subviews outlive disposed wrappers', () {
    final builder = allocator.allocate(8)..writeBytes(0, [1, 2, 3, 4]);
    final buffer = builder.freeze(length: 4);
    final retained = buffer.slice(1, 4);
    final root = buffer.bytes;
    final view = Uint8List.sublistView(root, 1, 3);
    buffer.dispose();
    retained.dispose();
    expect(view, [2, 3]);
    expect(() => root[0] = 9, throwsUnsupportedError);
    expect(() => view[0] = 9, throwsUnsupportedError);
    expect(() => root.buffer.asUint8List()[0] = 9, throwsUnsupportedError);
    expect(
      () => root.buffer.asByteData().setUint8(0, 9),
      throwsUnsupportedError,
    );
    expect(() => root.buffer.asInt8List()[0] = 9, throwsUnsupportedError);
    expect(root, [1, 2, 3, 4]);
  });

  test('empty buffers and slices retain valid ownership', () {
    final empty = allocator.allocate(0).freeze();
    final slice = empty.retain();
    empty.dispose();
    expect(slice.bytes, isEmpty);
    slice.dispose();
  });

  test('implicit freeze and slice ends preserve the remaining range', () {
    final buffer = (allocator.allocate(
      8,
    )..writeBytes(0, [0, 1, 2, 3, 4, 5, 6, 7])).freeze(offset: 4);
    final slice = buffer.slice(2);
    expect(buffer.bytes, [4, 5, 6, 7]);
    expect(slice.bytes, [6, 7]);
    buffer.dispose();
    slice.dispose();
  });

  test('FlatBuffers finish reset and freeze enforce builder state', () {
    final builder = allocator.flatBuffers();
    expect(builder.freeze, throwsStateError);
    final first = wire.MessageObjectBuilder(
      msgType: wire.AnyMessageTypeId.Call,
      msg: wire.CallObjectBuilder(request: 12, procedure: 'com.example.first'),
    );
    builder.finish(first.finish(builder));
    expect(() => builder.putUint8(7), throwsStateError);
    builder.reset();
    expect(builder.freeze, throwsStateError);
    final second = wire.MessageObjectBuilder(
      msgType: wire.AnyMessageTypeId.Call,
      msg: wire.CallObjectBuilder(request: 13, procedure: 'com.example.é🐈'),
    );
    builder.finish(second.finish(builder));
    final buffer = builder.freeze();
    expect(
      (wire.Message(buffer.bytes).msg as wire.Call).procedure,
      'com.example.é🐈',
    );
    expect((wire.Message(buffer.bytes).msg as wire.Call).request, 13);
    builder.dispose();
    builder.dispose();
    expect(builder.freeze, throwsStateError);
    expect(() => builder.reset(), throwsStateError);
    buffer.dispose();
  });

  test(
    'FlatBuffers callbacks cannot freeze or dispose during a vector write',
    () {
      final builder = allocator.flatBuffers();
      var prevented = 0;
      builder.writeListUint8(
        _ReentrantBytes(() {
          expect(builder.freeze, throwsStateError);
          expect(builder.dispose, throwsStateError);
          prevented++;
        }),
      );
      expect(prevented, greaterThan(0));
      builder.dispose();
    },
  );

  for (final webSocket in [false, true]) {
    test(
      'native ${webSocket ? 'WebSocket' : 'RawSocket'} accepts retained and transferred native frames',
      () async {
        final replies = ReceivePort();
        final messages = StreamIterator<dynamic>(replies);
        final server = await Isolate.spawn(_ownedFrameServer, (
          replies.sendPort,
          webSocket,
        ));
        addTearDown(() async {
          await messages.cancel();
          replies.close();
          server.kill(priority: Isolate.immediate);
        });
        expect(await messages.moveNext(), isTrue);
        final port = messages.current as int;
        final AbstractTransport transport = webSocket
            ? NativeWebSocketTransport.withJsonSerializer(
                'ws://127.0.0.1:$port/',
              )
            : NativeRawSocketTransport.withJsonSerializer('127.0.0.1', port);
        addTearDown(transport.close);
        final nativeTransport = transport as NativeBufferTransport;
        final builder = nativeTransport.nativeBuffers.allocate(128);
        const frame = '[48,42,{},"com.example.proc",[1]]';
        for (var index = 0; index < frame.length; index++) {
          builder.setUint8(64 + index, frame.codeUnitAt(index));
        }
        final buffer = builder.freeze(offset: 64, length: frame.length);
        addTearDown(buffer.dispose);
        expect(
          () => nativeTransport.sendEncodedNativeBuffer(buffer, transfer: true),
          throwsStateError,
        );
        expect(buffer.isDisposed, isFalse);
        await transport.open();
        await transport.onReady;
        final view = buffer.bytes;
        nativeTransport.sendEncodedNativeBuffer(buffer);
        expect(buffer.isDisposed, isFalse);
        expect(await messages.moveNext(), isTrue);
        expect(messages.current, utf8.encode(frame));
        nativeTransport.sendEncodedNativeBuffer(buffer, transfer: true);
        expect(buffer.isDisposed, isTrue);
        expect(await messages.moveNext(), isTrue);
        expect(messages.current, utf8.encode(frame));
        expect(view, utf8.encode(frame));
        expect(buffer.growthCopiedBytes, 0);
        expect(buffer.inputCopiedBytes, 0);
      },
    );
  }

  test('preallocated model construction has no frame or growth copy', () {
    final buffer = allocator.buildFlatBuffer(
      wire.MessageObjectBuilder(
        msgType: wire.AnyMessageTypeId.Call,
        msg: wire.CallObjectBuilder(
          request: 77,
          procedure: 'com.example.proc',
          args: [0x80],
        ),
      ),
      initialSize: 1024,
    );
    addTearDown(buffer.dispose);
    final call = wire.Message(buffer.bytes).msg as wire.Call;
    expect(call.request, 77);
    expect(call.procedure, 'com.example.proc');
    expect(call.args, [0x80]);
    expect(buffer.growthCopiedBytes, 0);
    expect(buffer.inputCopiedBytes, 1);
  });

  test(
    'native FlatBuffers remain physically aligned with odd capacity requests',
    () {
      final alignment =
          DynamicLibrary.open(
            NativeClientRuntime.instance().libraryPath,
          ).lookupFunction<UintPtr Function(), int Function()>(
            'ct_test_owned_buffer_last_frozen_alignment',
          );
      for (final size in [1023, 1, 9]) {
        final buffer = allocator.buildFlatBuffer(
          wire.MessageObjectBuilder(
            msgType: wire.AnyMessageTypeId.Publish,
            msg: wire.PublishObjectBuilder(
              request: 42,
              topic: 'com.example.topic',
              exclude: [4294967296],
            ),
          ),
          initialSize: size,
        );
        expect(alignment(), 0, reason: 'initialSize=$size');
        expect((wire.Message(buffer.bytes).msg as wire.Publish).exclude, [
          4294967296,
        ]);
        buffer.dispose();
      }
    },
  );

  test('growth copies are counted and all writes are guarded after freeze', () {
    final builder = allocator.flatBuffers(initialSize: 8);
    final model = wire.MessageObjectBuilder(
      msgType: wire.AnyMessageTypeId.Publish,
      msg: wire.PublishObjectBuilder(
        request: 42,
        topic: 'com.example.topic',
        exclude: [1, 4294967296],
      ),
    );
    builder.finish(model.finish(builder));
    final buffer = builder.freeze();
    addTearDown(buffer.dispose);
    expect(builder.allocationCount, greaterThan(1));
    expect(buffer.growthCopiedBytes, greaterThan(0));
    expect((wire.Message(buffer.bytes).msg as wire.Publish).exclude, [
      1,
      4294967296,
    ]);
    for (final write in <void Function()>[
      () => builder.putUint8(1),
      () => builder.addOffset(0, 1),
      () => builder.startTable(1),
      () => builder.endTable(),
      () => builder.pad(1),
      () => builder.writeListUint8([1]),
      () => builder.writeString('x'),
      () => builder.reset(),
    ]) {
      expect(write, throwsStateError);
    }
    builder.dispose();
    expect(buffer.bytes, isNotEmpty);
  });

  test('model callbacks receive the guarded facade', () {
    final builder = allocator.flatBuffers();
    final model = _CapturingStruct();
    builder.writeListOfStructs([model]);
    expect(identical(model.builder, builder), isTrue);
    builder.dispose();
    expect(() => model.builder!.putUint32(3), throwsStateError);
  });

  test('reentrant input cannot release an allocation while writing', () {
    final builder = allocator.allocate(4);
    var blocked = 0;
    final bytes = _ReentrantBytes(() {
      try {
        builder.dispose();
      } on StateError {
        blocked++;
      }
      try {
        builder.freeze();
      } on StateError {
        blocked++;
      }
    });
    builder.writeBytes(0, bytes);
    final buffer = builder.freeze();
    addTearDown(buffer.dispose);
    expect(buffer.bytes, [1, 2, 3, 4]);
    expect(blocked, greaterThan(0));
  });

  test('native rejection consumes transfers and preserves retained sends', () {
    final buffer = allocator.allocate(4).freeze();
    final bytes = buffer.bytes;
    for (final connection in [0, -1, 0x100000001]) {
      expect(
        () => allocator.send(connection, buffer, transfer: true),
        throwsRangeError,
      );
      expect(buffer.isDisposed, isFalse);
    }
    expect(
      () => allocator.send(0x7fffffff, buffer),
      throwsA(isA<NativeBufferException>()),
    );
    expect(buffer.isDisposed, isFalse);
    expect(buffer.bytes, [0, 0, 0, 0]);
    expect(
      () => allocator.send(0x7fffffff, buffer, transfer: true),
      throwsA(isA<NativeBufferException>()),
    );
    expect(buffer.isDisposed, isTrue);
    expect(bytes, [0, 0, 0, 0]);
    expect(() => allocator.send(0x7fffffff, buffer), throwsStateError);
    // The runtime can initialize later; allocation ownership is independent.
    expect(NativeClientRuntime.instance().nativeBuffers.isSupported, isTrue);
  });
}

@pragma('vm:entry-point')
Future<void> _ownedFrameServer((SendPort, bool) configuration) async {
  final (replies, webSocket) = configuration;
  if (webSocket) {
    final server = await HttpServer.bind('127.0.0.1', 0);
    replies.send(server.port);
    final request = await server.first;
    final socket = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: (protocols) =>
          protocols.contains('wamp.2.json') ? 'wamp.2.json' : null,
    );
    await for (final message in socket) {
      replies.send(message is String ? utf8.encode(message) : message);
    }
    await server.close(force: true);
  } else {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    replies.send(server.port);
    final socket = await server.first;
    final pending = <int>[];
    var handshake = false;
    await for (final chunk in socket) {
      pending.addAll(chunk);
      if (!handshake && pending.length >= 4) {
        if (pending[0] != 0x7f || (pending[1] & 0x0f) != 1) {
          throw StateError('Unexpected RawSocket handshake');
        }
        socket.add([0x7f, 0xf1, 0, 0]);
        pending.removeRange(0, 4);
        handshake = true;
      }
      while (handshake && pending.length >= 4) {
        final length = (pending[1] << 16) | (pending[2] << 8) | pending[3];
        if (pending.length < length + 4) break;
        if (pending[0] != 0) throw StateError('Expected WAMP frame');
        replies.send(pending.sublist(4, length + 4));
        pending.removeRange(0, length + 4);
      }
    }
    await server.close();
  }
}

class _CapturingStruct extends fb.ObjectBuilder {
  fb.Builder? builder;
  @override
  int finish(fb.Builder fbBuilder) {
    builder = fbBuilder;
    fbBuilder.putUint32(7);
    return fbBuilder.offset;
  }

  @override
  Uint8List toBytes() =>
      throw UnsupportedError('Test uses native struct vector');
}

class _ReentrantBytes extends ListBase<int> {
  _ReentrantBytes(this.callback);
  final void Function() callback;
  @override
  int get length => 4;
  @override
  set length(int value) => throw UnsupportedError('Fixed test input');
  @override
  int operator [](int index) {
    callback();
    return index + 1;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read only');
}
