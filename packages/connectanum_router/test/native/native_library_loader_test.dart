@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library native_library_loader_test;

import 'dart:io';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  final skipEnvReason = envOverride != null && envOverride.isNotEmpty
      ? 'CONNECTANUM_NATIVE_LIB is set; resolution is env-driven.'
      : null;

  test('resolvePath prefers hooks_runner artifacts when present', () async {
    final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
    expect(envOverride, anyOf(isNull, isEmpty));
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
    );
    expect(resolved, equals(libFile.path));
  }, skip: skipEnvReason);

  test('resolvePath prefers explicit overridePath', () {
    const override = '/tmp/connectanum_test_override.so';
    expect(NativeLibraryLoader.resolvePath(override), equals(override));
  });
}

String _defaultLibraryFileName() => switch (Platform.operatingSystem) {
  'linux' => 'libct_ffi.so',
  'macos' => 'libct_ffi.dylib',
  'windows' => 'ct_ffi.dll',
  _ => 'libct_ffi.so',
};
