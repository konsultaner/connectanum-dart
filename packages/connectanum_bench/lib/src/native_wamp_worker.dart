import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'wamp_transport_targets.dart';
import 'wamp_workload_runner.dart';

class NativeWampWorkerFileSegmentMetrics {
  const NativeWampWorkerFileSegmentMetrics({
    this.rawSocketZeroCopyCalls = 0,
    this.rawSocketZeroCopyBytes = 0,
    this.bufferedFileSegmentCalls = 0,
    this.bufferedFileSegmentBytes = 0,
  });

  final int rawSocketZeroCopyCalls;
  final int rawSocketZeroCopyBytes;
  final int bufferedFileSegmentCalls;
  final int bufferedFileSegmentBytes;

  factory NativeWampWorkerFileSegmentMetrics.fromJson(
    Map<String, Object?> json,
  ) => NativeWampWorkerFileSegmentMetrics(
    rawSocketZeroCopyCalls:
        (json['rawsocket_zero_copy_calls'] as num?)?.toInt() ?? 0,
    rawSocketZeroCopyBytes:
        (json['rawsocket_zero_copy_bytes'] as num?)?.toInt() ?? 0,
    bufferedFileSegmentCalls:
        (json['buffered_file_segment_calls'] as num?)?.toInt() ?? 0,
    bufferedFileSegmentBytes:
        (json['buffered_file_segment_bytes'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'rawsocket_zero_copy_calls': rawSocketZeroCopyCalls,
    'rawsocket_zero_copy_bytes': rawSocketZeroCopyBytes,
    'buffered_file_segment_calls': bufferedFileSegmentCalls,
    'buffered_file_segment_bytes': bufferedFileSegmentBytes,
  };
}

class NativeWampWorkerProcessMetrics {
  const NativeWampWorkerProcessMetrics({
    required this.pid,
    required this.rssBeforeBytes,
    required this.currentRssBytes,
    required this.maxRssBytes,
  });

  final int pid;
  final int rssBeforeBytes;
  final int currentRssBytes;
  final int maxRssBytes;

  factory NativeWampWorkerProcessMetrics.fromJson(
    Map<String, Object?> json,
  ) => NativeWampWorkerProcessMetrics(
    pid: (json['pid'] as num).toInt(),
    rssBeforeBytes: (json['rss_before_bytes'] as num).toInt(),
    currentRssBytes: (json['current_rss_bytes'] as num).toInt(),
    maxRssBytes: (json['max_rss_bytes'] as num).toInt(),
  );

  Map<String, Object?> toJson() => {
    'pid': pid,
    'rss_before_bytes': rssBeforeBytes,
    'current_rss_bytes': currentRssBytes,
    'max_rss_bytes': maxRssBytes,
  };
}

class NativeWampWorkerResult {
  const NativeWampWorkerResult({
    required this.samples,
    required this.fileSegmentMetrics,
    this.processMetrics,
  });

  final List<WampSample> samples;
  final NativeWampWorkerFileSegmentMetrics fileSegmentMetrics;
  final NativeWampWorkerProcessMetrics? processMetrics;
}

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

  _WorkerGeneration? _generation;
  Future<void>? _closing;
  Future<void> _runTail = Future<void>.value();
  int _closeEpoch = 0;

  Future<void> start() async {
    await _ensureStarted();
  }

  Future<List<WampSample>> run(WampScenario scenario) async =>
      (await runWithMetrics(scenario)).samples;

  Future<NativeWampWorkerResult> runWithMetrics(WampScenario scenario) {
    // Each scenario owns a fresh native runtime. Queue callers rather than
    // letting one scenario's cleanup cancel another scenario's response.
    final epoch = _closeEpoch;
    final result = _runTail.then((_) {
      if (epoch != _closeEpoch) {
        throw StateError('Native WAMP worker stopped');
      }
      return _runScenario(scenario);
    });
    _runTail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<NativeWampWorkerResult> _runScenario(WampScenario scenario) async {
    final generation = await _ensureStarted();
    final completer = Completer<_WorkerResponse>();
    generation.response = completer;
    // A child can fail while flush is suspended, before the response is awaited.
    completer.future.ignore();
    try {
      final stdin = generation.process!.stdin;
      stdin.writeln(jsonEncode(scenario.toJson()));
      await stdin.flush();
      final response = await completer.future;
      final error = response.error;
      if (error != null) {
        throw StateError(error);
      }
      return NativeWampWorkerResult(
        samples: response.samples,
        fileSegmentMetrics: response.fileSegmentMetrics,
        processMetrics: response.processMetrics,
      );
    } finally {
      // Native cancel-cycle workloads can leave late interrupts/errors in flight.
      // Recycle the helper between scenarios so those messages do not poison the
      // next benchmark command in the same worker isolate.
      await _stop(generation);
    }
  }

  Future<void> close() {
    _closeEpoch++;
    final generation = _generation;
    return generation == null
        ? _closing ?? Future<void>.value()
        : _stop(generation);
  }

  Future<_WorkerGeneration> _ensureStarted() async {
    final epoch = _closeEpoch;
    while (_closing != null) {
      await _closing;
    }
    if (epoch != _closeEpoch) {
      throw StateError('Native WAMP worker stopped');
    }
    var generation = _generation;
    if (generation == null) {
      generation = _WorkerGeneration();
      _generation = generation;
      generation.started = _startGeneration(generation);
    }
    await generation.started;
    if (generation.stopping) {
      throw StateError('Native WAMP worker stopped');
    }
    return generation;
  }

  Future<void> _startGeneration(_WorkerGeneration generation) async {
    final ready = generation.ready.future.timeout(
      _readyTimeout,
      onTimeout: () {
        throw TimeoutException(
          'Native WAMP worker did not become ready within $_readyTimeout',
        );
      },
    );
    ready.ignore();
    final targetsJson = jsonEncode({
      for (final entry in wampTargets.entries)
        entry.key.name: entry.value.toJson(),
    });
    final secureTargetsJson = jsonEncode({
      for (final entry in secureWampTargets.entries)
        entry.key.name: entry.value.toJson(),
    });
    final usesDirectExecutable = _usesDirectExecutable;
    generation.launched = Process.start(
      usesDirectExecutable ? workerScriptPath : dartExecutable,
      [
        if (_usesPackageExecutable) 'run',
        if (!usesDirectExecutable) workerScriptPath,
        '--realm',
        realmUri,
        '--targets-json',
        targetsJson,
        '--secure-targets-json',
        secureTargetsJson,
        '--native-lib',
        nativeLibraryPath,
      ],
      workingDirectory: _workerPackageDirectory.path,
    );
    try {
      final process = await generation.launched;
      generation.process = process;
      if (generation.stopping) {
        throw StateError('Native WAMP worker stopped');
      }
      generation.stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (generation.stopping) return;
              final trimmed = line.trim();
              if (!generation.ready.isCompleted &&
                  (trimmed == 'READY' || trimmed.endsWith('...READY'))) {
                generation.isReady = true;
                generation.ready.complete();
                return;
              }
              final completer = generation.response;
              if (completer == null) {
                _logger.warning('Unexpected native worker output: $line');
                return;
              }
              generation.response = null;
              try {
                final raw = jsonDecode(line) as Map<String, Object?>;
                completer.complete(_WorkerResponse.fromJson(raw));
              } catch (error, stackTrace) {
                completer.completeError(error, stackTrace);
              }
            },
            onError: (Object error, StackTrace stack) {
              _fail(generation, error, stack);
            },
            onDone: () {
              // Before READY, preserve the exit code from the exit callback.
              // A child that closes output without exiting hits the ready timer.
              if (generation.isReady) {
                _fail(
                  generation,
                  StateError('Native WAMP worker closed output'),
                );
              }
            },
          );
      generation.stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (!generation.stopping) {
                _logger.warning('native worker stderr: $line');
              }
            },
            onError: (Object error, StackTrace stack) {
              _fail(generation, error, stack);
            },
          );
      unawaited(
        process.exitCode.then((code) {
          _fail(
            generation,
            StateError('Native WAMP worker exited with code $code'),
          );
        }),
      );
      await ready;
    } catch (_) {
      await _stop(generation);
      rethrow;
    }
  }

  void _fail(_WorkerGeneration generation, Object error, [StackTrace? stack]) {
    if (generation.stopping) return;
    if (!generation.ready.isCompleted) {
      generation.ready.completeError(error, stack);
    }
    generation.response?.completeError(error, stack);
    generation.response = null;
    unawaited(_stop(generation));
  }

  Future<void> _stop(_WorkerGeneration generation) {
    final closed = generation.closed;
    if (closed != null) return closed;
    final completion = Completer<void>();
    generation.closed = completion.future;
    generation.stopping = true;
    final interrupt = !generation.isReady || generation.response != null;
    if (identical(_generation, generation)) {
      _generation = null;
      _closing = completion.future;
    }
    final error = StateError('Native WAMP worker stopped');
    if (!generation.ready.isCompleted) generation.ready.completeError(error);
    generation.response?.completeError(error);
    generation.response = null;
    unawaited(() async {
      try {
        Process process;
        try {
          process = await generation.launched;
        } catch (_) {
          return;
        }
        if (interrupt) process.kill(ProcessSignal.sigkill);
        try {
          if (!interrupt) process.stdin.writeln('STOP');
          await process.stdin.close().timeout(const Duration(seconds: 1));
        } catch (_) {
          // A failed or unresponsive pipe must not prevent child reaping.
          process.kill(ProcessSignal.sigkill);
        }
        await generation.stdoutSubscription?.cancel();
        await generation.stderrSubscription?.cancel();
        await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return process.exitCode;
          },
        );
      } finally {
        if (identical(_closing, completion.future)) _closing = null;
        completion.complete();
      }
    }());
    return completion.future;
  }

  Directory get _workerPackageDirectory =>
      _usesPackageExecutable || _usesDirectExecutable
      ? Directory.current.absolute
      : File(workerScriptPath).absolute.parent.parent;

  bool get _usesPackageExecutable => _isPackageExecutable(workerScriptPath);

  bool get _usesDirectExecutable =>
      !_usesPackageExecutable && !workerScriptPath.endsWith('.dart');
}

class _WorkerGeneration {
  final ready = Completer<void>();
  late final Future<Process> launched;
  late final Future<void> started;
  Process? process;
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
  Completer<_WorkerResponse>? response;
  Future<void>? closed;
  bool isReady = false;
  bool stopping = false;
}

String _normalizeWorkerEntrypoint(String workerScriptPath) {
  if (_isPackageExecutable(workerScriptPath)) {
    return workerScriptPath;
  }
  return File(workerScriptPath).absolute.path;
}

bool _isPackageExecutable(String value) => RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*:[A-Za-z0-9_.-]+$',
).hasMatch(value);

class _WorkerResponse {
  _WorkerResponse({
    required this.samples,
    required this.fileSegmentMetrics,
    this.processMetrics,
    this.error,
  });

  final List<WampSample> samples;
  final NativeWampWorkerFileSegmentMetrics fileSegmentMetrics;
  final NativeWampWorkerProcessMetrics? processMetrics;
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
      fileSegmentMetrics: NativeWampWorkerFileSegmentMetrics.fromJson(
        Map<String, Object?>.from(
          json['file_segment_metrics'] as Map? ?? const <String, Object?>{},
        ),
      ),
      processMetrics: switch (json['process_metrics']) {
        final Map raw => NativeWampWorkerProcessMetrics.fromJson(
          Map<String, Object?>.from(raw),
        ),
        _ => null,
      },
      error: json['error'] as String?,
    );
  }
}
