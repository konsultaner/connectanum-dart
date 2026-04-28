@TestOn('vm')
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as build_hook;

void main() {
  test('build hook reuses CONNECTANUM_NATIVE_LIB without invoking cargo', () {
    return _withPackageRoot(() async {
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum_client_hook_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final prebuiltLibrary = File(
        '${tempDir.path}/${_defaultLibraryFileName()}',
      )..writeAsStringSync('client-prebuilt');

      await testCodeBuildHook(
        mainMethod: (args) => build_hook.runBuildHook(
          args,
          environment: {_nativeLibEnv: prebuiltLibrary.path},
          cargoRunner: _unexpectedCargoRunner,
        ),
        check: (_, output) {
          expect(output.assets.code, hasLength(1));
          final asset = output.assets.code.single;
          expect(asset.file, isNotNull);
          expect(asset.file!.pathSegments.last, equals(_hookLibraryFileName()));
          expect(
            File.fromUri(asset.file!).readAsStringSync(),
            equals('client-prebuilt'),
          );
          expect(output.dependencies, contains(prebuiltLibrary.uri));
        },
      );
    });
  });

  test('build hook honors CONNECTANUM_SKIP_NATIVE_BUILD', () {
    return _withPackageRoot(() async {
      await testCodeBuildHook(
        mainMethod: (args) => build_hook.runBuildHook(
          args,
          environment: {_skipNativeBuildEnv: '1'},
          cargoRunner: _unexpectedCargoRunner,
        ),
        check: (_, output) {
          expect(output.assets.code, isEmpty);
        },
      );
    });
  });

  test('build hook downloads prebuilt release assets when configured', () {
    return _withPackageRoot(() async {
      final archiveBytes = 'client-release-archive'.codeUnits;
      final downloaded = <Uri>[];

      await testCodeBuildHook(
        mainMethod: (args) => build_hook.runBuildHook(
          args,
          environment: {
            _releaseTagEnv: 'ct-ffi-v2026.04.22-validation.043206-attest',
            _releaseRepoEnv: 'konsultaner/connectanum-dart',
          },
          cargoRunner: _unexpectedCargoRunner,
          artifactDownloader: ({required source, required destination}) async {
            downloaded.add(source);
            destination.parent.createSync(recursive: true);
            if (destination.path.endsWith('.sha256')) {
              final digest = sha256.convert(archiveBytes).toString();
              destination.writeAsStringSync(
                '$digest  ${_releaseArchiveName()}',
              );
            } else {
              destination.writeAsBytesSync(archiveBytes);
            }
          },
          archiveExtractor: ({required archive, required destination}) {
            expect(archive.readAsBytesSync(), archiveBytes);
            final extractedLib = File(
              '${destination.path}/${_releaseBundleName()}/${_defaultLibraryFileName()}',
            );
            extractedLib.parent.createSync(recursive: true);
            extractedLib.writeAsStringSync('client-release-prebuilt');
          },
        ),
        check: (_, output) {
          expect(output.assets.code, hasLength(1));
          final asset = output.assets.code.single;
          expect(asset.file, isNotNull);
          expect(asset.file!.pathSegments.last, equals(_hookLibraryFileName()));
          expect(
            File.fromUri(asset.file!).readAsStringSync(),
            equals('client-release-prebuilt'),
          );
          expect(
            downloaded.map((uri) => uri.toString()),
            contains(
              'https://github.com/konsultaner/connectanum-dart/releases/download/'
              'ct-ffi-v2026.04.22-validation.043206-attest/${_releaseArchiveName()}',
            ),
          );
          expect(
            downloaded.map((uri) => uri.toString()),
            contains(
              'https://github.com/konsultaner/connectanum-dart/releases/download/'
              'ct-ffi-v2026.04.22-validation.043206-attest/${_releaseArchiveName()}.sha256',
            ),
          );
        },
      );
    });
  });

  test('release host triples cover native artifact matrix targets', () {
    expect(
      build_hook.hostTripleForTarget(
        targetOS: OS.linux,
        targetArch: Architecture.x64,
      ),
      equals('x86_64-unknown-linux-gnu'),
    );
    expect(
      build_hook.hostTripleForTarget(
        targetOS: OS.linux,
        targetArch: Architecture.arm64,
      ),
      equals('aarch64-unknown-linux-gnu'),
    );
    expect(
      build_hook.hostTripleForTarget(
        targetOS: OS.macOS,
        targetArch: Architecture.arm64,
      ),
      equals('aarch64-apple-darwin'),
    );
    expect(
      build_hook.hostTripleForTarget(
        targetOS: OS.windows,
        targetArch: Architecture.x64,
      ),
      equals('x86_64-pc-windows-msvc'),
    );
  });
}

const _nativeLibEnv = 'CONNECTANUM_NATIVE_LIB';
const _releaseTagEnv = 'CONNECTANUM_NATIVE_RELEASE_TAG';
const _releaseRepoEnv = 'CONNECTANUM_NATIVE_RELEASE_REPOSITORY';
const _skipNativeBuildEnv = 'CONNECTANUM_SKIP_NATIVE_BUILD';

ProcessResult _unexpectedCargoRunner({
  required List<String> args,
  required String workingDirectory,
  required Map<String, String> environment,
}) => throw StateError('cargo should not be invoked in this test');

Future<void> _withPackageRoot(Future<void> Function() body) async {
  final original = Directory.current;
  Directory.current = _locatePackageRoot('connectanum_client');
  try {
    await _cleanPackageBuildArtifacts();
    await body();
    await _cleanPackageBuildArtifacts();
  } finally {
    Directory.current = original;
  }
}

Directory _locatePackageRoot(String packageName) {
  final current = Directory.current.absolute;
  if (_isPackageRoot(current, packageName)) {
    return current;
  }
  final nested = Directory('${current.path}/packages/$packageName');
  if (_isPackageRoot(nested, packageName)) {
    return nested.absolute;
  }
  throw StateError('Failed to locate package root for $packageName.');
}

bool _isPackageRoot(Directory directory, String packageName) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    return false;
  }
  return pubspec.readAsStringSync().contains('name: $packageName');
}

Future<void> _cleanPackageBuildArtifacts() async {
  for (final path in [
    '${Directory.current.path}/.dart_tool/lib',
    '${Directory.current.path}/.dart_tool/connectanum',
  ]) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
  final nativeAssetsYaml = File(
    '${Directory.current.path}/.dart_tool/native_assets.yaml',
  );
  if (nativeAssetsYaml.existsSync()) {
    await nativeAssetsYaml.delete();
  }

  final repoRoot = Directory('${Directory.current.path}/../..').absolute;
  for (final path in [
    '${repoRoot.path}/.dart_tool/hooks_runner/connectanum_client',
    '${repoRoot.path}/.dart_tool/hooks_runner/shared/connectanum_client',
  ]) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

String _defaultLibraryFileName() => switch (Platform.operatingSystem) {
  'linux' => 'libct_ffi.so',
  'macos' => 'libct_ffi.dylib',
  'windows' => 'ct_ffi.dll',
  _ => 'libct_ffi.so',
};

String _hookLibraryFileName() => switch (Platform.operatingSystem) {
  'linux' => 'libconnectanum_client_ct_ffi.so',
  'macos' => 'libconnectanum_client_ct_ffi.dylib',
  'windows' => 'connectanum_client_ct_ffi.dll',
  _ => 'libconnectanum_client_ct_ffi.so',
};

String _releaseBundleName() => 'ct-ffi-${_hostTriple()}';

String _releaseArchiveName() => '${_releaseBundleName()}.tar.gz';

String _hostTriple() => switch (Platform.operatingSystem) {
  'linux' => 'x86_64-unknown-linux-gnu',
  'macos' =>
    Platform.version.contains('arm64')
        ? 'aarch64-apple-darwin'
        : 'x86_64-apple-darwin',
  _ => 'x86_64-unknown-linux-gnu',
};
