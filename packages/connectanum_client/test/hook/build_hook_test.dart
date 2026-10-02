@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as build_hook;

void main() {
  test('publication cleans the staged copy when rename fails', () {
    final root = Directory.systemTemp.createTempSync('hook_rename_failure_');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = File('${root.path}/source')
      ..writeAsStringSync('new library');
    final destination = Directory('${root.path}/occupied')..createSync();
    final existing = File('${destination.path}/keep')
      ..writeAsStringSync('keep');
    expect(
      () => build_hook.publishNativeLibrary(
        source: source,
        destination: File(destination.path),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(source.readAsStringSync(), 'new library');
    expect(existing.readAsStringSync(), 'keep');
    expect(
      root.listSync().where((entry) => entry.path.contains('.tmp.')),
      isEmpty,
    );
  });

  test('release selection rejects unsupported OS and architecture pairs', () {
    for (final (os, arch) in [
      (OS.android, Architecture.arm64),
      (OS.iOS, Architecture.arm64),
      (OS.windows, Architecture.arm64),
      (OS.linux, Architecture.arm),
    ]) {
      expect(
        () => build_hook.hostTripleForTarget(targetOS: os, targetArch: arch),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Unsupported release host combination'),
          ),
        ),
      );
    }
  });

  test('concurrent hook fixtures keep their package roots isolated', () async {
    final original = Directory.current.path;
    final bothEntered = Completer<void>();
    final roots = <String>[];
    await Future.wait([
      for (var index = 0; index < 2; index++)
        _withPackageRoot(() async {
          final ownRoot = Directory.current.path;
          roots.add(ownRoot);
          if (roots.length == 2) bothEntered.complete();
          await bothEntered.future;
          expect(Directory.current.path, ownRoot);
          expect(roots.toSet(), hasLength(2));
          expect(ownRoot, isNot(original));
        }),
    ]);
    expect(Directory.current.path, original);
    expect(roots.every((path) => !Directory(path).existsSync()), isTrue);
  });

  test('configured native library copy replaces the hook output inode', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'connectanum_client_configured_copy_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final source = File('${tempDir.path}/${_defaultLibraryFileName()}')
      ..writeAsStringSync('client-prebuilt-v1');
    final destination = File(
      '${tempDir.path}/missing/hook/output/${_hookLibraryFileName()}',
    );

    expect(destination.parent.existsSync(), isFalse);
    build_hook.publishNativeLibrary(
      source: source,
      destination: destination,
    );

    RandomAccessFile? mappedOutput;
    if (!Platform.isWindows) {
      mappedOutput = destination.openSync();
      addTearDown(mappedOutput.closeSync);
    }

    source.writeAsStringSync('client-prebuilt-v2');
    build_hook.publishNativeLibrary(
      source: source,
      destination: destination,
    );

    expect(destination.readAsStringSync(), equals('client-prebuilt-v2'));
    if (mappedOutput != null) {
      mappedOutput.setPositionSync(0);
      expect(
        String.fromCharCodes(
          mappedOutput.readSync('client-prebuilt-v1'.length),
        ),
        equals('client-prebuilt-v1'),
      );
    }
    expect(
      destination.parent.listSync().where(
        (entry) => entry.path.contains('${destination.path}.tmp.'),
      ),
      isEmpty,
    );
  });

  test('native library publication preserves output after copy failure', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'connectanum_client_failed_publish_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final destination = File(
      '${tempDir.path}/hook/output/${_hookLibraryFileName()}',
    );
    destination.parent.createSync(recursive: true);
    destination.writeAsStringSync('known-good-client-native');

    expect(
      () => build_hook.publishNativeLibrary(
        source: File('${tempDir.path}/missing-native-library'),
        destination: destination,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      destination.readAsStringSync(),
      equals('known-good-client-native'),
    );
    expect(
      destination.parent.listSync().where(
        (entry) => entry.path.contains('${destination.path}.tmp.'),
      ),
      isEmpty,
    );
  });

  test('build hook reuses CONNECTANUM_NATIVE_LIB user define', () {
    return _withPackageRoot(() async {
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum_client_hook_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final prebuiltLibrary = File(
        '${tempDir.path}/${_defaultLibraryFileName()}',
      )..writeAsStringSync('client-prebuilt');

      await testCodeBuildHook(
        mainMethod: (args) =>
            build_hook.runBuildHook(args, cargoRunner: _unexpectedCargoRunner),
        userDefines: _userDefines(
          basePath: tempDir.uri,
          defines: {_nativeLibEnv: prebuiltLibrary.path},
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

  test('path user define preserves Windows drive paths', () {
    for (final nativeLibraryPath in const [
      'D:/native/ct_ffi.dll',
      r'D:\native\ct_ffi.dll',
      r'\\build-server\native\ct_ffi.dll',
      '//build-server/native/ct_ffi.dll',
    ]) {
      expect(
        build_hook.resolvePathUserDefine(
          nativeLibraryPath,
          Uri.parse('D:/native/ct_ffi.dll'),
        ),
        nativeLibraryPath,
      );
    }
  });

  test('path user define resolves relative paths', () {
    const nativeLibraryPath = 'native/ct_ffi.dll';
    final resolved = Directory.systemTemp.uri.resolve(nativeLibraryPath);

    expect(
      build_hook.resolvePathUserDefine(nativeLibraryPath, resolved),
      resolved.toFilePath(),
    );
    expect(
      build_hook.resolvePathUserDefine(nativeLibraryPath, null),
      nativeLibraryPath,
    );
  });

  test('build hook honors CONNECTANUM_SKIP_NATIVE_BUILD user define', () {
    return _withPackageRoot(() async {
      await testCodeBuildHook(
        mainMethod: (args) => build_hook.runBuildHook(
          args,
          environment: const {},
          cargoRunner: _unexpectedCargoRunner,
        ),
        userDefines: _userDefines(defines: {_skipNativeBuildEnv: true}),
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
      late Directory extractionDirectory;

      await testCodeBuildHook(
        mainMethod: (args) => build_hook.runBuildHook(
          args,
          environment: const {},
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
            extractionDirectory = destination;
            expect(archive.readAsBytesSync(), archiveBytes);
            final extractedLib = File(
              '${destination.path}/${_releaseBundleName()}/${_defaultLibraryFileName()}',
            );
            extractedLib.parent.createSync(recursive: true);
            extractedLib.writeAsStringSync('client-release-prebuilt');
          },
        ),
        userDefines: _userDefines(
          defines: {
            _releaseTagEnv: 'ct-ffi-v2026.04.22-validation.043206-attest',
            _releaseRepoEnv: 'konsultaner/connectanum-dart',
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
          final cacheSuffix = extractionDirectory.path
              .split(
                '${Platform.pathSeparator}prebuilt${Platform.pathSeparator}',
              )
              .last;
          expect(cacheSuffix.length, lessThanOrEqualTo(40));
          expect(cacheSuffix, isNot(contains('konsultaner_connectanum-dart')));
        },
      );
    });
  });

  test(
    'build hook defaults isolated packages to matching release assets',
    () async {
      final packageRoot = await Directory.systemTemp.createTemp(
        'connectanum_client_hosted_hook_',
      );
      addTearDown(() => packageRoot.delete(recursive: true));
      File('${packageRoot.path}/pubspec.yaml').writeAsStringSync('''
name: connectanum_client
version: 3.0.0-beta.6
environment:
  sdk: ^3.9.2
''');

      final archiveBytes = 'client-hosted-release-archive'.codeUnits;
      final downloaded = <Uri>[];
      await IOOverrides.runZoned(() async {
        await testCodeBuildHook(
          mainMethod: (args) => build_hook.runBuildHook(
            args,
            environment: const {},
            cargoRunner: _unexpectedCargoRunner,
            artifactDownloader:
                ({required source, required destination}) async {
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
              final extractedLib = File(
                '${destination.path}/${_releaseBundleName()}/${_defaultLibraryFileName()}',
              );
              extractedLib.parent.createSync(recursive: true);
              extractedLib.writeAsStringSync('client-hosted-prebuilt');
            },
          ),
          check: (_, output) {
            expect(output.assets.code, hasLength(1));
            expect(
              File.fromUri(output.assets.code.single.file!).readAsStringSync(),
              equals('client-hosted-prebuilt'),
            );
            expect(
              downloaded.map((uri) => uri.toString()),
              contains(
                'https://github.com/konsultaner/connectanum-dart/releases/download/'
                'v3.0.0-beta.6/${_releaseArchiveName()}',
              ),
            );
          },
        );
      }, getCurrentDirectory: () => packageRoot);
    },
  );

  test('source checkout detection recognizes incomplete workspace', () async {
    final checkout = await Directory.systemTemp.createTemp(
      'connectanum_client_incomplete_checkout_',
    );
    addTearDown(() => checkout.delete(recursive: true));
    File('${checkout.path}/pubspec.yaml').writeAsStringSync('''
name: connectanum_workspace
environment:
  sdk: ^3.9.2
''');
    final packageRoot = Directory(
      '${checkout.path}/packages/connectanum_client',
    )..createSync(recursive: true);
    File('${packageRoot.path}/pubspec.yaml').writeAsStringSync('''
name: connectanum_client
version: 3.0.0-beta.6
environment:
  sdk: ^3.9.2
''');

    expect(build_hook.isConnectanumSourceCheckout(packageRoot), isTrue);
  });

  test('hosted release tag derivation rejects malformed versions', () async {
    final packageRoot = await Directory.systemTemp.createTemp(
      'connectanum_client_invalid_version_',
    );
    addTearDown(() => packageRoot.delete(recursive: true));
    File(
      '${packageRoot.path}/pubspec.yaml',
    ).writeAsStringSync('name: connectanum_client\nversion: development\n');

    expect(
      () => build_hook.releaseTagForPackage(packageRoot),
      throwsA(isA<BuildError>()),
    );
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

PackageUserDefines _userDefines({
  Map<String, Object?> defines = const {},
  Uri? basePath,
}) => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: defines,
    basePath: basePath ?? Directory.current.uri,
  ),
);

Future<void> _withPackageRoot(Future<void> Function() body) async {
  final root = await Directory.systemTemp.createTemp('client_hook_package_');
  try {
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: connectanum_client\nversion: 3.0.0-beta.6\n',
    );
    await IOOverrides.runZoned(body, getCurrentDirectory: () => root);
  } finally {
    await root.delete(recursive: true);
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
