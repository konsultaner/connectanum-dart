import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'attachment_crypto_worker.dart';
import 'attachment_crypto_worker_source.dart';

final class PlatformAttachmentCryptoWorker implements AttachmentCryptoWorker {
  PlatformAttachmentCryptoWorker()
    : _workerSource = attachmentCryptoWorkerSource;

  PlatformAttachmentCryptoWorker.withWorkerSourceForTesting(this._workerSource);

  final Set<_WebAttachmentCryptoTask> _tasks = <_WebAttachmentCryptoTask>{};
  final String _workerSource;
  String? _workerUrl;
  bool _disposed = false;

  @override
  AttachmentCryptoTask start(
    AttachmentCryptoRequest request, {
    Duration? timeout,
  }) {
    if (_disposed) throw StateError('Attachment crypto worker is disposed');
    late final _WebAttachmentCryptoTask task;
    task = _WebAttachmentCryptoTask(
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
      throw const AttachmentCryptoException('worker initialization failed');
    }
  }
}

final class _WebAttachmentCryptoTask implements AttachmentCryptoTask {
  _WebAttachmentCryptoTask(
    this._request, {
    required this.workerUrl,
    required this.timeout,
    required this.onDone,
  });

  final AttachmentCryptoRequest _request;
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
          _fail(const AttachmentCryptoException('worker failed'));
        }
      }).toJS;
      worker.onmessageerror = ((web.Event _) {
        _fail(const AttachmentCryptoException('worker message failed'));
      }).toJS;
      worker.onerror = ((web.Event _) {
        _fail(const AttachmentCryptoException('worker failed'));
      }).toJS;
      if (timeout != null) {
        _timer = Timer(
          timeout!,
          () => _fail(const AttachmentCryptoTimeoutException()),
        );
      }

      final key = _copyToJs(_request.key);
      final nonce = _copyToJs(_request.nonce);
      final additionalData = _copyToJs(_request.additionalData);
      final input = _copyToJs(_request.input);
      final message = _AttachmentCryptoWorkerRequest(
        operation: _request.operation.name,
        key: key.bytes,
        nonce: nonce.bytes,
        additionalData: additionalData.bytes,
        input: input.bytes,
      );
      try {
        worker.postMessage(
          message,
          <JSArrayBuffer>[
            key.buffer,
            nonce.buffer,
            additionalData.buffer,
            input.buffer,
          ].toJS,
        );
      } catch (_) {
        _clear(key.bytes.toDart);
        _clear(nonce.bytes.toDart);
        _clear(additionalData.bytes.toDart);
        _clear(input.bytes.toDart);
        rethrow;
      }
      _clearRequest(_request);
    } catch (_) {
      _clearRequest(_request);
      _fail(const AttachmentCryptoException('worker initialization failed'));
    }
  }

  @override
  Future<void> cancel() async {
    _fail(const AttachmentCryptoCancelledException());
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
extension type _AttachmentCryptoWorkerRequest._(JSObject _)
    implements JSObject {
  external factory _AttachmentCryptoWorkerRequest({
    String operation,
    JSUint8Array key,
    JSUint8Array nonce,
    JSUint8Array additionalData,
    JSUint8Array input,
  });
}

({JSArrayBuffer buffer, JSUint8Array bytes}) _copyToJs(Uint8List source) {
  final buffer = JSArrayBuffer(source.length);
  final bytes = JSUint8Array(buffer);
  bytes.toDart.setAll(0, source);
  return (buffer: buffer, bytes: bytes);
}

void _clearRequest(AttachmentCryptoRequest request) {
  _clear(request.key);
  _clear(request.nonce);
  _clear(request.additionalData);
  _clear(request.input);
}

void _clear(Uint8List value) => value.fillRange(0, value.length, 0);
