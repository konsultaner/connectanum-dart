@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_router/src/native_release_installer.dart' as native;
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/install_native.dart' as cli;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('connectanum_install_cli_');
  });
  tearDown(() => root.delete(recursive: true));

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

Future<File> _install(
  List<String> args,
  Directory root,
  List<Uri> urls, {
  Map<String, String> environment = const {},
}) {
  final archiveBytes = 'fixture archive'.codeUnits;
  return cli.installNative(
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
  );
}

Future<({int code, String out, String err})> _run(
  List<String> args,
  Directory root, {
  bool failDownload = false,
}) async {
  final output = _CapturedStdout();
  final errors = _CapturedStdout();
  final previousCode = exitCode;
  var networkAttempts = 0;
  exitCode = 0;
  try {
    await IOOverrides.runZoned(
      () => HttpOverrides.runZoned(
        () => cli.main(args),
        createHttpClient: (_) {
          networkAttempts++;
          throw StateError('offline fixture');
        },
      ),
      stdout: () => output,
      stderr: () => errors,
      getCurrentDirectory: () => root,
    );
    expect(networkAttempts, failDownload ? 1 : 0);
    return (
      code: exitCode,
      out: output.text.toString(),
      err: errors.text.toString(),
    );
  } finally {
    exitCode = previousCode;
  }
}

final class _CapturedStdout implements Stdout {
  final text = StringBuffer();
  @override
  void writeln([Object? object = '']) => text.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
