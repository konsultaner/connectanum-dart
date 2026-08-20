import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('progressive file transfer', () {
    test('setFile sends metadata then bounded binary chunks', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final bytes = Uint8List.fromList(<int>[0, 1, 2, 3, 4]);

      final result = await session.setFile(
        'files.set',
        WampFileSource.bytes(
          bytes,
          name: 'sample.bin',
          contentType: 'application/octet-stream',
          sha256Digest: sha256.convert(bytes).toString(),
        ),
        chunkSize: 2,
      );

      expect(result.arguments, equals(const <dynamic>['ok']));
      expect(transport.calls, hasLength(4));
      expect(
        transport.calls.map((call) => call.requestId).toSet(),
        hasLength(1),
      );
      expect(transport.calls.first.options?.progress, isTrue);
      expect(
        transport.calls.first.argumentsKeywords,
        equals(<String, dynamic>{
          wampFileMetadataKey: <String, dynamic>{
            'version': 1,
            'name': 'sample.bin',
            'size': 5,
            'chunk_size': 2,
            'content_type': 'application/octet-stream',
            'sha256': sha256.convert(bytes).toString(),
          },
        }),
      );
      expect(
        transport.calls.skip(1).map((call) => call.options?.progress),
        equals(const <bool>[true, true, false]),
      );
      expect(
        transport.calls
            .skip(1)
            .map((call) => (call.arguments?.single as Uint8List).toList()),
        equals(const <List<int>>[
          <int>[0, 1],
          <int>[2, 3],
          <int>[4],
        ]),
      );
    });

    test(
      'setFile terminates an empty file with an empty binary chunk',
      () async {
        final transport = _FileTransferTransport();
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;

        await session.setFile(
          'files.set',
          WampFileSource.bytes(Uint8List(0), name: 'empty.bin'),
        );

        expect(transport.calls, hasLength(2));
        expect(transport.calls.last.options?.progress, isFalse);
        expect(
          transport.calls.last.arguments,
          equals(<dynamic>[Uint8List(0)]),
        );
      },
    );

    test(
      'setFile uses file-backed segments when the transport supports them',
      () async {
        final transport = _FileSegmentTransferTransport();
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;
        final source = WampFileSource(
          name: 'native.bin',
          length: 5,
          nativePath: '/tmp/native.bin',
          openRead: () =>
              throw StateError('buffered source must not be opened'),
        );

        final result = await session.setFile('files.set', source, chunkSize: 2);

        expect(result.arguments, equals(const <dynamic>['ok']));
        expect(transport.openedPath, equals('/tmp/native.bin'));
        expect(transport.openedLength, equals(5));
        expect(
          transport.segments,
          equals(const <_SentFileSegment>[
            _SentFileSegment(offset: 0, length: 2, progress: true),
            _SentFileSegment(offset: 2, length: 2, progress: true),
            _SentFileSegment(offset: 4, length: 1, progress: false),
          ]),
        );
        expect(transport.source?.closed, isTrue);
      },
    );

    test('setFile cancels when the source is shorter than declared', () async {
      final transport = _FileTransferTransport();
      final session = await Client(
        realm: 'test.realm',
        transport: transport,
      ).connect().first;
      final source = WampFileSource(
        name: 'short.bin',
        length: 3,
        openRead: () => Stream<Uint8List>.value(
          Uint8List.fromList(const <int>[1, 2]),
        ),
      );

      await expectLater(
        session.setFile('files.set', source),
        throwsA(isA<WampFileTransferException>()),
      );
      await _waitUntil(() => transport.cancels.isNotEmpty);
      expect(
        transport.cancels.single.options?.mode,
        CancelOptions.modeKillNoWait,
      );
    });

    test(
      'receiver applies backpressure and returns a verified receipt',
      () async {
        final transport = _FileTransferTransport();
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;
        final sink = _CollectingFileSink();
        final bytes = Uint8List.fromList(const <int>[1, 2, 3]);
        final receiver = await WampFileReceiver.register(
          session,
          'files.set',
          (_) => sink,
        );

        transport.invokeHeader(
          requestId: 77,
          metadata: WampFileMetadata(
            name: 'received.bin',
            size: bytes.length,
            chunkSize: 2,
            sha256Digest: sha256.convert(bytes).toString(),
          ),
        );
        transport.invokeChunk(
          requestId: 77,
          bytes: Uint8List.sublistView(bytes, 0, 2),
          progress: true,
        );
        transport.invokeChunk(
          requestId: 77,
          bytes: Uint8List.sublistView(bytes, 2),
          progress: false,
        );

        await _waitUntil(() => transport.yields.isNotEmpty);
        expect(sink.bytes, equals(bytes));
        expect(sink.receipt?.receivedBytes, equals(3));
        expect(
          transport.yields.single.argumentsKeywords?['file'],
          equals(<String, dynamic>{
            'name': 'received.bin',
            'size': 3,
            'sha256': sha256.convert(bytes).toString(),
          }),
        );
        expect(receiver.activeTransfers, equals(0));
        expect(receiver.bufferedBytes, equals(0));
        await receiver.close();
      },
    );

    test(
      'receiver rejects data beyond its global buffered-byte limit',
      () async {
        final transport = _FileTransferTransport();
        final session = await Client(
          realm: 'test.realm',
          transport: transport,
        ).connect().first;
        final sink = _BlockingFileSink();
        final receiver = await WampFileReceiver.register(
          session,
          'files.set',
          (_) => sink,
          maxBufferedBytes: 3,
        );

        transport.invokeHeader(
          requestId: 88,
          metadata: WampFileMetadata(
            name: 'bounded.bin',
            size: 4,
            chunkSize: 2,
          ),
        );
        transport.invokeChunk(
          requestId: 88,
          bytes: Uint8List.fromList(const <int>[1, 2]),
          progress: true,
        );
        transport.invokeChunk(
          requestId: 88,
          bytes: Uint8List.fromList(const <int>[3, 4]),
          progress: false,
        );

        await _waitUntil(() => transport.errors.isNotEmpty);
        expect(
          transport.errors.single.error,
          WampFileReceiver.capacityExceededError,
        );
        await _waitUntil(() => sink.aborted && receiver.bufferedBytes == 0);
        expect(receiver.activeTransfers, equals(0));
        await receiver.close();
      },
    );

    test('receiver aborts an idle transfer and releases capacity', () async {
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
        idleTimeout: const Duration(milliseconds: 20),
      );

      transport.invokeHeader(
        requestId: 99,
        metadata: WampFileMetadata(
          name: 'idle.bin',
          size: 1,
          chunkSize: 1,
        ),
      );

      await _waitUntil(() => transport.errors.isNotEmpty);
      expect(transport.errors.single.error, WampFileReceiver.timeoutError);
      expect(sink.aborted, isTrue);
      expect(receiver.activeTransfers, equals(0));
      await receiver.close();
    });

    test('receiver rejects a mismatched SHA-256 digest', () async {
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

      transport.invokeHeader(
        requestId: 100,
        metadata: WampFileMetadata(
          name: 'checksum.bin',
          size: 1,
          chunkSize: 1,
          sha256Digest: '0' * 64,
        ),
      );
      transport.invokeChunk(
        requestId: 100,
        bytes: Uint8List.fromList(const <int>[1]),
        progress: false,
      );

      await _waitUntil(() => transport.errors.isNotEmpty);
      expect(
        transport.errors.single.error,
        WampFileReceiver.checksumMismatchError,
      );
      expect(sink.aborted, isTrue);
      await receiver.close();
    });

    test('Dart IO path source reports and streams the file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'connectanum-file-source-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/source.bin');
      await file.writeAsBytes(const <int>[4, 5, 6], flush: true);

      final source = await wampFileSourceFromPath(file.path);
      final streamed = <int>[];
      await for (final chunk in source.openRead()) {
        streamed.addAll(chunk);
      }

      expect(source.name, equals('source.bin'));
      expect(source.length, equals(3));
      expect(streamed, equals(const <int>[4, 5, 6]));
    });
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for asynchronous file-transfer state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class _CollectingFileSink extends WampFileSink {
  final List<int> _bytes = <int>[];
  WampFileReceipt? receipt;
  bool aborted = false;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  void add(Uint8List chunk) {
    _bytes.addAll(chunk);
  }

  @override
  Map<String, dynamic> close(WampFileReceipt receipt) {
    this.receipt = receipt;
    return const <String, dynamic>{'stored': true};
  }

  @override
  void abort(Object error) {
    aborted = true;
  }
}

class _BlockingFileSink extends WampFileSink {
  final Completer<void> _write = Completer<void>();
  bool aborted = false;

  @override
  Future<void> add(Uint8List chunk) => _write.future;

  @override
  Map<String, dynamic>? close(WampFileReceipt receipt) => null;

  @override
  void abort(Object error) {
    aborted = true;
    if (!_write.isCompleted) {
      _write.complete();
    }
  }
}

class _FileTransferTransport extends AbstractTransport {
  final StreamController<AbstractMessage> _inbound =
      StreamController<AbstractMessage>.broadcast(sync: true);
  final List<Call> calls = <Call>[];
  final List<Cancel> cancels = <Cancel>[];
  final List<Yield> yields = <Yield>[];
  final List<Error> errors = <Error>[];
  Completer<void>? _disconnect;
  Completer<void>? _connectionLost;
  bool _open = false;

  @override
  Completer<void>? get onDisconnect => _disconnect;

  @override
  Completer<void>? get onConnectionLost => _connectionLost;

  @override
  bool get isOpen => _open;

  @override
  bool get isReady => _open;

  @override
  Future<void> get onReady => Future<void>.value();

  @override
  Future<void> open({Duration? pingInterval}) async {
    _open = true;
    _disconnect = Completer<void>();
    _connectionLost = Completer<void>();
  }

  @override
  Future<void> close({error}) async {
    _open = false;
    if (_disconnect?.isCompleted == false) {
      _disconnect!.complete();
    }
  }

  @override
  Stream<AbstractMessage> receive() => _inbound.stream;

  @override
  void send(AbstractMessage message) {
    if (message is Hello) {
      _inbound.add(Welcome(1, Details.forWelcome()));
      return;
    }
    if (message is Register) {
      _inbound.add(Registered(message.requestId, 20));
      return;
    }
    if (message is Unregister) {
      _inbound.add(Unregistered(message.requestId));
      return;
    }
    if (message is Call) {
      calls.add(message);
      if (message.options?.progress == false) {
        _inbound.add(
          Result(
            message.requestId,
            ResultDetails(progress: false),
            arguments: const <dynamic>['ok'],
          ),
        );
      }
      return;
    }
    if (message is Cancel) {
      cancels.add(message);
      return;
    }
    if (message is Yield) {
      yields.add(message);
      return;
    }
    if (message is Error) {
      errors.add(message);
    }
  }

  void invokeHeader({
    required int requestId,
    required WampFileMetadata metadata,
  }) {
    final details = InvocationDetails(1, 'files.set', false)..progress = true;
    _inbound.add(
      Invocation(
        requestId,
        20,
        details,
        argumentsKeywords: <String, dynamic>{
          wampFileMetadataKey: metadata.toJson(),
        },
      ),
    );
  }

  void invokeChunk({
    required int requestId,
    required Uint8List bytes,
    required bool progress,
  }) {
    final details = InvocationDetails(1, 'files.set', false)
      ..progress = progress;
    final invocation = Invocation(
      requestId,
      20,
      details,
      arguments: <dynamic>[bytes],
    );
    _inbound.add(invocation);
  }
}

class _TestTransportFileSource implements TransportFileSource {
  bool closed = false;

  @override
  void close() {
    closed = true;
  }
}

class _SentFileSegment {
  const _SentFileSegment({
    required this.offset,
    required this.length,
    required this.progress,
  });

  final int offset;
  final int length;
  final bool progress;

  @override
  bool operator ==(Object other) =>
      other is _SentFileSegment &&
      other.offset == offset &&
      other.length == length &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(offset, length, progress);
}

class _FileSegmentTransferTransport extends _FileTransferTransport
    implements FileSegmentTransport {
  final List<_SentFileSegment> segments = <_SentFileSegment>[];
  String? openedPath;
  int? openedLength;
  _TestTransportFileSource? source;

  @override
  bool get supportsFileSegments => true;

  @override
  TransportFileSource openFileSegmentSource(String path, int expectedLength) {
    openedPath = path;
    openedLength = expectedLength;
    return source = _TestTransportFileSource();
  }

  @override
  void sendFileSegment(
    AbstractMessage message, {
    required TransportFileSource source,
    required int offset,
    required int length,
  }) {
    final call = message as Call;
    calls.add(call);
    segments.add(
      _SentFileSegment(
        offset: offset,
        length: length,
        progress: call.options?.progress ?? false,
      ),
    );
    if (call.options?.progress == false) {
      _inbound.add(
        Result(
          call.requestId,
          ResultDetails(progress: false),
          arguments: const <dynamic>['ok'],
        ),
      );
    }
  }
}
