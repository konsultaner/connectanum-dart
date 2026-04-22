@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/install_native.dart' as install_native;
import '../../hook/build.dart' as build_hook;

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
          expect(archive.readAsBytesSync(), archiveBytes);
          final extractedLib = File(
            '${destination.path}/${_releaseBundleName()}/${_defaultLibraryFileName()}',
          );
          extractedLib.parent.createSync(recursive: true);
          extractedLib.writeAsStringSync('router-installed-native');
        },
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
}

String _defaultLibraryFileName() => switch (Platform.operatingSystem) {
  'linux' => 'libct_ffi.so',
  'macos' => 'libct_ffi.dylib',
  'windows' => 'ct_ffi.dll',
  _ => 'libct_ffi.so',
};

String _releaseBundleName() => 'ct-ffi-${build_hook.currentHostTriple()}';

String _releaseArchiveName() => '${_releaseBundleName()}.tar.gz';
