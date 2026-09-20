@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('native build process', () {
    for (final stdoutBytes in [0, 524288]) {
      for (final stderrBytes in [0, 524288]) {
        for (final code in [0, 7]) {
          test('stdout=$stdoutBytes stderr=$stderrBytes exit=$code', () async {
            await _checkBuild(
              stdoutBytes: stdoutBytes,
              stderrBytes: stderrBytes,
              code: code,
            );
          });
        }
      }
    }
    test('preserves small binary output and a distinct exit code', () async {
      await _checkBuild(stdoutBytes: 8, stderrBytes: 9, code: 23);
    });
    test('disabled native build does not spawn cargo', () async {
      await _checkBuild(build: false);
    });
  }, skip: Platform.isWindows ? 'POSIX executable fixture' : false);
}

Future<void> _checkBuild({
  bool build = true,
  int stdoutBytes = 0,
  int stderrBytes = 0,
  int code = 0,
}) async {
  var root = Directory.current.absolute;
  while (!File('${root.path}/.dart_tool/package_config.json').existsSync()) {
    if (root.parent.path == root.path) {
      throw StateError('Workspace package configuration not found');
    }
    root = root.parent;
  }
  final fixture = await Directory.systemTemp.createTemp('bench-build-process-');
  addTearDown(() => fixture.delete(recursive: true));
  final nativeDirectory = Directory('${fixture.path}/native/transport');
  await nativeDirectory.create(recursive: true);
  final executable = File('${fixture.path}/fake-bin/cargo');
  await executable.parent.create();
  await executable.writeAsString(_cargo);
  final chmod = await Process.run('chmod', ['+x', executable.path]);
  if (chmod.exitCode != 0) {
    throw ProcessException('chmod', ['+x', executable.path], '${chmod.stderr}');
  }
  final pidFile = File('${fixture.path}/cargo.pid');
  final process = await Process.start(
    Platform.resolvedExecutable,
    [
      '--packages=${root.path}/.dart_tool/package_config.json',
      '${root.path}/packages/connectanum_bench/test/support/benchmark_build_probe.dart',
      build ? 'build' : 'skip',
    ],
    workingDirectory: fixture.path,
    environment: {
      'PATH': '${executable.parent.path}:${Platform.environment['PATH']}',
      'CONNECTANUM_FAKE_CARGO_PID_FILE': pidFile.path,
      'CONNECTANUM_FAKE_CARGO_STDOUT_BYTES': '$stdoutBytes',
      'CONNECTANUM_FAKE_CARGO_STDERR_BYTES': '$stderrBytes',
      'CONNECTANUM_FAKE_CARGO_EXIT': '$code',
    },
  );
  var exited = false;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  final ready = Completer<void>();
  final prefix = StringBuffer();
  final output = process.stdout.map((bytes) {
    final text = String.fromCharCodes(bytes);
    if (!ready.isCompleted) {
      prefix.write(text);
      if (prefix.toString().contains('PROBE_READY\n')) ready.complete();
    }
    return text;
  }).join();
  final errors = process.stderr.fold<List<int>>(
    [],
    (all, bytes) => all..addAll(bytes),
  );
  addTearDown(() async {
    if (!exited) {
      if (pidFile.existsSync()) {
        Process.killPid(
          int.parse(pidFile.readAsStringSync().trim()),
          ProcessSignal.sigkill,
        );
      }
      process.kill(ProcessSignal.sigkill);
    }
    await exit;
    await Future.wait<Object?>([output, errors]);
  });
  // Exclude Dart compilation/startup from the pipe-drain deadline.
  await ready.future.timeout(const Duration(seconds: 30));
  final startupClock = Stopwatch()..start();
  while (build && !pidFile.existsSync() && !exited) {
    if (startupClock.elapsed > const Duration(seconds: 10)) {
      throw TimeoutException('Fake cargo did not start');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final result = await exit.timeout(const Duration(seconds: 2));
  if (result != 0) {
    throw ProcessException('build probe', [], await output, result);
  }
  final text = await output;
  final metadata = jsonDecode(text.split('BUILD_PROBE_RESULT:').last);
  expect(pidFile.existsSync(), build);
  if (build) {
    expect(text.codeUnits.where((byte) => byte == 0), hasLength(stdoutBytes));
    expect(
      text,
      contains('FAKE_BUILD_DONE\n${String.fromCharCodes([255, 254, 253])}'),
    );
    expect(await errors, [
      for (var i = 0; i < stderrBytes; i++) 0,
      253,
      254,
      255,
    ]);
    expect(File('${pidFile.path}.args').readAsLinesSync(), [
      'build',
      '-p',
      'ct_ffi',
      '--release',
    ]);
    expect(
      File('${pidFile.path}.cwd').readAsStringSync().trim(),
      nativeDirectory.resolveSymbolicLinksSync(),
    );
  } else {
    expect(text, isNot(contains('FAKE_BUILD_DONE')));
    expect(await errors, isEmpty);
  }
  final expectedMetadata = build && code != 0
      ? {
          'error_type': 'ProcessException',
          'exit_code': code,
          'executable': 'cargo',
          'arguments': ['build', '-p', 'ct_ffi', '--release'],
          'message': 'Native build failed with exit code $code',
        }
      : {'error_type': 'FileSystemException', 'path': 'never-read.yaml'};
  expect(metadata, expectedMetadata);
  final expectedOutput =
      'PROBE_READY\n'
      '${build ? String.fromCharCodes(List<int>.filled(stdoutBytes, 0)) : ''}'
      '${build ? 'FAKE_BUILD_DONE\n${String.fromCharCodes([255, 254, 253])}' : ''}'
      'BUILD_PROBE_RESULT:${jsonEncode(expectedMetadata)}\n';
  expect(
    text == expectedOutput,
    isTrue,
    reason: 'Build stdout must preserve all bytes and their order.',
  );
}

const _cargo = r'''#!/bin/sh
printf '%s\n' "$$" > "$CONNECTANUM_FAKE_CARGO_PID_FILE"
printf '%s\n' "$@" > "$CONNECTANUM_FAKE_CARGO_PID_FILE.args"
pwd -P > "$CONNECTANUM_FAKE_CARGO_PID_FILE.cwd"
if [ "$CONNECTANUM_FAKE_CARGO_STDOUT_BYTES" -gt 0 ]; then
  head -c "$CONNECTANUM_FAKE_CARGO_STDOUT_BYTES" /dev/zero
fi
if [ "$CONNECTANUM_FAKE_CARGO_STDERR_BYTES" -gt 0 ]; then
  head -c "$CONNECTANUM_FAKE_CARGO_STDERR_BYTES" /dev/zero >&2
fi
printf 'FAKE_BUILD_DONE\n\377\376\375'
printf '\375\376\377' >&2
exit "$CONNECTANUM_FAKE_CARGO_EXIT"
''';
