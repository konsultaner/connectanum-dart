@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_client/src/transport/native/native_transports_io.dart'
    as native;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:test/test.dart';
import 'package:crypto/crypto.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';

const _deadline = Duration(seconds: 5);

// RFC 6455 continuation frames, emitted independently of the client encoder.
int _sendFragments(Socket socket, Uint8List payload) {
  var frames = 0;
  for (var offset = 0; offset < payload.length; offset += 4096) {
    final end = (offset + 4096).clamp(0, payload.length);
    final length = end - offset;
    final header = Uint8List(length < 126 ? 2 : 4);
    header[0] = (offset == 0 ? 2 : 0) | (end == payload.length ? 128 : 0);
    if (length < 126) {
      header[1] = length;
    } else {
      header[1] = 126;
      ByteData.sublistView(header).setUint16(2, length, Endian.big);
    }
    socket.add(header);
    socket.add(Uint8List.sublistView(payload, offset, end));
    frames++;
  }
  return frames;
}

Future<void> _server(List<Object?> startup) async {
  final parent = startup[0] as SendPort;
  final config = startup[1] as Map<String, Object?>;
  final commands = ReceivePort();
  final sockets = <WebSocket>[];
  HttpServer? server;
  try {
    if (config['tls'] == true) {
      final security = SecurityContext()
        ..useCertificateChain(config['certificate'] as String)
        ..usePrivateKey(config['key'] as String);
      server = await HttpServer.bindSecure('127.0.0.1', 0, security);
    } else {
      server = await HttpServer.bind('127.0.0.1', 0);
    }
    parent.send({'port': server.port, 'commands': commands.sendPort});
    final codes = <int>[];
    final codec = flat.Serializer();
    final subscription = server.listen((request) async {
      try {
        final scenario = config['scenario'];
        Socket? fragmentedSocket;
        late WebSocket socket;
        if (scenario == 'fragmented-incoming' ||
            scenario == 'missing-protocol' ||
            scenario == 'wrong-protocol') {
          final selected = scenario == 'missing-protocol'
              ? null
              : scenario == 'wrong-protocol'
              ? 'wamp.2.json'
              : 'wamp.2.flatbuffers';
          final key = request.headers.value('Sec-WebSocket-Key')!;
          final response = request.response;
          response.statusCode = HttpStatus.switchingProtocols;
          response.headers
            ..set('Upgrade', 'websocket')
            ..set('Connection', 'Upgrade')
            ..set(
              'Sec-WebSocket-Accept',
              base64.encode(
                sha1
                    .convert(
                      utf8.encode(
                        '$key'
                        '258EAFA5-E914-47DA-95CA-C5AB0DC85B11',
                      ),
                    )
                    .bytes,
              ),
            );
          if (selected != null)
            response.headers.set('Sec-WebSocket-Protocol', selected);
          final raw = await response.detachSocket(writeHeaders: true);
          socket = WebSocket.fromUpgradedSocket(
            raw,
            serverSide: true,
            protocol: selected,
          );
          if (scenario == 'fragmented-incoming') fragmentedSocket = raw;
        } else {
          socket = await WebSocketTransformer.upgrade(
            request,
            protocolSelector: (protocols) => protocols.single,
          );
        }
        sockets.add(socket);
        parent.send({'protocol': socket.protocol});
        var profile = const flat.FlatBuffersSessionProfile.router();
        void send(core.AbstractMessage message, {bool acknowledge = true}) {
          if (acknowledge) profile = profile.prepareOutgoing(message);
          final bytes = codec.serialize(message);
          final raw = fragmentedSocket;
          if (raw == null) {
            socket.add(bytes);
          } else {
            parent.send({'frames': _sendFragments(raw, bytes)});
          }
        }

        socket.listen((input) {
          try {
            final message = codec.deserialize(
              Uint8List.fromList(input as List<int>),
            )!;
            codes.add(message.id);
            parent.send({'codes': codes.toList()});
            profile = profile.acceptIncoming(message);
            final scenario = config['scenario'];
            if (message is core.Hello) {
              if (scenario == 'anonymous' ||
                  scenario == 'fragmented-incoming') {
                send(core.Welcome(42, core.Details.forWelcome()));
              } else {
                send(
                  core.Challenge('ticket', core.Extra()),
                  acknowledge: scenario != 'missing-challenge',
                );
              }
            } else if (message is core.Authenticate) {
              if (message.signature != 'secret')
                throw StateError('Wrong ticket');
              send(
                core.Welcome(42, core.Details.forWelcome()),
                acknowledge: scenario != 'missing-welcome',
              );
            } else if (message is core.Call) {
              if (message.procedure == 'missing') {
                send(
                  core.Error(
                    48,
                    message.requestId,
                    {},
                    'wamp.error.no_such_procedure',
                  ),
                );
              } else {
                if (message.options?.receiveProgress == true) {
                  send(
                    core.Result(
                      message.requestId,
                      core.ResultDetails(progress: true),
                      arguments: ['progress'],
                    ),
                  );
                }
                send(
                  core.Result(
                    message.requestId,
                    core.ResultDetails(),
                    arguments: message.arguments,
                    argumentsKeywords: message.argumentsKeywords,
                  ),
                );
              }
            } else if (message is core.Subscribe) {
              send(core.Subscribed(message.requestId, 100));
            } else if (message is core.Publish) {
              send(
                core.Event(
                  100,
                  101,
                  core.EventDetails(),
                  arguments: message.arguments,
                ),
              );
            } else if (message is core.Goodbye) {
              send(core.Goodbye(null, 'wamp.close.goodbye_and_out'));
            }
          } catch (error, stack) {
            parent.send({'error': '$error\n$stack'});
          }
        }, onError: (Object error) => parent.send({'error': '$error'}));
      } catch (error, stack) {
        parent.send({'error': '$error\n$stack'});
      }
    }, onError: (Object error) => parent.send({'error': '$error'}));
    await commands.first;
    for (final socket in sockets) {
      await socket.close();
    }
    await subscription.cancel();
    await server.close(force: true);
    parent.send({'closed': true});
  } catch (error, stack) {
    parent.send({'error': '$error\n$stack'});
  } finally {
    commands.close();
  }
}

class _Peer {
  _Peer(this.inbox);
  final ReceivePort inbox;
  final ready = Completer<void>();
  final closed = Completer<void>();
  final selected = Completer<String?>();
  final errors = <Object>[];
  List<int> codes = [];
  final frames = <int>[];
  late int port;
  late SendPort commands;
  late Isolate isolate;
  late StreamSubscription<dynamic> subscription;
  static Future<_Peer> start(bool tls, String scenario) async {
    final peer = _Peer(ReceivePort());
    peer.subscription = peer.inbox.listen((dynamic input) {
      final event = input as Map;
      if (event.containsKey('port')) {
        peer.port = event['port'] as int;
        peer.commands = event['commands'] as SendPort;
        peer.ready.complete();
      } else if (event.containsKey('codes')) {
        peer.codes = (event['codes'] as List).cast<int>();
      } else if (event.containsKey('protocol')) {
        if (!peer.selected.isCompleted)
          peer.selected.complete(event['protocol'] as String?);
      } else if (event.containsKey('frames')) {
        peer.frames.add(event['frames'] as int);
      } else if (event.containsKey('closed')) {
        peer.closed.complete();
      } else if (event.containsKey('error')) {
        peer.errors.add(event['error']!);
        if (!peer.ready.isCompleted)
          peer.ready.completeError(StateError('${event['error']}'));
      }
    });
    final package = await Isolate.resolvePackageUri(
      Uri.parse('package:connectanum_client/native_buffers.dart'),
    );
    peer.isolate = await Isolate.spawn(_server, <Object?>[
      peer.inbox.sendPort,
      <String, Object?>{
        'tls': tls,
        'scenario': scenario,
        'certificate': package!
            .resolve('../../../native/bench/bench_tls.crt')
            .toFilePath(),
        'key': package
            .resolve('../../../native/bench/bench_tls.key')
            .toFilePath(),
      },
    ]);
    await peer.ready.future.timeout(_deadline);
    return peer;
  }

  Future<void> dispose() async {
    commands.send('close');
    try {
      await closed.future.timeout(_deadline);
    } finally {
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      inbox.close();
    }
  }
}

Future<core.AbstractMessage> _next(
  StreamIterator<core.AbstractMessage?> input,
) async {
  expect(await input.moveNext().timeout(_deadline), isTrue);
  return input.current!;
}

void main() {
  final library = Platform.environment['CONNECTANUM_NATIVE_LIB']!;
  _nativeContractTests(library);
  _nativeComposedTests(library);
  for (final tls in [false, true]) {
    for (final scenario in ['anonymous', 'ticket']) {
      test(
        'native FlatBuffers WebSocket TLS=$tls $scenario fragmented sends RPC/pubsub/progress/error',
        () async {
          final peer = await _Peer.start(tls, scenario);
          final channel =
              native.NativeWebSocketTransport.withFlatBuffersSerializer(
                '${tls ? 'wss' : 'ws'}://127.0.0.1:${peer.port}/ws',
                null,
                tls,
                library,
                4096,
              );
          StreamIterator<core.AbstractMessage?>? input;
          try {
            final opening = channel.open();
            await channel.onReady.timeout(_deadline);
            await opening;
            expect(
              await peer.selected.future.timeout(_deadline),
              'wamp.2.flatbuffers',
            );
            input = StreamIterator(channel.receive());
            expect(() => channel.send(core.Call(1, 'echo')), throwsStateError);
            channel.send(core.Hello('realm', core.Details.forHello()));
            if (scenario == 'ticket') {
              expect(await _next(input), isA<core.Challenge>());
              channel.send(core.Authenticate(signature: 'secret'));
            }
            expect(await _next(input), isA<core.Welcome>());
            final data = Uint8List.fromList(
              List.generate(128 * 1024, (i) => i % 251),
            );
            channel.send(
              core.Call(
                1,
                'echo',
                arguments: [data],
                options: core.CallOptions(receiveProgress: true),
              ),
            );
            final progress = await _next(input) as core.Result;
            expect(progress.details.progress, isTrue);
            expect(progress.arguments, ['progress']);
            final result = await _next(input) as core.Result;
            expect(result.arguments!.single, orderedEquals(data));
            channel.send(core.Call(2, 'missing'));
            final error = await _next(input) as core.Error;
            expect(error.requestId, 2);
            expect(error.error, 'wamp.error.no_such_procedure');
            channel.send(core.Subscribe(3, 'topic'));
            expect(await _next(input), isA<core.Subscribed>());
            channel.send(core.Publish(4, 'topic', arguments: [data]));
            final event = await _next(input) as core.Event;
            expect(event.arguments!.single, orderedEquals(data));
            channel.send(core.Goodbye(null, 'wamp.close.normal'));
            expect(await _next(input), isA<core.Goodbye>());
          } finally {
            try {
              await channel.close().timeout(_deadline);
            } finally {
              await input?.cancel();
              await peer.dispose();
            }
          }
          expect(peer.errors, isEmpty);
          expect(
            peer.codes,
            scenario == 'ticket'
                ? [1, 5, 48, 48, 32, 16, 6]
                : [1, 48, 48, 32, 16, 6],
          );
        },
      );
    }
  }
}

void _nativeComposedTests(String library) {
  for (final tls in [false, true]) {
    for (final transfer in [false, true]) {
      test(
        'native composed WebSocket TLS=$tls transfer=$transfer preserves large arguments and keywords',
        () async {
          final peer = await _Peer.start(tls, 'anonymous');
          final channel = _transport(
            peer,
            library,
            tls: tls,
            allowInsecure: tls,
          );
          StreamIterator<core.AbstractMessage?>? input;
          NativeFlatBufferFrame? frame;
          try {
            await channel.open();
            await channel.onReady.timeout(_deadline);
            input = StreamIterator(channel.receive());
            channel.send(core.Hello('realm', core.Details.forHello()));
            expect(await _next(input), isA<core.Welcome>());
            const payloadLength = 128 * 1024;
            final argsBuilder = channel.nativeBuffers.allocate(
              payloadLength + 6,
            );
            late final NativeOwnedBuffer args;
            try {
              // CBOR [binary], constructed directly in the native allocation.
              argsBuilder.setUint8(0, 0x81);
              argsBuilder.setUint8(1, 0x5a);
              argsBuilder.setUint32(2, payloadLength, Endian.big);
              for (var i = 0; i < payloadLength; i++) {
                argsBuilder.setUint8(i + 6, i % 251);
              }
              args = argsBuilder.freeze();
            } finally {
              argsBuilder.dispose();
            }
            final kwargsBuilder = channel.nativeBuffers.allocate(5)
              ..setUint8(0, 0xa1)
              ..setUint8(1, 0x61)
              ..setUint8(2, 0x6e)
              ..setUint8(3, 0x18)
              ..setUint8(4, 42);
            final kwargs = kwargsBuilder.freeze();
            kwargsBuilder.dispose();
            final controlBuilder = channel.nativeBuffers.flatBuffers(
              initialSize: 8192,
            );
            NativeOwnedBuffer? control;
            try {
              controlBuilder.finish(
                flat.writeWampFlatBufferMessage(
                  core.Call(7, 'echo'),
                  controlBuilder,
                ),
              );
              control = controlBuilder.freeze();
              frame = channel.nativeBuffers.composeFlatBufferFrame(
                control,
                arguments: args,
                argumentsKeywords: kwargs,
              );
              expect(args.inputCopiedBytes, 0);
              expect(args.growthCopiedBytes, 0);
              expect(kwargs.inputCopiedBytes, 0);
              expect(frame.segmentCount, greaterThan(2));
            } finally {
              controlBuilder.dispose();
              control?.dispose();
              args.dispose();
              kwargs.dispose();
            }
            final expected = List<int>.generate(payloadLength, (i) => i % 251);
            Future<void> exchange(bool transfer) async {
              final receipt = channel.sendNativeFrameTracked(
                frame!,
                transfer: transfer,
              );
              try {
                expect(frame.isDisposed, transfer);
                expect(
                  await receipt.wait().timeout(_deadline),
                  NativeWriteOutcome.written,
                );
                final result = await _next(input!) as core.Result;
                expect(result.callRequestId, 7);
                expect(result.arguments!.single, orderedEquals(expected));
                expect(result.argumentsKeywords, {'n': 42});
              } finally {
                receipt.dispose();
              }
            }

            await exchange(transfer);
            if (!transfer) {
              // Reuse the retained immutable frame, then transfer its final handle.
              await exchange(true);
            }
            channel.send(core.Goodbye(null, 'wamp.close.normal'));
            expect(await _next(input), isA<core.Goodbye>());
          } finally {
            frame?.dispose();
            try {
              await channel.close().timeout(_deadline);
            } finally {
              await input?.cancel();
              await peer.dispose();
            }
          }
          expect(peer.errors, isEmpty);
          expect(peer.codes, transfer ? [1, 48, 6] : [1, 48, 48, 6]);
        },
      );
    }
  }
}

class _GatedTransport extends native.NativeWebSocketTransport {
  _GatedTransport(
    String url,
    String library,
    this.gates, {
    this.connectFirst = false,
  }) : super(
         url,
         flat.Serializer(),
         'wamp.2.flatbuffers',
         null,
         false,
         library,
       );
  final List<Completer<void>> gates;
  final bool connectFirst;
  final allocated = Completer<int>();
  var attempts = 0;
  @override
  Future<int> openNativeConnection(Duration? pingInterval) async {
    final gate = gates[attempts++];
    int? id;
    if (connectFirst) {
      id = await super.openNativeConnection(pingInterval);
      allocated.complete(id);
    }
    await gate.future;
    return id ?? await super.openNativeConnection(pingInterval);
  }
}

native.NativeWebSocketTransport _transport(
  _Peer peer,
  String library, {
  bool tls = false,
  bool allowInsecure = false,
}) => native.NativeWebSocketTransport.withFlatBuffersSerializer(
  '${tls ? 'wss' : 'ws'}://127.0.0.1:${peer.port}/ws',
  null,
  allowInsecure,
  library,
);

void _nativeContractTests(String library) {
  test(
    'closing an old native transport cannot affect a restarted runtime',
    () async {
      final peer = await _Peer.start(false, 'anonymous');
      final old = _transport(peer, library);
      final fresh = _transport(peer, library);
      StreamIterator<core.AbstractMessage?>? input;
      try {
        await old.open();
        await old.onReady.timeout(_deadline);
        final oldId = old.connectionId!;
        NativeClientRuntime.shutdownShared();
        await fresh.open();
        await fresh.onReady.timeout(_deadline);
        expect(fresh.connectionId, isNot(oldId));
        await old.close().timeout(_deadline);
        expect(fresh.isReady, isTrue);
        input = StreamIterator(fresh.receive());
        fresh.send(core.Hello('realm', core.Details.forHello()));
        expect(await _next(input), isA<core.Welcome>());
      } finally {
        await old.close();
        await fresh.close();
        await input?.cancel();
        await peer.dispose();
      }
      expect(peer.errors, isEmpty);
      expect(peer.codes, [1]);
    },
  );
  test(
    'cancelled native open cannot close a connection after runtime restart',
    () async {
      final peer = await _Peer.start(false, 'anonymous');
      final old = _transport(peer, library);
      final fresh = _transport(peer, library);
      StreamIterator<core.AbstractMessage?>? input;
      try {
        final opening = old.open();
        final cancelled = expectLater(
          old.onReady.timeout(_deadline),
          throwsStateError,
        );
        final closing = old.close();
        NativeClientRuntime.shutdownShared();
        final freshOpening = fresh.open();
        await Future.wait([opening, closing, freshOpening]).timeout(_deadline);
        await cancelled;
        await fresh.onReady.timeout(_deadline);
        final id = fresh.connectionId!;
        expect(
          NativeClientRuntime.instance(
            libraryPath: library,
          ).connectionSupportsFileSegments(id),
          isTrue,
        );
        expect(old.connectionId, isNull);
        input = StreamIterator(fresh.receive());
        fresh.send(core.Hello('realm', core.Details.forHello()));
        expect(await _next(input), isA<core.Welcome>());
      } finally {
        await old.close();
        await fresh.close();
        await input?.cancel();
        await peer.dispose();
      }
      expect(peer.errors, isEmpty);
      expect(peer.codes, [1]);
    },
  );
  test(
    'native close does not wait for a paused receive subscription',
    () async {
      final peer = await _Peer.start(false, 'anonymous');
      final channel = _transport(peer, library);
      StreamSubscription<core.AbstractMessage?>? incoming;
      try {
        await channel.open();
        await channel.onReady.timeout(_deadline);
        incoming = channel.receive().listen((_) {})..pause();
        await channel.close().timeout(_deadline);
        expect(channel.isOpen, isFalse);
        expect(channel.onDisconnect!.isCompleted, isTrue);
      } finally {
        await incoming?.cancel();
        await channel.close();
        await peer.dispose();
      }
    },
  );
  test(
    'old native close preserves the reopened session and message stream',
    () async {
      final peer = await _Peer.start(false, 'anonymous');
      final channel = _transport(peer, library);
      StreamSubscription<core.AbstractMessage?>? oldIncoming;
      StreamIterator<core.AbstractMessage?>? input;
      try {
        await channel.open();
        await channel.onReady.timeout(_deadline);
        oldIncoming = channel.receive().listen((_) {});
        final oldDisconnect = channel.onDisconnect!;
        final closing = channel.close();
        await channel.open();
        await channel.onReady.timeout(_deadline);
        final freshDisconnect = channel.onDisconnect!;
        input = StreamIterator(channel.receive());
        await closing.timeout(_deadline);
        expect(oldDisconnect.isCompleted, isTrue);
        expect(freshDisconnect.isCompleted, isFalse);
        expect(channel.isOpen, isTrue);
        expect(channel.isReady, isTrue);
        channel.send(core.Hello('realm', core.Details.forHello()));
        expect(await _next(input), isA<core.Welcome>());
      } finally {
        await oldIncoming?.cancel();
        await channel.close();
        await input?.cancel();
        await peer.dispose();
      }
      expect(peer.errors, isEmpty);
    },
  );
  test(
    'cancelled native open closes its late allocation and fails old readiness',
    () async {
      final peer = await _Peer.start(false, 'anonymous');
      final gate = Completer<void>();
      final channel = _GatedTransport(
        'ws://127.0.0.1:${peer.port}/ws',
        library,
        [gate],
        connectFirst: true,
      );
      try {
        final opening = channel.open();
        final failedReady = expectLater(
          channel.onReady.timeout(_deadline),
          throwsStateError,
        );
        final id = await channel.allocated.future.timeout(_deadline);
        await channel.close().timeout(_deadline);
        gate.complete();
        await opening.timeout(_deadline);
        await failedReady;
        expect(channel.connectionId, isNull);
        expect(channel.isReady, isFalse);
        expect(
          () => NativeClientRuntime.instance(
            libraryPath: library,
          ).connectionSupportsFileSegments(id),
          throwsA(
            isA<NativeTransportException>().having(
              (e) => e.code,
              'connection was removed',
              -10,
            ),
          ),
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
        await channel.close();
        await peer.dispose();
      }
    },
  );
  test(
    'concurrent native opens share one attempt and readiness owner',
    () async {
      final peer = await _Peer.start(false, 'anonymous');
      final gate = Completer<void>();
      final channel = _GatedTransport(
        'ws://127.0.0.1:${peer.port}/ws',
        library,
        [gate],
      );
      try {
        final first = channel.open();
        final ready = channel.onReady;
        final second = channel.open();
        expect(channel.onReady, same(ready));
        expect(channel.attempts, 1);
        gate.complete();
        await Future.wait([first, second]).timeout(_deadline);
        await ready.timeout(_deadline);
        expect(channel.isReady, isTrue);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await channel.close();
        await peer.dispose();
      }
    },
  );
  test(
    'late cancelled native open error cannot poison reopened readiness',
    () async {
      final peer = await _Peer.start(false, 'anonymous');
      final oldGate = Completer<void>();
      final freshGate = Completer<void>();
      final channel = _GatedTransport(
        'ws://127.0.0.1:${peer.port}/ws',
        library,
        [oldGate, freshGate],
      );
      StreamIterator<core.AbstractMessage?>? input;
      try {
        final first = channel.open();
        final cancelled = expectLater(
          channel.onReady.timeout(_deadline),
          throwsStateError,
        );
        await channel.close().timeout(_deadline);
        await cancelled;
        final second = channel.open();
        final freshReady = channel.onReady;
        final freshLost = channel.onConnectionLost!;
        oldGate.completeError(StateError('old attempt failure'));
        await first.timeout(_deadline);
        expect(freshLost.isCompleted, isFalse);
        freshGate.complete();
        await second.timeout(_deadline);
        await freshReady.timeout(_deadline);
        expect(channel.isReady, isTrue);
        expect(freshLost.isCompleted, isFalse);
        input = StreamIterator(channel.receive());
        channel.send(core.Hello('realm', core.Details.forHello()));
        expect(await _next(input), isA<core.Welcome>());
      } finally {
        if (!oldGate.isCompleted) oldGate.complete();
        if (!freshGate.isCompleted) freshGate.complete();
        await channel.close();
        await input?.cancel();
        await peer.dispose();
      }
      expect(peer.errors, isEmpty);
    },
  );
  for (final scenario in ['missing-challenge', 'missing-welcome']) {
    test(
      'native $scenario profile rejected before dependent delivery',
      () async {
        final peer = await _Peer.start(false, scenario);
        final channel = _transport(peer, library);
        final delivered = <core.AbstractMessage?>[];
        final challenge = Completer<void>();
        final failure = Completer<Object>();
        StreamSubscription<core.AbstractMessage?>? incoming;
        try {
          await channel.open();
          await channel.onReady.timeout(_deadline);
          incoming = channel.receive().listen((message) {
            delivered.add(message);
            if (message is core.Challenge) challenge.complete();
          }, onError: (Object error) => failure.complete(error));
          channel.send(core.Hello('realm', core.Details.forHello()));
          if (scenario == 'missing-welcome') {
            await challenge.future.timeout(_deadline);
            channel.send(core.Authenticate(signature: 'secret'));
          }
          expect(
            await failure.future.timeout(_deadline),
            isA<UnsupportedError>().having(
              (e) => e.message,
              'profile diagnostic',
              contains('_connectanum_flatbuffers_metadata_v1'),
            ),
          );
          expect(
            delivered,
            scenario == 'missing-challenge'
                ? isEmpty
                : everyElement(isA<core.Challenge>()),
          );
          expect(() => channel.send(core.Call(7, 'echo')), throwsStateError);
        } finally {
          await channel.close().timeout(_deadline);
          await incoming?.cancel();
          await peer.dispose();
        }
        expect(peer.errors, isEmpty);
        expect(peer.codes, scenario == 'missing-challenge' ? [1] : [1, 5]);
      },
    );
  }
  for (final scenario in ['missing-protocol', 'wrong-protocol']) {
    test('native WebSocket rejects $scenario before WAMP sending', () async {
      final peer = await _Peer.start(false, scenario);
      final channel = _transport(peer, library);
      try {
        final opening = channel.open();
        await expectLater(
          channel.onReady,
          throwsA(isA<NativeTransportException>()),
        );
        await opening.timeout(_deadline);
        expect(channel.connectionId, isNull);
        expect(channel.isReady, isFalse);
        expect(
          () => channel.send(core.Hello('realm', core.Details.forHello())),
          throwsStateError,
        );
      } finally {
        await channel.close().timeout(_deadline);
        await peer.dispose();
      }
      expect(peer.codes, isEmpty);
    });
  }
  test(
    'native FlatBuffers TLS rejects untrusted peer without bypass',
    () async {
      final peer = await _Peer.start(true, 'anonymous');
      final channel = _transport(peer, library, tls: true);
      try {
        final opening = channel.open();
        await expectLater(
          channel.onReady,
          throwsA(isA<NativeTransportException>()),
        );
        await opening.timeout(_deadline);
        expect(channel.connectionId, isNull);
        expect(channel.isReady, isFalse);
      } finally {
        await channel.close().timeout(_deadline);
        await peer.dispose();
      }
      expect(peer.codes, isEmpty);
    },
  );
  test(
    'native FlatBuffers reassembles real server continuation frames',
    () async {
      final peer = await _Peer.start(false, 'fragmented-incoming');
      final channel = _transport(peer, library);
      StreamIterator<core.AbstractMessage?>? input;
      try {
        await channel.open();
        await channel.onReady.timeout(_deadline);
        input = StreamIterator(channel.receive());
        channel.send(core.Hello('realm', core.Details.forHello()));
        expect(await _next(input), isA<core.Welcome>());
        final data = Uint8List.fromList(
          List.generate(128 * 1024, (i) => i % 251),
        );
        channel.send(core.Call(7, 'echo', arguments: [data]));
        final result = await _next(input) as core.Result;
        expect(result.callRequestId, 7);
        expect(result.arguments!.single, orderedEquals(data));
      } finally {
        await channel.close().timeout(_deadline);
        await input?.cancel();
        await peer.dispose();
      }
      expect(peer.errors, isEmpty);
      expect(peer.frames, hasLength(2));
      expect(peer.frames.last, greaterThan(32));
    },
  );
}
