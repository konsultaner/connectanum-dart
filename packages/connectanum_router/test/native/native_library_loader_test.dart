@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library native_library_loader_test;

import 'dart:io';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  test('resolvePath prefers hooks_runner artifacts when present', () async {
    final temp = await Directory.systemTemp.createTemp(
      'connectanum_native_loader_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final libName = _defaultLibraryFileName();
    final libFile = File(
      '${temp.path}/.dart_tool/hooks_runner/shared/connectanum_router/build/'
      'test-config/$libName',
    );
    libFile.parent.createSync(recursive: true);
    libFile.writeAsStringSync('not-a-real-dylib');

    final resolved = NativeLibraryLoader.resolvePath(
      null,
      currentDirectory: temp,
      ignoreEnvironmentOverride: true,
    );
    expect(resolved, equals(libFile.path));
  });

  test('resolvePath prefers explicit overridePath', () {
    const override = '/tmp/connectanum_test_override.so';
    expect(NativeLibraryLoader.resolvePath(override), equals(override));
  });

  test('resolvePath bounds hook ancestor search from both directory roots', () {
    final temp = Directory.systemTemp.createTempSync('native-loader-depth-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final artifact = File(
      '${temp.path}/.dart_tool/hooks_runner/shared/connectanum_router/build/'
      'root/${_defaultLibraryFileName()}',
    );
    artifact.parent.createSync(recursive: true);
    artifact.writeAsStringSync('path selection only');
    var nested = temp;
    for (var depth = 1; depth <= 9; depth++) {
      nested = Directory('${nested.path}/level$depth')..createSync();
      if (depth < 8) continue;
      final resolved = NativeLibraryLoader.resolvePath(
        null,
        currentDirectory: nested,
        ignoreEnvironmentOverride: true,
      );
      expect(
        resolved,
        depth == 8 ? artifact.path : isNot(artifact.path),
        reason: 'cwd.parent extends the eight-directory search by one level',
      );
    }
  });

  test('resolvePath selects freshest complete hook artifact across builds', () {
    final temp = Directory.systemTemp.createTempSync('native-loader-builds-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final build = Directory(
      '${temp.path}/.dart_tool/hooks_runner/shared/connectanum_router/build',
    )..createSync(recursive: true);
    File('${build.path}/not-a-config').writeAsStringSync('ignore');
    Directory('${build.path}/incomplete').createSync();
    final artifacts = [
      for (final config in ['first', 'second', 'third'])
        File('${build.path}/$config/${_defaultLibraryFileName()}'),
    ];
    for (final artifact in artifacts) {
      artifact.parent.createSync();
      artifact.writeAsStringSync('path selection only; never loaded');
      artifact.setLastModifiedSync(DateTime.utc(2020));
    }
    final nested = Directory('${temp.path}/consumer/nested')
      ..createSync(recursive: true);
    expect(
      () => NativeLibraryLoader.resolvePath(
        null,
        currentDirectory: nested,
        ignoreEnvironmentOverride: true,
      ),
      returnsNormally,
      reason: 'missing nearer build directories must not abort discovery',
    );
    for (final newest in artifacts.reversed) {
      for (final artifact in artifacts) {
        artifact.setLastModifiedSync(
          DateTime.utc(artifact == newest ? 2022 : 2020),
        );
      }
      expect(
        NativeLibraryLoader.resolvePath(
          '',
          currentDirectory: nested,
          ignoreEnvironmentOverride: true,
        ),
        newest.path,
        reason: 'selection must follow timestamps, not config listing order',
      );
    }
  });

  test(
    'resolvePath skips empty nearer hook builds and prefers local recovery',
    () {
      final temp = Directory.systemTemp.createTempSync(
        'native-loader-ancestor-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      File artifact(Directory root, String config) {
        final file = File(
          '${root.path}/.dart_tool/hooks_runner/shared/connectanum_router/build/'
          '$config/${_defaultLibraryFileName()}',
        );
        file.parent.createSync(recursive: true);
        return file;
      }

      final parentArtifact = artifact(temp, 'parent')
        ..writeAsStringSync('parent');
      final nested = Directory('${temp.path}/consumer/nested')
        ..createSync(recursive: true);
      final localArtifact = artifact(nested, 'local');
      artifact(nested.parent, 'incomplete-parent');
      String resolve() => NativeLibraryLoader.resolvePath(
        null,
        currentDirectory: nested,
        ignoreEnvironmentOverride: true,
      );
      expect(resolve(), parentArtifact.path);
      localArtifact.writeAsStringSync('local');
      localArtifact.setLastModifiedSync(DateTime.utc(2000));
      parentArtifact.setLastModifiedSync(DateTime.utc(2022));
      expect(
        resolve(),
        localArtifact.path,
        reason: 'nearest workspace wins before comparing build timestamps',
      );
      localArtifact.deleteSync();
      expect(
        resolve(),
        parentArtifact.path,
        reason: 'deleted builds must not leave a stale cached path',
      );
    },
  );

  test(
    'resolvePath does not follow linked hook configuration directories',
    () {
      final temp = Directory.systemTemp.createTempSync('native-loader-links-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final build = Directory(
        '${temp.path}/.dart_tool/hooks_runner/shared/connectanum_router/build',
      )..createSync(recursive: true);
      final local = File('${build.path}/local/${_defaultLibraryFileName()}');
      local.parent.createSync();
      local.writeAsStringSync('local');
      local.setLastModifiedSync(DateTime.utc(2000));
      final external = File(
        '${temp.path}/external/${_defaultLibraryFileName()}',
      );
      external.parent.createSync();
      external.writeAsStringSync('external');
      external.setLastModifiedSync(DateTime.utc(2022));
      Link('${build.path}/linked').createSync(external.parent.path);
      expect(
        NativeLibraryLoader.resolvePath(
          null,
          currentDirectory: temp,
          ignoreEnvironmentOverride: true,
        ),
        local.path,
      );
    },
    skip: Platform.isWindows ? 'Creating symlinks requires privileges' : false,
  );
}

String _defaultLibraryFileName() => switch (Platform.operatingSystem) {
  'linux' => 'libct_ffi.so',
  'macos' => 'libct_ffi.dylib',
  'windows' => 'ct_ffi.dll',
  _ => 'libct_ffi.so',
};
