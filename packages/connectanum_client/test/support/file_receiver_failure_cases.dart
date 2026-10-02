part of '../file_transfer_test.dart';

const _receiverAbcSha =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

void _fileReceiverFailureCases() {
  group('file receiver failure recovery', () {
    for (final asynchronous in [false, true]) {
      test(
        'factory failure async=$asynchronous permits a new transfer',
        () async {
          final failure = StateError('private factory detail');
          var creations = 0;
          final healthy = _FailureProbeSink();
          final (transport, receiver) = await _failureReceiver((_) {
            if (creations++ == 0) {
              if (asynchronous) return Future<WampFileSink>.error(failure);
              throw failure;
            }
            return healthy;
          });
          _sendReceiverHeader(transport, 77);
          transport.invokeChunk(
            requestId: 77,
            bytes: Uint8List.fromList([97, 98, 99]),
            progress: false,
          );
          await _settleChunkContinuations();
          expect(receiver.bufferedBytes, 0);
          expect(transport.errors, hasLength(1));
          expect(transport.errors.single.requestId, 77);
          expect(
            transport.errors.single.error,
            WampFileReceiver.sinkFailedError,
          );
          expect(transport.errors.single.arguments, [
            'File sink initialization failed',
          ]);
          expect(receiver.activeTransfers, 0);
          expect(transport.yields, isEmpty);
          await _assertReceiverRecovery(transport, receiver, healthy);
          expect(creations, 2);
        },
      );

      for (final stage in ['add', 'close']) {
        for (final abortFails in [false, true]) {
          test('$stage async=$asynchronous abortFails=$abortFails', () async {
            final failure = StateError('private $stage detail');
            final broken = _FailureProbeSink(
              failure: failure,
              failureStage: stage,
              asynchronous: asynchronous,
              abortFails: abortFails,
            );
            final healthy = _FailureProbeSink();
            var creations = 0;
            final (transport, receiver) = await _failureReceiver(
              (_) => creations++ == 0 ? broken : healthy,
            );
            _sendReceiverHeader(transport, 77);
            await _settleChunkContinuations();
            expect(creations, 1);
            transport.invokeChunk(
              requestId: 77,
              bytes: Uint8List.fromList([97, 98, 99]),
              progress: false,
            );
            await _settleChunkContinuations();
            expect(receiver.bufferedBytes, 0);
            expect(transport.errors, hasLength(1));
            expect(transport.errors.single.requestId, 77);
            expect(
              transport.errors.single.error,
              WampFileReceiver.sinkFailedError,
            );
            expect(transport.errors.single.arguments, [
              'File sink operation failed',
            ]);
            expect(transport.yields, isEmpty);
            expect(broken.writes, [
              [97, 98, 99],
            ]);
            expect(broken.closes, stage == 'close' ? 1 : 0);
            expect(broken.aborts, [same(failure)]);
            expect(receiver.activeTransfers, 0);
            await _assertReceiverRecovery(transport, receiver, healthy);
            expect(broken.aborts, hasLength(1));
          });
        }
      }

      test(
        'queued writes stop after first failed add async=$asynchronous',
        () async {
          final created = Completer<WampFileSink>();
          final broken = _FailureProbeSink(
            failure: StateError('write failed'),
            failureStage: 'add',
            asynchronous: asynchronous,
          );
          final (transport, receiver) = await _failureReceiver(
            (_) => created.future,
          );
          _sendReceiverHeader(transport, 77);
          transport.invokeChunk(
            requestId: 77,
            bytes: Uint8List.fromList([97]),
            progress: true,
          );
          transport.invokeChunk(
            requestId: 77,
            bytes: Uint8List.fromList([98, 99]),
            progress: false,
          );
          await _settleChunkContinuations();
          expect(receiver.bufferedBytes, 3);
          created.complete(broken);
          await _settleChunkContinuations();
          expect(receiver.activeTransfers, 0);
          expect(receiver.bufferedBytes, 0);
          expect(broken.writes, [
            [97],
          ]);
          expect(broken.closes, 0);
          expect(broken.aborts, hasLength(1));
          expect(transport.errors, hasLength(1));
          expect(
            transport.errors.single.error,
            WampFileReceiver.sinkFailedError,
          );
          expect(transport.yields, isEmpty);
        },
      );
    }

    for (final failLate in [false, true]) {
      test(
        'late factory after close failLate=$failLate stays closed',
        () async {
          final created = Completer<WampFileSink>();
          var creations = 0;
          final sink = _FailureProbeSink();
          final (transport, receiver) = await _failureReceiver((_) {
            creations++;
            return created.future;
          });
          _sendReceiverHeader(transport, 77);
          transport.invokeChunk(
            requestId: 77,
            bytes: Uint8List.fromList([97, 98, 99]),
            progress: false,
          );
          await _settleChunkContinuations();
          expect(creations, 1);
          expect(receiver.bufferedBytes, 3);
          await receiver.close();
          expect(receiver.activeTransfers, 0);
          if (failLate) {
            created.completeError(StateError('late private factory failure'));
          } else {
            created.complete(sink);
          }
          await _settleChunkContinuations();
          expect(receiver.bufferedBytes, 0);
          expect(sink.writes, isEmpty);
          expect(sink.closes, 0);
          expect(sink.aborts, hasLength(failLate ? 0 : 1));
          if (!failLate) {
            expect(
              sink.aborts.single,
              isA<WampFileTransferException>().having(
                (error) => error.message,
                'message',
                'File receiver closed',
              ),
            );
          }
          expect(transport.errors, isEmpty);
          expect(transport.yields, isEmpty);
          await receiver.close();
          expect(receiver.activeTransfers, 0);
          expect(creations, 1);
        },
      );

      test(
        'late sink close failLate=$failLate cannot report success',
        () async {
          final closed = Completer<Map<String, dynamic>?>();
          final sink = _FailureProbeSink(closeResult: closed.future);
          final (transport, receiver) = await _failureReceiver((_) => sink);
          _sendReceiverHeader(transport, 77);
          transport.invokeChunk(
            requestId: 77,
            bytes: Uint8List.fromList([97, 98, 99]),
            progress: false,
          );
          await _settleChunkContinuations();
          expect(sink.closes, 1);
          expect(receiver.bufferedBytes, 3);
          await receiver.close();
          if (failLate) {
            closed.completeError(StateError('late private close failure'));
          } else {
            closed.complete({'committed': true});
          }
          await _settleChunkContinuations();
          expect(receiver.bufferedBytes, 0);
          expect(receiver.activeTransfers, 0);
          expect(sink.writes, [
            [97, 98, 99],
          ]);
          expect(sink.aborts, hasLength(1));
          expect(transport.yields, isEmpty);
          expect(transport.errors, isEmpty);
        },
      );
    }
  });
}

Future<(_FileTransferTransport, WampFileReceiver)> _failureReceiver(
  WampFileSinkFactory factory,
) async {
  final transport = _FileTransferTransport();
  final session = await Client(
    realm: 'test.realm',
    transport: transport,
  ).connect().first;
  addTearDown(() async {
    await transport.close();
    await transport._inbound.close();
  });
  final receiver = await WampFileReceiver.register(
    session,
    'files.set',
    factory,
    maxConcurrentTransfers: 1,
    maxBufferedBytes: 3,
  );
  addTearDown(receiver.close);
  return (transport, receiver);
}

void _sendReceiverHeader(_FileTransferTransport transport, int requestId) {
  transport.invokeHeader(
    requestId: requestId,
    metadata: WampFileMetadata(
      name: 'received.bin',
      size: 3,
      chunkSize: 3,
      sha256Digest: _receiverAbcSha,
    ),
  );
}

Future<void> _assertReceiverRecovery(
  _FileTransferTransport transport,
  WampFileReceiver receiver,
  _FailureProbeSink healthy,
) async {
  _sendReceiverHeader(transport, 88);
  transport.invokeChunk(
    requestId: 88,
    bytes: Uint8List.fromList([97, 98, 99]),
    progress: false,
  );
  await _settleChunkContinuations();
  expect(transport.errors, hasLength(1));
  expect(transport.yields, hasLength(1));
  expect(transport.yields.single.invocationRequestId, 88);
  expect(transport.yields.single.argumentsKeywords, {
    'file': {'name': 'received.bin', 'size': 3, 'sha256': _receiverAbcSha},
    'result': {'saved': true},
  });
  expect(healthy.writes, [
    [97, 98, 99],
  ]);
  expect(healthy.closes, 1);
  expect(healthy.aborts, isEmpty);
  expect(receiver.activeTransfers, 0);
  expect(receiver.bufferedBytes, 0);
}

class _FailureProbeSink extends WampFileSink {
  _FailureProbeSink({
    this.failure,
    this.failureStage,
    this.asynchronous = false,
    this.abortFails = false,
    this.closeResult,
  });
  final Object? failure;
  final String? failureStage;
  final bool asynchronous;
  final bool abortFails;
  final Future<Map<String, dynamic>?>? closeResult;
  final writes = <List<int>>[];
  final aborts = <Object>[];
  int closes = 0;

  @override
  FutureOr<void> add(Uint8List bytes) {
    writes.add(bytes.toList());
    if (failureStage == 'add') {
      if (asynchronous) return Future<void>.error(failure!);
      throw failure!;
    }
  }

  @override
  FutureOr<Map<String, dynamic>?> close(WampFileReceipt receipt) {
    closes++;
    if (failureStage == 'close') {
      if (asynchronous) return Future<Map<String, dynamic>?>.error(failure!);
      throw failure!;
    }
    return closeResult ?? {'saved': true};
  }

  @override
  FutureOr<void> abort(Object error) {
    aborts.add(error);
    if (abortFails) {
      final abortFailure = StateError('secondary cleanup failure');
      if (asynchronous) return Future<void>.error(abortFailure);
      throw abortFailure;
    }
  }
}
