part of '../file_transfer_test.dart';

void _fileReceiverAdmissionCases() {
  group('file receiver admission', () {
    for (final (field, value) in [
      ('concurrent', 0),
      ('concurrent', -1),
      ('file', -1),
      ('chunk', 0),
      ('chunk', -1),
      ('buffer', 0),
      ('buffer', -1),
      ('idle', 0),
      ('idle', -1),
    ]) {
      test('rejects invalid $field=$value before registering', () async {
        final (transport, session) = await _admissionSession();
        var allocations = 0;
        final attempt = WampFileReceiver.register(
          session,
          'files.set',
          (_) {
            allocations++;
            return _CollectingFileSink();
          },
          maxConcurrentTransfers: field == 'concurrent' ? value : 1,
          maxFileSize: field == 'file' ? value : 3,
          maxChunkSize: field == 'chunk' ? value : 3,
          maxBufferedBytes: field == 'buffer' ? value : 3,
          idleTimeout: Duration(milliseconds: field == 'idle' ? value : 30000),
        );
        // Dispose an incorrectly accepted receiver as well as a correct one.
        final observed = attempt.then<WampFileReceiver>((receiver) {
          addTearDown(receiver.close);
          return receiver;
        });
        await expectLater(
          observed,
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              'File receiver limits must be positive',
            ),
          ),
        );
        expect(transport.registrations, isEmpty);
        expect(allocations, 0);
        final receiver = await _admissionReceiver(
          session,
          (_) => _CollectingFileSink(),
        );
        expect(transport.registrations, hasLength(1));
        expect(transport.registrations.single.procedure, 'files.set');
        expect(receiver.activeTransfers, 0);
      });
    }

    for (final size in [0, 3]) {
      test('accepts exact file/chunk limits with size=$size', () async {
        final (transport, session) = await _admissionSession();
        final sink = _CollectingFileSink();
        final receiver = await _admissionReceiver(
          session,
          (_) => sink,
          maxFileSize: size,
        );
        transport.invokeHeader(
          requestId: 70,
          metadata: WampFileMetadata(name: 'data', size: size, chunkSize: 3),
        );
        transport.invokeChunk(
          requestId: 70,
          bytes: Uint8List(size),
          progress: false,
        );
        await _waitUntil(
          () => transport.yields.isNotEmpty || transport.errors.isNotEmpty,
        );
        expect(transport.errors, isEmpty);
        expect(transport.yields, hasLength(1));
        expect(transport.yields.single.invocationRequestId, 70);
        expect(sink.bytes, List<int>.filled(size, 0));
        expect(sink.receipt?.receivedBytes, size);
        expect(sink.receipt?.metadata.chunkSize, 3);
        expect(receiver.activeTransfers, 0);
        expect(receiver.bufferedBytes, 0);
        expect(sink.aborted, isFalse);
      });
    }

    for (final oversized in ['file', 'chunk']) {
      test('rejects oversized $oversized before allocating a sink', () async {
        final (transport, session) = await _admissionSession();
        final sinks = <_CollectingFileSink>[];
        final receiver = await _admissionReceiver(session, (_) {
          final sink = _CollectingFileSink();
          sinks.add(sink);
          return sink;
        });
        transport.invokeHeader(
          requestId: 71,
          metadata: WampFileMetadata(
            name: 'data',
            size: oversized == 'file' ? 4 : 3,
            chunkSize: oversized == 'chunk' ? 4 : 3,
          ),
        );
        await _expectAdmissionRejection(
          transport,
          receiver,
          sinks,
          error: WampFileReceiver.capacityExceededError,
          message: 'Declared file or chunk size exceeds receiver limits',
        );
        await _admissionRecovery(transport, receiver, sinks);
      });
    }

    for (final scenario in [
      'not-progressive',
      'arguments',
      'missing-keywords',
      'empty-keywords',
      'extra-keyword',
      'not-object',
      'bad-version',
      'invalid-digest',
      'non-string-key',
    ]) {
      test('rejects $scenario metadata without retaining state', () async {
        final (transport, session) = await _admissionSession();
        final sinks = <_CollectingFileSink>[];
        final receiver = await _admissionReceiver(session, (_) {
          final sink = _CollectingFileSink();
          sinks.add(sink);
          return sink;
        });
        final metadata = <String, dynamic>{
          'version': 1,
          'name': 'data',
          'size': 3,
          'chunk_size': 3,
        };
        Map<String, dynamic>? keywords = {wampFileMetadataKey: metadata};
        switch (scenario) {
          case 'missing-keywords':
            keywords = null;
          case 'empty-keywords':
            keywords = {};
          case 'extra-keyword':
            keywords['extra'] = true;
          case 'not-object':
            keywords[wampFileMetadataKey] = 'invalid';
          case 'bad-version':
            metadata['version'] = 2;
          case 'invalid-digest':
            metadata['sha256'] = 'not-a-digest';
          case 'non-string-key':
            keywords[wampFileMetadataKey] = {1: 'invalid'};
        }
        transport._inbound.add(
          Invocation(
            71,
            20,
            InvocationDetails(1, 'files.set', false)
              ..progress = scenario != 'not-progressive',
            arguments: scenario == 'arguments' ? ['unexpected'] : null,
            argumentsKeywords: keywords,
          ),
        );
        final message = switch (scenario) {
          'not-progressive' || 'arguments' =>
            'The first invocation must contain progressive metadata only',
          'bad-version' ||
          'invalid-digest' ||
          'non-string-key' => 'Malformed file metadata',
          _ => 'Missing file metadata',
        };
        await _expectAdmissionRejection(
          transport,
          receiver,
          sinks,
          error: WampFileReceiver.invalidMetadataError,
          message: message,
        );
        await _admissionRecovery(transport, receiver, sinks);
      });
    }

    test(
      'concurrent limit preserves the first transfer and permits reuse',
      () async {
        final (transport, session) = await _admissionSession();
        final sinks = <_CollectingFileSink>[];
        final receiver = await _admissionReceiver(session, (_) {
          final sink = _CollectingFileSink();
          sinks.add(sink);
          return sink;
        });
        final metadata = WampFileMetadata(name: 'data', size: 3, chunkSize: 3);
        transport.invokeHeader(requestId: 70, metadata: metadata);
        await _waitUntil(() => sinks.isNotEmpty || transport.errors.isNotEmpty);
        expect(transport.errors, isEmpty);
        expect(sinks, hasLength(1));
        expect(receiver.activeTransfers, 1);
        transport.invokeHeader(requestId: 71, metadata: metadata);
        await _waitUntil(() => transport.errors.isNotEmpty || sinks.length > 1);
        expect(sinks, hasLength(1));
        expect(transport.errors, hasLength(1));
        expect(transport.errors.single.requestId, 71);
        expect(
          transport.errors.single.error,
          WampFileReceiver.capacityExceededError,
        );
        expect(transport.errors.single.arguments, [
          'Concurrent file-transfer limit reached',
        ]);
        expect(receiver.activeTransfers, 1);
        expect(sinks.single.aborted, isFalse);
        transport.invokeChunk(
          requestId: 70,
          bytes: Uint8List.fromList([97, 98, 99]),
          progress: false,
        );
        await _waitUntil(
          () => transport.yields.isNotEmpty || transport.errors.length > 1,
        );
        expect(transport.errors, hasLength(1));
        expect(transport.yields.single.invocationRequestId, 70);
        expect(sinks.single.bytes, [97, 98, 99]);
        expect(receiver.activeTransfers, 0);
        transport.yields.clear();
        sinks.clear();
        await _admissionRecovery(transport, receiver, sinks);
      },
    );
  });
}

Future<(_AdmissionTransport, Session)> _admissionSession() async {
  final transport = _AdmissionTransport();
  final session = await Client(
    realm: 'test.realm',
    transport: transport,
  ).connect().first;
  addTearDown(() async {
    await transport.close();
    await transport._inbound.close();
  });
  return (transport, session);
}

Future<WampFileReceiver> _admissionReceiver(
  Session session,
  WampFileSinkFactory factory, {
  int maxFileSize = 3,
}) async {
  final attempt = WampFileReceiver.register(
    session,
    'files.set',
    factory,
    maxConcurrentTransfers: 1,
    maxFileSize: maxFileSize,
    maxChunkSize: 3,
    maxBufferedBytes: 3,
  );
  WampFileReceiver? accepted;
  Object? failure;
  await attempt.then<void>(
    (receiver) {
      accepted = receiver;
      addTearDown(receiver.close);
    },
    onError: (Object error, StackTrace stack) {
      failure = error;
    },
  );
  expect(
    failure,
    isNull,
    reason: 'Valid receiver limits must permit registration',
  );
  expect(accepted, isNotNull);
  return accepted!;
}

Future<void> _expectAdmissionRejection(
  _AdmissionTransport transport,
  WampFileReceiver receiver,
  List<_CollectingFileSink> sinks, {
  required String error,
  required String message,
}) async {
  await _waitUntil(() => transport.errors.isNotEmpty || sinks.isNotEmpty);
  expect(sinks, isEmpty);
  expect(transport.errors, hasLength(1));
  expect(transport.errors.single.requestId, 71);
  expect(transport.errors.single.error, error);
  expect(transport.errors.single.arguments, [message]);
  expect(transport.yields, isEmpty);
  expect(receiver.activeTransfers, 0);
  expect(receiver.bufferedBytes, 0);
}

Future<void> _admissionRecovery(
  _AdmissionTransport transport,
  WampFileReceiver receiver,
  List<_CollectingFileSink> sinks,
) async {
  transport.invokeHeader(
    requestId: 71,
    metadata: WampFileMetadata(name: 'data', size: 3, chunkSize: 3),
  );
  transport.invokeChunk(
    requestId: 71,
    bytes: Uint8List.fromList([97, 98, 99]),
    progress: false,
  );
  await _waitUntil(
    () => transport.yields.isNotEmpty || transport.errors.length > 1,
  );
  expect(transport.errors, hasLength(1));
  expect(transport.yields, hasLength(1));
  expect(transport.yields.single.invocationRequestId, 71);
  expect(sinks, hasLength(1));
  expect(sinks.single.bytes, [97, 98, 99]);
  expect(sinks.single.receipt?.sha256Digest, _receiverAbcSha);
  expect(sinks.single.aborted, isFalse);
  expect(receiver.activeTransfers, 0);
  expect(receiver.bufferedBytes, 0);
}

class _AdmissionTransport extends _FileTransferTransport {
  final registrations = <Register>[];

  @override
  void send(AbstractMessage message) {
    if (message is Register) registrations.add(message);
    super.send(message);
  }
}
