@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';
import 'package:connectanum_client/src/transport/socket/socket_helper.dart';
import 'package:connectanum_client/src/transport/socket/socket_transport.dart';
import 'package:test/test.dart';

void main() {
  group('Socket open and close', () {
    test('initial close', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) {
        socket.listen((message) {});
      });
      final transportJson = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        json_serializer.Serializer(),
        SocketHelper.serializationJson,
      );
      await transportJson.open();
      transportJson.receive().listen((event) {});
      await transportJson.close();

      final transportMsgpack = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        msgpack_serializer.Serializer(),
        SocketHelper.serializationMsgpack,
      );
      await transportMsgpack.open();
      transportMsgpack.receive().listen((event) {});
      await transportMsgpack.close();

      final transportCbor = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        cbor_serializer.Serializer(),
        SocketHelper.serializationCbor,
      );
      await transportCbor.open();
      transportCbor.receive().listen((event) {});
      await transportCbor.close();
    });
  });
  group('Socket protocol negotiation', () {
    test('upgrade exponent uses the documented low nibble', () {
      for (final exponent in const <int>[25, 30, 40]) {
        final handshake = Uint8List.fromList(
          SocketHelper.getUpgradeHandshake(exponent),
        );
        expect(handshake[0], 0x3F);
        expect(handshake[1] & 0xF0, 0);
        expect(
          SocketHelper.getMaxUpgradeMessageSizeExponent(handshake),
          exponent,
        );
      }
    });

    test('Opening with max header', () async {
      var handshakes = <Uint8List?>[null, null];
      var serializer = json_serializer.Serializer();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(
              SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
                SocketHelper.serializationJson,
              ),
            );
          }
          if (message.length == 2) {
            handshakes[1] = message;
            socket.add(
              SocketHelper.getUpgradeHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
              ),
            );
          }
        });
      });
      final transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        serializer,
        SocketHelper.serializationJson,
        messageLengthExponent: SocketHelper.maxMessageLengthConnectanumExponent,
      );
      addTearDown(() => transport.close());
      await transport.open();
      final handshakeCompleter = Completer();
      unawaited(
        transport.onReady.then((aVoid) {
          handshakeCompleter.complete();
        }),
      );
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0]![0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 30)));
      expect(handshakes[1]![0], equals(0x3F));
    });
    test('Opening with server only allowing power of 20', () async {
      var handshakes = <Uint8List?>[null, null];
      var serializer = json_serializer.Serializer();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(
              SocketHelper.getInitialHandshake(
                20,
                SocketHelper.serializationJson,
              ),
            );
          }
        });
      });
      final transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        serializer,
        SocketHelper.serializationJson,
        messageLengthExponent: SocketHelper.maxMessageLengthConnectanumExponent,
      );
      addTearDown(() => transport.close());
      await transport.open();
      final handshakeCompleter = Completer();
      unawaited(
        transport.onReady.then((aVoid) {
          handshakeCompleter.complete();
        }),
      );
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0]![0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 20)));
      expect(handshakes[1], equals(null));
    });
    test('Opening with client max header of 20', () async {
      var handshakes = <Uint8List?>[null, null];
      var serializer = json_serializer.Serializer();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) {
        socket.listen((message) {
          if (message.length == 4) {
            handshakes[0] = message;
            socket.add(
              SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
                SocketHelper.serializationJson,
              ),
            );
          }
          if (message.length == 2) {
            // Server could response with 30 but doesn't
            handshakes[1] = message;
            socket.add(
              SocketHelper.getUpgradeHandshake(
                SocketHelper.maxMessageLengthConnectanumExponent,
              ),
            );
          }
        });
      });
      final transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        serializer,
        SocketHelper.serializationJson,
        messageLengthExponent: 20,
      );
      addTearDown(() => transport.close());
      await transport.open();
      final handshakeCompleter = Completer();
      unawaited(
        transport.onReady.then((aVoid) {
          handshakeCompleter.complete();
        }),
      );
      transport.receive().listen((message) {});
      await handshakeCompleter.future;
      expect(handshakes[0]![0], equals(0x7F));
      expect(transport.maxMessageLength, equals(pow(2, 20)));
      expect(handshakes[1], equals(null));
    });
    test('Opening with server error', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) {
        socket.listen((message) {
          if (SocketHelper.getMaxMessageSizeExponent(message) == 9) {
            socket.add(
              SocketHelper.getError(
                SocketHelper.errorMaxConnectionCountExceeded,
              ),
            );
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 10) {
            socket.add(
              SocketHelper.getError(SocketHelper.errorUseOfReservedBits),
            );
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 11) {
            socket.add(
              SocketHelper.getError(SocketHelper.errorMessageLengthExceeded),
            );
          }
          if (SocketHelper.getMaxMessageSizeExponent(message) == 12) {
            socket.add(
              SocketHelper.getError(SocketHelper.errorSerializerNotSupported),
            );
          }
        });
      });

      // error 1
      var transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        json_serializer.Serializer(),
        SocketHelper.serializationJson,
        messageLengthExponent: 9,
      );
      await transport.open();
      var errorCompleter = Completer();
      unawaited(
        transport.onReady.then(
          (aVoid) {},
          onError: (error) => errorCompleter.complete(error),
        ),
      );
      transport.receive().listen(
        (message) {},
        onError: (error) => transport.onDisconnect!.complete(error),
      );
      var error = await errorCompleter.future;
      expect(error['error'], isNotNull);
      expect(
        error['errorNumber'],
        equals(SocketHelper.errorMaxConnectionCountExceeded),
      );
      await transport.onDisconnect!.future;
      expect(transport.isOpen, isFalse);

      // error 2
      transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        json_serializer.Serializer(),
        SocketHelper.serializationJson,
        messageLengthExponent: 10,
      );
      await transport.open();
      errorCompleter = Completer();
      unawaited(
        transport.onReady.then(
          (aVoid) {},
          onError: (error) => errorCompleter.complete(error),
        ),
      );
      transport.receive().listen(
        (message) {},
        onError: (error) => transport.onDisconnect!.complete(error),
        cancelOnError: true,
      );
      error = await errorCompleter.future;
      expect(error['error'], isNotNull);
      expect(error['errorNumber'], equals(SocketHelper.errorUseOfReservedBits));
      await transport.onDisconnect!.future;
      expect(transport.isOpen, isFalse);

      // error 3
      transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        json_serializer.Serializer(),
        SocketHelper.serializationJson,
        messageLengthExponent: 11,
      );
      await transport.open();
      errorCompleter = Completer();
      unawaited(
        transport.onReady.then(
          (aVoid) {},
          onError: (error) => errorCompleter.complete(error),
        ),
      );
      transport.receive().listen(
        (message) {},
        onError: (error) => transport.onDisconnect!.complete(error),
      );
      error = await errorCompleter.future;
      expect(error['error'], isNotNull);
      expect(
        error['errorNumber'],
        equals(SocketHelper.errorMessageLengthExceeded),
      );
      await transport.onDisconnect!.future;
      expect(transport.isOpen, isFalse);

      // error 4
      transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        json_serializer.Serializer(),
        SocketHelper.serializationJson,
        messageLengthExponent: 12,
      );
      await transport.open();
      errorCompleter = Completer();
      unawaited(
        transport.onReady.then(
          (aVoid) {},
          onError: (error) => errorCompleter.complete(error),
        ),
      );
      transport.receive().listen(
        (message) {},
        onError: (error) => transport.onDisconnect!.complete(error),
      );
      error = await errorCompleter.future;
      expect(error['error'], isNotNull);
      expect(
        error['errorNumber'],
        equals(SocketHelper.errorSerializerNotSupported),
      );
      await transport.onDisconnect!.future;
      expect(transport.isOpen, isFalse);
    });
    test('Ping Pong', () async {
      var serializer = json_serializer.Serializer();
      var pongCompleter = Completer();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) {
        socket.listen((message) {
          if (message[0] == 0x7F) {
            socket.add(
              SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthExponent,
                SocketHelper.serializationJson,
              ),
            );
            if (message.length > 4) {
              message = message.sublist(4);
            }
          }
          if (message[0] == SocketHelper.messagePing) {
            Future.delayed(Duration(milliseconds: 1)).then((_) {
              socket.add(
                SocketHelper.getPong(0, false) + SocketHelper.getPing(false),
              );
            });
            if (message.length > 4) {
              message = message.sublist(4);
            }
          }
          if (message[0] == SocketHelper.messagePong) {
            pongCompleter.complete();
          }
        });
      });
      final transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        serializer,
        SocketHelper.serializationJson,
        messageLengthExponent: SocketHelper.maxMessageLengthExponent,
      );
      addTearDown(() => transport.close());
      await transport.open();
      transport.receive().listen((message) {});
      var pong = await transport.sendPing();
      expect(pong, isNotNull);
      await pongCompleter.future;
      expect(pongCompleter.isCompleted, isTrue);
    });

    test(
      'sends WAMP frames as a single socket write after handshake',
      () async {
        final serializer = json_serializer.Serializer();
        final receivedFrames = <Uint8List>[];
        final frameCompleter = Completer<void>();
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((socket) {
          var handshakeDone = false;
          socket.listen((message) {
            if (!handshakeDone) {
              handshakeDone = true;
              socket.add(
                SocketHelper.getInitialHandshake(
                  SocketHelper.maxMessageLengthExponent,
                  SocketHelper.serializationJson,
                ),
              );
              return;
            }
            receivedFrames.add(Uint8List.fromList(message));
            if (!frameCompleter.isCompleted) {
              frameCompleter.complete();
            }
          });
        });

        final transport = SocketTransport(
          InternetAddress.loopbackIPv4.address,
          server.port,
          serializer,
          SocketHelper.serializationJson,
          messageLengthExponent: SocketHelper.maxMessageLengthExponent,
        );
        await transport.open();
        transport.receive().listen((_) {});
        await transport.onReady;

        transport.send(Hello('bench.realm', Details.forHello()));
        await frameCompleter.future;

        expect(receivedFrames, hasLength(1));
        final frame = receivedFrames.single;
        expect(frame.first, SocketHelper.messageWamp);
        final payloadLength = SocketHelper.getPayloadLength(
          frame,
          transport.headerLength,
        );
        expect(payloadLength, frame.length - transport.headerLength);

        await transport.close();
        await server.close();
      },
    );

    test('buffers partial raw socket frames until complete', () async {
      final serializer = json_serializer.Serializer();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        var handshakeDone = false;
        socket.listen((message) {
          if (handshakeDone) {
            return;
          }
          handshakeDone = true;
          socket.add(
            SocketHelper.getInitialHandshake(
              SocketHelper.maxMessageLengthExponent,
              SocketHelper.serializationJson,
            ),
          );
          final encoded = utf8.encoder.convert(
            serializer.serialize(
              Goodbye(GoodbyeMessage('bye'), Goodbye.reasonGoodbyeAndOut),
            ),
          );
          final frame = Uint8List.fromList(
            SocketHelper.buildMessageHeader(
                  SocketHelper.messageWamp,
                  encoded.length,
                  false,
                ) +
                encoded,
          );
          socket.add(frame.sublist(0, 3));
          Future<void>.delayed(const Duration(milliseconds: 10)).then((_) {
            socket.add(frame.sublist(3));
          });
        });
      });

      final transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        serializer,
        SocketHelper.serializationJson,
        messageLengthExponent: SocketHelper.maxMessageLengthExponent,
      );
      await transport.open();

      final message = await transport.receive().first.timeout(
        const Duration(seconds: 1),
      );

      expect(message, isA<Goodbye>());

      await transport.close();
      await server.close();
    });

    test(
      'retains fragmented CBOR payloads when the final chunk includes another frame',
      () async {
        final serializer = cbor_serializer.Serializer();
        final payload = Uint8List.fromList(
          List<int>.generate(256 * 1024, (index) => index & 0xff),
        );
        final firstPayload = serializer.serialize(
          Result(7, ResultDetails(), arguments: <dynamic>[payload]),
        );
        final secondPayload = serializer.serialize(
          Goodbye(GoodbyeMessage('bye'), Goodbye.reasonGoodbyeAndOut),
        );
        Uint8List frame(Uint8List encoded) {
          final builder = BytesBuilder(copy: false)
            ..add(
              SocketHelper.buildMessageHeader(
                SocketHelper.messageWamp,
                encoded.length,
                false,
              ),
            )
            ..add(encoded);
          return builder.takeBytes();
        }

        final firstFrame = frame(firstPayload);
        final secondFrame = frame(secondPayload);
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final acceptedSockets = <Socket>[];
        addTearDown(() async {
          for (final socket in acceptedSockets) {
            socket.destroy();
          }
          await server.close();
        });
        server.listen((socket) {
          acceptedSockets.add(socket);
          var handshakeDone = false;
          socket.listen((message) {
            if (handshakeDone) {
              return;
            }
            handshakeDone = true;
            socket.add(
              SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthExponent,
                SocketHelper.serializationCbor,
              ),
            );
            unawaited(() async {
              const retainedTailLength = 11;
              final fragmentedLength = firstFrame.length - retainedTailLength;
              const forcedFirstChunkLength = 4093;
              socket.add(
                Uint8List.sublistView(
                  firstFrame,
                  0,
                  forcedFirstChunkLength,
                ),
              );
              await socket.flush();
              await Future<void>.delayed(const Duration(milliseconds: 10));
              var offset = forcedFirstChunkLength;
              while (offset < fragmentedLength) {
                final end = min(offset + 4093, fragmentedLength);
                socket.add(Uint8List.sublistView(firstFrame, offset, end));
                await socket.flush();
                offset = end;
              }
              final combined = BytesBuilder(copy: false)
                ..add(
                  Uint8List.sublistView(
                    firstFrame,
                    fragmentedLength,
                    firstFrame.length,
                  ),
                )
                ..add(secondFrame);
              socket.add(combined.takeBytes());
            }());
          });
        });

        final transport = SocketTransport(
          InternetAddress.loopbackIPv4.address,
          server.port,
          serializer,
          SocketHelper.serializationCbor,
          messageLengthExponent: SocketHelper.maxMessageLengthExponent,
        );
        addTearDown(() => transport.close());
        await transport.open();

        final messages = await transport
            .receive()
            .take(2)
            .toList()
            .timeout(
              const Duration(seconds: 5),
            );

        expect(messages, hasLength(2));
        expect(messages.first, isA<Result>());
        expect(messages.last, isA<Goodbye>());
        expect(hasRetainedNativeExternalBytes(messages.first), isTrue);
        final receivedPayload =
            (messages.first as Result).arguments!.single as Uint8List;
        expect(receivedPayload, orderedEquals(payload));
        expect(
          nativeExternalByteSlice(receivedPayload, anchor: messages.first),
          isNotNull,
        );
      },
    );

    test('sends a large CBOR call as one segmented RawSocket frame', () async {
      final serializer = cbor_serializer.Serializer();
      final receivedFrame = Completer<Uint8List>();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final acceptedSockets = <Socket>[];
      addTearDown(() async {
        for (final socket in acceptedSockets) {
          socket.destroy();
        }
        await server.close();
      });
      server.listen((socket) {
        acceptedSockets.add(socket);
        var handshakeDone = false;
        final received = <int>[];
        int? frameLength;
        socket.listen((message) {
          if (!handshakeDone) {
            handshakeDone = true;
            socket.add(
              SocketHelper.getInitialHandshake(
                SocketHelper.maxMessageLengthExponent,
                SocketHelper.serializationCbor,
              ),
            );
            return;
          }
          received.addAll(message);
          if (frameLength == null && received.length >= 4) {
            final prefix = Uint8List.fromList(received.take(4).toList());
            frameLength = 4 + SocketHelper.getPayloadLength(prefix, 4);
          }
          if (frameLength case final expected?
              when received.length >= expected && !receivedFrame.isCompleted) {
            receivedFrame.complete(Uint8List.fromList(received));
          }
        });
      });

      final transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        serializer,
        SocketHelper.serializationCbor,
        messageLengthExponent: SocketHelper.maxMessageLengthExponent,
      );
      addTearDown(() => transport.close());
      await transport.open();
      transport.receive().listen((_) {});
      await transport.onReady;
      final payload = Uint8List.fromList(
        List<int>.generate(256 * 1024, (index) => index & 0xff),
      );

      transport.send(
        Call(11, 'bench.rpc.echo', arguments: <dynamic>[payload]),
      );
      final rawFrame = await receivedFrame.future.timeout(
        const Duration(seconds: 5),
      );

      expect(rawFrame.first, SocketHelper.messageWamp);
      final encodedLength = SocketHelper.getPayloadLength(rawFrame, 4);
      expect(rawFrame, hasLength(4 + encodedLength));
      final call =
          serializer.deserialize(
                Uint8List.sublistView(rawFrame, 4, rawFrame.length),
              )
              as Call;
      expect(call.procedure, equals('bench.rpc.echo'));
      expect(call.arguments!.single, orderedEquals(payload));
    });

    test('closes connection when inbound WAMP frame is malformed', () async {
      final serializer = json_serializer.Serializer();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final acceptedSockets = <Socket>[];
      addTearDown(() async {
        for (final socket in acceptedSockets) {
          socket.destroy();
        }
        await server.close();
      });

      server.listen((socket) {
        acceptedSockets.add(socket);
        var handshakeDone = false;
        socket.listen((message) {
          if (handshakeDone) {
            return;
          }
          handshakeDone = true;
          socket.add(
            SocketHelper.getInitialHandshake(
              SocketHelper.maxMessageLengthExponent,
              SocketHelper.serializationJson,
            ),
          );
          final encoded = utf8.encoder.convert('[999]');
          final frame = Uint8List.fromList(
            SocketHelper.buildMessageHeader(
                  SocketHelper.messageWamp,
                  encoded.length,
                  false,
                ) +
                encoded,
          );
          socket.add(frame);
        });
      });

      final transport = SocketTransport(
        InternetAddress.loopbackIPv4.address,
        server.port,
        serializer,
        SocketHelper.serializationJson,
        messageLengthExponent: SocketHelper.maxMessageLengthExponent,
      );
      addTearDown(() => transport.close());

      await transport.open();
      final subscription = transport.receive().listen((_) {});
      addTearDown(subscription.cancel);
      await transport.onReady;

      final error = await transport.onConnectionLost!.future.timeout(
        const Duration(seconds: 1),
      );

      expect(error, isA<FormatException>());
      expect(
        error.toString(),
        contains('Could not deserialize inbound WAMP message'),
      );
      expect(transport.isOpen, isFalse);
    });
  });

  group('Socket helper validation', () {
    test('rejects unknown raw socket message types', () {
      expect(
        SocketHelper.isValidMessage(Uint8List.fromList([9, 0, 0, 0])),
        isFalse,
      );
      expect(
        SocketHelper.isValidMessage(
          Uint8List.fromList([SocketHelper.messageWamp, 0, 0, 0]),
        ),
        isTrue,
      );
    });
  });
}
