@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_bench/src/http_auth_bench_harness.dart';
import 'package:connectanum_router/connectanum_router.dart' hide Invocation;
import 'package:test/test.dart';

void main() {
  test(
    'shutdown destroys an active response before its flush completes',
    () async {
      final server = _MemoryServer();
      final socket = _MemorySocket();
      final outcome = await IOOverrides.runZoned(
        () => HttpAuthBenchHarness.maybeStart(
          settings: _settings(),
        ).then<Object?>((value) => value, onError: (Object error) => error),
        serverSocketBind:
            (
              address,
              port, {
              backlog = 0,
              v6Only = false,
              shared = false,
            }) async => server,
      );
      expect(outcome, isA<HttpAuthBenchHarness>());
      final harness = outcome as HttpAuthBenchHarness;
      try {
        server.accept(socket);
        socket.request();
        await socket.flushStarted.future.timeout(const Duration(seconds: 2));
        expect(socket.destroyed, isFalse);
        expect(socket.response, contains('200 OK'));
        expect(socket.response, contains('"active":true'));
        await harness.close();
        expect(socket.destroyed, isTrue);
        expect(socket.flushReleased.isCompleted, isFalse);
      } finally {
        socket.releaseFlush();
        socket.destroy();
        await harness.close();
      }
    },
  );

  test(
    'startup rollback destroys active responses and preserves bind failure',
    () async {
      final server = _MemoryServer();
      final socket = _MemorySocket();
      final secondBind = Completer<ServerSocket>();
      final secondBindStarted = Completer<void>();
      final bindFailure = StateError('synthetic bind failure');
      var binds = 0;
      final started = IOOverrides.runZoned(
        () => HttpAuthBenchHarness.maybeStart(
          settings: _settings(twoServers: true),
        ).then<Object?>((value) => value, onError: (Object error) => error),
        serverSocketBind:
            (address, port, {backlog = 0, v6Only = false, shared = false}) {
              if (binds++ == 0) return Future.value(server);
              secondBindStarted.complete();
              return secondBind.future;
            },
      );
      try {
        final pendingSecondBind = Object();
        final startup = await Future.any<Object?>([
          secondBindStarted.future.then((_) => pendingSecondBind),
          started,
        ]).timeout(const Duration(seconds: 2));
        expect(startup, same(pendingSecondBind));
        server.accept(socket);
        socket.request();
        await socket.flushStarted.future.timeout(const Duration(seconds: 2));
        expect(socket.destroyed, isFalse);
        expect(socket.response, contains('"active":true'));
        secondBind.completeError(bindFailure);
        expect(await started, same(bindFailure));
        expect(socket.destroyed, isTrue);
        expect(socket.flushReleased.isCompleted, isFalse);
      } finally {
        if (secondBindStarted.isCompleted && !secondBind.isCompleted) {
          secondBind.completeError(bindFailure);
        }
        socket.releaseFlush();
        socket.destroy();
        await started;
        if (binds > 0) await server.close();
      }
    },
  );

  test('an interrupted body is not disguised as a malformed form', () async {
    final server = _MemoryServer();
    final socket = _MemorySocket();
    final ready = Completer<Object?>();
    final transportFailure = Completer<Object>();
    final errors = <Object>[];
    runZonedGuarded(
      () => IOOverrides.runZoned(
        () async {
          ready.complete(
            await HttpAuthBenchHarness.maybeStart(
              settings: _settings(),
            ).then<Object?>((value) => value, onError: (Object error) => error),
          );
        },
        serverSocketBind:
            (
              address,
              port, {
              backlog = 0,
              v6Only = false,
              shared = false,
            }) async => server,
      ),
      (error, stack) {
        errors.add(error);
        if (!transportFailure.isCompleted) transportFailure.complete(error);
      },
    );
    final outcome = await ready.future.timeout(const Duration(seconds: 2));
    expect(outcome, isA<HttpAuthBenchHarness>());
    final harness = outcome as HttpAuthBenchHarness;
    try {
      server.accept(socket);
      socket.request(completeBody: false);
      unawaited(socket.endInput());
      final result = await Future.any<Object>([
        transportFailure.future,
        socket.responseStarted.future.then((_) => 'response started'),
        socket.done.then<Object>((_) async {
          // EOF closes the socket and reports its error through separate
          // microtask chains. Observe both before classifying a silent close.
          await Future<void>.delayed(Duration.zero);
          return errors.isEmpty
              ? 'connection closed without transport error'
              : errors.first;
        }),
      ]).timeout(const Duration(seconds: 2));
      expect(result, isA<HttpException>());
      expect(errors, hasLength(1));
      expect(socket.response, isEmpty);
      expect(socket.responseStarted.isCompleted, isFalse);
    } finally {
      socket.releaseFlush();
      socket.destroy();
      await harness.close();
    }
  });
}

RouterSettings _settings({bool twoServers = false}) {
  final builder = RouterSettingsBuilder();
  for (var index = 0; index < (twoServers ? 2 : 1); index++) {
    builder.addHttpAuthProvider(
      'provider$index',
      HttpAuthProviderDefinition(
        type: 'oauth',
        options: {'url': 'http://127.0.0.1:${12345 + index}/introspect'},
      ),
    );
  }
  return builder.build();
}

class _MemoryServer extends Stream<Socket> implements ServerSocket {
  final _accepted = StreamController<Socket>(sync: true);

  void accept(Socket socket) => _accepted.add(socket);

  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;

  @override
  int get port => 12345;

  @override
  Future<ServerSocket> close() async {
    await _accepted.close();
    return this;
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _accepted.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemorySocket extends Stream<Uint8List> implements Socket {
  final _incoming = StreamController<Uint8List>(sync: true);
  final _outgoing = <int>[];
  final responseStarted = Completer<void>();
  final flushStarted = Completer<void>();
  final flushReleased = Completer<void>();
  final _closed = Completer<void>();
  var destroyed = false;

  String get response => utf8.decode(_outgoing);

  void request({bool completeBody = true}) {
    final body = 'token=${HttpAuthBenchHarness.defaultOAuthAccessToken}';
    _incoming.add(
      Uint8List.fromList(
        ascii.encode(
          'POST /introspect HTTP/1.1\r\nHost: localhost\r\n'
          'Content-Length: ${body.length}\r\n\r\n${completeBody ? body : 'token='}',
        ),
      ),
    );
  }

  Future<void> endInput() => _incoming.close();

  void releaseFlush() {
    if (!flushReleased.isCompleted) flushReleased.complete();
  }

  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;

  @override
  int get port => 12345;

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  void add(List<int> data) => _outgoing.addAll(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    if (!responseStarted.isCompleted) responseStarted.complete();
    await for (final bytes in stream) {
      add(bytes);
    }
  }

  @override
  Future<void> flush() {
    if (!flushStarted.isCompleted) flushStarted.complete();
    return flushReleased.future;
  }

  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    unawaited(_incoming.close());
    _closed.complete();
  }

  @override
  Future<void> close() async => destroy();

  @override
  Future<void> get done => _closed.future;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
