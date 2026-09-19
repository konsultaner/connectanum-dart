@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:connectanum_router/src/native_release_installer.dart'
    as native_installer;

import '../../tool/install_native.dart' as install_native;
import '../../hook/build.dart' as build_hook;
import 'installer_assertions.dart';

void main() {
  test(
    'install_native downloads hosted release assets into default cache',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum_router_install_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final archiveBytes = 'router-install-archive'.codeUnits;
      final downloaded = <Uri>[];

      final installed = await expectValidInstall(
        () => install_native.installNative(
          ['--tag', 'ct-ffi-v2026.04.22-validation.043206-attest'],
          workingDirectory: tempDir,
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
            extractedLib.writeAsStringSync('router-installed-native');
          },
        ),
      );

      expect(
        installed.path,
        equals(
          '${tempDir.path}/.dart_tool/connectanum/native/'
          '${build_hook.currentHostTriple()}/${_defaultLibraryFileName()}',
        ),
      );
      expect(installed.readAsStringSync(), equals('router-installed-native'));
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

  test('release installer extracts inside paths containing spaces', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'connectanum native extraction ',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final releaseAsset = native_installer.ReleaseAssetSpec(
      repository: 'konsultaner/connectanum-dart',
      tag: 'v3.0.0-beta.6',
      hostTriple: build_hook.currentHostTriple(),
    );
    final sourceRoot = Directory('${tempDir.path}/source bundle')
      ..createSync(recursive: true);
    final bundledLibrary = File(
      '${sourceRoot.path}/${releaseAsset.bundleName}/'
      '${_defaultLibraryFileName()}',
    );
    bundledLibrary.parent.createSync(recursive: true);
    bundledLibrary.writeAsStringSync('verified native archive');
    final sourceArchive = File('${tempDir.path}/${releaseAsset.archiveName}');
    final createResult = Process.runSync('tar', [
      '-czf',
      sourceArchive.path,
      '-C',
      sourceRoot.path,
      releaseAsset.bundleName,
    ]);
    expect(createResult.exitCode, isZero, reason: '${createResult.stderr}');
    final sourceChecksum = File('${sourceArchive.path}.sha256')
      ..writeAsStringSync(
        '${sha256.convert(sourceArchive.readAsBytesSync())}  '
        '${releaseAsset.archiveName}',
      );
    final installed = await expectValidInstall(
      () => native_installer.installHostedNativeLibrary(
        tag: releaseAsset.tag,
        installRoot: Directory('${tempDir.path}/installed native'),
        artifactDownloader: ({required source, required destination}) async {
          destination.parent.createSync(recursive: true);
          final sourceFile = source.path.endsWith('.sha256')
              ? sourceChecksum
              : sourceArchive;
          sourceFile.copySync(destination.path);
        },
      ),
    );
    expect(installed.readAsStringSync(), 'verified native archive');
  });

  test('release installer maps every hosted native artifact target', () {
    expect(
      native_installer.hostTripleForPlatform(
        operatingSystem: 'linux',
        architectureLabel: 'x64',
      ),
      equals('x86_64-unknown-linux-gnu'),
    );
    expect(
      native_installer.hostTripleForPlatform(
        operatingSystem: 'linux',
        architectureLabel: 'arm64',
      ),
      equals('aarch64-unknown-linux-gnu'),
    );
    expect(
      native_installer.hostTripleForPlatform(
        operatingSystem: 'macos',
        architectureLabel: 'x64',
      ),
      equals('x86_64-apple-darwin'),
    );
    expect(
      native_installer.hostTripleForPlatform(
        operatingSystem: 'macos',
        architectureLabel: 'arm64',
      ),
      equals('aarch64-apple-darwin'),
    );
    expect(
      native_installer.hostTripleForPlatform(
        operatingSystem: 'windows',
        architectureLabel: 'x64',
      ),
      equals('x86_64-pc-windows-msvc'),
    );
  });

  test('release installer reports unsupported host and architecture', () {
    expect(
      () => native_installer.hostTripleForPlatform(
        operatingSystem: 'windows',
        architectureLabel: 'arm64',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Unsupported install host windows / arm64.'),
        ),
      ),
    );
  });
}

String _defaultLibraryFileName() => switch (Platform.operatingSystem) {
  'linux' => 'libct_ffi.so',
  'macos' => 'libct_ffi.dylib',
  'windows' => 'ct_ffi.dll',
  _ => 'libct_ffi.so',
};

String _releaseBundleName() => 'ct-ffi-${build_hook.currentHostTriple()}';

String _releaseArchiveName() => '${_releaseBundleName()}.tar.gz';
