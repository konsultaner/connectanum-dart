@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:connectanum_client/src/native_release_installer.dart'
    as native_installer;

import '../../tool/install_native.dart' as install_native;
import '../../hook/build.dart' as build_hook;

void main() {
  test(
    'install_native downloads hosted release assets into default cache',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum_client_install_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final archiveBytes = 'client-install-archive'.codeUnits;
      final downloaded = <Uri>[];
      late Directory extractionDirectory;

      final installed = await install_native.installNative(
        ['--tag', 'ct-ffi-v2026.04.22-validation.043206-attest'],
        workingDirectory: tempDir,
        artifactDownloader: ({required source, required destination}) async {
          downloaded.add(source);
          destination.parent.createSync(recursive: true);
          if (destination.path.endsWith('.sha256')) {
            final digest = sha256.convert(archiveBytes).toString();
            destination.writeAsStringSync('$digest  ${_releaseArchiveName()}');
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
          extractedLib.writeAsStringSync('client-installed-native');
        },
      );

      expect(
        installed.path,
        equals(
          '${tempDir.path}/.dart_tool/connectanum/native/'
          '${build_hook.currentHostTriple()}/${_defaultLibraryFileName()}',
        ),
      );
      expect(installed.readAsStringSync(), equals('client-installed-native'));
      final cacheSuffix = extractionDirectory.path
          .split(
            '${Platform.pathSeparator}prebuilt${Platform.pathSeparator}',
          )
          .last;
      expect(cacheSuffix.length, lessThanOrEqualTo(40));
      expect(cacheSuffix, isNot(contains('konsultaner_connectanum-dart')));
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

  test('release cache identity isolates tags with a bounded digest', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'connectanum_client_release_cache_',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final archivePaths = <String>[];

    Future<void> install(String tag) async {
      final releaseAsset = native_installer.ReleaseAssetSpec(
        repository: 'konsultaner/connectanum-dart',
        tag: tag,
        hostTriple: build_hook.currentHostTriple(),
      );
      final archiveBytes = tag.codeUnits;
      await native_installer.installReleaseAsset(
        releaseAsset: releaseAsset,
        outputLibFile: File(
          '${tempDir.path}/installed/${_defaultLibraryFileName()}',
        ),
        bundledLibName: _defaultLibraryFileName(),
        downloadArtifact: ({required source, required destination}) async {
          destination.parent.createSync(recursive: true);
          if (destination.path.endsWith('.sha256')) {
            final digest = sha256.convert(archiveBytes).toString();
            destination.writeAsStringSync(
              '$digest  ${releaseAsset.archiveName}',
            );
          } else {
            archivePaths.add(destination.path);
            destination.writeAsBytesSync(archiveBytes);
          }
        },
        extractArchive: ({required archive, required destination}) {
          final extractedLib = File(
            '${destination.path}/${releaseAsset.bundleName}/'
            '${_defaultLibraryFileName()}',
          );
          extractedLib.parent.createSync(recursive: true);
          extractedLib.writeAsStringSync(tag);
        },
      );
    }

    await install('v3.0.0-beta.2');
    await install('v3.0.0-beta.3');

    expect(archivePaths, hasLength(2));
    final cacheKeys = archivePaths
        .map(
          (path) => File(path).parent.path.split(Platform.pathSeparator).last,
        )
        .toSet();
    expect(cacheKeys, hasLength(2));
    expect(
      cacheKeys,
      everyElement(matches(RegExp(r'^[0-9a-f]{32}$'))),
    );
  });

  test('tar extraction keeps Windows drive paths out of operands', () {
    final archive = File(
      'D:/a/connectanum-dart/cache/ct-ffi-x86_64-pc-windows-msvc.tar.gz',
    );
    final destination = Directory('D:/a/connectanum-dart/cache/extract');

    final invocations = [
      native_installer.tarExtractionInvocation(
        archive: archive,
        destination: destination,
      ),
      build_hook.tarExtractionInvocation(
        archive: archive,
        destination: destination,
      ),
    ];

    for (final invocation in invocations) {
      expect(
        invocation.arguments,
        equals([
          '-xzf',
          'ct-ffi-x86_64-pc-windows-msvc.tar.gz',
          '-C',
          'extract',
        ]),
      );
      expect(invocation.arguments.join(' '), isNot(contains('D:')));
      expect(invocation.workingDirectory, equals(archive.parent.path));
    }
  });

  test('tar extraction keeps Unix absolute paths out of operands', () {
    final archive = File('/tmp/connectanum/cache/ct-ffi.tar.gz');
    final destination = Directory('/tmp/connectanum/cache/extract/');

    final invocation = native_installer.tarExtractionInvocation(
      archive: archive,
      destination: destination,
    );

    expect(
      invocation.arguments,
      equals(['-xzf', 'ct-ffi.tar.gz', '-C', 'extract']),
    );
    expect(invocation.workingDirectory, equals('/tmp/connectanum/cache'));
  });

  test('tar extraction rejects non-sibling destinations', () {
    final archive = File('/tmp/connectanum/archive/ct-ffi.tar.gz');
    final destination = Directory('/tmp/connectanum/output/extract');

    for (final invocationBuilder in [
      native_installer.tarExtractionInvocation,
      build_hook.tarExtractionInvocation,
    ]) {
      expect(
        () => invocationBuilder(
          archive: archive,
          destination: destination,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Archive and extraction destination must share a parent directory.',
          ),
        ),
      );
    }
  });

  test('release installer extracts inside paths containing spaces', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'connectanum native extraction ',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final releaseAsset = native_installer.ReleaseAssetSpec(
      repository: 'konsultaner/connectanum-dart',
      tag: 'v3.0.0-beta.5',
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
    final sourceArchive = File(
      '${tempDir.path}/${releaseAsset.archiveName}',
    );
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

    final installed = await native_installer.installHostedNativeLibrary(
      tag: releaseAsset.tag,
      installRoot: Directory('${tempDir.path}/installed native'),
      artifactDownloader: ({required source, required destination}) async {
        destination.parent.createSync(recursive: true);
        final sourceFile = source.path.endsWith('.sha256')
            ? sourceChecksum
            : sourceArchive;
        sourceFile.copySync(destination.path);
      },
    );

    expect(installed.readAsStringSync(), equals('verified native archive'));
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
