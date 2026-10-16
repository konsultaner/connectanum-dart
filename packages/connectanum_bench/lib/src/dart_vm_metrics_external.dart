import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart_vm_metrics.dart';
import 'dart_vm_metrics_wire.dart';

/// Supervises one VM through an observer outside both benchmark processes.
class ExternalDartVmMetricsCollector implements DartVmMetricsObserver {
  ExternalDartVmMetricsCollector._(this._process, this._targetPid) {
    _stdout = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _receive,
          onError: (Object error) => _fail(error),
          onDone: () {
            if (!_closing || _pending.isNotEmpty) {
              _fail(StateError('Metrics observer closed its output'));
            }
          },
        );
    _stderr = _process.stderr.transform(utf8.decoder).listen((line) {
      _diagnostic = '$_diagnostic$line';
      if (_diagnostic.length > 4096) {
        _diagnostic = _diagnostic.substring(_diagnostic.length - 4096);
      }
    }, onError: (Object error) => _fail(error));
    unawaited(
      _process.stdin.done.then<void>(
        (_) {},
        onError: (Object error) {
          _fail(error);
        },
      ),
    );
    unawaited(
      _process.exitCode.then((code) {
        if (!_closing) {
          _fail(StateError('Metrics observer exited $code: $_diagnostic'));
        }
      }),
    );
  }

  final Process _process;
  final int _targetPid;
  final _ready = Completer<void>();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  late final StreamSubscription<String> _stdout;
  late final StreamSubscription<String> _stderr;
  String _diagnostic = '';
  Object? _failure;
  int _sequence = 0;
  bool _closing = false;
  Future<void>? _closeFuture;

  static Future<ExternalDartVmMetricsCollector> connect({
    required Uri serviceUri,
    required int pid,
    bool allIsolates = false,
    Future<Process> Function(String, List<String>)? startProcess,
  }) async {
    final script = await Isolate.resolvePackageUri(
      Uri.parse(
        'package:connectanum_bench/src/dart_vm_metrics_observer_main.dart',
      ),
    );
    final packages = await Isolate.packageConfig;
    if (script == null || packages == null) {
      throw StateError(
        'External VM metrics require source package configuration',
      );
    }
    final process = await (startProcess ?? Process.start)(
      Platform.resolvedExecutable,
      [
        '--packages=${packages.toFilePath()}',
        script.toFilePath(),
        jsonEncode({
          'service_uri': serviceUri.toString(),
          'pid': pid,
          'all_isolates': allIsolates,
        }),
      ],
    );
    final collector = ExternalDartVmMetricsCollector._(process, pid);
    try {
      await collector._ready.future.timeout(const Duration(seconds: 30));
      return collector;
    } catch (_) {
      await collector.close();
      rethrow;
    }
  }

  void _receive(String line) {
    try {
      if (line == 'READY' && !_ready.isCompleted) {
        _ready.complete();
        return;
      }
      final response = metricsObject(jsonDecode(line));
      final id = response['id'];
      if (id is! int || id <= 0) {
        throw const FormatException('Invalid observer response id');
      }
      final pending = _pending.remove(id);
      if (pending == null) {
        throw const FormatException('Unexpected observer response');
      }
      if (response['error'] case final error?) {
        pending.completeError(StateError('Metrics observer: $error'));
      } else {
        // Complete this request on decode failure before poisoning the channel.
        try {
          pending.complete(metricsObject(response['result']));
        } catch (error, stack) {
          pending.completeError(error, stack);
          rethrow;
        }
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    _failure ??= error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    _process.kill();
  }

  Future<Map<String, Object?>> _command(
    String command, [
    Map<String, Object?> fields = const {},
  ]) async {
    if (_failure case final error?) throw error;
    if (_closing && command != 'close') {
      throw StateError('Metrics observer is closing');
    }
    final id = ++_sequence;
    final response = Completer<Map<String, Object?>>();
    // Pipe errors can arrive during flush, before the ordinary await is attached.
    response.future.ignore();
    _pending[id] = response;
    try {
      _process.stdin.writeln(
        jsonEncode({'id': id, 'command': command, ...fields}),
      );
      await _process.stdin.flush();
      return await response.future.timeout(const Duration(seconds: 30));
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  @override
  Future<DartVmMetricsWindow> beginWindow() async =>
      decodeMetricsWindow(await _command('begin'));

  @override
  Future<DartVmMetricsResult> endWindow(
    DartVmMetricsWindow window, {
    required DartVmMetricsRssSnapshot rssSnapshot,
  }) async {
    final result = decodeMetricsResult(
      await _command('end', {
        'window': encodeMetricsWindow(window),
        'rss': {
          'current': rssSnapshot.currentRssBytes,
          'peak': rssSnapshot.peakRssBytes,
        },
      }),
    );
    final metadata = result.allocationMeasurement;
    if (metadata?['observer_pid'] is! int ||
        metadata?['observed_pid'] is! int ||
        metadata!['observer_pid'] != _process.pid ||
        metadata['observed_pid'] != _targetPid) {
      final error = StateError('Metrics observer process attribution changed');
      _fail(error);
      throw error;
    }
    return result;
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    try {
      if (_failure == null && _ready.isCompleted) {
        await _command('close').timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      _process.kill();
    } finally {
      try {
        await _process.stdin.close();
      } catch (_) {
        _process.kill();
      }
      await _process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          _process.kill(ProcessSignal.sigkill);
          return await _process.exitCode.timeout(const Duration(seconds: 2));
        },
      );
      await _stdout.cancel();
      await _stderr.cancel();
    }
  }
}
