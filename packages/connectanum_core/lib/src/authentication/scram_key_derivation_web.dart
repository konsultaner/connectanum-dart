import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'scram_argon2_worker_source.g.dart';
import 'scram_key_derivation.dart';

final class PlatformScramKeyDeriver implements ScramKeyDeriver {
  PlatformScramKeyDeriver() : _workerSource = scramArgon2WorkerSource;

  /// Creates a deriver with a controlled Worker program for browser tests.
  PlatformScramKeyDeriver.withWorkerSourceForTesting(this._workerSource);

  final Set<_WebDerivationTask> _tasks = <_WebDerivationTask>{};
  final String _workerSource;
  String? _workerUrl;
  bool _disposed = false;

  @override
  ScramKeyDerivationTask start(
    ScramKeyDerivationRequest request, {
    Duration? timeout,
  }) {
    if (_disposed) {
      throw StateError('SCRAM key deriver is disposed');
    }
    late final _WebDerivationTask task;
    task = _WebDerivationTask(
      request,
      workerUrl: _workerUrl ??= _createWorkerUrl(),
      timeout: timeout,
      onDone: () => _tasks.remove(task),
    );
    _tasks.add(task);
    task.start();
    return task;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final tasks = _tasks.toList(growable: false);
    await Future.wait(tasks.map((task) => task.cancel()));
    _tasks.clear();
    final workerUrl = _workerUrl;
    if (workerUrl != null) web.URL.revokeObjectURL(workerUrl);
    _workerUrl = null;
  }

  String _createWorkerUrl() {
    try {
      final blob = web.Blob(
        <web.BlobPart>[_workerSource.toJS].toJS,
        web.BlobPropertyBag(type: 'text/javascript'),
      );
      return web.URL.createObjectURL(blob);
    } catch (_) {
      throw const ScramKeyDerivationException(
        'worker initialization failed',
      );
    }
  }
}

final class _WebDerivationTask implements ScramKeyDerivationTask {
  _WebDerivationTask(
    this._request, {
    required this.workerUrl,
    required this.timeout,
    required this.onDone,
  });

  final ScramKeyDerivationRequest _request;
  final String workerUrl;
  final Duration? timeout;
  final void Function() onDone;
  final Completer<Uint8List> _completer = Completer<Uint8List>();
  web.Worker? _worker;
  Timer? _timer;
  bool _finished = false;

  @override
  Future<Uint8List> get result => _completer.future;

  void start() {
    try {
      final worker = web.Worker(workerUrl.toJS);
      _worker = worker;
      worker.onmessage = ((web.MessageEvent event) {
        final data = event.data;
        if (data?.isA<JSUint8Array>() ?? false) {
          final workerBytes = (data! as JSUint8Array).toDart;
          final result = Uint8List.fromList(workerBytes);
          _clear(workerBytes);
          _succeed(result);
        } else {
          _fail(const ScramKeyDerivationException('worker returned no result'));
        }
      }).toJS;
      worker.onmessageerror = ((web.Event _) {
        _fail(const ScramKeyDerivationException('worker message failed'));
      }).toJS;
      worker.onerror = ((web.Event _) {
        _fail(const ScramKeyDerivationException('worker failed'));
      }).toJS;
      if (timeout != null) {
        _timer = Timer(
          timeout!,
          () => _fail(const ScramKeyDerivationTimeoutException()),
        );
      }
      final passwordBuffer = JSArrayBuffer(_request.password.length);
      final saltBuffer = JSArrayBuffer(_request.salt.length);
      final password = JSUint8Array(passwordBuffer);
      final salt = JSUint8Array(saltBuffer);
      password.toDart.setAll(0, _request.password);
      salt.toDart.setAll(0, _request.salt);
      final message = _ScramWorkerRequest(
        kdf: _request.kdf,
        password: password,
        salt: salt,
        iterations: _request.iterations,
        memory: _request.memory,
        keyLength: _request.keyLength,
      );
      try {
        worker.postMessage(
          message,
          <JSArrayBuffer>[passwordBuffer, saltBuffer].toJS,
        );
      } catch (_) {
        _clear(password.toDart);
        _clear(salt.toDart);
        rethrow;
      }
      _clear(_request.password);
      _clear(_request.salt);
    } catch (_) {
      _clear(_request.password);
      _clear(_request.salt);
      _fail(const ScramKeyDerivationException('worker initialization failed'));
    }
  }

  @override
  Future<void> cancel() async {
    _fail(const ScramKeyDerivationCancelledException());
  }

  void _succeed(Uint8List value) {
    if (_finished) {
      _clear(value);
      return;
    }
    _finished = true;
    _completer.complete(value);
    _cleanup();
  }

  void _fail(Object error) {
    if (_finished) return;
    _finished = true;
    _completer.completeError(error);
    _cleanup();
  }

  void _cleanup() {
    _timer?.cancel();
    _worker?.terminate();
    _worker = null;
    onDone();
  }
}

@JS()
extension type _ScramWorkerRequest._(JSObject _) implements JSObject {
  external factory _ScramWorkerRequest({
    String kdf,
    JSUint8Array password,
    JSUint8Array salt,
    int iterations,
    int memory,
    int keyLength,
  });
}

void _clear(Uint8List value) => value.fillRange(0, value.length, 0);
