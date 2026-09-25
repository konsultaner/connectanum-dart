@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:connectanum_client/src/native_release_installer.dart' as native;
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;
import 'installer_assertions.dart';

void main() {
  for (final (name, architecture) in [
    ('library', native.architectureLabelForDartVersion),
    ('hook', hook.architectureLabelForDartVersion),
  ]) {
    test('$name recognizes each supported Dart architecture spelling', () {
      for (final (target, expected) in [
        ('linux_x64', 'x64'),
        ('macos_x64', 'x64'),
        ('windows_x64', 'x64'),
        ('linux_arm64', 'arm64'),
        ('macos_arm64', 'arm64'),
        ('linux_aarch64', 'arm64'),
      ]) {
        expect(
          architecture('3.13.1 (stable) on "$target"'),
          expected,
          reason: target,
        );
      }
    });
  }

  for (final (name, install) in [
    ('library', native.installHostedNativeLibrary),
    ('hook', hook.installHostedNativeLibrary),
  ]) {
    group(name, () {
      late Directory root;
      late File output;
      final bytes = 'invalid archive with a valid checksum'.codeUnits;
      final digest = sha256.convert(bytes).toString();
      final bundle = 'ct-ffi-${native.currentHostTriple()}';
      final libraryName = native.currentPlatformLibraryFileName('ct_ffi');

      setUp(() async {
        root = await Directory.systemTemp.createTemp('connectanum_installer_');
        output = File('${root.path}/$libraryName');
        output.writeAsStringSync('previous verified library');
      });
      tearDown(() => root.delete(recursive: true));

      test(
        'default installation stays inside the consumer working directory',
        () async {
          final requested = <Uri>[];
          final installed = await expectValidInstall(
            () => IOOverrides.runZoned(
              () => install(
                tag: ' v-default ',
                repository: ' example/releases ',
                artifactDownloader:
                    ({required source, required destination}) async {
                      requested.add(source);
                      if (source.path.endsWith('.sha256')) {
                        destination.writeAsStringSync(
                          '$digest  $bundle.tar.gz',
                        );
                      } else {
                        destination.writeAsBytesSync(bytes);
                      }
                    },
                archiveExtractor: ({required archive, required destination}) {
                  expect(archive.readAsBytesSync(), bytes);
                  final library = File(
                    '${destination.path}/$bundle/$libraryName',
                  );
                  library.parent.createSync(recursive: true);
                  library.writeAsStringSync('default installed library');
                },
              ),
              getCurrentDirectory: () => root,
            ),
          );
          expect(
            installed.path,
            '${root.path}/.dart_tool/connectanum/native/'
            '${native.currentHostTriple()}/$libraryName',
          );
          expect(installed.readAsStringSync(), 'default installed library');
          expect(output.readAsStringSync(), 'previous verified library');
          expect(requested, [
            Uri.parse(
              'https://github.com/example/releases/releases/download/'
              'v-default/$bundle.tar.gz',
            ),
            Uri.parse(
              'https://github.com/example/releases/releases/download/'
              'v-default/$bundle.tar.gz.sha256',
            ),
          ]);
        },
      );

      for (final (checksum, reason) in [
        (' \n', 'was empty'),
        ('${'0' * 64}  archive.tar.gz', 'Checksum verification failed'),
      ]) {
        test(
          'rejects $reason without extraction or output replacement',
          () async {
            var extractionCalls = 0;
            await expectLater(
              install(
                tag: 'v-test',
                installRoot: root,
                artifactDownloader:
                    ({required source, required destination}) async {
                      if (source.path.endsWith('.sha256')) {
                        destination.writeAsStringSync(checksum);
                      } else {
                        destination.writeAsBytesSync(bytes);
                      }
                    },
                archiveExtractor: ({required archive, required destination}) {
                  extractionCalls++;
                },
              ),
              throwsA(_installerError(name, reason)),
            );
            expect(extractionCalls, 0);
            expect(output.readAsStringSync(), 'previous verified library');
          },
        );
      }

      for (final missingLibrary in [true, false]) {
        test(
          'rejects ${missingLibrary ? 'missing library' : 'invalid tar archive'}',
          () async {
            await expectLater(
              install(
                tag: 'v-test',
                installRoot: root,
                artifactDownloader:
                    ({required source, required destination}) async {
                      if (source.path.endsWith('.sha256')) {
                        destination.writeAsStringSync(
                          '$digest  $bundle.tar.gz',
                        );
                      } else {
                        destination.writeAsBytesSync(bytes);
                      }
                    },
                archiveExtractor: missingLibrary
                    ? ({required archive, required destination}) {}
                    : null,
              ),
              throwsA(
                _installerError(
                  name,
                  missingLibrary
                      ? 'library was not found'
                      : 'Failed to extract',
                ),
              ),
            );
            expect(output.readAsStringSync(), 'previous verified library');
          },
        );
      }

      for (final failure in [
        'none',
        'http',
        'truncated',
        'truncated-checksum',
      ]) {
        test(
          'default HTTP downloader handles $failure and closes its clients',
          () async {
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            addTearDown(() => server.close(force: true));
            var requests = 0;
            server.listen((request) async {
              requests++;
              if (requests == 1 && failure == 'http') {
                request.response.statusCode = HttpStatus.notFound;
              } else if ((requests == 1 && failure == 'truncated') ||
                  (requests == 2 && failure == 'truncated-checksum')) {
                final socket = await request.response.detachSocket(
                  writeHeaders: false,
                );
                socket.add(
                  utf8.encode(
                    'HTTP/1.1 200 OK\r\nContent-Length: 1024\r\n'
                    'Connection: close\r\n\r\npartial',
                  ),
                );
                await socket.flush();
                socket.destroy();
                return;
              } else if (request.uri.path.endsWith('.sha256')) {
                request.response.write('$digest  $bundle.tar.gz');
              } else {
                request.response.add(bytes);
              }
              await request.response.close();
            });
            final overrides = _LoopbackDownloads(server.port);
            addTearDown(() {
              for (final client in overrides.clients) {
                client.delegate.close(force: true);
              }
            });
            Future<File> attempt() => HttpOverrides.runWithHttpOverrides(
              () => install(
                tag: 'v-test',
                installRoot: root,
                archiveExtractor: ({required archive, required destination}) {
                  expect(archive.readAsBytesSync(), bytes);
                  final library = File(
                    '${destination.path}/$bundle/$libraryName',
                  );
                  library.parent.createSync(recursive: true);
                  library.writeAsStringSync('downloaded verified library');
                },
              ),
              overrides,
            );
            if (failure != 'none') {
              await expectLater(
                attempt(),
                throwsA(
                  failure == 'http'
                      ? _installerError(name, 'HTTP 404')
                      : isA<HttpException>(),
                ),
              );
              expect(output.readAsStringSync(), 'previous verified library');
              expect(
                root
                    .listSync(recursive: true)
                    .whereType<File>()
                    .where(
                      (file) => file.path.endsWith(
                        failure == 'truncated-checksum' ? '.sha256' : '.tar.gz',
                      ),
                    ),
                isEmpty,
              );
              expect(
                root
                    .listSync(recursive: true)
                    .whereType<Directory>()
                    .where(
                      (dir) => dir.uri.pathSegments.any(
                        (part) => part.startsWith('.download-'),
                      ),
                    ),
                isEmpty,
              );
            }
            expect(
              (await expectValidInstall(attempt)).readAsStringSync(),
              'downloaded verified library',
            );
            expect(requests, failure == 'none' ? 2 : 3);
            expect(overrides.clients, hasLength(requests));
            expect(
              root
                  .listSync(recursive: true)
                  .whereType<Directory>()
                  .where(
                    (dir) => dir.uri.pathSegments.any(
                      (part) => part.startsWith('.download-'),
                    ),
                  ),
              isEmpty,
            );
            for (final client in overrides.clients) {
              expect(client.forcedCloses, 1);
            }
          },
        );
      }

      test(
        'clears interrupted extraction and then reuses verified cache',
        () async {
          final downloads = <Uri>[];
          var extractionCalls = 0;
          Future<File> attempt() => install(
            tag: '  v-test  ',
            repository: '  example/consumer  ',
            installRoot: root,
            artifactDownloader:
                ({required source, required destination}) async {
                  downloads.add(source);
                  if (source.path.endsWith('.sha256')) {
                    destination.writeAsStringSync(
                      '${digest.toUpperCase()}  $bundle.tar.gz\n',
                    );
                  } else {
                    destination.writeAsBytesSync(bytes);
                  }
                },
            archiveExtractor: ({required archive, required destination}) {
              extractionCalls++;
              final partial = File('${destination.path}/partial');
              if (extractionCalls == 1) {
                partial.writeAsStringSync('interrupted extraction');
                throw const FileSystemException('interrupted extraction');
              }
              expect(partial.existsSync(), isFalse);
              expect(archive.readAsBytesSync(), bytes);
              final library = File('${destination.path}/$bundle/$libraryName');
              library.parent.createSync(recursive: true);
              library.writeAsStringSync('new verified library');
            },
          );

          await expectLater(attempt(), throwsA(isA<FileSystemException>()));
          expect(output.readAsStringSync(), 'previous verified library');
          expect(
            (await expectValidInstall(attempt)).readAsStringSync(),
            'new verified library',
          );
          expect(
            (await expectValidInstall(attempt)).readAsStringSync(),
            'new verified library',
          );
          expect(extractionCalls, 2);
          expect(downloads.map((uri) => uri.toString()), [
            'https://github.com/example/consumer/releases/download/v-test/$bundle.tar.gz',
            'https://github.com/example/consumer/releases/download/v-test/$bundle.tar.gz.sha256',
          ]);
        },
      );
    });
  }
}

Matcher _installerError(String implementation, String message) =>
    implementation == 'hook'
    ? isA<BuildError>().having((e) => e.message, 'message', contains(message))
    : isA<StateError>().having((e) => e.message, 'message', contains(message));

final class _LoopbackDownloads extends HttpOverrides {
  _LoopbackDownloads(this.port);
  final int port;
  final clients = <_LoopbackClient>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _LoopbackClient(super.createHttpClient(context), port);
    clients.add(client);
    return client;
  }
}

final class _LoopbackClient implements HttpClient {
  _LoopbackClient(this.delegate, this.port);
  final HttpClient delegate;
  final int port;
  int forcedCloses = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    expect(url.scheme, 'https');
    expect(url.host, 'github.com');
    return delegate.getUrl(Uri.http('127.0.0.1:$port', url.path));
  }

  @override
  void close({bool force = false}) {
    if (force) forcedCloses++;
    delegate.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
