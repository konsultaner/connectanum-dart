part of '../runtime_file_segment_test.dart';

void _consumingE2eeMessageCases(NativeClientRuntime Function() getRuntime) {
  for (final (wire, serializer) in [
    ..._wireCases,
    (NativeMessageSerializer.flatbuffers, flat.Serializer()),
  ]) {
    for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
      test(
        '${wire.name} $cipher received decryption owns and caches its payload',
        () async {
          final runtime = getRuntime();
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
              () => NativeClientRuntime.releaseOwnedExternalBytes(result.bytes),
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
          final runtime = getRuntime();
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
    }
  }
}
