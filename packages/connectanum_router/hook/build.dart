import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _nativeLibEnv = 'CONNECTANUM_NATIVE_LIB';
const _skipNativeBuildEnv = 'CONNECTANUM_SKIP_NATIVE_BUILD';

Future<void> main(List<String> args) => runBuildHook(args);

Future<void> runBuildHook(
  List<String> args, {
  Map<String, String>? environment,
  ProcessResult Function({
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  })?
  cargoRunner,
}) async {
  final buildEnvironment = environment ?? Platform.environment;
  final runCargo = cargoRunner ?? _runCargo;
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;
    final supportedHost =
        (targetOS == OS.linux && targetArch == Architecture.x64) ||
        (targetOS == OS.macOS &&
            (targetArch == Architecture.x64 ||
                targetArch == Architecture.arm64));
    if (!supportedHost) {
      // Unsupported hosts should still be able to run pure Dart/browser flows.
      return;
    }

    final transportDir = _findTransportWorkspace(
      Directory.fromUri(input.packageRoot),
    );
    if (transportDir == null) {
      throw BuildError(
        message:
            'Failed to locate native transport workspace. Expected '
            '`native/transport/Cargo.toml` above ${input.packageRoot.toFilePath()}.',
      );
    }

    final dylibName = targetOS.dylibFileName('ct_ffi');
    final outputLibUri = input.outputDirectory.resolve(dylibName);
    final outputLibFile = File.fromUri(outputLibUri);

    final dependencies = _collectTransportDependencies(transportDir);
    final configuredNativeLib = _configuredNativeLibrary(buildEnvironment);
    if (configuredNativeLib != null && !configuredNativeLib.existsSync()) {
      throw BuildError(
        message:
            '$_nativeLibEnv points to ${configuredNativeLib.path}, but that '
            'file does not exist.',
      );
    }
    if (configuredNativeLib != null) {
      dependencies.add(configuredNativeLib);
    }
    output.dependencies.addAll(dependencies.map((e) => e.uri));

    if (_shouldSkipNativeBuild(buildEnvironment) &&
        configuredNativeLib == null) {
      return;
    }

    final latestDependencyChange = _latestModified(dependencies);
    if (outputLibFile.existsSync() &&
        latestDependencyChange != null &&
        outputLibFile.lastModifiedSync().isAfter(latestDependencyChange)) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'ct_ffi.dart',
          linkMode: DynamicLoadingBundled(),
          file: outputLibUri,
        ),
      );
      return;
    }

    if (configuredNativeLib != null) {
      configuredNativeLib.copySync(outputLibFile.path);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'ct_ffi.dart',
          linkMode: DynamicLoadingBundled(),
          file: outputLibUri,
        ),
      );
      return;
    }

    final cargoTargetDir = Directory.fromUri(
      input.outputDirectory.resolve('cargo_target/'),
    );
    cargoTargetDir.createSync(recursive: true);

    final buildEnv = <String, String>{
      ...buildEnvironment,
      'CARGO_TARGET_DIR': cargoTargetDir.path,
    };

    final result = runCargo(
      args: const ['build', '-p', 'ct_ffi', '--release'],
      workingDirectory: transportDir.path,
      environment: buildEnv,
    );
    if (result.exitCode != 0) {
      throw BuildError(
        message:
            'Failed to build ct_ffi (exit ${result.exitCode}).\n'
            'stdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
    }

    final builtLib = File('${cargoTargetDir.path}/release/$dylibName');
    if (!builtLib.existsSync()) {
      throw BuildError(
        message:
            'cargo build succeeded but expected output was not found at '
            '${builtLib.path}.',
      );
    }

    builtLib.copySync(outputLibFile.path);

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'ct_ffi.dart',
        linkMode: DynamicLoadingBundled(),
        file: outputLibUri,
      ),
    );
  });
}

bool _shouldSkipNativeBuild(Map<String, String> environment) =>
    _isTruthy(environment[_skipNativeBuildEnv]);

File? _configuredNativeLibrary(Map<String, String> environment) {
  final configuredPath = environment[_nativeLibEnv];
  if (configuredPath == null || configuredPath.isEmpty) {
    return null;
  }
  return File(configuredPath);
}

bool _isTruthy(String? value) {
  if (value == null) {
    return false;
  }
  switch (value.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
      return true;
    default:
      return false;
  }
}

Directory? _findTransportWorkspace(Directory start) {
  var current = start.absolute;
  for (var depth = 0; depth < 12; depth++) {
    final candidate = File('${current.path}/native/transport/Cargo.toml');
    if (candidate.existsSync()) {
      return candidate.parent;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
  return null;
}

List<File> _collectTransportDependencies(Directory transportDir) {
  final deps = <File>[];
  for (final path in [
    '${transportDir.path}/Cargo.toml',
    '${transportDir.path}/Cargo.lock',
    '${transportDir.path}/ct_core/Cargo.toml',
    '${transportDir.path}/ct_ffi/Cargo.toml',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      deps.add(file);
    }
  }

  for (final dir in [
    Directory('${transportDir.path}/ct_core/src'),
    Directory('${transportDir.path}/ct_ffi/src'),
  ]) {
    if (!dir.existsSync()) {
      continue;
    }
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.rs')) {
        deps.add(entity);
      }
    }
  }
  return deps;
}

DateTime? _latestModified(List<File> files) {
  DateTime? latest;
  for (final file in files) {
    if (!file.existsSync()) {
      continue;
    }
    final modified = file.lastModifiedSync();
    if (latest == null || modified.isAfter(latest)) {
      latest = modified;
    }
  }
  return latest;
}

ProcessResult _runCargo({
  required List<String> args,
  required String workingDirectory,
  required Map<String, String> environment,
}) {
  try {
    return Process.runSync(
      'cargo',
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: true,
    );
  } on ProcessException catch (error, stackTrace) {
    throw InfraError(
      message: 'Failed to invoke cargo: $error',
      wrappedException: error,
      wrappedTrace: stackTrace,
    );
  }
}
