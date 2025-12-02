import 'dart:io';

/// Resolve (and optionally build) the native `ct_ffi` library so integration
/// tests run against a fresh artifact.
///
/// Resolution order:
/// 1. `CONNECTANUM_NATIVE_LIB` if it exists.
/// 2. Existing artifacts under `native/transport/target`.
/// 3. Build via `cargo build -p ct_ffi --release` (with `--features ffi-test`)
///    when no fresh artifact is found.
String? resolveOrBuildNativeLib({bool useFfiTest = true}) {
  final env = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (env != null && File(env).existsSync()) {
    return env;
  }

  final candidates = <String>[
    if (useFfiTest) 'native/transport/target/ffi-test/release/libct_ffi.so',
    'native/transport/target/release/libct_ffi.so',
    if (useFfiTest) 'native/transport/target/ffi-test/debug/libct_ffi.so',
    'native/transport/target/debug/libct_ffi.so',
  ];

  final existing = _freshestExisting(candidates);
  if (existing != null) {
    return existing;
  }

  _buildNativeLib(useFfiTest: useFfiTest);
  return _freshestExisting(candidates);
}

String? _freshestExisting(List<String> candidates) {
  final latestSourceChange = _latestSourceChange();
  File? freshest;
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    if (freshest == null ||
        file.lastModifiedSync().isAfter(freshest.lastModifiedSync())) {
      freshest = file;
    }
  }
  if (freshest == null) {
    return null;
  }
  if (latestSourceChange != null &&
      latestSourceChange.isAfter(freshest.lastModifiedSync())) {
    return null;
  }
  return freshest.path;
}

DateTime? _latestSourceChange() {
  final srcDir = Directory('native/transport/src');
  if (!srcDir.existsSync()) {
    return null;
  }
  final timestamps = <DateTime>[];
  for (final entity in srcDir.listSync(recursive: true)) {
    if (entity is File) {
      timestamps.add(entity.lastModifiedSync());
    }
  }
  for (final file in [
    File('native/transport/Cargo.toml'),
    File('native/transport/Cargo.lock'),
  ]) {
    if (file.existsSync()) {
      timestamps.add(file.lastModifiedSync());
    }
  }
  if (timestamps.isEmpty) {
    return null;
  }
  timestamps.sort();
  return timestamps.last;
}

void _buildNativeLib({required bool useFfiTest}) {
  final args = <String>['build', '-p', 'ct_ffi', '--release'];
  if (useFfiTest) {
    args.addAll(['--features', 'ffi-test']);
  }
  final result = Process.runSync(
    'cargo',
    args,
    workingDirectory: 'native/transport',
    runInShell: true,
  );
  if (result.exitCode != 0) {
    stderr.writeln(
      'Failed to build ct_ffi (exit ${result.exitCode}). stdout: ${result.stdout}\n'
      'stderr: ${result.stderr}',
    );
  }
}
