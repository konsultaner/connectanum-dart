@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:test/test.dart';

void main() {
  final envOverride = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  final skipEnvReason = envOverride != null && envOverride.isNotEmpty
      ? 'CONNECTANUM_NATIVE_LIB is set; resolution is env-driven.'
      : null;

  test('resolvePath prefers hooks_runner artifacts when present', () async {
    final temp = await Directory.systemTemp.createTemp(
      'connectanum_client_native_loader_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final hookLibrary = File(
      '${temp.path}/.dart_tool/hooks_runner/shared/connectanum_client/build/'
      'test-config/${_hookLibraryFileName()}',
    );
    hookLibrary.parent.createSync(recursive: true);
    hookLibrary.writeAsStringSync('not-a-real-dylib');

    final original = Directory.current;
    Directory.current = temp;
    addTearDown(() => Directory.current = original);

    final resolved = NativeLibraryLoader.resolvePath();
    expect(
      File(resolved).resolveSymbolicLinksSync(),
      equals(hookLibrary.resolveSymbolicLinksSync()),
    );
  }, skip: skipEnvReason);

  test('resolvePath prefers explicit overridePath', () {
    const override = '/tmp/connectanum_client_test_override.so';
    expect(NativeLibraryLoader.resolvePath(override), equals(override));
  });

  test(
    'resolvePath falls back to bare library name for system installs',
    () {
      final original = Directory.current;
      final temp = Directory.systemTemp.createTempSync(
        'connectanum_client_native_loader_empty_',
      );
      addTearDown(() {
        Directory.current = original;
        temp.deleteSync(recursive: true);
      });
      Directory.current = temp;

      expect(
        NativeLibraryLoader.resolvePath(),
        equals(_defaultLibraryFileName()),
      );
    },
    skip: skipEnvReason,
  );
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
