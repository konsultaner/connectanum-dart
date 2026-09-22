part of '../file_transfer_test.dart';

void _fileReceiverChunkCases() {
  group('file receiver chunk contract', () {
    for (final scenario in [
      'missing',
      'empty-arguments',
      'extra-argument',
      'string',
      'scalar',
      'mixed-list',
      'keywords',
      'empty-progress',
    ]) {
      test('rejects $scenario data before writing and permits retry', () async {
        final fixture = await _ChunkFixture.start();
        await fixture.header(70);
        final sink = fixture.sinks.single;
        final bytes = Uint8List.fromList([97, 98, 99]);
        final List<dynamic>? arguments = switch (scenario) {
          'missing' => null,
          'empty-arguments' => [],
          'extra-argument' => [bytes, bytes],
          'string' => ['abc'],
          'scalar' => [1],
          'mixed-list' => [
            <Object>[97, '98'],
          ],
          'empty-progress' => [Uint8List(0)],
          _ => [bytes],
        };
        fixture.chunk(
          70,
          arguments: arguments,
          keywords: scenario == 'keywords' ? {'unexpected': true} : null,
          progress: scenario == 'empty-progress',
        );
        await _settleChunkContinuations();
        expect(sink.writes, isEmpty);
        await fixture.expectFailure(
          70,
          'Data invocations must contain binary payload only',
        );
        expect(sink.closes, 0);
        expect(sink.aborts, hasLength(1));
        await fixture.recover();
      });
    }

    test('accepts integer-list binary data and empty keyword map', () async {
      final fixture = await _ChunkFixture.start();
      await fixture.header(70);
      fixture.chunk(
        70,
        arguments: [
          <int>[97, 98, 99],
        ],
        keywords: {},
      );
      await fixture.expectSuccess(70);
      expect(fixture.sinks.single.writes, [
        [97, 98, 99],
      ]);
    });

    for (final scenario in ['chunk-limit', 'cumulative-limit', 'short-final']) {
      test('rejects $scenario without a successful receipt', () async {
        final fixture = await _ChunkFixture.start();
        await fixture.header(70, chunkSize: scenario == 'chunk-limit' ? 2 : 3);
        final sink = fixture.sinks.single;
        if (scenario == 'cumulative-limit') {
          fixture.chunk(
            70,
            arguments: [
              Uint8List.fromList([97, 98]),
            ],
            progress: true,
          );
          await _settleChunkContinuations();
          expect(fixture.transport.errors, isEmpty);
          expect(sink.writes, [
            [97, 98],
          ]);
        }
        fixture.chunk(
          70,
          arguments: [
            Uint8List.fromList(
              scenario == 'chunk-limit' ? [97, 98, 99] : [99, 100],
            ),
          ],
        );
        await _settleChunkContinuations();
        await fixture.expectFailure(
          70,
          scenario == 'short-final'
              ? 'Received byte count does not match declared file size'
              : 'File chunk exceeds declared transfer bounds',
        );
        expect(sink.closes, 0);
        expect(sink.aborts, hasLength(1));
        expect(
          sink.writes,
          scenario == 'chunk-limit'
              ? <List<int>>[]
              : scenario == 'cumulative-limit'
              ? [
                  [97, 98],
                ]
              : [
                  [99, 100],
                ],
        );
        await fixture.recover();
      });
    }

    test('allows an empty final marker after all progressive bytes', () async {
      final fixture = await _ChunkFixture.start();
      await fixture.header(70);
      fixture.chunk(
        70,
        arguments: [
          Uint8List.fromList([97, 98, 99]),
        ],
        progress: true,
      );
      await _settleChunkContinuations();
      expect(fixture.sinks.single.writes, [
        [97, 98, 99],
      ]);
      expect(fixture.transport.errors, isEmpty);
      expect(fixture.transport.yields, isEmpty);
      expect(fixture.receiver.activeTransfers, 1);
      fixture.chunk(70, arguments: [Uint8List(0)]);
      await fixture.expectSuccess(70);
      expect(fixture.sinks.single.writes, [
        [97, 98, 99],
        <int>[],
      ]);
    });

    test(
      'queued asynchronous writes preserve ordering and exact byte accounting',
      () async {
        final fixture = await _ChunkFixture.start(blockFirst: true);
        await fixture.header(70);
        final sink = fixture.sinks.single;
        fixture.chunk(
          70,
          arguments: [
            Uint8List.fromList([97]),
          ],
          progress: true,
        );
        await _settleChunkContinuations();
        expect(sink.writes, [
          [97],
        ]);
        expect(fixture.transport.errors, isEmpty);
        fixture.chunk(
          70,
          arguments: [
            Uint8List.fromList([98, 99]),
          ],
        );
        await _settleChunkContinuations();
        expect(fixture.receiver.bufferedBytes, 3);
        expect(fixture.transport.errors, isEmpty);
        expect(sink.writes, [
          [97],
        ]);
        expect(sink.closes, 0);
        expect(fixture.transport.yields, isEmpty);
        expect(fixture.receiver.activeTransfers, 1);
        sink.release();
        await fixture.expectSuccess(70);
        expect(sink.writes, [
          [97],
          [98, 99],
        ]);
      },
    );

    test(
      'extra chunk after queued final chunk aborts without committing queued data',
      () async {
        final fixture = await _ChunkFixture.start(blockFirst: true);
        await fixture.header(70);
        final sink = fixture.sinks.single;
        fixture.chunk(
          70,
          arguments: [
            Uint8List.fromList([97]),
          ],
          progress: true,
        );
        await _settleChunkContinuations();
        expect(sink.writes, [
          [97],
        ]);
        expect(fixture.transport.errors, isEmpty);
        fixture.chunk(
          70,
          arguments: [
            Uint8List.fromList([98, 99]),
          ],
        );
        fixture.chunk(70, arguments: [Uint8List(0)]);
        sink.release();
        await _settleChunkContinuations();
        await fixture.expectFailure(
          70,
          'File transfer already reached a terminal chunk',
        );
        expect(sink.writes, [
          [97],
        ]);
        expect(sink.closes, 0);
        expect(sink.aborts, hasLength(1));
        await fixture.recover();
      },
    );

    test(
      'aggregate buffer admission rejects only the transfer exceeding shared capacity',
      () async {
        final fixture = await _ChunkFixture.start(
          blockFirst: true,
          maxConcurrent: 2,
        );
        await fixture.header(70);
        await fixture.header(71);
        final first = fixture.sinks[0];
        final second = fixture.sinks[1];
        fixture.chunk(
          70,
          arguments: [
            Uint8List.fromList([97, 98]),
          ],
          progress: true,
        );
        await _settleChunkContinuations();
        expect(first.writes, [
          [97, 98],
        ]);
        expect(fixture.transport.errors, isEmpty);
        expect(fixture.receiver.bufferedBytes, 2);
        fixture.chunk(
          71,
          arguments: [
            Uint8List.fromList([97, 98]),
          ],
          progress: true,
        );
        await _settleChunkContinuations();
        expect(fixture.transport.errors, hasLength(1));
        expect(fixture.transport.errors.single.requestId, 71);
        expect(
          fixture.transport.errors.single.error,
          WampFileReceiver.capacityExceededError,
        );
        expect(fixture.transport.errors.single.arguments, [
          'Buffered file data exceeds receiver limit',
        ]);
        expect(second.writes, isEmpty);
        expect(second.aborts, hasLength(1));
        expect(first.aborts, isEmpty);
        expect(fixture.receiver.activeTransfers, 1);
        expect(fixture.receiver.bufferedBytes, 2);
        first.release();
        await _settleChunkContinuations();
        expect(fixture.receiver.bufferedBytes, 0);
        fixture.chunk(
          70,
          arguments: [
            Uint8List.fromList([99]),
          ],
        );
        await fixture.expectSuccess(70, priorErrors: 1);
        expect(first.writes, [
          [97, 98],
          [99],
        ]);
        await fixture.recover(priorYields: 1);
      },
    );
  });
}

class _ChunkFixture {
  _ChunkFixture(this.transport, this.receiver, this.sinks);
  final _AdmissionTransport transport;
  final WampFileReceiver receiver;
  final List<_ChunkSink> sinks;
  final _sinksByRequest = <int, _ChunkSink>{};

  static Future<_ChunkFixture> start({
    bool blockFirst = false,
    int maxConcurrent = 1,
  }) async {
    final (transport, session) = await _admissionSession();
    final sinks = <_ChunkSink>[];
    WampFileReceiver? receiver;
    Object? failure;
    await WampFileReceiver.register(
      session,
      'files.set',
      (_) {
        final sink = _ChunkSink(blockFirst && sinks.isEmpty);
        sinks.add(sink);
        return sink;
      },
      maxConcurrentTransfers: maxConcurrent,
      maxFileSize: 3,
      maxChunkSize: 3,
      maxBufferedBytes: 3,
    ).then<void>(
      (value) {
        receiver = value;
        addTearDown(value.close);
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
      },
    );
    expect(failure, isNull);
    expect(receiver, isNotNull);
    return _ChunkFixture(transport, receiver!, sinks);
  }

  Future<void> header(int id, {int chunkSize = 3}) async {
    final before = sinks.length;
    final errors = transport.errors.length;
    transport.invokeHeader(
      requestId: id,
      metadata: WampFileMetadata(
        name: 'data',
        size: 3,
        chunkSize: chunkSize,
        sha256Digest: _receiverAbcSha,
      ),
    );
    await _settleChunkContinuations();
    expect(transport.errors, hasLength(errors));
    expect(sinks, hasLength(before + 1));
    _sinksByRequest[id] = sinks.last;
  }

  void chunk(
    int id, {
    List<dynamic>? arguments,
    Map<String, dynamic>? keywords,
    bool progress = false,
  }) {
    transport._inbound.add(
      Invocation(
        id,
        20,
        InvocationDetails(1, 'files.set', false)..progress = progress,
        arguments: arguments,
        argumentsKeywords: keywords,
      ),
    );
  }

  Future<void> expectFailure(int id, String message) async {
    expect(transport.errors, hasLength(1));
    expect(transport.errors.single.requestId, id);
    expect(transport.errors.single.error, WampFileReceiver.invalidChunkError);
    expect(transport.errors.single.arguments, [message]);
    expect(transport.yields, isEmpty);
    expect(receiver.activeTransfers, 0);
    await _settleChunkContinuations();
    expect(receiver.bufferedBytes, 0);
  }

  Future<void> expectSuccess(
    int id, {
    int priorErrors = 0,
    int priorYields = 0,
  }) async {
    await _settleChunkContinuations();
    expect(transport.errors, hasLength(priorErrors));
    expect(transport.yields, hasLength(priorYields + 1));
    expect(transport.yields.last.invocationRequestId, id);
    expect(transport.yields.last.argumentsKeywords, {
      'file': {'name': 'data', 'size': 3, 'sha256': _receiverAbcSha},
      'result': {'stored': true},
    });
    expect(_sinksByRequest[id]?.closes, 1);
    expect(_sinksByRequest[id]?.aborts, isEmpty);
    expect(receiver.activeTransfers, 0);
    await _settleChunkContinuations();
    expect(receiver.bufferedBytes, 0);
  }

  Future<void> recover({int priorYields = 0}) async {
    await header(72);
    chunk(
      72,
      arguments: [
        Uint8List.fromList([97, 98, 99]),
      ],
    );
    await expectSuccess(72, priorErrors: 1, priorYields: priorYields);
    expect(sinks.last.writes, [
      [97, 98, 99],
    ]);
  }
}

// This synchronous transport has no I/O; admission and released writes schedule
// only microtasks. An event turn drains them before checking exact outcomes.
Future<void> _settleChunkContinuations() => Future<void>(() {});

class _ChunkSink extends WampFileSink {
  _ChunkSink(bool blocking) : barrier = blocking ? Completer<void>() : null;
  final Completer<void>? barrier;
  final writes = <List<int>>[];
  final aborts = <Object>[];
  int closes = 0;

  void release() {
    if (barrier?.isCompleted == false) barrier!.complete();
  }

  @override
  FutureOr<void> add(Uint8List bytes) {
    writes.add(bytes.toList());
    return barrier?.future;
  }

  @override
  Map<String, dynamic> close(WampFileReceipt receipt) {
    closes++;
    return {'stored': true};
  }

  @override
  void abort(Object error) {
    aborts.add(error);
    release();
  }
}
