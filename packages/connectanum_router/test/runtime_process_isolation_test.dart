@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:async/async.dart';
import 'package:test/test.dart';

import 'support/native_lib.dart';

class _RouterProcess {
  _RouterProcess(this.process)
    : lines = StreamQueue(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      errors = process.stderr.transform(utf8.decoder).join();

  final Process process;
  final StreamQueue<String> lines;
  final Future<String> errors;
  bool stopped = false;

  Future<Map<String, dynamic>> ready() async {
    final line = await lines.next.timeout(const Duration(seconds: 20));
    final ready = jsonDecode(line) as Map<String, dynamic>;
    expect(ready['ready'], true);
    expect(ready['port'], greaterThan(0));
    return ready;
  }

  Future<void> exited() async {
    final code = await process.exitCode.timeout(const Duration(seconds: 10));
    expect(code, 0, reason: await errors);
    expect(await lines.next, 'cleanup completed');
    stopped = true;
  }

  Future<void> cleanup() async {
    if (!stopped) {
      process.kill();
      await process.exitCode.timeout(const Duration(seconds: 5));
    }
    await process.stdin.close();
    await lines.cancel();
  }
}

void main() {
  final nativeLib = resolveOrBuildNativeLib();
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    test(
      'router CLI reloads on SIGHUP and exits naturally on $signal',
      () async {
        final temp = Directory.systemTemp.createTempSync(
          'connectanum-cli-reload-',
        );
        addTearDown(() => temp.deleteSync(recursive: true));
        final root =
            Directory.current.path.endsWith('packages/connectanum_router')
            ? Directory('../..').absolute
            : Directory.current;
        final configuration = File('${temp.path}/router.yaml')
          ..writeAsStringSync(
            File(
              '${root.path}/examples/quickstart/router.yaml',
            ).readAsStringSync().replaceAll('127.0.0.1:8080', '127.0.0.1:0'),
          );
        final packageConfig = (await Isolate.packageConfig)!.toFilePath();
        final process = await Process.start(Platform.resolvedExecutable, [
          '--packages=$packageConfig',
          '${root.path}/packages/connectanum_router/bin/connectanum_router.dart',
          '--native-lib',
          nativeLib!,
          '--config',
          configuration.path,
        ]);
        final lines = StreamQueue(
          process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        final errors = process.stderr.transform(utf8.decoder).join();
        var stopped = false;
        addTearDown(() async {
          if (!stopped) process.kill();
          await process.exitCode.timeout(const Duration(seconds: 5));
          await process.stdin.close();
          await lines.cancel();
        });
        Future<String> until(String prefix) async {
          while (true) {
            if (!await lines.hasNext.timeout(const Duration(seconds: 20))) {
              fail('CLI exited before $prefix: ${await errors}');
            }
            final line = await lines.next.timeout(const Duration(seconds: 20));
            if (line.startsWith(prefix)) return line;
          }
        }

        await until('Router running.');
        expect(process.kill(ProcessSignal.sighup), isTrue);
        expect(
          await until('Reloaded TLS'),
          'Reloaded TLS configuration for 1 listener(s).',
        );
        expect(process.kill(signal), isTrue);
        final code = await process.exitCode.timeout(
          const Duration(seconds: 10),
        );
        expect(code, 0, reason: await errors);
        stopped = true;
      },
      skip: nativeLib == null || Platform.isWindows
          ? 'Requires native runtime and POSIX signals'
          : false,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  }
  for (final mode in [
    'internal-startup',
    'internal-spawn',
    'bootstrap-startup',
    'cleanup-failure',
    'active-client',
  ]) {
    test(
      'router exits naturally after $mode',
      () async {
        final packageConfig = (await Isolate.packageConfig)!.toFilePath();
        final fixture = [
          File('test/fixtures/runtime_process_fixture.dart'),
          File(
            'packages/connectanum_router/test/fixtures/runtime_process_fixture.dart',
          ),
        ].firstWhere((file) => file.existsSync()).absolute.path;
        final child = _RouterProcess(
          await Process.start(Platform.resolvedExecutable, [
            '--packages=$packageConfig',
            fixture,
            nativeLib!,
            mode,
          ]),
        );
        addTearDown(child.cleanup);
        await child.ready();
        await child.exited();
      },
      skip: nativeLib == null ? 'Native transport library unavailable' : false,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  }
  test(
    'independent router processes share a temp directory and exit naturally',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'connectanum-router-processes-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final packageConfigUri = await Isolate.packageConfig;
      if (packageConfigUri == null) {
        throw StateError(
          'Subprocess smoke requires a Dart package configuration',
        );
      }
      final packageConfig = packageConfigUri.toFilePath();
      final fixture = [
        File('test/fixtures/runtime_process_fixture.dart'),
        File(
          'packages/connectanum_router/test/fixtures/runtime_process_fixture.dart',
        ),
      ].firstWhere((file) => file.existsSync()).absolute.path;
      Future<_RouterProcess> launch(String mode) async {
        final child = _RouterProcess(
          await Process.start(
            Platform.resolvedExecutable,
            ['--packages=$packageConfig', fixture, nativeLib!, mode],
            environment: {
              'TMPDIR': temp.path,
              'TMP': temp.path,
              'TEMP': temp.path,
            },
          ),
        );
        addTearDown(child.cleanup);
        return child;
      }

      final first = await launch('hold');
      final firstReady = await first.ready();
      final second = await launch('exit');
      // The first still holds its runtime ownership; the second must start now,
      // not only after releasing the first process's lock.
      final secondReady = await second.ready();
      expect(secondReady['pid'], isNot(firstReady['pid']));
      expect(secondReady['port'], isNot(firstReady['port']));
      await second.exited();
      first.process.stdin.writeln('stop');
      await first.exited();
    },
    skip: nativeLib == null ? 'Native transport library unavailable' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
