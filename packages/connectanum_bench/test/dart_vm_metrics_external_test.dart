@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectanum_bench/src/dart_vm_metrics.dart';
import 'package:connectanum_bench/src/dart_vm_metrics_external.dart';
import 'package:connectanum_bench/src/dart_vm_metrics_wire.dart';
import 'package:test/test.dart';

const targetPid = 2147483646;
const rss = DartVmMetricsRssSnapshot(currentRssBytes: 1024, peakRssBytes: 2048);
final window = DartVmMetricsWindow(
  cpuUserTicks: null,
  cpuSystemTicks: null,
  isolateIds: ['isolates/1'],
);

void main() {
  Future<ExternalDartVmMetricsCollector> connect(_ObserverProcess child) =>
      ExternalDartVmMetricsCollector.connect(
        serviceUri: Uri.parse('http://127.0.0.1:1/'),
        pid: targetPid,
        startProcess: (_, _) async => child,
      );
  for (final fault in [
    'invalid_utf8',
    'invalid_json',
    'bad_id',
    'unknown_id',
    'bad_result',
    'exit',
    'stdout_error',
    'stderr_error',
    'stdin_error',
    'stdout_done',
  ]) {
    test('observer rejects broken channel $fault', () async {
      final child = _ObserverProcess();
      addTearDown(child.dispose);
      final collector = await connect(child);
      addTearDown(collector.close);
      child.request = (request) {
        switch (fault) {
          case 'invalid_utf8':
            child.output.add([255]);
          case 'invalid_json':
            child.line('{broken');
          case 'bad_id':
            child.reply({'id': 'bad', 'result': {}});
          case 'unknown_id':
            child.reply({'id': 999, 'result': {}});
          case 'bad_result':
            child.reply({'id': request['id'], 'result': 'broken'});
          case 'exit':
            child.finish(7);
          case 'stdout_error':
            child.output.addError(StateError('read failed'));
          case 'stderr_error':
            child.errors.addError(StateError('diagnostic read failed'));
          case 'stdin_error':
            throw StateError('write pipe failed');
          case 'stdout_done':
            unawaited(child.output.close());
        }
      };
      final expected =
          {
            'invalid_utf8',
            'invalid_json',
            'bad_id',
            'unknown_id',
            'bad_result',
          }.contains(fault)
          ? throwsFormatException
          : throwsStateError;
      await expectLater(collector.beginWindow(), expected);
      await expectLater(collector.beginWindow(), expected);
      expect(child.signals, isNotEmpty);
    });
  }
  test('observer startup failure owns and closes its process', () async {
    final child = _ObserverProcess(ready: false);
    addTearDown(child.dispose);
    scheduleMicrotask(() {
      child.errors.add(utf8.encode('x' * 5000));
      child.finish(9);
    });
    await expectLater(connect(child), throwsStateError);
  });
  test('observer rejects malformed startup readiness', () async {
    final child = _ObserverProcess(ready: false);
    addTearDown(child.dispose);
    scheduleMicrotask(() => child.line('not READY'));
    await expectLater(connect(child), throwsFormatException);
  });
  test(
    'structured method errors invalidate the measurement channel',
    () async {
      final child = _ObserverProcess();
      addTearDown(child.dispose);
      final collector = await connect(child);
      addTearDown(collector.close);
      child.request = (request) =>
          child.reply({'id': request['id'], 'error': 'unsupported request'});
      await expectLater(collector.beginWindow(), throwsStateError);
      await expectLater(collector.beginWindow(), throwsStateError);
      expect(child.signals, isNotEmpty);
      child.request = null;
    },
  );
  for (final attribution in ['observer', 'target', 'type']) {
    test('observer result validates $attribution PID attribution', () async {
      final child = _ObserverProcess();
      addTearDown(child.dispose);
      final collector = await connect(child);
      addTearDown(collector.close);
      child.request = (request) => child.reply({
        'id': request['id'],
        'result': encodeMetricsResult(
          DartVmMetricsResult(
            allocatedBytes: null,
            gcCount: null,
            gcPauseMicros: null,
            cpuUserMicros: null,
            cpuSystemMicros: null,
            currentRssBytes: 1024,
            peakRssBytes: 2048,
            allocationMeasurement: {
              'observer_pid': attribution == 'type'
                  ? 'wrong'
                  : attribution == 'observer'
                  ? child.pid + 1
                  : child.pid,
              'observed_pid': attribution == 'target'
                  ? targetPid + 1
                  : targetPid,
            },
          ),
        ),
      });
      await expectLater(
        collector.endWindow(window, rssSnapshot: rss),
        throwsStateError,
      );
      expect(child.signals, isNotEmpty);
    });
  }
  test('observer closes once and rejects new requests during close', () async {
    final child = _ObserverProcess();
    addTearDown(child.dispose);
    final collector = await connect(child);
    final seen = Completer<void>();
    final release = Completer<void>();
    child.request = (request) async {
      seen.complete();
      await release.future;
      child.reply({'id': request['id'], 'result': {}});
    };
    final close = collector.close();
    expect(identical(close, collector.close()), isTrue);
    await seen.future;
    await expectLater(collector.beginWindow(), throwsStateError);
    release.complete();
    await close;
  });
  test('observer reaps a child requiring SIGKILL', () async {
    final child = _ObserverProcess(hang: true);
    addTearDown(child.dispose);
    final collector = await connect(child);
    await collector.close();
    expect(child.signals, contains(ProcessSignal.sigkill));
  });
  test(
    'observer handles stdin close failure and still reaps its child',
    () async {
      final child = _ObserverProcess(failClose: true);
      addTearDown(child.dispose);
      final collector = await connect(child);
      await collector.close();
      expect(child.signals, isNotEmpty);
    },
  );
}

// Owns only in-memory pipes; kill never addresses an operating-system PID.
class _ObserverProcess implements Process {
  _ObserverProcess({
    bool ready = true,
    this.hang = false,
    this.failClose = false,
  }) {
    input = IOSink(_ObserverInput(this));
    if (ready) scheduleMicrotask(() => line('READY'));
  }
  final bool hang, failClose;
  final output = StreamController<List<int>>(),
      errors = StreamController<List<int>>();
  final exited = Completer<int>();
  final signals = <ProcessSignal>[];
  late final IOSink input;
  FutureOr<void> Function(Map<String, Object?>)? request;
  @override
  int get pid => 424242;
  @override
  IOSink get stdin => input;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => exited.future;
  void line(String text) => output.add(utf8.encode('$text\n'));
  void reply(Map<String, Object?> response) => line(jsonEncode(response));
  void finish(int code) {
    if (!exited.isCompleted) exited.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (!hang || signal == ProcessSignal.sigkill) finish(0);
    return true;
  }

  Future<void> dispose() async {
    finish(0);
    try {
      await input.close();
    } catch (_) {}
    await output.close();
    await errors.close();
  }
}

class _ObserverInput implements StreamConsumer<List<int>> {
  _ObserverInput(this.owner);
  final _ObserverProcess owner;
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final line
        in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final message = Map<String, Object?>.from(jsonDecode(line) as Map);
      final handler = owner.request;
      if (handler != null) {
        await handler(message);
      } else {
        owner.reply({
          'id': message['id'],
          'result': message['command'] == 'begin'
              ? encodeMetricsWindow(window)
              : {},
        });
      }
    }
  }

  @override
  Future<void> close() async {
    if (owner.failClose) throw StateError('close pipe failed');
    if (!owner.hang) owner.finish(0);
  }
}
