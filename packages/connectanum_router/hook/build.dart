import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _nativeLibEnv = 'CONNECTANUM_NATIVE_LIB';
const _nativeReleaseTagEnv = 'CONNECTANUM_NATIVE_RELEASE_TAG';
const _nativeReleaseRepoEnv = 'CONNECTANUM_NATIVE_RELEASE_REPOSITORY';
const _skipNativeBuildEnv = 'CONNECTANUM_SKIP_NATIVE_BUILD';
const _defaultReleaseRepository = 'konsultaner/connectanum-dart';

typedef _DownloadArtifact =
    Future<void> Function({required Uri source, required File destination});
typedef _ExtractArchive =
    void Function({required File archive, required Directory destination});

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
  _DownloadArtifact? artifactDownloader,
  _ExtractArchive? archiveExtractor,
}) async {
  final buildEnvironment = environment ?? Platform.environment;
  final runCargo = cargoRunner ?? _runCargo;
  final downloadArtifact = artifactDownloader ?? _downloadArtifact;
  final extractArchive = archiveExtractor ?? _extractArchive;
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

    final dylibName = targetOS.dylibFileName('ct_ffi');
    final outputLibUri = input.outputDirectory.resolve(dylibName);
    final outputLibFile = File.fromUri(outputLibUri);

    final configuredNativeLib = _configuredNativeLibrary(buildEnvironment);
    final releaseAsset = _configuredReleaseAsset(
      buildEnvironment,
      targetOS: targetOS,
      targetArch: targetArch,
    );
    if (configuredNativeLib != null && !configuredNativeLib.existsSync()) {
      throw BuildError(
        message:
            '$_nativeLibEnv points to ${configuredNativeLib.path}, but that '
            'file does not exist.',
      );
    }

    final dependencies = <File>[];
    if (configuredNativeLib != null) {
      dependencies.add(configuredNativeLib);
    }

    Directory? transportDir;
    if (releaseAsset == null &&
        configuredNativeLib == null &&
        !_shouldSkipNativeBuild(buildEnvironment)) {
      transportDir = _findTransportWorkspace(
        Directory.fromUri(input.packageRoot),
      );
      if (transportDir == null) {
        throw BuildError(
          message:
              'Failed to locate native transport workspace. Expected '
              '`native/transport/Cargo.toml` above ${input.packageRoot.toFilePath()}.',
        );
      }
      dependencies.addAll(_collectTransportDependencies(transportDir));
    }

    output.dependencies.addAll(dependencies.map((e) => e.uri));

    if (releaseAsset != null) {
      await _installReleaseAsset(
        releaseAsset: releaseAsset,
        outputLibFile: outputLibFile,
        bundledLibName: dylibName,
        downloadArtifact: downloadArtifact,
        extractArchive: extractArchive,
      );
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

    transportDir ??= _findTransportWorkspace(
      Directory.fromUri(input.packageRoot),
    );
    if (transportDir == null) {
      throw BuildError(
        message:
            'Failed to locate native transport workspace. Expected '
            '`native/transport/Cargo.toml` above ${input.packageRoot.toFilePath()}.',
      );
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

_ReleaseAssetSpec? _configuredReleaseAsset(
  Map<String, String> environment, {
  required OS targetOS,
  required Architecture targetArch,
}) {
  final tag = environment[_nativeReleaseTagEnv]?.trim();
  if (tag == null || tag.isEmpty) {
    return null;
  }

  final repository =
      environment[_nativeReleaseRepoEnv]?.trim().isNotEmpty == true
      ? environment[_nativeReleaseRepoEnv]!.trim()
      : _defaultReleaseRepository;

  return _ReleaseAssetSpec(
    repository: repository,
    tag: tag,
    hostTriple: _hostTriple(targetOS: targetOS, targetArch: targetArch),
  );
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

Future<void> _installReleaseAsset({
  required _ReleaseAssetSpec releaseAsset,
  required File outputLibFile,
  required String bundledLibName,
  required _DownloadArtifact downloadArtifact,
  required _ExtractArchive extractArchive,
}) async {
  final cacheRoot = Directory(
    '${outputLibFile.parent.path}/prebuilt/'
    '${_sanitizePathComponent(releaseAsset.repository)}/'
    '${_sanitizePathComponent(releaseAsset.tag)}/'
    '${releaseAsset.hostTriple}',
  );
  cacheRoot.createSync(recursive: true);

  final archiveFile = File('${cacheRoot.path}/${releaseAsset.archiveName}');
  final checksumFile = File('${archiveFile.path}.sha256');
  final extractDir = Directory('${cacheRoot.path}/extract');
  final extractedLib = File(
    '${extractDir.path}/${releaseAsset.bundleName}/$bundledLibName',
  );

  if (!archiveFile.existsSync()) {
    await downloadArtifact(
      source: releaseAsset.archiveUri,
      destination: archiveFile,
    );
  }
  if (!checksumFile.existsSync()) {
    await downloadArtifact(
      source: releaseAsset.checksumUri,
      destination: checksumFile,
    );
  }

  _verifyDownloadedArchive(archiveFile, checksumFile);

  if (!extractedLib.existsSync()) {
    if (extractDir.existsSync()) {
      extractDir.deleteSync(recursive: true);
    }
    extractDir.createSync(recursive: true);
    extractArchive(archive: archiveFile, destination: extractDir);
  }

  if (!extractedLib.existsSync()) {
    throw BuildError(
      message:
          'Downloaded ${releaseAsset.archiveName}, but the expected native '
          'library was not found at ${extractedLib.path}.',
    );
  }

  outputLibFile.parent.createSync(recursive: true);
  extractedLib.copySync(outputLibFile.path);
}

void _verifyDownloadedArchive(File archiveFile, File checksumFile) {
  final checksumLine = checksumFile.readAsStringSync().trim();
  if (checksumLine.isEmpty) {
    throw BuildError(
      message:
          'Downloaded checksum file ${checksumFile.path} was empty for '
          '${archiveFile.path}.',
    );
  }

  final expectedDigest = checksumLine.split(RegExp(r'\s+')).first.toLowerCase();
  final actualDigest = sha256.convert(archiveFile.readAsBytesSync()).toString();
  if (actualDigest != expectedDigest) {
    throw BuildError(
      message:
          'Checksum verification failed for ${archiveFile.path}. Expected '
          '$expectedDigest but computed $actualDigest.',
    );
  }
}

String _hostTriple({required OS targetOS, required Architecture targetArch}) {
  return switch ((targetOS, targetArch)) {
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    _ => throw StateError(
      'Unsupported release host combination: $targetOS / $targetArch',
    ),
  };
}

String _sanitizePathComponent(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

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

Future<void> _downloadArtifact({
  required Uri source,
  required File destination,
}) async {
  destination.parent.createSync(recursive: true);

  final client = HttpClient();
  try {
    final request = await client.getUrl(source);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw BuildError(
        message:
            'Failed to download $source (HTTP ${response.statusCode} '
            '${response.reasonPhrase ?? ''}).',
      );
    }

    final sink = destination.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
  } finally {
    client.close(force: true);
  }
}

void _extractArchive({required File archive, required Directory destination}) {
  final result = Process.runSync('tar', [
    '-xzf',
    archive.path,
    '-C',
    destination.path,
  ], runInShell: true);
  if (result.exitCode != 0) {
    throw BuildError(
      message:
          'Failed to extract ${archive.path} (exit ${result.exitCode}).\n'
          'stdout:\n${result.stdout}\n'
          'stderr:\n${result.stderr}',
    );
  }
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

final class _ReleaseAssetSpec {
  const _ReleaseAssetSpec({
    required this.repository,
    required this.tag,
    required this.hostTriple,
  });

  final String repository;
  final String tag;
  final String hostTriple;

  String get bundleName => 'ct-ffi-$hostTriple';
  String get archiveName => '$bundleName.tar.gz';

  Uri get archiveUri => Uri.https(
    'github.com',
    '/$repository/releases/download/$tag/$archiveName',
  );

  Uri get checksumUri => Uri.https(
    'github.com',
    '/$repository/releases/download/$tag/${archiveName}.sha256',
  );
}
