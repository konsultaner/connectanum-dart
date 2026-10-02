@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;

const _package = 'connectanum_client';
const _outputName = 'connectanum_client_ct_ffi';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('connectanum_hook_execution_');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'hook entrypoint without code assets does not invoke native tools',
    () async {
      final fixture = _BuildFixture(
        root,
        codeAssets: false,
      );
      await hook.main(['--config=${fixture.config.path}']);
      final output = BuildOutput(
        jsonDecode(File.fromUri(fixture.input.outputFile).readAsStringSync())
            as Map<String, Object?>,
      );
      expect(
        await ProtocolBase.validateBuildOutput(fixture.input, output),
        isEmpty,
      );
      expect(output.assets.code, isEmpty);
      expect(fixture.library.existsSync(), isFalse);
      expect(fixture.cargoTarget.existsSync(), isFalse);
    },
  );

  test(
    'source disappearing before Cargo launch preserves infrastructure error',
    () async {
      final fixture = _BuildFixture(root);
      fixture.sourceCheckout();
      fixture.library.writeAsStringSync('previous installation');
      fixture.library.setLastModifiedSync(DateTime(2000));
      final overrides = _DisappearingSource(
        fixture.cargoTarget.path,
        fixture.transport,
      );
      final output = BuildOutputBuilder();
      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => hook.buildNativeAssets(
            fixture.input,
            output,
            environment: const {},
          ),
          overrides,
        ),
        throwsA(
          isA<InfraError>()
              .having(
                (error) => error.message,
                'message',
                contains('Failed to invoke cargo'),
              )
              .having(
                (error) => error.wrappedException,
                'cause',
                isA<ProcessException>(),
              )
              .having((error) => error.wrappedTrace, 'trace', isNotNull),
        ),
      );
      expect(overrides.removed, isTrue);
      expect(BuildOutput(output.json).assets.code, isEmpty);
      expect(fixture.library.readAsStringSync(), 'previous installation');
    },
  );

  test('a build without code assets performs no native work', () async {
    final fixture = _BuildFixture(root, codeAssets: false);
    final output = await fixture.run();
    expect(output.assets.code, isEmpty);
    expect(output.dependencies, isEmpty);
  });

  for (final (os, arch) in [
    (OS.android, Architecture.arm64),
    (OS.iOS, Architecture.arm64),
    (OS.windows, Architecture.arm64),
    (OS.linux, Architecture.arm),
  ]) {
    test('unsupported target $os/$arch does not attempt native IO', () async {
      final fixture = _BuildFixture(root, os: os, arch: arch);
      final output = await fixture.run(
        environment: {
          hook.nativeLibEnv: '${root.path}/missing',
          hook.nativeReleaseTagEnv: 'not-downloaded',
        },
      );
      expect(output.assets.code, isEmpty);
      expect(output.dependencies, isEmpty);
    });
  }

  for (final value in [true, 1, -1, ' TRUE ', ' yes ', 'on']) {
    test('skip user define $value suppresses discovery and builds', () async {
      final fixture = _BuildFixture(
        root,
        defines: {hook.skipNativeBuildEnv: value},
      );
      final output = await fixture.run();
      expect(output.assets.code, isEmpty);
      expect(output.dependencies, isEmpty);
      expect(fixture.library.existsSync(), isFalse);
    });
  }

  for (final (os, arch) in [
    (OS.linux, Architecture.x64),
    (OS.linux, Architecture.arm64),
    (OS.macOS, Architecture.x64),
    (OS.macOS, Architecture.arm64),
    (OS.windows, Architecture.x64),
  ]) {
    test(
      'configured library publishes the correct asset for $os/$arch',
      () async {
        final source = File('${root.path}/prebuilt')
          ..writeAsStringSync('configured');
        final fixture = _BuildFixture(root, os: os, arch: arch);
        final output = await fixture.run(
          environment: {
            hook.nativeLibEnv: '  ${source.path}  ',
            hook.skipNativeBuildEnv: 'true',
          },
        );
        fixture.expectAsset(output, 'configured');
        expect(output.dependencies, [source.uri]);
        expect(source.readAsStringSync(), 'configured');
      },
    );
  }

  test('blank path define falls back to trimmed environment', () async {
    final source = File('${root.path}/prebuilt')..writeAsStringSync('fallback');
    final fixture = _BuildFixture(root, defines: {hook.nativeLibEnv: '  '});
    final output = await fixture.run(
      environment: {hook.nativeLibEnv: ' ${source.path} '},
    );
    fixture.expectAsset(output, 'fallback');
    expect(output.dependencies, [source.uri]);
  });

  for (final value in [false, 0, 'off']) {
    test('explicit false skip $value overrides true environment', () async {
      final fixture = _BuildFixture(
        root,
        defines: {hook.skipNativeBuildEnv: value},
      );
      final dependencies = fixture.sourceCheckout();
      var builds = 0;
      final output = await fixture.run(
        environment: {hook.skipNativeBuildEnv: 'true', 'FIXTURE_ENV': 'kept'},
        cargo:
            ({required args, required workingDirectory, required environment}) {
              builds++;
              expect(args, ['build', '-p', 'ct_ffi', '--release']);
              expect(workingDirectory, fixture.transport.path);
              expect(environment['FIXTURE_ENV'], 'kept');
              expect(environment['CARGO_TARGET_DIR'], fixture.cargoTarget.path);
              fixture.builtLibrary.parent.createSync(recursive: true);
              fixture.builtLibrary.writeAsStringSync('built');
              return ProcessResult(1, 0, '', '');
            },
      );
      expect(builds, 1);
      fixture.expectAsset(output, 'built');
      expect(
        output.dependencies,
        unorderedEquals(dependencies.map((f) => f.uri)),
      );
    });
  }

  for (final change in ['older', 'equal', 'newer']) {
    test(
      'source dependency $change than output selects rebuild correctly',
      () async {
        final fixture = _BuildFixture(root);
        final dependencies = fixture.sourceCheckout();
        final base = DateTime.utc(2020);
        for (final file in dependencies) {
          file.setLastModifiedSync(base.subtract(const Duration(days: 2)));
        }
        fixture.library.writeAsStringSync('cached');
        fixture.library.setLastModifiedSync(base);
        final changed = dependencies.last;
        changed.setLastModifiedSync(switch (change) {
          'older' => base.subtract(const Duration(days: 1)),
          'equal' => base,
          _ => base.add(const Duration(days: 1)),
        });
        var builds = 0;
        final output = await fixture.run(
          cargo:
              ({
                required args,
                required workingDirectory,
                required environment,
              }) {
                builds++;
                fixture.builtLibrary.parent.createSync(recursive: true);
                fixture.builtLibrary.writeAsStringSync('rebuilt');
                return ProcessResult(1, 0, '', '');
              },
        );
        expect(builds, change == 'older' ? 0 : 1);
        fixture.expectAsset(output, change == 'older' ? 'cached' : 'rebuilt');
        expect(
          output.dependencies,
          unorderedEquals(dependencies.map((f) => f.uri)),
        );
      },
    );
  }

  test(
    'missing optional manifests and source directories are not dependencies',
    () async {
      final fixture = _BuildFixture(root);
      final manifest = File('${fixture.transport.path}/Cargo.toml');
      manifest.parent.createSync(recursive: true);
      manifest.writeAsStringSync('[workspace]');
      final output = await fixture.run(
        cargo:
            ({required args, required workingDirectory, required environment}) {
              fixture.builtLibrary.parent.createSync(recursive: true);
              fixture.builtLibrary.writeAsStringSync('minimal');
              return ProcessResult(1, 0, '', '');
            },
      );
      fixture.expectAsset(output, 'minimal');
      expect(output.dependencies, [manifest.uri]);
    },
  );

  for (final failure in [
    'missing-library',
    'missing-workspace',
    'cargo-exit',
    'missing-output',
  ]) {
    test('$failure fails without replacing an installed library', () async {
      final fixture = _BuildFixture(
        root,
        defines: failure == 'missing-library'
            ? {hook.nativeLibEnv: '${root.path}/missing-library'}
            : const {},
      );
      fixture.library.writeAsStringSync('previous installation');
      if (failure == 'missing-workspace') {
        File(
          '${root.path}/pubspec.yaml',
        ).writeAsStringSync('name: connectanum_workspace\n');
      } else if (failure != 'missing-library') {
        fixture.sourceCheckout();
        fixture.library.setLastModifiedSync(DateTime.utc(2000));
      }
      final output = BuildOutputBuilder();
      var builds = 0;
      await expectLater(
        hook.buildNativeAssets(
          fixture.input,
          output,
          environment: const {},
          cargoRunner:
              ({
                required args,
                required workingDirectory,
                required environment,
              }) {
                builds++;
                return ProcessResult(
                  1,
                  failure == 'cargo-exit' ? 7 : 0,
                  'compiler output',
                  'compiler failure',
                );
              },
          artifactDownloader: ({required source, required destination}) async =>
              throw StateError('Unexpected network request'),
        ),
        throwsA(
          isA<BuildError>().having(
            (error) => error.message,
            'message',
            switch (failure) {
              'missing-library' => contains('but that file does not exist'),
              'missing-workspace' => contains('Connectanum source checkout'),
              'cargo-exit' => allOf(
                contains('exit 7'),
                contains('compiler output'),
                contains('compiler failure'),
              ),
              _ => contains(
                'cargo build succeeded but expected output was not found',
              ),
            },
          ),
        ),
      );
      expect(
        builds,
        failure.startsWith('cargo') || failure == 'missing-output' ? 1 : 0,
      );
      expect(BuildOutput(output.json).assets.code, isEmpty);
      expect(fixture.library.readAsStringSync(), 'previous installation');
    });
  }

  test(
    'default Cargo runner preserves failure diagnostics and receives its environment',
    () async {
      final fixture = _BuildFixture(root);
      fixture.sourceCheckout();
      final cargo = File('${root.path}/bin/cargo');
      cargo.parent.createSync();
      cargo.writeAsStringSync(
        '#!/bin/sh\n'
        'printf "%s" "\$CARGO_TARGET_DIR" > "${root.path}/cargo-marker"\n'
        'printf "fixture cargo failure" >&2\nexit 9\n',
      );
      expect(Process.runSync('chmod', ['+x', cargo.path]).exitCode, 0);
      await expectLater(
        hook.buildNativeAssets(
          fixture.input,
          BuildOutputBuilder(),
          environment: {'PATH': cargo.parent.path},
        ),
        throwsA(
          isA<BuildError>().having(
            (error) => error.message,
            'message',
            allOf(contains('exit 9'), contains('fixture cargo failure')),
          ),
        ),
      );
      expect(
        File('${root.path}/cargo-marker').readAsStringSync(),
        fixture.cargoTarget.path,
      );
      expect(fixture.library.existsSync(), isFalse);
    },
    testOn: '!windows',
  );

  test('missing package manifest reports a release-tag error', () {
    expect(
      () => hook.releaseTagForPackage(root),
      throwsA(
        isA<BuildError>().having(
          (error) => error.message,
          'message',
          contains('does not exist'),
        ),
      ),
    );
  });

  test('installed library lookup distinguishes missing from present', () {
    const triple = 'fixture-triple';
    const name = 'fixture-library';
    expect(
      hook.installedNativeLibrary(
        hostTriple: triple,
        bundledLibName: name,
        workingDirectory: root,
      ),
      isNull,
    );
    final expected = File(
      '${root.path}/.dart_tool/connectanum/native/$triple/$name',
    );
    expected.parent.createSync(recursive: true);
    expected.writeAsStringSync('installed');
    final found = hook.installedNativeLibrary(
      hostTriple: triple,
      bundledLibName: name,
      workingDirectory: root,
    );
    expect(found?.path, expected.path);
    expect(found?.readAsStringSync(), 'installed');
  });
}

typedef _Cargo =
    ProcessResult Function({
      required List<String> args,
      required String workingDirectory,
      required Map<String, String> environment,
    });

final class _DisappearingSource extends IOOverrides {
  _DisappearingSource(this.targetPath, this.source);
  final String targetPath;
  final Directory source;
  var removed = false;

  @override
  Directory createDirectory(String path) {
    final directory = super.createDirectory(path);
    if (path != targetPath) return directory;
    return _OnCreateDirectory(directory, () {
      source.deleteSync(recursive: true);
      removed = true;
    });
  }
}

final class _OnCreateDirectory implements Directory {
  _OnCreateDirectory(this.directory, this.afterCreate);
  final Directory directory;
  final void Function() afterCreate;
  @override
  String get path => directory.path;
  @override
  void createSync({bool recursive = false}) {
    directory.createSync(recursive: recursive);
    afterCreate();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BuildFixture {
  _BuildFixture(
    this.root, {
    this.os = OS.linux,
    Architecture arch = Architecture.x64,
    bool codeAssets = true,
    Map<String, Object?> defines = const {},
  }) {
    packageRoot.createSync(recursive: true);
    final shared = Directory('${root.path}/output/shared')
      ..createSync(recursive: true);
    final builder = BuildInputBuilder()
      ..setupShared(
        packageRoot: packageRoot.uri,
        packageName: _package,
        outputDirectoryShared: shared.uri,
        outputFile: File('${root.path}/output/result.json').uri,
        userDefines: PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: defines,
            basePath: root.uri,
          ),
        ),
      )
      ..setupBuildInput();
    builder.config.setupBuild(linkingEnabled: false);
    if (codeAssets) {
      builder.addExtension(
        CodeAssetExtension(
          targetArchitecture: arch,
          targetOS: os,
          linkModePreference: LinkModePreference.dynamic,
        ),
      );
    }
    input = builder.build();
    Directory.fromUri(input.outputDirectory).createSync(recursive: true);
    config.writeAsStringSync(jsonEncode(input.json));
  }

  final Directory root;
  final OS os;
  late final BuildInput input;
  Directory get packageRoot => Directory('${root.path}/packages/$_package');
  Directory get transport => Directory('${root.path}/native/transport');
  Directory get cargoTarget =>
      Directory.fromUri(input.outputDirectory.resolve('cargo_target/'));
  File get builtLibrary =>
      File('${cargoTarget.path}/release/${os.dylibFileName('ct_ffi')}');
  File get library => File.fromUri(
    input.outputDirectory.resolve(os.dylibFileName(_outputName)),
  );
  File get config => File('${root.path}/input.json');

  List<File> sourceCheckout() {
    final files = [
      for (final path in [
        'Cargo.toml',
        'Cargo.lock',
        'ct_core/Cargo.toml',
        'ct_ffi/Cargo.toml',
        'ct_core/src/lib.rs',
        'ct_ffi/src/nested/worker.rs',
      ])
        File('${transport.path}/$path'),
    ];
    for (final file in files) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('fixture');
    }
    File(
      '${transport.path}/ct_core/src/ignored.txt',
    ).writeAsStringSync('not Rust');
    return files;
  }

  Future<BuildOutput> run({
    Map<String, String> environment = const {},
    _Cargo? cargo,
  }) async {
    await hook.runBuildHook(
      ['--config=${config.path}'],
      environment: environment,
      cargoRunner:
          cargo ??
          ({required args, required workingDirectory, required environment}) =>
              throw StateError('Unexpected Cargo invocation'),
      artifactDownloader: ({required source, required destination}) async =>
          throw StateError('Unexpected download: $source'),
      archiveExtractor: ({required archive, required destination}) =>
          throw StateError('Unexpected extraction'),
    );
    final output = BuildOutput(
      jsonDecode(File.fromUri(input.outputFile).readAsStringSync())
          as Map<String, Object?>,
    );
    expect(await ProtocolBase.validateBuildOutput(input, output), isEmpty);
    return output;
  }

  void expectAsset(BuildOutput output, String content) {
    expect(output.assets.code, hasLength(1));
    final asset = output.assets.code.single;
    expect(asset.id, 'package:$_package/ct_ffi.dart');
    expect(asset.linkMode, isA<DynamicLoadingBundled>());
    expect(asset.file, library.uri);
    expect(library.readAsStringSync(), content);
  }
}
