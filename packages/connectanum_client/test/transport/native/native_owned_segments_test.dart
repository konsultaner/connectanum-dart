@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:test/test.dart';

void main() {
  late NativeBufferAllocator allocator;
  setUpAll(() => allocator = NativeBufferAllocator.instance());
  tearDownAll(NativeClientRuntime.shutdownShared);

  NativeOwnedBuffer native(Uint8List bytes) {
    final builder = allocator.allocate(bytes.length);
    try {
      builder.writeBytes(0, bytes);
      return builder.freeze();
    } finally {
      builder.dispose();
    }
  }

  test('shared owned-segment submission ABI is available', () {
    expect(allocator.supportsSegmentedBuffers, isTrue);
  });

  test('old libraries and invalid segment arrays reject without transfer', () {
    final old = NativeBufferAllocator(
      DynamicLibrary.open(
        Platform.isMacOS ? '/usr/lib/libSystem.B.dylib' : 'libc.so.6',
      ),
    );
    expect(old.supportsSegmentedBuffers, isFalse);
    expect(() => old.sendSegments(1, []), throwsUnsupportedError);
    expect(() => old.sendSegmentsTracked(1, []), throwsUnsupportedError);
    final owner = native(Uint8List.fromList([1]));
    final empty = native(Uint8List(0));
    addTearDown(owner.dispose);
    addTearDown(empty.dispose);
    for (final tracked in [false, true]) {
      void send(int connection, List<NativeOwnedBuffer> parts) {
        if (tracked) {
          allocator.sendSegmentsTracked(connection, parts);
        } else {
          allocator.sendSegments(connection, parts);
        }
      }

      expect(() => send(0, [owner]), throwsRangeError);
      expect(() => send(1, []), throwsRangeError);
      expect(() => send(1, List.filled(65, owner)), throwsRangeError);
      expect(() => send(1, [empty]), throwsArgumentError);
      expect(
        () => send(0x7fffffff, [empty, owner]),
        throwsA(isA<NativeBufferException>()),
      );
      expect(owner.isDisposed, isFalse);
      expect(owner.bytes, [1]);
    }
    owner.dispose();
    expect(() => allocator.sendSegments(1, [owner]), throwsStateError);
  });

  test(
    'segment ABI requires its complete version and rejects foreign buffers',
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
        'connectanum-owned-segments-abi-',
      );
      addTearDown(() => directory.delete(recursive: true));
      Future<NativeBufferAllocator> load(
        int version, {
        bool omitTracked = false,
        bool writeReceipts = true,
      }) async {
        final output =
            '${directory.path}/segments-$version-$omitTracked-$writeReceipts.${Platform.isMacOS ? 'dylib' : 'so'}';
        final result = await Process.run('cc', [
          Platform.isMacOS ? '-dynamiclib' : '-shared',
          '-fPIC',
          '-DOWNED_BUFFER_VERSION=1',
          '-DEXTERNAL_LEASE_VERSION=1',
          if (writeReceipts) '-DWRITE_RECEIPT_VERSION=1',
          '-DOWNED_SEGMENTS_VERSION=$version',
          if (omitTracked) '-DOMIT_SEGMENTS_TRACKED',
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

      for (final unsupported in [
        await load(2),
        await load(1, omitTracked: true),
        await load(1, writeReceipts: false),
      ]) {
        expect(unsupported.isSupported, isTrue);
        expect(unsupported.supportsSegmentedBuffers, isFalse);
        expect(() => unsupported.sendSegments(1, []), throwsUnsupportedError);
      }
      final foreign = await load(1);
      expect(foreign.supportsSegmentedBuffers, isTrue);
      final owner = native(Uint8List.fromList([1]));
      addTearDown(owner.dispose);
      expect(() => foreign.sendSegments(1, [owner]), throwsArgumentError);
      expect(
        () => foreign.sendSegmentsTracked(1, [owner]),
        throwsArgumentError,
      );
      expect(owner.isDisposed, isFalse);
    },
  );

  test(
    'segmented raw submission preserves the FlatBuffers profile guard',
    () async {
      final peer = await _SegmentPeer.start('flatbuffers', true);
      addTearDown(peer.dispose);
      final transport = NativeWebSocketTransport.withFlatBuffersSerializer(
        'ws://127.0.0.1:${peer.port}/wamp',
      );
      await transport.open();
      addTearDown(transport.close);
      final owner = native(Uint8List.fromList([1]));
      addTearDown(owner.dispose);
      final capability = transport as NativeSegmentedBufferTransport;
      expect(
        () => capability.sendEncodedNativeBufferSegments([owner]),
        throwsUnsupportedError,
      );
      expect(
        () => capability.sendEncodedNativeBufferSegmentsTracked([owner]),
        throwsUnsupportedError,
      );
      expect(owner.isDisposed, isFalse);
    },
  );

  for (final codec in ['cbor', 'msgpack']) {
    test(
      '$codec packed native PPT tags only its exact view and decodes lazily',
      () {
        final owner = native(Uint8List.fromList([1, 2, 3]));
        addTearDown(owner.dispose);
        var decoded = 0;
        final payload = owner.asPptPayload(
          encoding: codec == 'cbor'
              ? LazyPayloadEncoding.cbor
              : LazyPayloadEncoding.messagePack,
          packedPayloadDecoder: (bytes) {
            decoded++;
            return (arguments: <dynamic>[bytes], argumentsKeywords: null);
          },
        );
        final bytes = payload.packedPayloadBytes!;
        expect(decoded, 0);
        expect(owner.ownsPptPayloadBytes(bytes), isTrue);
        expect(owner.ownsPptPayloadBytes(Uint8List.fromList(bytes)), isFalse);
        expect(
          owner.ownsPptPayloadBytes(Uint8List.sublistView(bytes)),
          isFalse,
        );
        expect(payload.arguments!.single, same(bytes));
        expect(decoded, 1);
        owner.dispose();
        expect(owner.ownsPptPayloadBytes(bytes), isFalse);
        expect(bytes, [1, 2, 3]);
        expect(
          () => owner.asPptPayload(
            encoding: LazyPayloadEncoding.cbor,
            packedPayloadDecoder: (_) =>
                (arguments: null, argumentsKeywords: null),
          ),
          throwsStateError,
        );
      },
    );

    for (final websocket in [false, true]) {
      test(
        '$codec owned PPT and tracked segments over ${websocket ? 'WebSocket' : 'RawSocket'}',
        () async {
          final peer = await _SegmentPeer.start(codec, websocket);
          addTearDown(peer.dispose);
          final AbstractTransport transport = websocket
              ? codec == 'cbor'
                    ? NativeWebSocketTransport.withCborSerializer(
                        'ws://127.0.0.1:${peer.port}/wamp',
                      )
                    : NativeWebSocketTransport.withMsgpackSerializer(
                        'ws://127.0.0.1:${peer.port}/wamp',
                      )
              : codec == 'cbor'
              ? NativeRawSocketTransport.withCborSerializer(
                  '127.0.0.1',
                  peer.port,
                )
              : NativeRawSocketTransport.withMsgpackSerializer(
                  '127.0.0.1',
                  peer.port,
                );
          final segmented = transport as NativeSegmentedBufferTransport;
          final AbstractSerializer serializer = codec == 'cbor'
              ? cbor.Serializer()
              : msgpack.Serializer();
          final owner = native(
            Uint8List.fromList(List.generate(65536, (index) => index & 255)),
          );
          addTearDown(owner.dispose);
          expect(
            () => segmented.sendEncodedNativeBufferSegments([owner]),
            throwsStateError,
          );
          expect(
            () => segmented.sendEncodedNativeBufferSegmentsTracked([owner]),
            throwsStateError,
          );
          await transport.open();
          addTearDown(transport.close);
          var decoded = 0;
          final payload = owner.asPptPayload(
            encoding: codec == 'cbor'
                ? LazyPayloadEncoding.cbor
                : LazyPayloadEncoding.messagePack,
            packedPayloadDecoder: (_) {
              decoded++;
              throw StateError('send must not decode');
            },
          );
          for (final publish in [false, true]) {
            final AbstractMessageWithPayload message = publish
                ? Publish(
                    7,
                    'com.echo',
                    options: PublishOptions(
                      pptScheme: 'x_test',
                      pptSerializer: codec,
                    ),
                  )
                : Call(
                    7,
                    'com.echo',
                    options: CallOptions(
                      pptScheme: 'x_test',
                      pptSerializer: codec,
                    ),
                  );
            message.restoreLazyPayload(payload);
            final expected = serializer.serialize(message) as Uint8List;
            final headerBytes = serializer
                .serializeFragments(message)!
                .where((part) => !identical(part, payload.packedPayloadBytes))
                .fold<int>(0, (length, part) => length + part.length);
            final before = NativeClientRuntime.instance()
                .transportCopyMetricsSnapshot()
                .dartToNativeCopiedBytesTotal;
            transport.send(message);
            await segmented.drainWrites();
            expect(await peer.frame(), expected);
            final after = NativeClientRuntime.instance()
                .transportCopyMetricsSnapshot()
                .dartToNativeCopiedBytesTotal;
            expect(
              after - before,
              headerBytes,
              reason: 'only newly encoded metadata crosses Dart/native',
            );
            expect(owner.isDisposed, isFalse);
            expect(decoded, 0);
          }

          // A copied list carrying a forged owner record must use its own bytes,
          // never the unrelated allocation indicated by the record.
          final replaced = Uint8List.fromList(payload.packedPayloadBytes!)
            ..[0] = 99;
          final fake = LazyMessagePayload.packed(
            encoding: payload.encoding!,
            packedPayloadBytes: replaced,
            packedPayloadDecoder: (_) =>
                (arguments: null, argumentsKeywords: null),
            storageOwner: (buffer: owner, bytes: replaced),
          );
          final forged = Call(
            8,
            'com.echo',
            options: CallOptions(pptScheme: 'x_test', pptSerializer: codec),
          )..restoreLazyPayload(fake);
          final before = NativeClientRuntime.instance()
              .transportCopyMetricsSnapshot()
              .dartToNativeCopiedBytesTotal;
          transport.send(forged);
          await segmented.drainWrites();
          expect(await peer.frame(), serializer.serialize(forged));
          final after = NativeClientRuntime.instance()
              .transportCopyMetricsSnapshot()
              .dartToNativeCopiedBytesTotal;
          expect(after - before, greaterThanOrEqualTo(replaced.length));

          final ordinary = Call(9, 'com.echo', arguments: ['tracked']);
          final encoded = serializer.serialize(ordinary) as Uint8List;
          final prefix = native(Uint8List.sublistView(encoded, 0, 2));
          final tail = native(Uint8List.sublistView(encoded, 2));
          final receipt = segmented.sendEncodedNativeBufferSegmentsTracked([
            prefix,
            tail,
          ]);
          prefix.dispose();
          tail.dispose();
          try {
            expect(await peer.frame(), encoded);
            expect(
              await receipt.wait(timeout: const Duration(seconds: 5)),
              NativeWriteOutcome.written,
            );
          } finally {
            receipt.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 20)),
      );
    }
  }
}

class _SegmentPeer {
  _SegmentPeer(this.isolate, this.port, this.events, this.receive);
  final Isolate isolate;
  final int port;
  final StreamIterator<dynamic> events;
  final ReceivePort receive;

  static Future<_SegmentPeer> start(String codec, bool websocket) async {
    final receive = ReceivePort();
    final events = StreamIterator<dynamic>(receive);
    final isolate = await Isolate.spawn(_segmentPeer, (
      receive.sendPort,
      codec,
      websocket,
    ));
    if (!await events.moveNext().timeout(const Duration(seconds: 5)) ||
        events.current is! int) {
      isolate.kill(priority: Isolate.immediate);
      receive.close();
      throw StateError('Peer startup failed: ${events.current}');
    }
    return _SegmentPeer(isolate, events.current as int, events, receive);
  }

  Future<Uint8List> frame() async {
    if (!await events.moveNext().timeout(const Duration(seconds: 5)) ||
        events.current is! Uint8List) {
      throw StateError('Peer failed: ${events.current}');
    }
    return events.current as Uint8List;
  }

  Future<void> dispose() async {
    isolate.kill(priority: Isolate.immediate);
    await events.cancel();
    receive.close();
  }
}

Future<void> _segmentPeer((SendPort, String, bool) config) async {
  final (parent, codec, websocket) = config;
  try {
    if (websocket) {
      final server = await HttpServer.bind('127.0.0.1', 0);
      parent.send(server.port);
      await for (final request in server) {
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (_) => 'wamp.2.$codec',
        );
        await for (final frame in socket) {
          parent.send(
            frame is Uint8List ? frame : Uint8List.fromList(frame as List<int>),
          );
        }
        await server.close(force: true);
        return;
      }
    } else {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      parent.send(server.port);
      final socket = await server.first;
      var pending = Uint8List(0);
      var handshake = false;
      await for (final chunk in socket) {
        pending =
            (BytesBuilder(copy: false)
                  ..add(pending)
                  ..add(chunk))
                .takeBytes();
        if (!handshake) {
          if (pending.length < 4) continue;
          final expected = codec == 'cbor' ? 3 : 2;
          if (pending[0] != 0x7f || pending[1] & 15 != expected) {
            throw StateError('wrong handshake');
          }
          socket.add(Uint8List.sublistView(pending, 0, 4));
          await socket.flush();
          pending = Uint8List.sublistView(pending, 4);
          handshake = true;
        }
        while (pending.length >= 4) {
          final length = pending[1] << 16 | pending[2] << 8 | pending[3];
          if (pending.length < 4 + length) break;
          parent.send(Uint8List.sublistView(pending, 4, 4 + length));
          pending = Uint8List.sublistView(pending, 4 + length);
        }
      }
      await server.close();
    }
  } catch (error, stack) {
    parent.send('$error\n$stack');
  }
}
