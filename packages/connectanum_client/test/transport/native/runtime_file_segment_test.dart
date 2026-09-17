@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor_codec;
import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_client/src/transport/native/native_transports_io.dart'
    show buildNativeFileSegmentPrefix;
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:test/test.dart';

import '../../test_support/native_runtime_support.dart';

final _wireCases = <(NativeMessageSerializer, AbstractSerializer)>[
  (NativeMessageSerializer.json, json.Serializer()),
  (NativeMessageSerializer.messagePack, msgpack.Serializer()),
  (NativeMessageSerializer.cbor, cbor.Serializer()),
];

Uint8List _encode(AbstractSerializer serializer, AbstractMessage message) {
  final encoded = serializer.serialize(message);
  return encoded is String ? Uint8List.fromList(utf8.encode(encoded)) : encoded;
}

Call _call(int request, Uint8List bytes) => Call(
  request,
  'files.write',
  options: CallOptions(progress: true),
)..arguments = <dynamic>[bytes];

void main() {
  group('native runtime file and key boundaries', () {
    late NativeClientRuntime runtime;
    setUp(() {
      runtime = NativeClientRuntime.instance();
      addTearDown(NativeClientRuntime.shutdownShared);
    });

    for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
      for (final keyId in [
        '\u00e9',
        '\u6f22',
        '\u{1f511}',
        'e\u0301',
        'key-\u00e9-end',
      ]) {
        test('$cipher preserves UTF-8 key $keyId across providers', () {
          final key = List<int>.generate(32, (index) => index + 1);
          final native = cipher == 'aes256gcm'
              ? NativeWampCborAes256GcmProvider.single(keyId: keyId, key: key)
              : NativeWampCborXsalsa20Poly1305Provider.single(
                  keyId: keyId,
                  key: key,
                );
          addTearDown(native.release);
          final portable = cipher == 'aes256gcm'
              ? WampCborAes256GcmProvider.single(keyId: keyId, key: key)
              : WampCborXsalsa20Poly1305Provider.single(keyId: keyId, key: key);
          final options = PublishOptions(pptScheme: 'wamp');
          final packed = native.packPayload(['native'], {'id': keyId}, options);
          expect(options.pptKeyId, keyId);
          final decoded = portable.unpackPayload(packed, options);
          expect(decoded.arguments, ['native']);
          expect(decoded.argumentsKeywords, {'id': keyId});
          final reverse = portable.packPayload(
            ['portable'],
            {'id': keyId},
            options,
          );
          final nativeDecoded = native.unpackPayload(reverse, options);
          expect(nativeDecoded.arguments, ['portable']);
          expect(nativeDecoded.argumentsKeywords, {'id': keyId});
        });
      }

      test('$cipher distinct Unicode IDs cannot alias the same native key', () {
        final keys = {
          '\u00e9a': List<int>.generate(32, (index) => index + 1),
          '\u00e9b': List<int>.generate(32, (index) => index + 65),
        };
        final native = cipher == 'aes256gcm'
            ? NativeWampCborAes256GcmProvider(
                keys: keys,
                defaultKeyId: '\u00e9a',
              )
            : NativeWampCborXsalsa20Poly1305Provider(
                keys: keys,
                defaultKeyId: '\u00e9a',
              );
        addTearDown(native.release);
        final portable = cipher == 'aes256gcm'
            ? WampCborAes256GcmProvider(keys: keys, defaultKeyId: '\u00e9a')
            : WampCborXsalsa20Poly1305Provider(
                keys: keys,
                defaultKeyId: '\u00e9a',
              );
        for (final keyId in keys.keys) {
          final options = PublishOptions(pptScheme: 'wamp', pptKeyId: keyId);
          final packed = native.packPayload([keyId], null, options);
          expect(portable.unpackPayload(packed, options).arguments, [keyId]);
          final reverse = portable.packPayload([keyId], null, options);
          expect(native.unpackPayload(reverse, options).arguments, [keyId]);
        }
      });

      test('$cipher session default selects the full Unicode key ID', () {
        final ring = runtime.createE2eeKeyring();
        addTearDown(() => runtime.releaseE2eeKeyring(ring));
        runtime.addE2eeKey(ring, 'other', Uint8List(32), makeDefault: true);
        runtime.addE2eeKey(
          ring,
          '\u00e9a',
          Uint8List.fromList(List.filled(32, 7)),
        );
        final session = runtime.createE2eeSession(
          ring,
          defaultKeyId: '\u00e9a',
        );
        addTearDown(() => runtime.releaseE2eeSession(session));
        final payload = Uint8List.fromList([0, 1, 254, 255]);
        final encrypted = runtime.encryptE2ee(session, payload, cipher: cipher);
        expect(
          runtime.decryptE2ee(
            session,
            encrypted,
            keyId: '\u00e9a',
            cipher: cipher,
          ),
          payload,
        );
        expect(
          () => runtime.decryptE2ee(
            session,
            encrypted,
            keyId: 'other',
            cipher: cipher,
          ),
          throwsA(
            isA<NativeTransportException>().having(
              (e) => e.code,
              'code',
              NativeTransportErrorCode.decryptionFailed,
            ),
          ),
        );
      });
    }

    for (final (wire, serializer) in _wireCases) {
      test(
        '${wire.name} file slices retain exact WAMP framing and bytes',
        () async {
          final peer = await _WirePeer.start(wire);
          addTearDown(peer.dispose);
          final connection = _connect(runtime, peer, wire);
          addTearDown(() => runtime.closeConnection(connection));
          expect(runtime.connectionSupportsFileSegments(connection), isTrue);
          expect(runtime.connectionMaxRawSocketExponent(connection), 24);
          final bytes = Uint8List.fromList(
            List.generate(65544, (i) => i % 256),
          );
          final file = _sourceFile(bytes);
          final handle = runtime.openFile(
            file.path,
            expectedLength: bytes.length,
          );
          addTearDown(() => runtime.releaseFile(handle));
          var request = 1;
          for (final length in [0, 1, 2, 3, 23, 24, 255, 256, 65536]) {
            final call = _call(request++, Uint8List(0));
            final prefix = buildNativeFileSegmentPrefix(
              _encode(serializer, call),
              serializerType: wire.id,
              fileLength: length,
            );
            runtime.sendMessageFileSegment(
              connection,
              prefix: prefix,
              fileHandle: handle,
              fileOffset: 4,
              fileLength: length,
              encodeBase64: wire == NativeMessageSerializer.json,
              suffix: wire == NativeMessageSerializer.json
                  ? Uint8List.fromList([0x22, 0x5d, 0x5d])
                  : null,
            );
            final frame = await peer.nextFrame();
            call.arguments = [Uint8List.sublistView(bytes, 4, 4 + length)];
            expect(
              frame,
              orderedEquals(_encode(serializer, call)),
              reason: 'length=$length',
            );
            final decoded = serializer.deserialize(frame) as Call;
            expect(decoded.procedure, 'files.write');
            expect(decoded.options!.progress, isTrue);
            expect(decoded.arguments!.single, bytes.sublist(4, 4 + length));
          }
          runtime.releaseFile(handle);
          runtime.releaseFile(handle);
          expect(
            () => runtime.sendMessageFileSegment(
              connection,
              prefix: Uint8List(0),
              fileHandle: handle,
              fileOffset: 0,
              fileLength: 0,
            ),
            throwsA(
              isA<NativeTransportException>().having(
                (e) => e.code,
                'code',
                NativeTransportErrorCode.handleUnavailable,
              ),
            ),
          );
          final recovery = _encode(
            serializer,
            _call(99, Uint8List.fromList([42])),
          );
          runtime.sendMessage(connection, recovery);
          expect(await peer.nextFrame(), orderedEquals(recovery));
        },
      );

      test(
        '${wire.name} owned segments preserve one frame and recover after errors',
        () async {
          final peer = await _WirePeer.start(wire);
          addTearDown(peer.dispose);
          final connection = _connect(runtime, peer, wire);
          addTearDown(() => runtime.closeConnection(connection));
          final bytes = _encode(
            serializer,
            _call(31, Uint8List.fromList(List.generate(1024, (i) => i % 256))),
          );
          final segments = [
            Uint8List(0),
            Uint8List.sublistView(bytes, 0, 7),
            Uint8List(0),
            Uint8List.sublistView(bytes, 7),
          ];
          expect(runtime.trySendMessageSegments(connection, []), isFalse);
          expect(
            () => runtime.trySendMessageSegments(
              connection,
              segments,
              fragmentSize: -1,
            ),
            throwsArgumentError,
          );
          expect(
            () => runtime.trySendMessageSegments(0x7fffffff, segments),
            throwsA(
              isA<NativeTransportException>().having(
                (e) => e.code,
                'code',
                NativeTransportErrorCode.connectionNotFound,
              ),
            ),
          );
          for (final fragment in [0, 1, 257, bytes.length + 1]) {
            expect(
              runtime.trySendMessageSegments(
                connection,
                segments,
                fragmentSize: fragment,
              ),
              isTrue,
            );
            expect(await peer.nextFrame(), orderedEquals(bytes));
          }
          expect(segments.expand((segment) => segment), orderedEquals(bytes));
        },
      );

      for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
        test(
          '${wire.name} $cipher received decryption owns and caches its payload',
          () async {
            final peer = await _WirePeer.start(wire);
            addTearDown(peer.dispose);
            final connection = _connect(runtime, peer, wire);
            addTearDown(() => runtime.closeConnection(connection));
            final key = Uint8List.fromList(List.filled(32, 19));
            final ring = runtime.createE2eeKeyring();
            addTearDown(() => runtime.releaseE2eeKeyring(ring));
            runtime.addE2eeKey(ring, '\u00e9a', key, makeDefault: true);
            final session = runtime.createE2eeSession(
              ring,
              defaultKeyId: '\u00e9a',
            );
            addTearDown(() => runtime.releaseE2eeSession(session));
            final portable = cipher == 'aes256gcm'
                ? WampCborAes256GcmProvider.single(keyId: '\u00e9a', key: key)
                : WampCborXsalsa20Poly1305Provider.single(
                    keyId: '\u00e9a',
                    key: key,
                  );
            for (final direct in [true, false]) {
              final args = direct
                  ? <dynamic>[
                      Uint8List.fromList([0, 255, 37]),
                    ]
                  : <dynamic>['payload', 42];
              final kwargs = direct
                  ? null
                  : <String, dynamic>{'marker': 'retained'};
              final options = PublishOptions(pptScheme: 'wamp');
              final encrypted = portable.packPayload(args, kwargs, options);
              final invocation = Invocation(
                71,
                81,
                InvocationDetails(
                  91,
                  'files.read',
                  true,
                  'wamp',
                  'cbor',
                  cipher,
                  '\u00e9a',
                ),
                arguments: encrypted,
              );
              peer.control.send(_encode(serializer, invocation));
              final handle = runtime.waitMessageHandle(
                connection,
                timeout: const Duration(seconds: 3),
              );
              expect(handle, greaterThan(0));
              final incoming = runtime.materialize(handle);
              addTearDown(incoming.release);
              final payload = runtime.decryptE2eeMessageSingleBinaryArgument(
                session,
                incoming,
                keyId: '\u00e9a',
                cipher: cipher,
              );
              expect(payload, isNotNull);
              final result = payload!;
              addTearDown(
                () =>
                    NativeClientRuntime.releaseOwnedExternalBytes(result.bytes),
              );
              expect(result.directBinary, direct);
              if (direct) {
                expect(result.bytes, args.single);
              } else {
                expect(cbor_codec.cbor.decode(result.bytes).toObject(), {
                  'args': args,
                  'kwargs': kwargs,
                });
              }
              incoming.release();
              incoming.release();
              expect(
                runtime
                    .decryptE2eeMessageSingleBinaryArgument(
                      session,
                      incoming,
                      keyId: '\u00e9a',
                      cipher: cipher,
                    )!
                    .bytes,
                same(result.bytes),
              );
              for (final changed in [
                (session, 'other', cipher),
                (session, '\u00e9a', 'other'),
                (session + 1, '\u00e9a', cipher),
              ]) {
                expect(
                  () => runtime.decryptE2eeMessageSingleBinaryArgument(
                    changed.$1,
                    incoming,
                    keyId: changed.$2,
                    cipher: changed.$3,
                  ),
                  throwsA(
                    isA<NativeTransportException>().having(
                      (e) => e.code,
                      'code',
                      NativeTransportErrorCode.handleUnavailable,
                    ),
                  ),
                );
              }
              expect(
                NativeClientRuntime.releaseOwnedExternalBytes(result.bytes),
                isTrue,
              );
              expect(
                NativeClientRuntime.releaseOwnedExternalBytes(result.bytes),
                isFalse,
              );
              expect(
                () => runtime.decryptE2eeMessageSingleBinaryArgument(
                  session,
                  incoming,
                  keyId: '\u00e9a',
                  cipher: cipher,
                ),
                throwsA(
                  isA<NativeTransportException>().having(
                    (e) => e.code,
                    'code',
                    NativeTransportErrorCode.handleUnavailable,
                  ),
                ),
              );
            }
          },
        );

        test(
          '${wire.name} $cipher rejected decryption consumes only that message',
          () async {
            final peer = await _WirePeer.start(wire);
            addTearDown(peer.dispose);
            final connection = _connect(runtime, peer, wire);
            addTearDown(() => runtime.closeConnection(connection));
            final key = Uint8List.fromList(List.filled(32, 29));
            final ring = runtime.createE2eeKeyring();
            addTearDown(() => runtime.releaseE2eeKeyring(ring));
            runtime.addE2eeKey(ring, 'key', key, makeDefault: true);
            final session = runtime.createE2eeSession(
              ring,
              defaultKeyId: 'key',
            );
            addTearDown(() => runtime.releaseE2eeSession(session));
            final portable = cipher == 'aes256gcm'
                ? WampCborAes256GcmProvider.single(keyId: 'key', key: key)
                : WampCborXsalsa20Poly1305Provider.single(
                    keyId: 'key',
                    key: key,
                  );
            final encrypted = portable.packPayload(
              [
                Uint8List.fromList([1, 2, 3]),
              ],
              null,
              PublishOptions(pptScheme: 'wamp'),
            );
            NativeIncomingMessage receive() {
              peer.control.send(
                _encode(
                  serializer,
                  Invocation(
                    72,
                    82,
                    InvocationDetails(
                      92,
                      'files.read',
                      false,
                      'wamp',
                      'cbor',
                      cipher,
                      'key',
                    ),
                    arguments: encrypted,
                  ),
                ),
              );
              final handle = runtime.waitMessageHandle(
                connection,
                timeout: const Duration(seconds: 3),
              );
              expect(handle, greaterThan(0));
              final message = runtime.materialize(handle);
              addTearDown(message.release);
              return message;
            }

            final released = receive()..release();
            expect(
              () => runtime.decryptE2eeMessageSingleBinaryArgument(
                session,
                released,
                keyId: 'key',
                cipher: cipher,
              ),
              throwsA(
                isA<NativeTransportException>().having(
                  (e) => e.code,
                  'code',
                  NativeTransportErrorCode.handleUnavailable,
                ),
              ),
            );
            final rejected = receive();
            expect(
              () => runtime.decryptE2eeMessageSingleBinaryArgument(
                session,
                rejected,
                keyId: 'missing',
                cipher: cipher,
              ),
              throwsA(
                isA<NativeTransportException>().having(
                  (e) => e.code,
                  'code',
                  NativeTransportErrorCode.keyNotFound,
                ),
              ),
            );
            expect(
              () => runtime.decryptE2eeMessageSingleBinaryArgument(
                session,
                rejected,
                keyId: 'key',
                cipher: cipher,
              ),
              throwsA(
                isA<NativeTransportException>().having(
                  (e) => e.code,
                  'code',
                  NativeTransportErrorCode.handleUnavailable,
                ),
              ),
            );
            final valid = receive();
            expect(
              () => runtime.decryptE2eeMessageSingleBinaryArgument(
                session,
                valid,
                keyId: 'key',
                cipher: 'unsupported',
              ),
              throwsArgumentError,
            );
            final recovered = runtime.decryptE2eeMessageSingleBinaryArgument(
              session,
              valid,
              keyId: 'key',
              cipher: cipher,
            )!;
            addTearDown(
              () => NativeClientRuntime.releaseOwnedExternalBytes(
                recovered.bytes,
              ),
            );
            expect(recovered.directBinary, isTrue);
            expect(recovered.bytes, [1, 2, 3]);
          },
        );

        test(
          '${wire.name} $cipher encrypts only the requested file range',
          () async {
            final peer = await _WirePeer.start(wire);
            addTearDown(peer.dispose);
            final connection = _connect(runtime, peer, wire);
            addTearDown(() => runtime.closeConnection(connection));
            final bytes = Uint8List.fromList(
              List.generate(259, (i) => i % 256),
            );
            final file = _sourceFile(bytes);
            final handle = runtime.openFile(
              file.path,
              expectedLength: bytes.length,
            );
            addTearDown(() => runtime.releaseFile(handle));
            final ring = runtime.createE2eeKeyring();
            addTearDown(() => runtime.releaseE2eeKeyring(ring));
            runtime.addE2eeKey(
              ring,
              '\u00e9a',
              Uint8List.fromList(List.filled(32, 9)),
              makeDefault: true,
            );
            final session = runtime.createE2eeSession(
              ring,
              defaultKeyId: '\u00e9a',
            );
            addTearDown(() => runtime.releaseE2eeSession(session));
            final portable = cipher == 'aes256gcm'
                ? WampCborAes256GcmProvider.single(
                    keyId: '\u00e9a',
                    key: List.filled(32, 9),
                  )
                : WampCborXsalsa20Poly1305Provider.single(
                    keyId: '\u00e9a',
                    key: List.filled(32, 9),
                  );
            void sendInvalid({
              int offset = 0,
              int length = 1,
              String? selectedCipher,
              String keyId = '\u00e9a',
            }) {
              runtime.sendMessageNativeE2eeFileSegment(
                connection,
                prefix: Uint8List(0),
                fileHandle: handle,
                fileOffset: offset,
                fileLength: length,
                sessionHandle: session,
                keyId: keyId,
                cipher: selectedCipher ?? cipher,
                encodeBase64: wire == NativeMessageSerializer.json,
              );
            }

            expect(() => sendInvalid(offset: -1), throwsArgumentError);
            expect(() => sendInvalid(length: -1), throwsArgumentError);
            expect(
              () => sendInvalid(selectedCipher: 'unsupported'),
              throwsArgumentError,
            );
            expect(
              () => sendInvalid(keyId: 'missing'),
              throwsA(
                isA<NativeTransportException>().having(
                  (e) => e.code,
                  'code',
                  NativeTransportErrorCode.keyNotFound,
                ),
              ),
            );
            expect(
              () => sendInvalid(offset: bytes.length),
              throwsA(
                isA<NativeTransportException>().having(
                  (e) => e.code,
                  'code',
                  NativeTransportErrorCode.invalidArgument,
                ),
              ),
            );
            for (final length in [0, 1, 2, 3, 255]) {
              final expected = Uint8List.sublistView(bytes, 4, 4 + length);
              final options = PublishOptions(pptScheme: 'wamp');
              final reference = portable.packPayload([expected], null, options);
              final cipherLength = (reference.single as Uint8List).length;
              final call = _call(length + 1, Uint8List(0));
              final prefix = buildNativeFileSegmentPrefix(
                _encode(serializer, call),
                serializerType: wire.id,
                fileLength: cipherLength,
              );
              runtime.sendMessageNativeE2eeFileSegment(
                connection,
                prefix: prefix,
                fileHandle: handle,
                fileOffset: 4,
                fileLength: length,
                sessionHandle: session,
                keyId: '\u00e9a',
                cipher: cipher,
                encodeBase64: wire == NativeMessageSerializer.json,
                suffix: wire == NativeMessageSerializer.json
                    ? Uint8List.fromList([0x22, 0x5d, 0x5d])
                    : null,
              );
              final frame = await peer.nextFrame();
              final decoded = serializer.deserialize(frame) as Call;
              expect(decoded.requestId, length + 1);
              expect(decoded.procedure, 'files.write');
              final encrypted = decoded.arguments!.single as Uint8List;
              expect(encrypted.length, cipherLength);
              final unpacked = portable.unpackPayload([encrypted], options);
              expect(unpacked.arguments!.single, expected);
              expect(unpacked.argumentsKeywords, isNull);
            }
          },
        );
      }
    }

    test(
      'file handles reject invalid sources and ranges without corrupting recovery',
      () async {
        final bytes = Uint8List.fromList([10, 20, 30, 40]);
        final file = _sourceFile(bytes);
        expect(
          () => runtime.openFile('', expectedLength: 0),
          throwsArgumentError,
        );
        expect(
          () => runtime.openFile(file.path, expectedLength: -1),
          throwsArgumentError,
        );
        for (final (path, length, code) in [
          (file.path, 3, NativeTransportErrorCode.invalidArgument),
          (file.parent.path, 4, NativeTransportErrorCode.invalidArgument),
          ('${file.path}.missing', 0, NativeTransportErrorCode.io),
        ]) {
          expect(
            () => runtime.openFile(path, expectedLength: length),
            throwsA(
              isA<NativeTransportException>().having(
                (e) => e.code,
                'code',
                code,
              ),
            ),
          );
        }
        expect(
          () => runtime.releaseFile(0),
          throwsA(
            isA<NativeTransportException>().having(
              (e) => e.code,
              'code',
              NativeTransportErrorCode.invalidArgument,
            ),
          ),
        );
        final handle = runtime.openFile(file.path, expectedLength: 4);
        addTearDown(() => runtime.releaseFile(handle));
        final peer = await _WirePeer.start(NativeMessageSerializer.cbor);
        addTearDown(peer.dispose);
        final connection = _connect(
          runtime,
          peer,
          NativeMessageSerializer.cbor,
        );
        addTearDown(() => runtime.closeConnection(connection));
        for (final base64 in [false, true]) {
          for (final (offset, length) in [(-1, 1), (0, -1), (3, 2)]) {
            expect(
              () => runtime.sendMessageFileSegment(
                connection,
                prefix: Uint8List.fromList([1]),
                suffix: Uint8List.fromList([2]),
                fileHandle: handle,
                fileOffset: offset,
                fileLength: length,
                encodeBase64: base64,
              ),
              offset < 0 || length < 0
                  ? throwsArgumentError
                  : throwsA(
                      isA<NativeTransportException>().having(
                        (e) => e.code,
                        'code',
                        NativeTransportErrorCode.invalidArgument,
                      ),
                    ),
            );
          }
        }
        runtime.sendMessageFileSegment(
          connection,
          prefix: Uint8List.fromList([0x82, 0x42]),
          fileHandle: handle,
          fileOffset: 1,
          fileLength: 2,
          suffix: Uint8List.fromList([0x01]),
        );
        expect(
          await peer.nextFrame(),
          orderedEquals([0x82, 0x42, 20, 30, 0x01]),
        );
      },
    );
  }, skip: nativeClientRuntimeSkipReason());
}

File _sourceFile(Uint8List bytes) {
  final directory = Directory.systemTemp.createTempSync('native-file-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/payload-\u00e9.bin')..writeAsBytesSync(bytes);
}

int _connect(
  NativeClientRuntime runtime,
  _WirePeer peer,
  NativeMessageSerializer wire,
) => runtime.connectRawSocket(
  host: '127.0.0.1',
  port: peer.port,
  useTls: false,
  allowInsecure: false,
  serializer: wire,
  maxMessageLengthExponent: 15,
);

class _WirePeer {
  _WirePeer(this.isolate, this.events, this.messages, this.control, this.port);
  final Isolate isolate;
  final ReceivePort events;
  final StreamIterator<Object?> messages;
  final SendPort control;
  final int port;

  static Future<_WirePeer> start(NativeMessageSerializer wire) async {
    final events = ReceivePort();
    final messages = StreamIterator<Object?>(events);
    final isolate = await Isolate.spawn(_wirePeerMain, (
      events.sendPort,
      wire.id,
    ), onError: events.sendPort);
    try {
      final ready = await _nextEvent(messages);
      if (ready is! (SendPort, int)) {
        throw StateError('Peer startup failed: $ready');
      }
      return _WirePeer(isolate, events, messages, ready.$1, ready.$2);
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      await messages.cancel();
      events.close();
      rethrow;
    }
  }

  Future<Uint8List> nextFrame() async {
    final frame = await _nextEvent(messages);
    if (frame is! Uint8List) throw StateError('Peer failed: $frame');
    return frame;
  }

  Future<void> dispose() async {
    try {
      control.send('stop');
      while (await _nextEvent(messages) != 'closed') {}
    } finally {
      isolate.kill(priority: Isolate.immediate);
      await messages.cancel();
      events.close();
    }
  }
}

Future<Object?> _nextEvent(StreamIterator<Object?> messages) async {
  if (!await messages.moveNext().timeout(const Duration(seconds: 5))) {
    throw StateError('Peer exited before responding');
  }
  return messages.current;
}

// The native connect call blocks, so the independent peer must not share its isolate.
Future<void> _wirePeerMain((SendPort, int) args) async {
  final (events, serializer) = args;
  final control = ReceivePort();
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  Socket? socket;
  control.listen((message) async {
    if (message is Uint8List) {
      final length = message.length;
      socket!.add([
        0,
        (length >> 16) & 255,
        (length >> 8) & 255,
        length & 255,
        ...message,
      ]);
      await socket.flush();
      return;
    }
    socket?.destroy();
    await server.close();
    control.close();
    events.send('closed');
  });
  events.send((control.sendPort, server.port));
  try {
    socket = await server.first;
    var pending = <int>[];
    var handshake = false;
    await for (final chunk in socket) {
      pending.addAll(chunk);
      if (!handshake) {
        if (pending.length < 4) continue;
        if (pending[0] != 0x7f ||
            pending[1] & 15 != serializer ||
            pending[2] != 0 ||
            pending[3] != 0) {
          throw StateError('Invalid RawSocket handshake');
        }
        socket.add([0x7f, 0xf0 | serializer, 0, 0]);
        await socket.flush();
        pending = pending.sublist(4);
        handshake = true;
      }
      while (pending.length >= 4) {
        final length = pending[1] << 16 | pending[2] << 8 | pending[3];
        if (pending.length < 4 + length) break;
        if (pending[0] != 0) {
          throw StateError('Unexpected RawSocket frame type');
        }
        events.send(Uint8List.fromList(pending.sublist(4, 4 + length)));
        pending = pending.sublist(4 + length);
      }
    }
  } catch (error, stack) {
    events.send([error.toString(), stack.toString()]);
  } finally {
    socket?.destroy();
    await server.close();
    // The control port remains alive until the owner requests disposal.
  }
}
