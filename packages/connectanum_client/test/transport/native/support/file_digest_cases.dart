part of '../runtime_file_segment_test.dart';

const _emptyFileSha =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const _abcFileSha =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

void _fileDigestCases(NativeClientRuntime Function() currentRuntime) {
  group('file digest ownership', () {
    for (final consume in [false, true]) {
      test('Dart bytes and slices, consume=$consume', () {
        final bytes = Uint8List.fromList(ascii.encode('!abc?'));
        final digest = file_digest.createFileTransferDigest(
          anchor: null,
          allowNative: true,
        );
        addTearDown(digest.abort);
        digest.add(
          Uint8List.sublistView(bytes, 1, 2),
          consumeNativeOwnership: consume,
        );
        digest.add(Uint8List(0), consumeNativeOwnership: consume);
        digest.add(
          Uint8List.sublistView(bytes, 2, 4),
          consumeNativeOwnership: consume,
        );
        expect(digest.finish(), _abcFileSha);
        expect(bytes, ascii.encode('!abc?'));
        expect(() => digest.finish(), throwsStateError);
        expect(() => digest.add(Uint8List(0)), throwsStateError);
        digest.abort();
        digest.abort();
      });

      test('external owner is consumed only when requested=$consume', () {
        final runtime = currentRuntime();
        final bytes = runtime.decodeCanonicalBase64Bytes(
          Uint8List.fromList(ascii.encode('YWJj')),
          0,
          4,
        );
        expect(bytes, isNotNull);
        final owned = bytes!;
        addTearDown(() => file_digest.releaseNativeFileChunkBytes(owned));
        final digest = file_digest.createFileTransferDigest(
          anchor: null,
          allowNative: false,
        );
        addTearDown(digest.abort);
        digest.add(owned, consumeNativeOwnership: consume);
        expect(digest.finish(), _abcFileSha);
        expect(file_digest.releaseNativeFileChunkBytes(owned), !consume);
        expect(file_digest.releaseNativeFileChunkBytes(owned), isFalse);
      });
    }

    test('abort rejects reuse and does not contaminate another transfer', () {
      final abandoned = file_digest.createFileTransferDigest(
        anchor: null,
        allowNative: false,
      );
      abandoned.add(Uint8List.fromList([97, 98]));
      abandoned.abort();
      abandoned.abort();
      expect(() => abandoned.finish(), throwsStateError);
      expect(() => abandoned.add(Uint8List(0)), throwsStateError);
      final fresh = file_digest.createFileTransferDigest(
        anchor: Object(),
        allowNative: true,
      );
      addTearDown(fresh.abort);
      expect(fresh.finish(), _emptyFileSha);
      expect(file_digest.nativeFileChunkBytes(null), isNull);
      expect(file_digest.nativeFileChunkBytes(Object()), isNull);
      expect(file_digest.releaseNativeFileChunkMessage(null), isFalse);
      expect(file_digest.releaseNativeFileChunkMessage(Object()), isFalse);
      expect(file_digest.releaseNativeFileChunkBytes(Uint8List(0)), isFalse);
    });

    for (final (wire, serializer) in _wireCases) {
      for (final allowNative in [false, true]) {
        test('${wire.name} retained chunk allowNative=$allowNative', () async {
          final runtime = currentRuntime();
          final incoming = await _digestMessage(runtime, wire, serializer);
          final bytes = file_digest.nativeFileChunkBytes(incoming.message);
          expect(bytes, ascii.encode('abc'));
          final digest = file_digest.createFileTransferDigest(
            anchor: incoming.message,
            allowNative: allowNative,
          );
          addTearDown(digest.abort);
          digest.add(bytes!, anchor: incoming.message);
          expect(digest.finish(), _abcFileSha);
          // Hashing borrows the message. It must remain usable until release.
          expect(file_digest.nativeFileChunkBytes(incoming.message), [
            97,
            98,
            99,
          ]);
          expect(
            file_digest.releaseNativeFileChunkMessage(incoming.message),
            isTrue,
          );
          expect(
            file_digest.releaseNativeFileChunkMessage(incoming.message),
            isTrue,
          );
          expect(
            () => runtime.materialize(incoming.handle),
            throwsA(isA<NativeTransportException>()),
          );
        });
      }

      if (wire == NativeMessageSerializer.json) continue;
      test(
        '${wire.name} missing anchor rejects without changing hash',
        () async {
          final runtime = currentRuntime();
          final incoming = await _digestMessage(runtime, wire, serializer);
          final bytes = file_digest.nativeFileChunkBytes(incoming.message)!;
          final digest = file_digest.createFileTransferDigest(
            anchor: incoming.message,
            allowNative: true,
          );
          addTearDown(digest.abort);
          expect(
            () => digest.add(bytes, anchor: Object()),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'Native file chunk lost its retained message handle',
              ),
            ),
          );
          digest.add(bytes, anchor: incoming.message);
          expect(digest.finish(), _abcFileSha);
        },
      );

      test('${wire.name} mismatched retained length fails closed', () async {
        final runtime = currentRuntime();
        final incoming = await _digestMessage(runtime, wire, serializer);
        final bytes = file_digest.nativeFileChunkBytes(incoming.message)!;
        final digest = file_digest.createFileTransferDigest(
          anchor: incoming.message,
          allowNative: true,
        );
        addTearDown(digest.abort);
        expect(
          () => digest.add(
            Uint8List.sublistView(bytes, 1),
            anchor: incoming.message,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Native file digest hashed 3 of 2 bytes',
            ),
          ),
        );
        digest.abort();
        expect(() => digest.finish(), throwsStateError);
        expect(
          () => digest.add(bytes, anchor: incoming.message),
          throwsStateError,
        );
        expect(file_digest.nativeFileChunkBytes(incoming.message), [
          97,
          98,
          99,
        ]);
      });
    }
  });
}

Future<NativeIncomingMessage> _digestMessage(
  NativeClientRuntime runtime,
  NativeMessageSerializer wire,
  AbstractSerializer serializer,
) async {
  final peer = await _WirePeer.start(wire);
  addTearDown(peer.dispose);
  final connection = _connect(runtime, peer, wire);
  addTearDown(() => runtime.closeConnection(connection));
  peer.control.send(
    _encode(
      serializer,
      Invocation(
        71,
        81,
        InvocationDetails(null, 'files.write', true),
        arguments: [Uint8List.fromList(ascii.encode('abc'))],
      ),
    ),
  );
  final handle = runtime.waitMessageHandle(
    connection,
    timeout: const Duration(seconds: 3),
  );
  expect(handle, greaterThan(0));
  final incoming = runtime.materialize(handle);
  addTearDown(incoming.release);
  attachSessionMessageAnchor(incoming.message, incoming);
  return incoming;
}
