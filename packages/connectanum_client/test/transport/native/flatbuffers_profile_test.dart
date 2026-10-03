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
        expect(await messages.moveNext(), isTrue);
        expect(messages.current, isA<Welcome>());
        client.send(Call(1, 'com.echo', arguments: ['value']));
        expect(await messages.moveNext(), isTrue);
        expect((messages.current as Result).arguments, ['value']);
        client.send(Goodbye(null, 'wamp.close.normal'));
        expect(await messages.moveNext(), isTrue);
        expect(messages.current, isA<Goodbye>());
        expect(await peer.close(), [1, 48, 6]);
      } finally {
        await messages.cancel();
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
          if (tracked) {
            final receipt = client.sendEncodedNativeBufferTracked(
              encodedOffer,
              transfer: true,
            );
            expect(await receipt.wait(), NativeWriteOutcome.written);
            receipt.dispose();
          } else {
            client.sendEncodedNativeBuffer(encodedOffer, transfer: true);
          }
          expect(encodedOffer.isDisposed, isTrue);
          expect(await messages.moveNext(), isTrue);
          expect(messages.current, isA<Welcome>());
          final encodedCall = _encodeNative(
            client,
            Call(1, 'com.echo', arguments: ['owned']),
          );
          client.sendEncodedNativeBuffer(encodedCall, transfer: true);
          expect(await messages.moveNext(), isTrue);
          expect((messages.current as Result).arguments, ['owned']);
          expect(await peer.close(), [1, 48]);
        } finally {
          await messages.cancel();
          await client.close();
          await peer.dispose();
        }
      },
    );
  }
}

Future<Stream<AbstractMessage?>> _open(NativeRawSocketTransport client) async {
  await client.open();
  await client.onReady.timeout(const Duration(seconds: 5));
  return client.receive();
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
              if (scenario == 'anonymous') {
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
              write(
                Result(
                  message.requestId,
                  ResultDetails(),
                  arguments: message.arguments,
                ),
              );
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
