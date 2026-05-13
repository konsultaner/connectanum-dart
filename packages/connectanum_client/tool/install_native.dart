import 'dart:io';

import 'package:connectanum_client/src/native_release_installer.dart'
    as native_build;

Future<void> main(List<String> args) async {
  try {
    final installed = await installNative(args);
    stdout.writeln(installed.path);
  } on _UsageException catch (error) {
    final sink = error.exitCode == 0 ? stdout : stderr;
    if (error.message.isNotEmpty) {
      sink.writeln(error.message);
    }
    sink.writeln(_usage);
    exitCode = error.exitCode;
  } catch (error) {
    stderr.writeln('Failed to install ct_ffi: $error');
    exitCode = 1;
  }
}

Future<File> installNative(
  List<String> args, {
  Map<String, String>? environment,
  Directory? workingDirectory,
  native_build.DownloadArtifact? artifactDownloader,
  native_build.ExtractArchive? archiveExtractor,
}) async {
  final parsed = _parseArgs(args);
  if (parsed.help) {
    throw const _UsageException('', exitCode: 0);
  }

  final env = environment ?? Platform.environment;
  final tag = parsed.tag ?? env[native_build.nativeReleaseTagEnv]?.trim();
  if (tag == null || tag.isEmpty) {
    throw _UsageException(
      'Missing release tag. Provide --tag or set ${native_build.nativeReleaseTagEnv}.',
    );
  }

  final cwd = workingDirectory ?? Directory.current;
  final installRoot = parsed.outDir != null
      ? _resolveDirectory(cwd, parsed.outDir!)
      : native_build.defaultInstalledNativeLibraryDirectory(
          hostTriple: native_build.currentHostTriple(),
          workingDirectory: cwd,
        );

  return native_build.installHostedNativeLibrary(
    tag: tag,
    repository:
        parsed.repository ?? env[native_build.nativeReleaseRepoEnv]?.trim(),
    installRoot: installRoot,
    artifactDownloader: artifactDownloader,
    archiveExtractor: archiveExtractor,
  );
}

Directory _resolveDirectory(Directory workingDirectory, String path) {
  final directory = Directory(path);
  if (directory.isAbsolute) {
    return directory;
  }
  return Directory('${workingDirectory.path}/$path');
}

_InstallArgs _parseArgs(List<String> args) {
  String? tag;
  String? repository;
  String? outDir;
  var help = false;

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == '--help' || arg == '-h') {
      help = true;
      continue;
    }
    if (arg.startsWith('--tag=')) {
      tag = arg.substring('--tag='.length).trim();
      continue;
    }
    if (arg == '--tag') {
      if (index + 1 >= args.length) {
        throw const _UsageException('Expected a value after --tag.');
      }
      tag = args[++index].trim();
      continue;
    }
    if (arg.startsWith('--repository=')) {
      repository = arg.substring('--repository='.length).trim();
      continue;
    }
    if (arg == '--repository') {
      if (index + 1 >= args.length) {
        throw const _UsageException('Expected a value after --repository.');
      }
      repository = args[++index].trim();
      continue;
    }
    if (arg.startsWith('--out-dir=')) {
      outDir = arg.substring('--out-dir='.length).trim();
      continue;
    }
    if (arg == '--out-dir') {
      if (index + 1 >= args.length) {
        throw const _UsageException('Expected a value after --out-dir.');
      }
      outDir = args[++index].trim();
      continue;
    }
    throw _UsageException('Unrecognized argument: $arg');
  }

  return _InstallArgs(
    tag: tag,
    repository: repository,
    outDir: outDir,
    help: help,
  );
}

const _usage =
    '''
Usage: dart packages/connectanum_client/tool/install_native.dart --tag <release-tag> [options]

Downloads the hosted ct_ffi bundle for the current host, verifies the published
SHA-256 sidecar, extracts the native library, and prints the installed library
path on stdout.

Options:
  --tag <release-tag>        Release tag to download. Falls back to
                             ${native_build.nativeReleaseTagEnv}.
  --repository <owner/repo>  Override the GitHub Releases source. Falls back to
                             ${native_build.nativeReleaseRepoEnv} and then
                             ${native_build.defaultReleaseRepository}.
  --out-dir <path>           Installation directory. Defaults to
                             .dart_tool/connectanum/native/<host-triple>.
  -h, --help                 Show this help text.
''';

final class _InstallArgs {
  const _InstallArgs({
    required this.tag,
    required this.repository,
    required this.outDir,
    required this.help,
  });

  final String? tag;
  final String? repository;
  final String? outDir;
  final bool help;
}

final class _UsageException implements Exception {
  const _UsageException(this.message, {this.exitCode = 64});

  final String message;
  final int exitCode;
}
