@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:connectanum_client/src/native_release_installer.dart' as native;
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/install_native.dart' as cli;
import 'installer_assertions.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('connectanum_install_cli_');
  });
  tearDown(() => root.delete(recursive: true));

  test('valid install assertion returns the original file', () async {
    final file = File('${root.path}/fixture');
    expect(await expectValidInstall(() async => file), same(file));
  });

  for (final asynchronous in [false, true]) {
    for (final failure in [
      const ProcessException('tar', [], 'fixture missing executable'),
      const SocketException('fixture unavailable connection'),
    ]) {
      test(
        'valid install assertion preserves ${failure.runtimeType} '
        '($asynchronous)',
        () async {
          await expectLater(
            () => expectValidInstall(() {
              if (asynchronous) return Future<File>.error(failure);
              throw failure;
            }),
            throwsA(same(failure)),
          );
        },
      );
    }
    test('valid install assertion preserves timeout ($asynchronous)', () async {
      final failure = TimeoutException('fixture timeout');
      await expectLater(
        () => expectValidInstall(() {
          if (asynchronous) return Future<File>.error(failure);
          throw failure;
        }),
        throwsA(same(failure)),
      );
    });
    test('valid install assertion rejects errors ($asynchronous)', () async {
      final failure = StateError('fixture failure');
      await expectLater(
        () => expectValidInstall(() {
          if (asynchronous) return Future<File>.error(failure);
          throw failure;
        }),
        throwsA(isA<TestFailure>()),
      );
    });
  }

  test('main forwards help output without network IO', () async {
    final output = _CapturedStdout();
    final errors = _CapturedStdout();
    await IOOverrides.runZoned(
      () => cli.main(['--help']),
      stdout: () => output,
      stderr: () => errors,
    );
    expect(output.text.toString(), startsWith('Usage:'));
    expect(errors.text.toString(), isEmpty);
  });

  test('executable reports real process exit codes and streams', () async {
    final source = await Isolate.resolvePackageUri(
      Uri.parse('package:connectanum_client/connectanum_client.dart'),
    );
    final packageConfig = await Isolate.packageConfig;
    expect(source, isNotNull);
    expect(packageConfig, isNotNull);
    final script = source!.resolve('../tool/install_native.dart').toFilePath();
    final output = '${root.path}/installed';
    final cachedArgs = ['--tag=v-cli', '--out-dir=$output'];
    final installed = await _install(cachedArgs, root, []);
    final blocked = File('${root.path}/not-a-directory')
      ..writeAsStringSync('keep');
    for (final (args, code, out, err) in [
      (['--help'], 0, startsWith('Usage:'), isEmpty),
      (['--unknown'], 64, isEmpty, contains('Unrecognized argument')),
      (cachedArgs, 0, equals('${installed.path}\n'), isEmpty),
      (
        ['--tag=v-cli', '--out-dir=${blocked.path}'],
        1,
        isEmpty,
        startsWith('Failed to install ct_ffi:'),
      ),
    ]) {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['--packages=${packageConfig!.toFilePath()}', script, ...args],
        workingDirectory: root.path,
      );
      expect(result.exitCode, code, reason: '$args\n${result.stderr}');
      expect(result.stdout, out);
      expect(result.stderr, err);
    }
    expect(blocked.readAsStringSync(), 'keep');
    expect(installed.readAsStringSync(), 'verified fixture library');
  });

  test('concurrent command results keep their own exit status', () async {
    final bothCompleted = Completer<void>();
    var completed = 0;
    Future<void> beforeCapture() {
      if (++completed == 2) bothCompleted.complete();
      return bothCompleted.future;
    }

    final results = await Future.wait([
      _run(['--help'], root, beforeCapture: beforeCapture),
      _run(['--unknown'], root, beforeCapture: beforeCapture),
    ]);
    expect(results.map((result) => result.code), [0, 64]);
    expect(results[0].err, isEmpty);
    expect(results[1].out, isEmpty);
  });

  for (final flag in ['--help', '-h']) {
    test('$flag prints help only to stdout without network IO', () async {
      final result = await _run([flag], root);
      expect(result.code, 0);
      expect(result.out, startsWith('Usage:'));
      expect(result.out, contains('--tag'));
      expect(result.err, isEmpty);
      expect(root.listSync(recursive: true), isEmpty);
    });
  }

  for (final (args, message) in [
    (['--tag'], 'Expected a value after --tag.'),
    (['--repository'], 'Expected a value after --repository.'),
    (['--out-dir'], 'Expected a value after --out-dir.'),
    (['--unknown'], 'Unrecognized argument: --unknown'),
    (['--tag='], 'Missing release tag.'),
    (['--tag', '  '], 'Missing release tag.'),
  ]) {
    test(
      'invalid options $args report usage and never access network',
      () async {
        final result = await _run(args, root);
        expect(result.code, 64);
        expect(result.out, isEmpty);
        expect(result.err, startsWith(message));
        expect(result.err, contains('Usage:'));
        expect(root.listSync(recursive: true), isEmpty);
      },
    );
  }

  for (final inline in [true, false]) {
    for (final absolute in [true, false]) {
      test(
        'explicit options override environment ($inline, $absolute)',
        () async {
          final output = absolute
              ? '${root.path}/installed'
              : 'nested/installed';
          final options = {
            'tag': 'v-cli',
            'repository': 'example/cli',
            'out-dir': output,
          };
          final args = [
            for (final entry in options.entries)
              if (inline)
                '--${entry.key}= ${entry.value} '
              else ...[
                '--${entry.key}',
                ' ${entry.value} ',
              ],
          ];
          final urls = <Uri>[];
          final installed = await _install(
            args,
            root,
            urls,
            environment: {
              native.nativeReleaseTagEnv: 'v-environment',
              native.nativeReleaseRepoEnv: 'example/environment',
            },
          );
          final directory = absolute ? output : '${root.path}/$output';
          expect(
            installed.path,
            '$directory/${native.currentPlatformLibraryFileName('ct_ffi')}',
          );
          expect(installed.readAsStringSync(), 'verified fixture library');
          expect(urls, hasLength(2));
          for (final url in urls) {
            expect(url.host, 'github.com');
            expect(
              url.path,
              startsWith('/example/cli/releases/download/v-cli/'),
            );
          }
        },
      );
    }
  }

  test(
    'environment supplies trimmed tag and repository with default output',
    () async {
      final urls = <Uri>[];
      final installed = await _install(
        [],
        root,
        urls,
        environment: {
          native.nativeReleaseTagEnv: '  v-env  ',
          native.nativeReleaseRepoEnv: '  example/env  ',
        },
      );
      expect(
        installed.path,
        '${root.path}/.dart_tool/connectanum/native/'
        '${native.currentHostTriple()}/${native.currentPlatformLibraryFileName('ct_ffi')}',
      );
      expect(urls, hasLength(2));
      expect(
        urls.every(
          (uri) => uri.path.startsWith('/example/env/releases/download/v-env/'),
        ),
        isTrue,
      );
    },
  );

  test('main prints the installed path from verified cache', () async {
    final args = ['--tag=v-cli', '--out-dir=${root.path}/installed'];
    final installed = await _install(args, root, []);
    final result = await _run(args, root);
    expect(result.code, 0);
    expect(result.out, '${installed.path}\n');
    expect(result.err, isEmpty);
    expect(installed.readAsStringSync(), 'verified fixture library');
  });

  test(
    'main reports download initialization failure without success output',
    () async {
      final result = await _run(['--tag=v-cli'], root, failDownload: true);
      expect(result.code, 1);
      expect(result.out, isEmpty);
      expect(
        result.err,
        'Failed to install ct_ffi: Bad state: offline fixture\n',
      );
    },
  );
}

// Only for valid fixture setup; negative installer calls keep their own checks.
Future<File> _install(
  List<String> args,
  Directory root,
  List<Uri> urls, {
  Map<String, String> environment = const {},
}) {
  final archiveBytes = 'fixture archive'.codeUnits;
  return expectValidInstall(
    () => cli.installNative(
      args,
      environment: environment,
      workingDirectory: root,
      artifactDownloader: ({required source, required destination}) async {
        urls.add(source);
        if (source.path.endsWith('.sha256')) {
          destination.writeAsStringSync(
            '${sha256.convert(archiveBytes)}  archive.tar.gz',
          );
        } else {
          destination.writeAsBytesSync(archiveBytes);
        }
      },
      archiveExtractor: ({required archive, required destination}) {
        expect(archive.readAsBytesSync(), archiveBytes);
        final file = File(
          '${destination.path}/ct-ffi-${native.currentHostTriple()}/'
          '${native.currentPlatformLibraryFileName('ct_ffi')}',
        );
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('verified fixture library');
      },
    ),
  );
}

Future<({int code, String out, String err})> _run(
  List<String> args,
  Directory root, {
  bool failDownload = false,
  Future<void> Function()? beforeCapture,
}) async {
  final output = _CapturedStdout();
  final errors = _CapturedStdout();
  var networkAttempts = 0;
  final code = await IOOverrides.runZoned(
    () => HttpOverrides.runZoned(
      () => cli.runInstallCommand(args),
      createHttpClient: (_) {
        networkAttempts++;
        throw StateError('offline fixture');
      },
    ),
    stdout: () => output,
    stderr: () => errors,
    getCurrentDirectory: () => root,
  );
  await beforeCapture?.call();
  expect(networkAttempts, failDownload ? 1 : 0);
  return (
    code: code,
    out: output.text.toString(),
    err: errors.text.toString(),
  );
}

final class _CapturedStdout implements Stdout {
  final text = StringBuffer();
  @override
  void writeln([Object? object = '']) => text.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
