@TestOn('vm')
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as build_hook;

void main() {
  test('build hook reuses CONNECTANUM_NATIVE_LIB without invoking cargo', () {
    return _withPackageRoot(() async {
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum_router_hook_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final prebuiltLibrary = File(
        '${tempDir.path}/${_defaultLibraryFileName()}',
      )..writeAsStringSync('router-prebuilt');

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
          expect(
            asset.file!.pathSegments.last,
            equals(_defaultLibraryFileName()),
          );
          expect(
            File.fromUri(asset.file!).readAsStringSync(),
            equals('router-prebuilt'),
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
}

const _nativeLibEnv = 'CONNECTANUM_NATIVE_LIB';
const _skipNativeBuildEnv = 'CONNECTANUM_SKIP_NATIVE_BUILD';

ProcessResult _unexpectedCargoRunner({
  required List<String> args,
  required String workingDirectory,
  required Map<String, String> environment,
}) => throw StateError('cargo should not be invoked in this test');

Future<void> _withPackageRoot(Future<void> Function() body) async {
  final original = Directory.current;
  Directory.current = _locatePackageRoot('connectanum_router');
  try {
    await body();
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

String _defaultLibraryFileName() => switch (Platform.operatingSystem) {
  'linux' => 'libct_ffi.so',
  'macos' => 'libct_ffi.dylib',
  'windows' => 'ct_ffi.dll',
  _ => 'libct_ffi.so',
};
