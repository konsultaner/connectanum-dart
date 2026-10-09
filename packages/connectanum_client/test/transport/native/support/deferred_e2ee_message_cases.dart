part of '../runtime_file_segment_test.dart';

void _deferredE2eeMessageCases(NativeClientRuntime Function() getRuntime) {
  for (final (wire, serializer) in [
    (NativeMessageSerializer.cbor, cbor.Serializer()),
    (NativeMessageSerializer.messagePack, msgpack.Serializer()),
    (NativeMessageSerializer.flatbuffers, flat.Serializer()),
  ]) {
    for (final cipher in ['aes256gcm', 'xsalsa20poly1305']) {
      for (final access in [
        'consume',
        'export',
        'release',
        'eager',
        'failed-decrypt',
        'external-release',
        'export-release',
      ]) {
        test('deferred ${wire.name} $cipher access=$access', () async {
          final runtime = getRuntime();
          final library = ffi.DynamicLibrary.open(runtime.libraryPath);
          final observe = library
              .lookupFunction<
                ffi.Pointer<ffi.Void> Function(ffi.Int64),
                ffi.Pointer<ffi.Void> Function(int)
              >(
                'ct_test_message_observer_new_wide',
              );
          final alive = library
              .lookupFunction<
                ffi.Int32 Function(ffi.Pointer<ffi.Void>),
                int Function(ffi.Pointer<ffi.Void>)
              >(
                'ct_test_message_observer_alive',
              );
          final free = library
              .lookupFunction<
                ffi.Void Function(ffi.Pointer<ffi.Void>),
                void Function(ffi.Pointer<ffi.Void>)
              >(
                'ct_test_message_observer_free',
              );
          final peer = await _WirePeer.start(wire);
          addTearDown(peer.dispose);
          final connection = _connect(runtime, peer, wire);
          addTearDown(() => runtime.closeConnection(connection));
          final key = Uint8List.fromList(List.filled(32, 31));
          final plaintext = Uint8List.fromList([0, 255, 37, 91]);
          final keyring = runtime.createE2eeKeyring();
          addTearDown(() => runtime.releaseE2eeKeyring(keyring));
          runtime.addE2eeKey(
            keyring,
            'typed',
            access == 'failed-decrypt'
                ? Uint8List.fromList(List.filled(32, 7))
                : key,
          );
          final session = runtime.createE2eeSession(keyring);
          addTearDown(() => runtime.releaseE2eeSession(session));
          final portable = cipher == 'aes256gcm'
              ? WampFlatBuffersAes256GcmProvider.single(
                  keyId: 'typed',
                  key: key,
                )
              : WampFlatBuffersXsalsa20Poly1305Provider.single(
                  keyId: 'typed',
                  key: key,
                );
          final encrypted = portable.packPayload(
            [plaintext],
            null,
            PublishOptions(),
          );
          peer.control.send(
            _encode(
              serializer,
              Invocation(
                71,
                81,
                InvocationDetails(
                  91,
                  'typed.read',
                  true,
                  'wamp',
                  'flatbuffers',
                  cipher,
                  'typed',
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
          final observer = observe(handle);
          expect(observer.address, isNot(0));
          addTearDown(() => free(observer));
          final incoming = runtime.materialize(
            handle,
            deferPayloadExports: access != 'eager',
          );
          addTearDown(incoming.release);
          expect(alive(observer), 1);
          final getters = <Object? Function()>[
            () => incoming.message,
            () => incoming.bytes,
            () => incoming.argumentsBytes,
            () => incoming.argumentsKeywordsBytes,
            () => incoming.singleBinaryArgumentBytes,
          ];
          Uint8List? observedCiphertext;
          if (access == 'export' ||
              access == 'eager' ||
              access == 'export-release') {
            observedCiphertext =
                incoming.singleBinaryArgumentBytes ??
                (incoming.message as AbstractMessageWithPayload)
                    .transparentBinaryPayload;
            expect(observedCiphertext, orderedEquals(encrypted.single));
            expect(() => observedCiphertext![0] = 0, throwsUnsupportedError);
            final message = incoming.message;
            expect(incoming.message, same(message));
          }
          if (access == 'export-release') {
            incoming.release();
            incoming.release();
            expect(alive(observer), 1);
            expect(observedCiphertext, orderedEquals(encrypted.single));
            for (final get in getters) {
              expect(get, returnsNormally);
            }
            return;
          }
          if (access == 'external-release') {
            runtime.releaseMessageHandle(handle);
            expect(
              () => incoming.message,
              throwsA(isA<NativeTransportException>()),
            );
            for (final get in getters) {
              expect(get, throwsStateError);
            }
            expect(alive(observer), 0);
            incoming.release();
            incoming.release();
            return;
          }
          if (access == 'failed-decrypt') {
            expect(
              () => runtime.decryptE2eeMessageSingleBinaryArgument(
                session,
                incoming,
                keyId: 'typed',
                cipher: cipher,
                plaintextFormat: NativeE2eePlaintextFormat.typedFlatBuffers,
              ),
              throwsA(
                isA<NativeTransportException>().having(
                  (e) => e.code,
                  'code',
                  NativeTransportErrorCode.decryptionFailed,
                ),
              ),
            );
            for (final get in getters) {
              expect(get, throwsStateError);
            }
            expect(alive(observer), 0);
            incoming.release();
            incoming.release();
            return;
          }
          if (access == 'release') {
            incoming.release();
            incoming.release();
            expect(alive(observer), 0);
            for (final get in getters) {
              expect(get, throwsStateError);
            }
            expect(
              () => runtime.decryptE2eeMessageSingleBinaryArgument(
                session,
                incoming,
                keyId: 'typed',
                cipher: cipher,
                plaintextFormat: NativeE2eePlaintextFormat.typedFlatBuffers,
              ),
              throwsA(
                isA<NativeTransportException>().having(
                  (e) => e.code,
                  'code',
                  NativeTransportErrorCode.handleUnavailable,
                ),
              ),
            );
            return;
          }
          final payload = runtime.decryptE2eeMessageSingleBinaryArgument(
            session,
            incoming,
            keyId: 'typed',
            cipher: cipher,
            plaintextFormat: NativeE2eePlaintextFormat.typedFlatBuffers,
          );
          expect(payload, isNotNull);
          final output = payload!.bytes;
          addTearDown(
            () => NativeClientRuntime.releaseOwnedExternalBytes(output),
          );
          expect(output, orderedEquals(plaintext));
          expect(payload.directBinary, isTrue);
          expect(alive(observer), observedCiphertext == null ? 0 : 1);
          incoming.release();
          incoming.release();
          if (observedCiphertext == null) {
            for (final get in getters) {
              expect(get, throwsStateError);
            }
          } else {
            expect(observedCiphertext, orderedEquals(encrypted.single));
            for (final get in getters) {
              expect(get, returnsNormally);
            }
          }
          expect(
            runtime
                .decryptE2eeMessageSingleBinaryArgument(
                  session,
                  incoming,
                  keyId: 'typed',
                  cipher: cipher,
                  plaintextFormat: NativeE2eePlaintextFormat.typedFlatBuffers,
                )!
                .bytes,
            same(output),
          );
          expect(output, orderedEquals(plaintext));
        }, tags: 'ffi-test-owner-oracle');
      }
    }
  }
  test(
    'deferred inputs and decrypted derived views obey GC ownership',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_client/connectanum.dart'),
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--enable-vm-service=0',
          '--disable-service-auth-codes',
          'run',
          source!
              .resolve(
                '../test/transport/native/support/deferred_e2ee_gc_probe.dart',
              )
              .toFilePath(),
        ],
        environment: {'CONNECTANUM_NATIVE_LIB': getRuntime().libraryPath},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains(
          'native-deferred-input-gc: retained then released unexported handles',
        ),
      );
      for (final cipher in ['xsalsa20poly1305', 'aes256gcm']) {
        expect(
          result.stdout,
          contains(
            'native-deferred-e2ee-gc: $cipher derived read-only view retained then released storage',
          ),
        );
      }
    },
    tags: 'ffi-test-owner-oracle',
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
