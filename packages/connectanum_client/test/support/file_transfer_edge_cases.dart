part of '../file_transfer_test.dart';

void _fileTransferEdgeCases() {
  group('file transfer edge contracts', () {
    test('rejects a negative timeout before starting a call', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final source = WampFileSource.bytes(
        Uint8List.fromList(const <int>[1]),
        name: 'negative-timeout.bin',
      );

      await expectLater(
        session.setFile(
          'files.set',
          source,
          timeout: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(transport.calls, isEmpty);
    });

    test('rejects a source that emits more bytes than declared', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final source = WampFileSource(
        name: 'too-long.bin',
        length: 2,
        openRead: () => Stream<Uint8List>.value(
          Uint8List.fromList(const <int>[1, 2, 3]),
        ),
      );

      await expectLater(
        session.setFile('files.set', source, chunkSize: 3),
        throwsA(
          isA<WampFileTransferException>().having(
            (error) => error.message,
            'message',
            'Source emitted more than its declared 2 bytes',
          ),
        ),
      );
      expect(transport.calls, hasLength(1));
    });

    test('does not open native segments for an empty native source', () async {
      final transport = _FileSegmentTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final source = WampFileSource(
        name: 'empty-native.bin',
        length: 0,
        nativePath: '/tmp/empty-native.bin',
        openRead: () => Stream<Uint8List>.empty(),
      );

      final result = await session.setFile(
        'files.set',
        source,
        chunkSize: 2,
        timeout: const Duration(milliseconds: 100),
      );

      expect(result.arguments, const <dynamic>['ok']);
      expect(transport.openedPath, isNull);
      expect(transport.calls.last.arguments, [Uint8List(0)]);
    });

    test('preserves an explicitly supplied call timeout', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;

      await session.setFile(
        'files.set',
        WampFileSource.bytes(
          Uint8List.fromList(const <int>[1]),
          name: 'timeout.bin',
        ),
        timeout: const Duration(seconds: 9),
        options: CallOptions(timeout: 1234),
      );

      expect(transport.calls.first.options?.timeout, 1234);
    });

    test('rechunking does not append an empty exact-boundary chunk', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final bytes = Uint8List.fromList(const <int>[1, 2]);
      final source = WampFileSource(
        name: 'exact-boundary.bin',
        length: 2,
        openRead: () => Stream<Uint8List>.value(bytes),
      );

      await session.setFile('files.set', source, chunkSize: 2);

      expect(transport.calls, hasLength(2));
      expect(transport.calls.last.arguments, [
        same(bytes),
      ]);
    });

    test(
      'stops when the remote returns a final result during a drain',
      () async {
        final transport = _EarlyFinalDrainFileTransferTransport();
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;

        await expectLater(
          session.setFile(
            'files.set',
            WampFileSource.bytes(
              Uint8List.fromList(const <int>[1, 2, 3]),
              name: 'early-final.bin',
            ),
            chunkSize: 1,
          ),
          throwsA(
            isA<WampFileTransferException>().having(
              (error) => error.message,
              'message',
              'Remote procedure completed before the file source was exhausted',
            ),
          ),
        );
        expect(transport.drainCount, 1);
        expect(transport.cancels, isEmpty);
      },
    );

    test('rechunking resets its buffer after a full chunk', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final source = WampFileSource(
        name: 'reset-buffer.bin',
        length: 3,
        openRead: () => Stream<Uint8List>.fromIterable(<Uint8List>[
          Uint8List.fromList(const <int>[1]),
          Uint8List.fromList(const <int>[2]),
          Uint8List.fromList(const <int>[3]),
        ]),
      );

      await session.setFile('files.set', source, chunkSize: 2);

      expect(
        transport.calls.skip(1).map((call) => call.arguments),
        [
          [
            Uint8List.fromList([1, 2]),
          ],
          [
            Uint8List.fromList([3]),
          ],
        ],
      );
    });

    test('receiver preserves a Uint8List binary argument instance', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final sink = _IdentityFileSink();
      final receiver = await WampFileReceiver.register(
        session,
        'files.set',
        (_) => sink,
      );
      addTearDown(receiver.close);
      final bytes = Uint8List.fromList(const <int>[1]);

      transport.invokeHeader(
        requestId: 902,
        metadata: WampFileMetadata(name: 'identity.bin', size: 1, chunkSize: 1),
      );
      transport.invokeChunk(requestId: 902, bytes: bytes, progress: false);
      await _settleChunkContinuations();

      expect(sink.received, same(bytes));
    });

    test('receiver close is idempotent and aborts active transfers', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final sink = _CollectingFileSink();
      final receiver = await WampFileReceiver.register(
        session,
        'files.set',
        (_) => sink,
      );
      addTearDown(receiver.close);

      transport.invokeHeader(
        requestId: 901,
        metadata: WampFileMetadata(
          name: 'close.bin',
          size: 1,
          chunkSize: 1,
        ),
      );
      await _settleChunkContinuations();
      expect(receiver.activeTransfers, 1);

      await receiver.close();
      await receiver.close();

      expect(receiver.activeTransfers, 0);
      expect(receiver.bufferedBytes, 0);
      expect(sink.aborted, isTrue);
      expect(sink.abortCount, 1);
      expect(transport.unregisterCount, 1);
    });

    test('receiver rejects an invocation racing with close', () async {
      final transport = _DelayedUnregisterFileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final receiver = await WampFileReceiver.register(
        session,
        'files.set',
        (_) => _CollectingFileSink(),
      );

      final closing = receiver.close();
      transport.invokeHeader(
        requestId: 905,
        metadata: WampFileMetadata(name: 'closed.bin', size: 1, chunkSize: 1),
      );
      await _settleChunkContinuations();
      expect(transport.errors, hasLength(1));
      expect(transport.errors.single.error, WampFileReceiver.sinkFailedError);

      transport.releaseUnregister();
      await closing;
    });

    test('receiver close aborts every active transfer', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final sinks = <String, _CollectingFileSink>{};
      final receiver = await WampFileReceiver.register(
        session,
        'files.set',
        (metadata) => sinks.putIfAbsent(metadata.name, _CollectingFileSink.new),
        maxConcurrentTransfers: 2,
      );
      addTearDown(receiver.close);

      transport.invokeHeader(
        requestId: 903,
        metadata: WampFileMetadata(name: 'first.bin', size: 1, chunkSize: 1),
      );
      transport.invokeHeader(
        requestId: 904,
        metadata: WampFileMetadata(name: 'second.bin', size: 1, chunkSize: 1),
      );
      await _settleChunkContinuations();
      expect(receiver.activeTransfers, 2);

      await receiver.close();

      expect(receiver.activeTransfers, 0);
      expect(sinks['first.bin']?.aborted, isTrue);
      expect(sinks['second.bin']?.aborted, isTrue);
    });

    test('IO file source honors an explicit display name', () async {
      final directory = await Directory.systemTemp.createTemp(
        'connectanum-file-name-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/source.bin');
      await file.writeAsBytes(const <int>[1], flush: true);

      final source = await wampFileSourceFromPath(
        file.path,
        name: 'display.bin',
      );

      expect(source.name, 'display.bin');
    });
  });
}

class _IdentityFileSink extends WampFileSink {
  Uint8List? received;

  @override
  void add(Uint8List chunk) {
    received = chunk;
  }

  @override
  Map<String, dynamic>? close(WampFileReceipt receipt) => null;

  @override
  void abort(Object error) {}
}

class _EarlyFinalDrainFileTransferTransport extends _FileTransferTransport
    implements DrainableTransport {
  int drainCount = 0;

  @override
  Future<void> drain() async {
    drainCount++;
    if (drainCount == 1) {
      _inbound.add(
        Result(
          calls.first.requestId,
          ResultDetails(progress: false),
          arguments: const <dynamic>['early'],
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _DelayedUnregisterFileTransferTransport extends _FileTransferTransport {
  final Completer<void> _unregister = Completer<void>();

  void releaseUnregister() {
    if (!_unregister.isCompleted) {
      _unregister.complete();
    }
  }

  @override
  void send(AbstractMessage message) {
    if (message is Unregister) {
      unregisterCount++;
      _unregister.future.then((_) {
        super.send(message);
      });
      return;
    }
    super.send(message);
  }
}
