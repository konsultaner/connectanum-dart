import 'dart:io';

Directory? _findRepoRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 10; i++) {
    final candidate = Directory('${dir.path}/native/transport');
    if (candidate.existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return null;
}

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

  final root = _findRepoRoot();
  if (root == null) {
    stderr.writeln(
      'Failed to locate repository root (expected native/transport). '
      'Current directory: ${Directory.current.path}',
    );
    return null;
  }

  final candidates = <String>[
    if (useFfiTest)
      '${root.path}/native/transport/target/ffi-test/release/libct_ffi.so',
    '${root.path}/native/transport/target/release/libct_ffi.so',
  ];

  final existing = _freshestExisting(root, candidates);
  if (existing != null) {
    return existing;
  }

  _buildNativeLib(root, useFfiTest: useFfiTest);
  return _freshestExisting(root, candidates);
}

String? _freshestExisting(Directory root, List<String> candidates) {
  final latestSourceChange = _latestSourceChange(root);
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

DateTime? _latestSourceChange(Directory root) {
  final srcDirs = <Directory>[
    Directory('${root.path}/native/transport/ct_core/src'),
    Directory('${root.path}/native/transport/ct_ffi/src'),
  ];
  final timestamps = <DateTime>[];
  for (final srcDir in srcDirs) {
    if (!srcDir.existsSync()) {
      continue;
    }
    for (final entity in srcDir.listSync(recursive: true)) {
      if (entity is File) {
        timestamps.add(entity.lastModifiedSync());
      }
    }
  }
  for (final file in [
    File('${root.path}/native/transport/Cargo.toml'),
    File('${root.path}/native/transport/Cargo.lock'),
    File('${root.path}/native/transport/ct_core/Cargo.toml'),
    File('${root.path}/native/transport/ct_ffi/Cargo.toml'),
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

void _buildNativeLib(Directory root, {required bool useFfiTest}) {
  final args = <String>['build', '-p', 'ct_ffi', '--release'];
  if (useFfiTest) {
    args.addAll(['--features', 'ffi-test']);
  }
  final environment = <String, String>{...Platform.environment};
  if (useFfiTest) {
    environment['CARGO_TARGET_DIR'] =
        '${root.path}/native/transport/target/ffi-test';
  }
  final result = Process.runSync(
    'cargo',
    args,
    workingDirectory: '${root.path}/native/transport',
    environment: environment,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    stderr.writeln(
      'Failed to build ct_ffi (exit ${result.exitCode}). stdout: ${result.stdout}\n'
      'stderr: ${result.stderr}',
    );
  }
}
