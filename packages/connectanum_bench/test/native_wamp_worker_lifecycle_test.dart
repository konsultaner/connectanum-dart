@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_bench/src/native_wamp_worker.dart';
import 'package:connectanum_bench/src/wamp_transport_targets.dart';
import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  for (var turns = 0; turns < 6; turns++) {
    test(
      'close settles a scenario during ready handoff ($turns microtasks)',
      () async {
        final fixture = await _WorkerFixture.create();
        await fixture.worker.start();
        var settled = false;
        Object? failure;
        fixture.worker
            .runWithMetrics(_scenario())
            .then(
              (_) {
                settled = true;
              },
              onError: (Object error) {
                failure = error;
                settled = true;
              },
            );
        for (var turn = 0; turn < turns; turn++) {
          await Future<void>.value();
        }
        await fixture.worker.close();
        await Future<void>.delayed(Duration.zero);
        expect(
          settled,
          isTrue,
          reason: 'Closed worker must settle its scenario.',
        );
        expect(failure, isA<StateError>());
        await fixture.expectNoLiveChildren();
      },
      skip: Platform.isWindows,
    );
  }
  test(
    'fixture deadline is a timeout rather than an assertion failure',
    () async {
      final fixture = await _WorkerFixture.create();
      await expectLater(
        fixture.waitFor(() => false, timeout: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
    },
    skip: Platform.isWindows ? 'POSIX executable fixture' : false,
  );

  group(
    'worker lifecycle',
    () {
      test(
        'concurrent starts share one process and one readiness result',
        () async {
          final fixture = await _WorkerFixture.create();
          await Future.wait(List.generate(4, (_) => fixture.worker.start()));
          expect(fixture.pids, hasLength(1));
          await fixture.worker.start();
          expect(fixture.pids, hasLength(1));
        },
      );

      test('close during process launch cancels startup', () async {
        final fixture = await _WorkerFixture.create();
        final starting = expectLater(fixture.worker.start(), throwsStateError);
        await fixture.worker.close();
        await starting;
        await fixture.expectNoLiveChildren();
        await fixture.worker.start();
        expect(
          (await fixture.worker.runWithMetrics(_scenario())).samples,
          hasLength(1),
        );
      });

      test('close before READY cancels all waiters promptly', () async {
        final fixture = await _WorkerFixture.create();
        fixture.enable('hold-ready');
        final first = expectLater(fixture.worker.start(), throwsStateError);
        final second = expectLater(fixture.worker.start(), throwsStateError);
        await fixture.waitFor(() => fixture.pids.isNotEmpty);
        await expectLater(
          fixture.worker.close().timeout(const Duration(seconds: 2)),
          completes,
        );
        await Future.wait([first, second]);
        await fixture.expectNoLiveChildren();
      });

      test('timeout is shared and a later start can recover', () async {
        final deadline = _ControlledDeadline(const Duration(hours: 1));
        final fixture = await _WorkerFixture.create(
          readyTimeout: deadline.duration,
        );
        fixture.enable('hold-ready');
        final first = expectLater(
          deadline.run(fixture.worker.start),
          throwsA(isA<TimeoutException>()),
        );
        final second = expectLater(
          deadline.run(fixture.worker.start),
          throwsA(isA<TimeoutException>()),
        );
        await fixture.waitFor(() => fixture.pids.isNotEmpty);
        expect(deadline.timers, hasLength(1));
        deadline.timers.single.fire();
        await Future.wait([first, second]);
        await fixture.expectNoLiveChildren();
        fixture.disable('hold-ready');
        await fixture.worker.start();
        expect(fixture.pids, hasLength(2));
      });

      test('process launch failure does not poison a later retry', () async {
        final fixture = await _WorkerFixture.create();
        final renamed = await fixture.executable.rename(
          '${fixture.executable.path}.saved',
        );
        await Future.wait(
          List.generate(
            2,
            (_) => expectLater(
              fixture.worker.start(),
              throwsA(isA<ProcessException>()),
            ),
          ),
        );
        await renamed.rename(fixture.executable.path);
        await fixture.worker.start();
        expect(fixture.pids, hasLength(1));
      });

      test('exit before READY fails all waiters and allows retry', () async {
        final fixture = await _WorkerFixture.create();
        fixture.enable('exit-before-ready');
        final error = throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('7')),
        );
        await Future.wait(
          List.generate(2, (_) => expectLater(fixture.worker.start(), error)),
        );
        fixture.disable('exit-before-ready');
        await fixture.worker.start();
        expect(fixture.pids, hasLength(2));
      });

      test(
        'concurrent close shares cleanup and restart waits for old exit',
        () async {
          final fixture = await _WorkerFixture.create();
          fixture.enable('hold-stop');
          await fixture.worker.start();
          var closed = false;
          var alsoClosed = false;
          final closing = fixture.worker.close().then((_) => closed = true);
          final alsoClosing = fixture.worker.close().then(
            (_) => alsoClosed = true,
          );
          var restarted = false;
          final restarting = fixture.worker.start().then(
            (_) => restarted = true,
          );
          await fixture.waitFor(() => fixture.hasMarker('stop'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(
            restarted,
            isFalse,
            reason: 'Restart must not overlap the closing generation.',
          );
          expect(fixture.pids, hasLength(1));
          expect(closed, isFalse, reason: 'The first close must await exit.');
          expect(alsoClosed, isFalse, reason: 'Each close must await exit.');
          fixture.disable('hold-stop');
          await Future.wait([closing, alsoClosing, restarting]);
          expect(fixture.pids, hasLength(2));
          final result = await fixture.worker.runWithMetrics(_scenario());
          expect(result.samples.single.requestBytes, 17);
        },
      );

      test(
        'close after READY but before start completes still cancels startup',
        () async {
          final logger = Logger('worker-close-at-ready');
          final closed = Completer<void>();
          final records = <String>[];
          late _WorkerFixture fixture;
          final subscription = logger.onRecord.listen((record) {
            records.add(record.message);
            if (record.message.endsWith('close-after-ready')) {
              fixture.worker.close().then(
                closed.complete,
                onError: closed.completeError,
              );
            }
          });
          addTearDown(subscription.cancel);
          fixture = await _WorkerFixture.create(logger: logger);
          fixture.enable('close-after-ready');
          await expectLater(fixture.worker.start(), throwsStateError);
          await closed.future;
          expect(
            records.any((message) => message.contains('late-after-close')),
            isFalse,
          );
          await fixture.expectNoLiveChildren();
        },
      );

      test('closing an active command also cancels queued commands', () async {
        final fixture = await _WorkerFixture.create();
        fixture.enable('hold-response');
        final first = expectLater(
          fixture.worker.runWithMetrics(_scenario()),
          throwsStateError,
        );
        final second = expectLater(
          fixture.worker.runWithMetrics(_scenario('second')),
          throwsStateError,
        );
        await fixture.waitFor(() => fixture.hasMarker('request'));
        await fixture.worker.close();
        await Future.wait([first, second]);
        await fixture.expectNoLiveChildren();
        expect(fixture.pids, hasLength(1));
        fixture.disable('hold-response');
        expect(await fixture.worker.run(_scenario()), hasLength(1));
      });

      test(
        'close cancels a start waiting for previous cleanup',
        () async {
          final fixture = await _WorkerFixture.create();
          fixture.enable('hold-stop');
          await fixture.worker.start();
          final closing = fixture.worker.close();
          final restarting = expectLater(
            fixture.worker.start(),
            throwsStateError,
          );
          await fixture.waitFor(() => fixture.hasMarker('stop'));
          final finalClose = fixture.worker.close();
          fixture.disable('hold-stop');
          await Future.wait([closing, restarting, finalClose]);
          expect(fixture.pids, hasLength(1));
          await fixture.expectNoLiveChildren();
        },
      );

      test(
        'unresponsive STOP is killed and reaped before close completes',
        () async {
          final fixture = await _WorkerFixture.create();
          fixture.enable('hold-stop');
          await fixture.worker.start();
          final deadline = _ControlledDeadline(const Duration(seconds: 5));
          final closing = deadline.run(fixture.worker.close);
          await fixture.waitFor(
            () => fixture.hasMarker('stop') && deadline.timers.isNotEmpty,
          );
          expect(deadline.timers, hasLength(1));
          deadline.timers.single.fire();
          await closing.timeout(const Duration(seconds: 2));
          expect(fixture.hasMarker('stop'), isTrue);
          await fixture.expectNoLiveChildren();
        },
      );

      test('closed stdin fails a command and still reaps the worker', () async {
        final fixture = await _WorkerFixture.create();
        fixture.enable('close-input');
        await fixture.worker.start();
        await fixture.waitFor(() => fixture.hasMarker('input-closed'));
        await expectLater(
          fixture.worker.run(_scenario()),
          throwsA(isA<IOException>()),
        );
        await fixture.expectNoLiveChildren();
      });

      test(
        'startup diagnostics remain visible without consuming a response',
        () async {
          final records = <LogRecord>[];
          final logger = Logger('worker-fixture');
          final subscription = logger.onRecord.listen(
            records.add,
          );
          addTearDown(subscription.cancel);
          final fixture = await _WorkerFixture.create(logger: logger);
          fixture.enable('diagnostics');
          expect(await fixture.worker.run(_scenario()), hasLength(1));
          expect(
            records.map((record) => record.message),
            contains('Unexpected native worker output: startup diagnostic'),
          );
          expect(
            records.map((record) => record.message),
            contains('native worker stderr: stderr diagnostic'),
          );
          expect(
            records.map((record) => record.loggerName),
            everyElement('worker-fixture'),
          );
        },
      );

      for (final (dartEntrypoint, packageEntrypoint) in [
        (false, false),
        (true, false),
        (true, true),
      ]) {
        test(
          'Launch preserves endpoints and cwd, dart=$dartEntrypoint package=$packageEntrypoint',
          () async {
            final fixture = await _WorkerFixture.create(
              dartEntrypoint: dartEntrypoint,
              packageEntrypoint: packageEntrypoint,
            );
            await fixture.worker.start();
            final args = File(
              '${fixture.directory.path}/args-${fixture.pids.single}',
            ).readAsLinesSync();
            expect(
              args.take(
                !dartEntrypoint
                    ? 0
                    : packageEntrypoint
                    ? 2
                    : 1,
              ),
              !dartEntrypoint
                  ? <String>[]
                  : packageEntrypoint
                  ? ['run', 'connectanum_bench:wamp_client_worker']
                  : [fixture.worker.workerScriptPath],
            );
            expect(
              fixture.worker.dartExecutable,
              dartEntrypoint
                  ? fixture.executable.path
                  : Platform.resolvedExecutable,
            );
            expect(
              File(
                '${fixture.directory.path}/cwd-${fixture.pids.single}',
              ).readAsStringSync().trim(),
              (dartEntrypoint && !packageEntrypoint
                      ? fixture.directory
                      : Directory.current)
                  .resolveSymbolicLinksSync(),
            );
            expect(args[args.indexOf('--realm') + 1], 'bench.control');
            expect(
              args[args.indexOf('--native-lib') + 1],
              fixture.worker.nativeLibraryPath,
            );
            expect(jsonDecode(args[args.indexOf('--targets-json') + 1]), {
              'rawsocket': {
                'transport': 'rawsocket',
                'host': '127.0.0.1',
                'port': 1234,
                'secure': false,
              },
            });
            expect(
              jsonDecode(args[args.indexOf('--secure-targets-json') + 1]),
              {
                'websocket': {
                  'transport': 'websocket',
                  'host': 'example.invalid',
                  'port': 4321,
                  'secure': true,
                  'web_socket_path': '/custom',
                },
              },
            );
          },
        );
      }

      test(
        'concurrent scenarios use separate generations without mixing results',
        () async {
          final fixture = await _WorkerFixture.create();
          final results = await Future.wait([
            fixture.worker.runWithMetrics(_scenario()),
            fixture.worker.runWithMetrics(_scenario('second')),
          ]);
          expect(results.map((result) => result.samples.single.requestBytes), [
            17,
            29,
          ]);
          expect(fixture.pids, hasLength(2));
          await fixture.expectNoLiveChildren();
        },
      );

      test(
        'response preserves samples and all metrics across recycling',
        () async {
          final fixture = await _WorkerFixture.create();
          final result = await fixture.worker.runWithMetrics(_scenario());
          expect(result.samples.single.toJson(), {
            'worker': 3,
            'iteration': 5,
            'latency_ms': 1.25,
            'request_bytes': 17,
            'response_bytes': 19,
            'started_at_us': 1000,
            'completed_at_us': 2250,
          });
          expect(result.fileSegmentMetrics.toJson(), {
            'rawsocket_zero_copy_calls': 2,
            'rawsocket_zero_copy_bytes': 4096,
            'buffered_file_segment_calls': 3,
            'buffered_file_segment_bytes': 8192,
          });
          expect(result.processMetrics?.toJson(), {
            'pid': 42,
            'rss_before_bytes': 11,
            'current_rss_bytes': 13,
            'max_rss_bytes': 23,
          });
          await fixture.expectNoLiveChildren();
          expect(await fixture.worker.run(_scenario()), hasLength(1));
          expect(fixture.pids, hasLength(2));
        },
      );

      for (final entry in <String, Matcher>{
        'not-json': isA<FormatException>(),
        '[]': isA<TypeError>(),
        '{"samples":[false]}': isA<TypeError>(),
        '{"file_segment_metrics":false}': isA<TypeError>(),
        '{"process_metrics":{}}': isA<TypeError>(),
        '{"error":"fixture scenario failed"}': isA<StateError>().having(
          (e) => e.message,
          'message',
          'fixture scenario failed',
        ),
      }.entries) {
        test(
          'bad response fails and next generation recovers: ${entry.key}',
          () async {
            final fixture = await _WorkerFixture.create();
            fixture.response.writeAsStringSync(entry.key);
            await expectLater(
              fixture.worker.runWithMetrics(_scenario()),
              throwsA(entry.value),
            );
            await fixture.expectNoLiveChildren();
            fixture.response.writeAsStringSync(_response);
            expect(await fixture.worker.run(_scenario()), hasLength(1));
          },
        );
      }

      for (final mode in [
        'exit-on-request',
        'stdout-eof',
        'stdout-invalid-utf8',
        'stderr-invalid-utf8',
      ]) {
        test(
          '$mode fails the command without an unhandled stream error',
          () async {
            final fixture = await _WorkerFixture.create();
            fixture.enable(mode);
            await expectLater(
              fixture.worker
                  .runWithMetrics(_scenario())
                  .timeout(const Duration(seconds: 2)),
              throwsA(
                mode.endsWith('utf8')
                    ? isA<FormatException>()
                    : isA<StateError>(),
              ),
            );
            await fixture.expectNoLiveChildren();
            fixture.disable(mode);
            expect(await fixture.worker.run(_scenario()), hasLength(1));
          },
        );
      }

      test(
        'legacy READY prefix and absent optional metrics remain compatible',
        () async {
          final fixture = await _WorkerFixture.create();
          fixture.enable('legacy-ready');
          fixture.response.writeAsStringSync('{}');
          final result = await fixture.worker.runWithMetrics(_scenario());
          expect(result.samples, isEmpty);
          expect(result.processMetrics, isNull);
          expect(result.fileSegmentMetrics.toJson().values, everyElement(0));
        },
      );
    },
    skip: Platform.isWindows
        ? 'The controlled worker fixture uses a POSIX shell.'
        : false,
  );
}

WampScenario _scenario([String suffix = 'first']) => WampScenario.fromJson({
  'transport': 'rawsocket',
  'client_impl': 'native',
  'mode': 'rpc',
  'uri': 'bench.rpc.$suffix',
});

const _response =
    '{"samples":[{"worker":3,"iteration":5,"latency_ms":1.25,"request_bytes":17,"response_bytes":19,"started_at_us":1000,"completed_at_us":2250}],"file_segment_metrics":{"rawsocket_zero_copy_calls":2,"rawsocket_zero_copy_bytes":4096,"buffered_file_segment_calls":3,"buffered_file_segment_bytes":8192},"process_metrics":{"pid":42,"rss_before_bytes":11,"current_rss_bytes":13,"max_rss_bytes":23}}';

class _ControlledDeadline {
  _ControlledDeadline(this.duration);
  final Duration duration;
  final timers = <_ControlledTimer>[];

  T run<T>(T Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, delay, callback) {
        if (delay != duration) return parent.createTimer(zone, delay, callback);
        final timer = _ControlledTimer(zone.bindCallbackGuarded(callback));
        timers.add(timer);
        return timer;
      },
    ),
  );
}

class _ControlledTimer implements Timer {
  _ControlledTimer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    expect(isActive, isTrue);
    isActive = false;
    tick++;
    callback();
  }
}

class _WorkerFixture {
  _WorkerFixture(this.directory, this.executable, this.worker);

  final Directory directory;
  final File executable;
  final NativeWampWorker worker;
  File get response => File('${directory.path}/response');
  List<int> get pids {
    final file = File('${directory.path}/pids');
    return file.existsSync()
        ? file.readAsLinesSync().map(int.parse).toList()
        : [];
  }

  static Future<_WorkerFixture> create({
    Duration readyTimeout = const Duration(seconds: 2),
    Logger? logger,
    bool dartEntrypoint = false,
    bool packageEntrypoint = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'connectanum-worker-lifecycle-',
    );
    final executable = File('${directory.path}/worker');
    final fixture = _WorkerFixture(
      directory,
      executable,
      NativeWampWorker(
        realmUri: 'bench.control',
        wampTargets: const {
          WampTransport.rawsocket: WampTransportTarget(
            transport: WampTransport.rawsocket,
            host: '127.0.0.1',
            port: 1234,
            secure: false,
          ),
        },
        secureWampTargets: const {
          WampTransport.websocket: WampTransportTarget(
            transport: WampTransport.websocket,
            host: 'example.invalid',
            port: 4321,
            secure: true,
            webSocketPath: '/custom',
          ),
        },
        nativeLibraryPath: '${directory.path}/unused',
        workerScriptPath: !dartEntrypoint
            ? executable.path
            : packageEntrypoint
            ? 'connectanum_bench:wamp_client_worker'
            : '${directory.path}/tool/worker.dart',
        dartExecutable: dartEntrypoint ? executable.path : null,
        readyTimeout: readyTimeout,
        logger: logger,
      ),
    );
    addTearDown(() async {
      for (final flag in ['hold-ready', 'hold-response', 'hold-stop']) {
        fixture.disable(flag);
      }
      try {
        await fixture.worker.close();
      } finally {
        for (final pid in fixture.pids) {
          Process.killPid(pid, ProcessSignal.sigkill);
        }
        await directory.delete(recursive: true);
      }
    });
    await executable.writeAsString(_script);
    final chmod = await Process.run('chmod', ['+x', executable.path]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
    fixture.response.writeAsStringSync(_response);
    return fixture;
  }

  void enable(String name) =>
      File('${directory.path}/$name').writeAsStringSync('');
  void disable(String name) {
    final file = File('${directory.path}/$name');
    if (file.existsSync()) file.deleteSync();
  }

  bool hasMarker(String name) =>
      directory.listSync().any((file) => file.path.contains('/$name-'));
  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final clock = Stopwatch()..start();
    while (!condition() && clock.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (!condition()) {
      throw TimeoutException(
        'Controlled child did not reach its barrier.',
        timeout,
      );
    }
  }

  Future<void> expectNoLiveChildren() async {
    for (final pid in pids) {
      final probe = await Process.run('kill', ['-0', '$pid']);
      expect(
        probe.exitCode,
        isNot(0),
        reason: 'Worker child $pid was not reaped.',
      );
    }
  }
}

const _script = r'''#!/bin/sh
root=${0%/*}
printf '%s\n' "$$" >> "$root/pids"
printf '%s\n' "$@" > "$root/args-$$"
pwd -P > "$root/cwd-$$"
[ -f "$root/exit-before-ready" ] && exit 7
while [ -f "$root/hold-ready" ]; do sleep 0.01; done
if [ -f "$root/diagnostics" ]; then printf 'startup diagnostic\n'; printf 'stderr diagnostic\n' >&2; fi
if [ -f "$root/close-after-ready" ]; then printf 'READY\nclose-after-ready\nlate-after-close\n'
elif [ -f "$root/legacy-ready" ]; then printf 'bootstrap...READY\n'
else printf 'READY\n'; fi
if [ -f "$root/close-input" ]; then
  exec 0<&-
  touch "$root/input-closed-$$"
  while [ -f "$root/close-input" ]; do sleep 0.01; done
  exit 0
fi
while IFS= read -r request; do
  if [ "$request" = STOP ]; then
    touch "$root/stop-$$"
    while [ -f "$root/hold-stop" ]; do sleep 0.01; done
    exit 0
  fi
  printf '%s\n' "$request" >> "$root/request-$$"
  [ -f "$root/exit-on-request" ] && exit 9
  if [ -f "$root/stdout-eof" ]; then exec 1>&-; IFS= read -r stop; exit 0; fi
  if [ -f "$root/stdout-invalid-utf8" ]; then printf '\377\n'; IFS= read -r stop; exit 0; fi
  if [ -f "$root/stderr-invalid-utf8" ]; then printf '\377\n' >&2; IFS= read -r stop; exit 0; fi
  while [ -f "$root/hold-response" ]; do sleep 0.01; done
  case "$request" in
    *bench.rpc.second*) sed 's/"request_bytes":17/"request_bytes":29/' "$root/response" ;;
    *) cat "$root/response" ;;
  esac
  printf '\n'
done
''';
