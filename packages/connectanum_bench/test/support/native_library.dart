import 'dart:io';

/// Canonical CI builds the test-enabled library in target/ffi-test/release.
/// Resolve it explicitly when the benchmark suite clears the environment.
String? nativeBenchTestLibrary() {
  final override = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (override != null && override.isNotEmpty) {
    return File(override).absolute.path;
  }
  final name = switch (Platform.operatingSystem) {
    'macos' => 'libct_ffi.dylib',
    'linux' => 'libct_ffi.so',
    _ => null,
  };
  if (name == null) return null;
  for (final prefix in ['native/transport', '../../native/transport']) {
    for (final target in ['target/ffi-test/release', 'target/release']) {
      final file = File('$prefix/$target/$name');
      if (file.existsSync()) return file.absolute.path;
    }
  }
  return null;
}
