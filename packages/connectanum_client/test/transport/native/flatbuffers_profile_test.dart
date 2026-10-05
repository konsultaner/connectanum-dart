@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart'
    hide NativeRawSocketTransport;
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_client/src/transport/native/native_transports_io.dart'
    show NativeRawSocketTransport;
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:test/test.dart';

NativeOwnedBuffer _encodeNative(
  NativeRawSocketTransport transport,
  AbstractMessage message,
) {
  final builder = transport.nativeBuffers.flatBuffers(initialSize: 8192);
  try {
    builder.finish(flat.writeWampFlatBufferMessage(message, builder));
    return builder.freeze();
  } finally {
    builder.dispose();
  }
}

void main() {
  NativeRawSocketTransport transport(_Peer peer) => NativeRawSocketTransport(
    '127.0.0.1',
    peer.port,
    flat.Serializer(),
    SocketHelper.serializationFlatBuffers,
  );

  test(
    'native FlatBuffers selection rejects a mismatched codec before opening',
    () {
      expect(
        () => NativeRawSocketTransport(
          '127.0.0.1',
          1,
          cbor.Serializer(),
          SocketHelper.serializationFlatBuffers,
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeRawSocketTransport(
          '127.0.0.1',
          1,
          flat.Serializer(),
          SocketHelper.serializationCbor,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'native FlatBuffers anonymous session exchanges RPC and closes',
    () async {
      final peer = await _Peer.start('anonymous');
      final client = transport(peer);
      final messages = StreamIterator<AbstractMessage?>(await _open(client));
      try {
        client.send(Hello('realm', Details.forHello()));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(messages.current, isA<Welcome>());
        client.send(Call(1, 'com.echo', arguments: ['value']));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect((messages.current as Result).arguments, ['value']);
        client.send(Goodbye(null, 'wamp.close.normal'));
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(messages.current, isA<Goodbye>());
        expect(await peer.close(), [1, 48, 6]);
      } finally {
        await messages.cancel();
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'native typed PPT cannot bypass the session profile state check',
    () async {
      final peer = await _Peer.start('anonymous');
      final client = _FrameCountingNativeRawSocketTransport(peer);
      NativeOwnedBuffer? owner;
      try {
        await client.open();
        await client.onReady.timeout(const Duration(seconds: 5));
        owner = _typedEntity(client.nativeBuffers, 51);
        final call = Call(
          1,
          'com.entity.read',
          options: CallOptions(
            pptScheme: 'x_flatbuffers',
            pptSerializer: 'flatbuffers',
          ),
        )..retainLazyPayload(owner.asFlatBuffersPptPayload());

        expect(() => client.send(call), throwsStateError);
        expect(client.nativeFrameSends, 0);
        expect(owner.isDisposed, isFalse);
      } finally {
        owner?.dispose();
        await client.close();
        await peer.dispose();
      }
    },
  );

  test(
    'Session sends native-owned typed FlatBuffers PPT as a retained frame',
    () async {
      final peer = await _Peer.start('ppt-echo');
      final client = _FrameCountingNativeRawSocketTransport(peer);
      NativeOwnedBuffer? typedOwner;
      NativeOwnedBuffer? fallbackOwner;
      try {
        await client.open();
        await client.onReady.timeout(const Duration(seconds: 5));
        final session = await Session.start('realm', client);
        typedOwner = _typedEntity(client.nativeBuffers, 51);
        final typedBytes = typedOwner.bytes.toList(growable: false);
        final typedResultFuture = session
            .callLazyPayload(
              'com.entity.read',
              payload: typedOwner.asFlatBuffersPptPayload(),
              options: CallOptions(
                pptScheme: 'x_flatbuffers',
                pptSerializer: 'flatbuffers',
              ),
            )
            .first
            .timeout(const Duration(seconds: 5));
        typedOwner.dispose();
        typedOwner = null;
        final typedResult = await typedResultFuture;
        expect(client.nativeFrameSends, 1);
        expect(typedResult.arguments, [typedBytes]);

        fallbackOwner = _typedEntity(client.nativeBuffers, 52);
        final nestedBytes = fallbackOwner.bytes.toList(growable: false);
        var nestedPayload = fallbackOwner.asFlatBuffersPptPayload();
        for (var depth = 0; depth < 6; depth++) {
          nestedPayload = core.LazyMessagePayload.packed(
            encoding: core.LazyPayloadEncoding.flatbuffers,
            packedPayloadBytes: nestedPayload.packedPayloadBytes!,
            packedPayloadDecoder: (bytes) => (
              arguments: <dynamic>[bytes],
              argumentsKeywords: null,
            ),
            anchor: nestedPayload,
          );
        }
        final nestedResultFuture = session
            .callLazyPayload(
              'com.entity.read',
              payload: nestedPayload,
              options: CallOptions(
                pptScheme: 'x_flatbuffers',
                pptSerializer: 'flatbuffers',
              ),
            )
            .first
            .timeout(const Duration(seconds: 5));
        fallbackOwner.dispose();
        fallbackOwner = null;
        final nestedResult = await nestedResultFuture;
        expect(client.nativeFrameSends, 2);
        expect(nestedResult.arguments, [nestedBytes]);

        fallbackOwner = _typedEntity(client.nativeBuffers, 53);
        final fallbackBytes = fallbackOwner.bytes.toList(growable: false);
        final fallbackResult = await session
            .callLazyPayload(
              'com.entity.read',
              payload: fallbackOwner.asFlatBuffersPptPayload(),
              options: CallOptions(
                pptScheme: 'x_flatbuffers',
                pptSerializer: 'cbor',
              ),
            )
            .first
            .timeout(const Duration(seconds: 5));
        fallbackOwner.dispose();
        expect(client.nativeFrameSends, 2);
        expect(fallbackResult.arguments, [fallbackBytes]);

        await session.close();
        await session.onGoodbye.timeout(const Duration(seconds: 5));
        expect(await peer.close(), [1, 48, 48, 48, 6]);
      } finally {
        typedOwner?.dispose();
        fallbackOwner?.dispose();
        await client.close();
        await peer.dispose();
      }
    },
  );

  for (final scenario in ['missing-challenge', 'missing-welcome']) {
    test(
      'native $scenario rejects before delivering unsupported bootstrap',
      () async {
        final peer = await _Peer.start(scenario);
        final client = transport(peer);
        final outcome = Completer<Object>();
        var credentials = 0;
        final stream = await _open(client);
        final subscription = stream.listen(
          (message) {
            if (message is Challenge) {
              credentials++;
              client.send(Authenticate(signature: 'secret'));
            } else if (!outcome.isCompleted && message is Welcome) {
              outcome.complete(message);
            }
          },
          onError: (Object error) {
            if (!outcome.isCompleted) outcome.complete(error);
          },
        );
        try {
          final offer = Hello('realm', Details.forHello());
          // Offer explicitly so the baseline probe isolates peer acknowledgement.
          const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
          client.send(offer);
          expect(
            await outcome.future.timeout(const Duration(seconds: 5)),
            isA<UnsupportedError>(),
          );
          final codes = await peer.close();
          expect(credentials, scenario == 'missing-challenge' ? 0 : 1);
          expect(codes, scenario == 'missing-challenge' ? [1] : [1, 5]);
        } finally {
          await subscription.cancel();
          await client.close();
          await peer.dispose();
        }
      },
    );
  }

  for (final tracked in [false, true]) {
    test(
      'native pre-encoded sends obey the profile, tracked=$tracked',
      () async {
        final peer = await _Peer.start('anonymous');
        final client = transport(peer);
        final messages = StreamIterator<AbstractMessage?>(await _open(client));
        try {
          final earlyCall = _encodeNative(client, Call(1, 'com.echo'));
          final credentials = _encodeNative(
            client,
            Authenticate(signature: 'secret'),
          );
          final unoffered = _encodeNative(
            client,
            Hello('realm', Details.forHello()),
          );
          for (final buffer in [earlyCall, credentials]) {
            expect(
              () => tracked
                  ? client.sendEncodedNativeBufferTracked(
                      buffer,
                      transfer: true,
                    )
                  : client.sendEncodedNativeBuffer(buffer, transfer: true),
              throwsStateError,
            );
            expect(buffer.isDisposed, isFalse);
            buffer.dispose();
          }
          expect(
            () => tracked
                ? client.sendEncodedNativeBufferTracked(
                    unoffered,
                    transfer: true,
                  )
                : client.sendEncodedNativeBuffer(unoffered, transfer: true),
            throwsUnsupportedError,
          );
          expect(unoffered.isDisposed, isFalse);
          unoffered.dispose();

          final offer = Hello('realm', Details.forHello());
          const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
          final encodedOffer = _encodeNative(client, offer);
          // StreamIterator subscribes lazily; start before awaiting a receipt.
          final welcome = messages.moveNext();
          if (tracked) {
            final receipt = client.sendEncodedNativeBufferTracked(
              encodedOffer,
              transfer: true,
            );
            expect(
              await receipt.wait(timeout: const Duration(seconds: 5)),
              NativeWriteOutcome.written,
            );
            receipt.dispose();
          } else {
            client.sendEncodedNativeBuffer(encodedOffer, transfer: true);
          }
          expect(encodedOffer.isDisposed, isTrue);
          expect(await welcome.timeout(const Duration(seconds: 5)), isTrue);
          expect(messages.current, isA<Welcome>());
          final encodedCall = _encodeNative(
            client,
            Call(1, 'com.echo', arguments: ['owned']),
          );
          client.sendEncodedNativeBuffer(encodedCall, transfer: true);
          expect(
            await messages.moveNext().timeout(const Duration(seconds: 5)),
            isTrue,
          );
          expect((messages.current as Result).arguments, ['owned']);
          expect(await peer.close(), [1, 48]);
        } finally {
          await messages.cancel();
          await client.close();
          await peer.dispose();
        }
      },
    );
    test('native composed sends obey the profile, tracked=$tracked', () async {
      final peer = await _Peer.start('anonymous');
      final client = transport(peer);
      final messages = StreamIterator<AbstractMessage?>(await _open(client));
      NativeFlatBufferFrame frame(
        AbstractMessage message, {
        NativeOwnedBuffer? arguments,
      }) {
        final control = _encodeNative(client, message);
        try {
          return client.nativeBuffers.composeFlatBufferFrame(
            control,
            arguments: arguments,
          );
        } finally {
          control.dispose();
        }
      }

      NativeWriteReceipt? send(NativeFlatBufferFrame value) {
        if (tracked) {
          return client.sendNativeFrameTracked(value, transfer: true);
        }
        client.sendNativeFrame(value, transfer: true);
        return null;
      }

      try {
        for (final message in [
          Call(1, 'com.echo'),
          Authenticate(signature: 'secret'),
        ]) {
          final value = frame(message);
          expect(() => send(value), throwsStateError);
          expect(value.isDisposed, isFalse);
          value.dispose();
        }
        final unoffered = frame(Hello('realm', Details.forHello()));
        expect(() => send(unoffered), throwsUnsupportedError);
        expect(unoffered.isDisposed, isFalse);
        unoffered.dispose();
        final offer = Hello('realm', Details.forHello());
        const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
        final offered = frame(offer);
        // Listen before the tracked write can yield to a fast WELCOME reply.
        final welcome = messages.moveNext();
        final helloReceipt = send(offered);
        if (helloReceipt != null) {
          expect(
            await helloReceipt.wait(timeout: const Duration(seconds: 5)),
            NativeWriteOutcome.written,
          );
          helloReceipt.dispose();
        }
        expect(offered.isDisposed, isTrue);
        expect(await welcome.timeout(const Duration(seconds: 5)), isTrue);
        expect(messages.current, isA<Welcome>());
        final builder = client.nativeBuffers.allocate(4);
        final NativeOwnedBuffer arguments;
        try {
          builder.setUint8(0, 0x83);
          builder.setUint8(1, 1);
          builder.setUint8(2, 2);
          builder.setUint8(3, 3);
          arguments = builder.freeze();
        } finally {
          builder.dispose();
        }
        expect(arguments.inputCopiedBytes, 0);
        final invocation = frame(Call(1, 'com.echo'), arguments: arguments);
        arguments.dispose();
        final callReceipt = send(invocation);
        if (callReceipt != null) {
          expect(
            await callReceipt.wait(timeout: const Duration(seconds: 5)),
            NativeWriteOutcome.written,
          );
          callReceipt.dispose();
        }
        expect(invocation.isDisposed, isTrue);
        expect(
          await messages.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect((messages.current as Result).arguments, [1, 2, 3]);
        expect(await peer.close(), [1, 48]);
      } finally {
        await messages.cancel();
        await client.close();
        await peer.dispose();
      }
    });
  }
}

Future<Stream<AbstractMessage?>> _open(NativeRawSocketTransport client) async {
  await client.open();
  await client.onReady.timeout(const Duration(seconds: 5));
  return client.receive();
}

NativeOwnedBuffer _typedEntity(NativeBufferAllocator allocator, int request) =>
    allocator.buildFlatBuffer(
      wire.MessageObjectBuilder(
        msgType: wire.AnyMessageTypeId.Call,
        msg: wire.CallObjectBuilder(
          request: request,
          procedure: 'com.example.entity',
        ),
      ),
      initialSize: 128,
    );

class _FrameCountingNativeRawSocketTransport extends NativeRawSocketTransport {
  _FrameCountingNativeRawSocketTransport(_Peer peer)
    : super(
        '127.0.0.1',
        peer.port,
        flat.Serializer(),
        SocketHelper.serializationFlatBuffers,
      );

  int nativeFrameSends = 0;

  @override
  void sendNativeFrame(NativeFlatBufferFrame frame, {bool transfer = false}) {
    nativeFrameSends++;
    super.sendNativeFrame(frame, transfer: transfer);
  }
}

class _Peer {
  _Peer(
    this.isolate,
    this.port,
    this.control,
    this.receivePort,
    this.exited,
    this.closed,
    this.subscription,
  );
  final Isolate isolate;
  final int port;
  final SendPort control;
  final ReceivePort receivePort;
  final Future<void> exited;
  final Completer<List<int>> closed;
  final StreamSubscription<dynamic> subscription;

  static Future<_Peer> start(String scenario) async {
    final receive = ReceivePort();
    final exit = ReceivePort();
    final exited = exit.first.then<void>((_) => exit.close());
    final ready = Completer<Map>();
    final closed = Completer<List<int>>();
    final subscription = receive.listen((dynamic event) {
      final message = event as Map;
      if (message['type'] == 'ready') ready.complete(message);
      if (message['type'] == 'closed') {
        closed.complete((message['codes'] as List).cast<int>());
      }
      if (message['type'] == 'error') {
        final error = StateError(message['error'] as String);
        if (!ready.isCompleted) ready.completeError(error);
        if (!closed.isCompleted) closed.completeError(error);
      }
    });
    final isolate = await Isolate.spawn(_peerMain, {
      'send': receive.sendPort,
      'scenario': scenario,
    }, onExit: exit.sendPort);
    final config = await ready.future.timeout(const Duration(seconds: 5));
    return _Peer(
      isolate,
      config['port'] as int,
      config['control'] as SendPort,
      receive,
      exited,
      closed,
      subscription,
    );
  }

  Future<List<int>> close() {
    if (!closed.isCompleted) control.send(null);
    return closed.future.timeout(const Duration(seconds: 5));
  }

  Future<void> dispose() async {
    if (!closed.isCompleted) await close();
    await exited.timeout(const Duration(seconds: 5));
    await subscription.cancel();
    receivePort.close();
  }
}

Future<void> _peerMain(Map<String, Object?> config) async {
  final send = config['send'] as SendPort;
  final scenario = config['scenario'] as String;
  final control = ReceivePort();
  final server = await ServerSocket.bind('127.0.0.1', 0);
  Socket? connection;
  final codes = <int>[];
  control.listen((_) async {
    connection?.destroy();
    await server.close();
    control.close();
    send.send({'type': 'closed', 'codes': codes});
  });
  server.listen((socket) {
    connection = socket;
    var bytes = Uint8List(0);
    var handshake = false;
    var profile = const flat.FlatBuffersSessionProfile.router();
    final codec = flat.Serializer();
    void write(AbstractMessage message, {bool acknowledge = true}) {
      if (acknowledge) profile = profile.prepareOutgoing(message);
      final encoded = codec.serialize(message);
      socket.add([
        0,
        (encoded.length >> 16) & 255,
        (encoded.length >> 8) & 255,
        encoded.length & 255,
        ...encoded,
      ]);
    }

    socket.listen(
      (chunk) {
        try {
          bytes = Uint8List.fromList([...bytes, ...chunk]);
          if (!handshake) {
            if (bytes.length < 4) return;
            if (bytes[0] != 0x7f || (bytes[1] & 15) != 5) {
              throw StateError('Incorrect FlatBuffers negotiation');
            }
            socket.add([0x7f, bytes[1], 0, 0]);
            bytes = Uint8List.sublistView(bytes, 4);
            handshake = true;
          }
          while (bytes.length >= 4) {
            final length = (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
            if (bytes.length < 4 + length) return;
            final message = codec.deserialize(
              Uint8List.sublistView(bytes, 4, 4 + length),
            )!;
            bytes = Uint8List.sublistView(bytes, 4 + length);
            codes.add(message.id);
            // A deliberately unacknowledged challenge cannot establish a profile.
            if (scenario != 'missing-challenge' || message is Hello) {
              profile = profile.acceptIncoming(message);
            }
            if (message is Hello) {
              if (scenario == 'anonymous' || scenario == 'ppt-echo') {
                write(Welcome(42, Details.forWelcome()));
              } else {
                write(
                  Challenge('ticket', Extra()),
                  acknowledge: scenario != 'missing-challenge',
                );
              }
            } else if (message is Authenticate) {
              write(
                Welcome(42, Details.forWelcome()),
                acknowledge: scenario != 'missing-welcome',
              );
            } else if (message is Call) {
              if (scenario == 'ppt-echo') {
                final result = Result(
                  message.requestId,
                  ResultDetails(
                    pptScheme: message.options?.pptScheme,
                    pptSerializer: message.options?.pptSerializer,
                  ),
                  arguments: message.arguments,
                  argumentsKeywords: message.argumentsKeywords,
                )..transparentBinaryPayload = message.transparentBinaryPayload;
                write(result);
              } else {
                write(
                  Result(
                    message.requestId,
                    ResultDetails(),
                    arguments: message.arguments,
                  ),
                );
              }
            } else if (message is Goodbye) {
              write(Goodbye(null, 'wamp.close.goodbye_and_out'));
            }
          }
        } catch (error) {
          send.send({'type': 'error', 'error': error.toString()});
        }
      },
      onError: (Object error) =>
          send.send({'type': 'error', 'error': error.toString()}),
    );
  });
  send.send({
    'type': 'ready',
    'port': server.port,
    'control': control.sendPort,
  });
}
