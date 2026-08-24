import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'scram_key_derivation.dart';

final class PlatformScramKeyDeriver implements ScramKeyDeriver {
  final Set<_NativeDerivationTask> _tasks = <_NativeDerivationTask>{};
  bool _disposed = false;

  @override
  ScramKeyDerivationTask start(
    ScramKeyDerivationRequest request, {
    Duration? timeout,
  }) {
    if (_disposed) {
      throw StateError('SCRAM key deriver is disposed');
    }
    late final _NativeDerivationTask task;
    task = _NativeDerivationTask(
      request,
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
  }
}

final class _NativeDerivationTask implements ScramKeyDerivationTask {
  _NativeDerivationTask(
    this._request, {
    required this.timeout,
    required this.onDone,
  });

  final ScramKeyDerivationRequest _request;
  final Duration? timeout;
  final void Function() onDone;
  final Completer<Uint8List> _completer = Completer<Uint8List>();
  final ReceivePort _resultPort = ReceivePort();
  final ReceivePort _errorPort = ReceivePort();
  final ReceivePort _exitPort = ReceivePort();
  Isolate? _isolate;
  Timer? _timer;
  bool _finished = false;

  @override
  Future<Uint8List> get result => _completer.future;

  Future<void> start() async {
    _resultPort.listen((message) {
      if (message is TransferableTypedData) {
        _succeed(message.materialize().asUint8List());
      } else {
        _fail(const ScramKeyDerivationException('worker returned no result'));
      }
    });
    _errorPort.listen((_) {
      _fail(const ScramKeyDerivationException('worker failed'));
    });
    _exitPort.listen((_) {
      if (!_finished) {
        _fail(const ScramKeyDerivationException('worker exited early'));
      }
    });

    if (timeout != null) {
      _timer = Timer(
        timeout!,
        () => _fail(const ScramKeyDerivationTimeoutException()),
      );
    }

    final password = TransferableTypedData.fromList(<Uint8List>[
      _request.password,
    ]);
    final salt = TransferableTypedData.fromList(<Uint8List>[_request.salt]);
    _clear(_request.password);
    _clear(_request.salt);
    try {
      _isolate = await Isolate.spawn<List<Object?>>(
        _deriveInIsolate,
        <Object?>[
          _resultPort.sendPort,
          _request.kdf,
          password,
          salt,
          _request.iterations,
          _request.memory,
          _request.keyLength,
        ],
        errorsAreFatal: true,
        onError: _errorPort.sendPort,
        onExit: _exitPort.sendPort,
      );
      if (_finished) {
        _isolate?.kill(priority: Isolate.immediate);
      }
    } catch (_) {
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
    _isolate?.kill(priority: Isolate.immediate);
    _resultPort.close();
    _errorPort.close();
    _exitPort.close();
    onDone();
  }
}

void _deriveInIsolate(List<Object?> message) {
  final sendPort = message[0]! as SendPort;
  final kdf = message[1]! as String;
  final password = (message[2]! as TransferableTypedData)
      .materialize()
      .asUint8List();
  final salt = (message[3]! as TransferableTypedData)
      .materialize()
      .asUint8List();
  final iterations = message[4]! as int;
  final memory = message[5]! as int;
  final keyLength = message[6]! as int;
  Uint8List? output;
  try {
    if (kdf == 'argon2id13') {
      output = Uint8List(keyLength);
      Argon2BytesGenerator()
        ..init(
          Argon2Parameters(
            Argon2Parameters.ARGON2_id,
            salt,
            desiredKeyLength: keyLength,
            iterations: iterations,
            memory: memory,
            version: Argon2Parameters.ARGON2_VERSION_13,
          ),
        )
        ..deriveKey(password, 0, output, 0);
    } else if (kdf == 'pbkdf2') {
      final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, iterations, keyLength));
      output = derivator.process(password);
    } else {
      throw ArgumentError.value(kdf, 'kdf', 'unsupported');
    }
    sendPort.send(TransferableTypedData.fromList(<Uint8List>[output]));
  } finally {
    _clear(password);
    _clear(salt);
    if (output != null) _clear(output);
  }
}

void _clear(Uint8List value) => value.fillRange(0, value.length, 0);
