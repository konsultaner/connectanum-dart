import 'dart:io';

import 'package:crypto/crypto.dart';

const nativeReleaseTagEnv = 'CONNECTANUM_NATIVE_RELEASE_TAG';
const nativeReleaseRepoEnv = 'CONNECTANUM_NATIVE_RELEASE_REPOSITORY';
const defaultReleaseRepository = 'konsultaner/connectanum-dart';

typedef DownloadArtifact =
    Future<void> Function({required Uri source, required File destination});
typedef ExtractArchive =
    void Function({required File archive, required Directory destination});

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

Directory defaultInstalledNativeLibraryDirectory({
  required String hostTriple,
  Directory? workingDirectory,
}) => Directory(
  '${(workingDirectory ?? Directory.current).path}/.dart_tool/connectanum/native/$hostTriple',
);

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
    throw StateError(
      'Downloaded ${releaseAsset.archiveName}, but the expected native '
      'library was not found at ${extractedLib.path}.',
    );
  }

  outputLibFile.parent.createSync(recursive: true);
  extractedLib.copySync(outputLibFile.path);
}

String currentHostTriple() => switch (Platform.operatingSystem) {
  'linux' => 'x86_64-unknown-linux-gnu',
  'macos' =>
    _currentArchitectureLabel() == 'arm64'
        ? 'aarch64-apple-darwin'
        : 'x86_64-apple-darwin',
  _ => throw StateError(
    'Unsupported install host ${Platform.operatingSystem}.',
  ),
};

String currentPlatformLibraryFileName(String libraryBaseName) =>
    switch (Platform.operatingSystem) {
      'linux' => 'lib$libraryBaseName.so',
      'macos' => 'lib$libraryBaseName.dylib',
      'windows' => '$libraryBaseName.dll',
      _ => throw StateError(
        'Unsupported install host ${Platform.operatingSystem}.',
      ),
    };

String _currentArchitectureLabel() {
  if (Platform.operatingSystem != 'macos') {
    return 'x64';
  }
  if (Platform.version.contains('arm64')) {
    return 'arm64';
  }
  return 'x64';
}

String _sanitizePathComponent(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

void _verifyDownloadedArchive(File archiveFile, File checksumFile) {
  final checksumLine = checksumFile.readAsStringSync().trim();
  if (checksumLine.isEmpty) {
    throw StateError(
      'Downloaded checksum file ${checksumFile.path} was empty for '
      '${archiveFile.path}.',
    );
  }

  final expectedDigest = checksumLine.split(RegExp(r'\s+')).first.toLowerCase();
  final actualDigest = sha256.convert(archiveFile.readAsBytesSync()).toString();
  if (actualDigest != expectedDigest) {
    throw StateError(
      'Checksum verification failed for ${archiveFile.path}. Expected '
      '$expectedDigest but computed $actualDigest.',
    );
  }
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
      throw StateError(
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
    throw StateError(
      'Failed to extract ${archive.path} (exit ${result.exitCode}).\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }
}
