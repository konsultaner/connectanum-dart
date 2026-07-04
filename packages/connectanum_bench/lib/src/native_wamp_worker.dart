import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'wamp_transport_targets.dart';
import 'wamp_workload_runner.dart';

class NativeWampWorker {
  NativeWampWorker({
    required this.realmUri,
    required this.wampTargets,
    this.secureWampTargets = const {},
    required String nativeLibraryPath,
    required String workerScriptPath,
    String? dartExecutable,
    Duration readyTimeout = const Duration(seconds: 60),
    Logger? logger,
  }) : nativeLibraryPath = File(nativeLibraryPath).absolute.path,
       workerScriptPath = _normalizeWorkerEntrypoint(workerScriptPath),
       dartExecutable = dartExecutable ?? Platform.resolvedExecutable,
       _readyTimeout = readyTimeout,
       _logger = logger ?? Logger('NativeWampWorker');

  final String realmUri;
  final Map<WampTransport, WampTransportTarget> wampTargets;
  final Map<WampTransport, WampTransportTarget> secureWampTargets;
  final String nativeLibraryPath;
  final String workerScriptPath;
  final String dartExecutable;
  final Duration _readyTimeout;
  final Logger _logger;

  Process? _process;
  IOSink? _stdin;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final Queue<Completer<_WorkerResponse>> _pending = Queue();
  Completer<void>? _readyCompleter;

  Future<void> start() => _ensureStarted();

  Future<List<WampSample>> run(WampScenario scenario) async {
    await _ensureStarted();
    final process = _process;
    final stdin = _stdin;
    if (process == null || stdin == null) {
      throw StateError('Native WAMP worker is not running.');
    }
    final completer = Completer<_WorkerResponse>();
    _pending.addLast(completer);
    stdin.writeln(jsonEncode(scenario.toJson()));
    await stdin.flush();
    try {
      final response = await completer.future;
      final error = response.error;
      if (error != null) {
        throw StateError(error);
      }
      return response.samples;
    } finally {
      // Native cancel-cycle workloads can leave late interrupts/errors in flight.
      // Recycle the helper between scenarios so those messages do not poison the
      // next benchmark command in the same worker isolate.
      await close();
    }
  }

  Future<void> close() async {
    final process = _process;
    _process = null;
    if (process == null) {
      return;
    }
    try {
      _stdin?.writeln('STOP');
      await _stdin?.flush();
    } catch (_) {
      // The worker may already be gone.
    }
    await _stdin?.close();
    _stdin = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    final pending = _pending.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Native WAMP worker stopped'));
      }
    }
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  Future<void> _ensureStarted() async {
    final current = _process;
    if (current != null) {
      return _readyCompleter?.future ?? Future<void>.value();
    }
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;
    final targetsJson = jsonEncode({
      for (final entry in wampTargets.entries)
        entry.key.name: entry.value.toJson(),
    });
    final secureTargetsJson = jsonEncode({
      for (final entry in secureWampTargets.entries)
        entry.key.name: entry.value.toJson(),
    });
    final process = await Process.start(dartExecutable, [
      if (_usesPackageExecutable) 'run',
      workerScriptPath,
      '--realm',
      realmUri,
      '--targets-json',
      targetsJson,
      '--secure-targets-json',
      secureTargetsJson,
      '--native-lib',
      nativeLibraryPath,
    ], workingDirectory: _workerPackageDirectory.path);
    _process = process;
    _stdin = process.stdin;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final trimmed = line.trim();
          if (!readyCompleter.isCompleted &&
              (trimmed == 'READY' || trimmed.endsWith('...READY'))) {
            if (!readyCompleter.isCompleted) {
              readyCompleter.complete();
            }
            return;
          }
          if (_pending.isEmpty) {
            _logger.warning('Unexpected native worker output: $line');
            return;
          }
          final completer = _pending.removeFirst();
          try {
            final raw = jsonDecode(line) as Map<String, Object?>;
            completer.complete(_WorkerResponse.fromJson(raw));
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        });
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _logger.warning('native worker stderr: $line');
        });
    unawaited(
      process.exitCode.then((code) {
        final isCurrentProcess = identical(_process, process);
        if (isCurrentProcess) {
          _process = null;
          _stdin = null;
          _readyCompleter = null;
        }
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(
            StateError('Native WAMP worker exited with code $code'),
          );
        }
        final pending = _pending.toList(growable: false);
        _pending.clear();
        for (final completer in pending) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('Native WAMP worker exited with code $code'),
            );
          }
        }
      }),
    );
    await readyCompleter.future.timeout(
      _readyTimeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException(
          'Native WAMP worker did not become ready within $_readyTimeout',
        );
      },
    );
  }

  Directory get _workerPackageDirectory => _usesPackageExecutable
      ? Directory.current.absolute
      : File(workerScriptPath).absolute.parent.parent;

  bool get _usesPackageExecutable =>
      workerScriptPath.contains(':') && !workerScriptPath.endsWith('.dart');
}

String _normalizeWorkerEntrypoint(String workerScriptPath) {
  if (workerScriptPath.contains(':') && !workerScriptPath.endsWith('.dart')) {
    return workerScriptPath;
  }
  return File(workerScriptPath).absolute.path;
}

class _WorkerResponse {
  _WorkerResponse({required this.samples, this.error});

  final List<WampSample> samples;
  final String? error;

  factory _WorkerResponse.fromJson(Map<String, Object?> json) {
    final rawSamples = json['samples'];
    return _WorkerResponse(
      samples: rawSamples is List
          ? rawSamples
                .cast<Map>()
                .map(
                  (sample) =>
                      WampSample.fromJson(Map<String, Object?>.from(sample)),
                )
                .toList(growable: false)
          : const <WampSample>[],
      error: json['error'] as String?,
    );
  }
}
