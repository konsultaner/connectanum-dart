@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/benchmark_child_coverage.dart';
import 'support/collect_benchmark_child_coverage.dart' as collector;

Map<String, Object?> _report(Object? hits, {String? source}) => {
  'coverage': [
    {
      'source': source ?? 'package:connectanum_bench/src/benchmark_runner.dart',
      'hits': hits,
    },
  ],
};

void main() {
  group('child report validation', () {
    test('accepts measured hits and retains unexecuted lines', () {
      final report = _report([31, 1, 74, 0]);
      final before = jsonEncode(report);
      validateBenchmarkChildCoverage(report);
      expect(jsonEncode(report), before);
    });
    final invalid = <String, Object?>{
      'null': null,
      'non map': [],
      'no coverage': {},
      'wrong coverage type': {'coverage': {}},
      'empty coverage': {'coverage': []},
      'non map entry': {
        'coverage': [null],
      },
      'wrong package': _report([
        31,
        1,
      ], source: 'package:other/benchmark_runner.dart'),
      'similar suffix': _report([
        31,
        1,
      ], source: 'package:connectanum_bench/src/benchmark_runner.dart.bak'),
      'missing hits': _report(null),
      'wrong hits type': _report({}),
      'empty hits': _report([]),
      'odd hit pairs': _report([31]),
      'line zero': _report([0, 1]),
      'negative line': _report([-1, 1]),
      'string line': _report(['31', 1]),
      'fractional line': _report([31.5, 1]),
      'negative count': _report([31, -1]),
      'string count': _report([31, '1']),
      'fractional count': _report([31, 1.5]),
      'zero hits': _report([31, 0, 74, 0]),
      'duplicate lines': _report([31, 1, 31, 2]),
      'duplicate sources': {
        'coverage': [
          ..._report([31, 1])['coverage'] as List,
          ..._report([31, 2])['coverage'] as List,
        ],
      },
    };
    for (final entry in invalid.entries) {
      test('rejects ${entry.key}', () {
        expect(
          () => validateBenchmarkChildCoverage(entry.value),
          throwsFormatException,
        );
      });
    }
  });

  group('collector ownership', () {
    late Directory root;
    late File output;
    final uri = Uri.parse('http://127.0.0.1:12345/token/');
    setUp(() async {
      root = await Directory.systemTemp.createTemp('bench-child-coverage-');
      addTearDown(() => root.delete(recursive: true));
      output = File('${root.path}/reports/child.json');
    });
    test('writer preserves existing evidence atomically', () async {
      await output.parent.create();
      await output.writeAsString('original');
      await expectLater(
        collector.writeChildCoverageReport(output, _report([31, 1])),
        throwsA(isA<FileSystemException>()),
      );
      expect(await output.readAsString(), 'original');
    });
    test('competing report writers have exactly one owner', () async {
      await output.parent.create();
      final reports = [
        _report([31, 1]),
        _report([74, 2]),
      ];
      final outcomes = await Future.wait([
        for (final report in reports)
          collector
              .writeChildCoverageReport(output, report)
              .then<Object>((_) => report, onError: (Object error) => error),
      ]);
      expect(outcomes.whereType<FileSystemException>(), hasLength(1));
      final winner = outcomes.whereType<Map>().single;
      expect(jsonDecode(await output.readAsString()), winner);
    });
    test('collector rejects existing output before connecting', () async {
      await output.parent.create();
      await output.writeAsString('original');
      await expectLater(
        collector.main(['invalid service URI', output.path]),
        throwsStateError,
      );
      expect(await output.readAsString(), 'original');
    });
    test(
      'uses workspace collector and original source, not global tooling',
      () async {
        final process = _Process()..finish(0);
        await collectBenchmarkChildCoverage(
          uri,
          output,
          root,
          startProcess: (executable, args) async {
            expect(executable, Platform.resolvedExecutable);
            expect(args, [
              '--packages=${root.path}/.dart_tool/package_config.json',
              '${root.path}/packages/connectanum_bench/test/support/collect_benchmark_child_coverage.dart',
              '$uri',
              output.path,
            ]);
            await output.writeAsString(jsonEncode(_report([31, 1, 74, 0])));
            return process;
          },
        );
        expect(process.kills, 0);
        expect(
          jsonDecode(await output.readAsString()),
          _report([31, 1, 74, 0]),
        );
      },
    );
    test('existing evidence is preserved without starting a process', () async {
      await output.parent.create();
      await output.writeAsString('original evidence');
      var started = false;
      await expectLater(
        collectBenchmarkChildCoverage(
          uri,
          output,
          root,
          startProcess: (_, _) async {
            started = true;
            return _Process()..finish(0);
          },
        ),
        throwsStateError,
      );
      expect(started, isFalse);
      expect(await output.readAsString(), 'original evidence');
    });
    for (final address in [
      'https://127.0.0.1:12/',
      'http://example.com:12/',
      'http://127.0.0.1:0/',
    ]) {
      test('rejects service URI $address before starting', () async {
        var started = false;
        await expectLater(
          collectBenchmarkChildCoverage(
            Uri.parse(address),
            output,
            root,
            startProcess: (_, _) async {
              started = true;
              return _Process()..finish(0);
            },
          ),
          throwsArgumentError,
        );
        expect(started, isFalse);
      });
    }
    test('spawn failure is propagated without fabricating evidence', () async {
      final error = ProcessException('fixture', [], 'spawn failed');
      await expectLater(
        collectBenchmarkChildCoverage(
          uri,
          output,
          root,
          startProcess: (_, _) async => throw error,
        ),
        throwsA(same(error)),
      );
      expect(await output.exists(), isFalse);
    });
    for (final code in [7, -9]) {
      test('nonzero exit $code fails even with a valid report', () async {
        final process = _Process(
          stdoutBytes: Stream.value([111, 117, 116, 255]),
          stderrBytes: Stream.value([101, 114, 114, 254]),
        )..finish(code);
        await expectLater(
          collectBenchmarkChildCoverage(
            uri,
            output,
            root,
            startProcess: (_, _) async {
              await output.writeAsString(jsonEncode(_report([31, 1])));
              return process;
            },
          ),
          throwsA(
            isA<ProcessException>()
                .having((error) => error.errorCode, 'exit code', code)
                .having(
                  (error) => error.message,
                  'both pipes',
                  contains('out\uFFFD\nerr\uFFFD'),
                ),
          ),
        );
        expect(process.kills, 0);
      });
    }
    for (final contents in <String?>[
      null,
      '{',
      '{}',
      jsonEncode(_report([31, 0])),
    ]) {
      test(
        'zero exit cannot conceal missing or invalid report: $contents',
        () async {
          final process = _Process()..finish(0);
          await expectLater(
            collectBenchmarkChildCoverage(
              uri,
              output,
              root,
              startProcess: (_, _) async {
                if (contents != null) await output.writeAsString(contents);
                return process;
              },
            ),
            contents == null
                ? throwsA(isA<FileSystemException>())
                : throwsFormatException,
          );
          expect(process.kills, 0);
        },
      );
    }
    test('timeout kills and awaits the collector without credit', () async {
      final process = _Process();
      await expectLater(
        collectBenchmarkChildCoverage(
          uri,
          output,
          root,
          timeout: const Duration(milliseconds: 10),
          startProcess: (_, _) async => process,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(process.kills, 1);
      expect(process.signal, ProcessSignal.sigkill);
      expect(await process.exitCode, -9);
      expect(await output.exists(), isFalse);
    });
    test('pipe failure kills and awaits the collector', () async {
      final error = StateError('broken pipe');
      final process = _Process(stdoutBytes: Stream.error(error));
      await expectLater(
        collectBenchmarkChildCoverage(
          uri,
          output,
          root,
          startProcess: (_, _) async => process,
        ),
        throwsA(same(error)),
      );
      expect(process.kills, 1);
      expect(await process.exitCode, -9);
    });
    test('real timed-out child is reaped', () async {
      late Process process;
      await expectLater(
        collectBenchmarkChildCoverage(
          uri,
          output,
          root,
          timeout: const Duration(milliseconds: 50),
          startProcess: (_, _) async =>
              process = await Process.start('sleep', ['60']),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(await process.exitCode, isNot(0));
      expect(process.kill(ProcessSignal.sigkill), isFalse);
      expect(await output.exists(), isFalse);
    }, skip: Platform.isWindows ? 'POSIX sleep fixture' : false);
  });
}

class _Process implements Process {
  final _exit = Completer<int>();
  final Stream<List<int>> stdoutBytes;
  final Stream<List<int>> stderrBytes;
  int kills = 0;
  ProcessSignal? signal;

  _Process({
    this.stdoutBytes = const Stream.empty(),
    this.stderrBytes = const Stream.empty(),
  });

  void finish(int code) => _exit.complete(code);

  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => stdoutBytes;
  @override
  Stream<List<int>> get stderr => stderrBytes;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    this.signal = signal;
    if (!_exit.isCompleted) finish(-9);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
