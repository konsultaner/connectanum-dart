import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const nativeLibEnv = 'CONNECTANUM_NATIVE_LIB';
const nativeReleaseTagEnv = 'CONNECTANUM_NATIVE_RELEASE_TAG';
const nativeReleaseRepoEnv = 'CONNECTANUM_NATIVE_RELEASE_REPOSITORY';
const skipNativeBuildEnv = 'CONNECTANUM_SKIP_NATIVE_BUILD';
const defaultReleaseRepository = 'konsultaner/connectanum-dart';

typedef DownloadArtifact =
    Future<void> Function({required Uri source, required File destination});
typedef ExtractArchive =
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
  DownloadArtifact? artifactDownloader,
  ExtractArchive? archiveExtractor,
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
        (targetOS == OS.linux &&
            (targetArch == Architecture.x64 ||
                targetArch == Architecture.arm64)) ||
        (targetOS == OS.macOS &&
            (targetArch == Architecture.x64 ||
                targetArch == Architecture.arm64)) ||
        (targetOS == OS.windows && targetArch == Architecture.x64);
    if (!supportedHost) {
      // Unsupported hosts should still be able to run pure Dart/browser flows.
      return;
    }

    final dylibName = targetOS.dylibFileName('ct_ffi');
    final outputLibUri = input.outputDirectory.resolve(dylibName);
    final outputLibFile = File.fromUri(outputLibUri);
    final hookSettings = _hookSettingsFor(input, buildEnvironment);
    final configuredNativeLib = _configuredNativeLibrary(hookSettings);
    final releaseAsset = _configuredReleaseAsset(
      hookSettings,
      targetOS: targetOS,
      targetArch: targetArch,
    );
    if (configuredNativeLib != null && !configuredNativeLib.existsSync()) {
      throw BuildError(
        message:
            '$nativeLibEnv points to ${configuredNativeLib.path}, but that '
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
        !_shouldSkipNativeBuild(hookSettings)) {
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
      await installReleaseAsset(
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

    if (_shouldSkipNativeBuild(hookSettings) && configuredNativeLib == null) {
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

final class _BuildHookSettings {
  const _BuildHookSettings({
    required this.nativeLibPath,
    required this.nativeReleaseTag,
    required this.nativeReleaseRepository,
    required this.skipNativeBuild,
  });

  final String? nativeLibPath;
  final String? nativeReleaseTag;
  final String? nativeReleaseRepository;
  final bool skipNativeBuild;
}

_BuildHookSettings _hookSettingsFor(
  BuildInput input,
  Map<String, String> environment,
) {
  final userDefines = input.userDefines;
  return _BuildHookSettings(
    nativeLibPath:
        _pathUserDefine(userDefines, nativeLibEnv) ??
        _stringEnvironment(environment, nativeLibEnv),
    nativeReleaseTag:
        _stringUserDefine(userDefines, nativeReleaseTagEnv) ??
        _stringEnvironment(environment, nativeReleaseTagEnv),
    nativeReleaseRepository:
        _stringUserDefine(userDefines, nativeReleaseRepoEnv) ??
        _stringEnvironment(environment, nativeReleaseRepoEnv),
    skipNativeBuild:
        _boolUserDefine(userDefines, skipNativeBuildEnv) ??
        _isTruthy(environment[skipNativeBuildEnv]),
  );
}

String? _pathUserDefine(HookInputUserDefines userDefines, String key) {
  final raw = _stringUserDefine(userDefines, key);
  if (raw == null) {
    return null;
  }
  return userDefines.path(key)?.toFilePath() ?? raw;
}

String? _stringUserDefine(HookInputUserDefines userDefines, String key) {
  final value = userDefines[key];
  if (value == null) {
    return null;
  }
  final string = value is String ? value : value.toString();
  final trimmed = string.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool? _boolUserDefine(HookInputUserDefines userDefines, String key) {
  final value = userDefines[key];
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  return _isTruthy(value.toString());
}

String? _stringEnvironment(Map<String, String> environment, String key) {
  final value = environment[key]?.trim();
  return value == null || value.isEmpty ? null : value;
}

bool _shouldSkipNativeBuild(_BuildHookSettings settings) =>
    settings.skipNativeBuild;

File? _configuredNativeLibrary(_BuildHookSettings settings) {
  final configuredPath = settings.nativeLibPath;
  if (configuredPath == null || configuredPath.isEmpty) {
    return null;
  }
  return File(configuredPath);
}

ReleaseAssetSpec? _configuredReleaseAsset(
  _BuildHookSettings settings, {
  required OS targetOS,
  required Architecture targetArch,
}) {
  final tag = settings.nativeReleaseTag;
  if (tag == null || tag.isEmpty) {
    return null;
  }

  final repository =
      settings.nativeReleaseRepository ?? defaultReleaseRepository;

  return ReleaseAssetSpec(
    repository: repository,
    tag: tag,
    hostTriple: hostTripleForTarget(targetOS: targetOS, targetArch: targetArch),
  );
}

Directory defaultInstalledNativeLibraryDirectory({
  required String hostTriple,
  Directory? workingDirectory,
}) => Directory(
  '${(workingDirectory ?? Directory.current).path}/.dart_tool/connectanum/native/$hostTriple',
);

File installedNativeLibraryPath({
  required String hostTriple,
  required String bundledLibName,
  Directory? workingDirectory,
}) => File(
  '${defaultInstalledNativeLibraryDirectory(hostTriple: hostTriple, workingDirectory: workingDirectory).path}/$bundledLibName',
);

File? installedNativeLibrary({
  required String hostTriple,
  required String bundledLibName,
  Directory? workingDirectory,
}) {
  final library = installedNativeLibraryPath(
    hostTriple: hostTriple,
    bundledLibName: bundledLibName,
    workingDirectory: workingDirectory,
  );
  return library.existsSync() ? library : null;
}

Future<File> installHostedNativeLibrary({
  required String tag,
  String? repository,
  Directory? installRoot,
  DownloadArtifact? artifactDownloader,
  ExtractArchive? archiveExtractor,
}) async {
  final releaseAsset = ReleaseAssetSpec(
    repository: repository?.trim().isNotEmpty == true
        ? repository!.trim()
        : defaultReleaseRepository,
    tag: tag.trim(),
    hostTriple: currentHostTriple(),
  );
  final outputDirectory =
      installRoot ??
      defaultInstalledNativeLibraryDirectory(
        hostTriple: releaseAsset.hostTriple,
      );
  final bundledLibName = currentPlatformLibraryFileName('ct_ffi');
  final outputLibFile = File('${outputDirectory.path}/$bundledLibName');
  await installReleaseAsset(
    releaseAsset: releaseAsset,
    outputLibFile: outputLibFile,
    bundledLibName: bundledLibName,
    downloadArtifact: artifactDownloader ?? _downloadArtifact,
    extractArchive: archiveExtractor ?? _extractArchive,
  );
  return outputLibFile;
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

Future<void> installReleaseAsset({
  required ReleaseAssetSpec releaseAsset,
  required File outputLibFile,
  required String bundledLibName,
  required DownloadArtifact downloadArtifact,
  required ExtractArchive extractArchive,
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

String hostTripleForTarget({
  required OS targetOS,
  required Architecture targetArch,
}) {
  return switch ((targetOS, targetArch)) {
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    _ => throw StateError(
      'Unsupported release host combination: $targetOS / $targetArch',
    ),
  };
}

String currentHostTriple() {
  final arch = _currentArchitectureLabel();
  return switch ((Platform.operatingSystem, arch)) {
    ('linux', 'x64') => 'x86_64-unknown-linux-gnu',
    ('linux', 'arm64') => 'aarch64-unknown-linux-gnu',
    ('macos', 'x64') => 'x86_64-apple-darwin',
    ('macos', 'arm64') => 'aarch64-apple-darwin',
    ('windows', 'x64') => 'x86_64-pc-windows-msvc',
    _ => throw StateError(
      'Unsupported install host ${Platform.operatingSystem} / $arch.',
    ),
  };
}

String currentPlatformLibraryFileName(String libraryBaseName) =>
    switch (Platform.operatingSystem) {
      'linux' => 'lib$libraryBaseName.so',
      'macos' => 'lib$libraryBaseName.dylib',
      'windows' => '$libraryBaseName.dll',
      _ => throw StateError(
        'Unsupported install host ${Platform.operatingSystem}.',
      ),
    };

String _sanitizePathComponent(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

String _currentArchitectureLabel() {
  if (Platform.version.contains('arm64') ||
      Platform.version.contains('aarch64')) {
    return 'arm64';
  }
  return 'x64';
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
            '${response.reasonPhrase}).',
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

final class ReleaseAssetSpec {
  const ReleaseAssetSpec({
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
    '/$repository/releases/download/$tag/$archiveName.sha256',
  );
}
