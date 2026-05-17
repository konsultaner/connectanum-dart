@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final nativeLib = _resolveNativeLib();
  final nativeSkipReason = !(Platform.isLinux || Platform.isMacOS)
      ? 'Auth server CLI runtime smoke only runs on Linux and macOS.'
      : nativeLib == null
      ? 'Native transport library missing; build native transport first.'
      : null;

  test(
    'package executable --check starts runtime and binds WAMP procedures',
    () async {
      final repoRoot = _resolveRepoRoot();
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum_auth_server_cli_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final configFile = File('${tempDir.path}/auth_service.json')
        ..writeAsStringSync(jsonEncode(_authServiceConfig()));

      final result = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          'run',
          'connectanum_auth_server:auth_server',
          '--config',
          configFile.path,
          '--native-lib',
          nativeLib!,
          '--check',
        ],
        workingDirectory: repoRoot.path,
        environment: <String, String>{
          ...Platform.environment,
          'CONNECTANUM_NATIVE_LIB': nativeLib,
        },
      ).timeout(const Duration(seconds: 45));

      expect(result.exitCode, 0, reason: _processOutput(result));
      expect(result.stdout, contains('Auth server procedures bound'));
      expect(result.stdout, contains('Auth server runtime check completed.'));
    },
    skip: nativeSkipReason,
  );

  test(
    'package executable --check loads documented YAML configuration',
    () async {
      final repoRoot = _resolveRepoRoot();
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum_auth_server_cli_yaml_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final configFile = File('${tempDir.path}/auth_service.yaml')
        ..writeAsStringSync(_authServiceYamlConfig());

      final result = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          'run',
          'connectanum_auth_server:auth_server',
          '--config',
          configFile.path,
          '--native-lib',
          nativeLib!,
          '--check',
        ],
        workingDirectory: repoRoot.path,
        environment: <String, String>{
          ...Platform.environment,
          'CONNECTANUM_NATIVE_LIB': nativeLib,
        },
      ).timeout(const Duration(seconds: 45));

      expect(result.exitCode, 0, reason: _processOutput(result));
      expect(result.stdout, contains('Loaded configuration from'));
      expect(result.stdout, contains('Auth server procedures bound'));
      expect(result.stdout, contains('Auth server runtime check completed.'));
    },
    skip: nativeSkipReason,
  );

  test(
    'package executable serves configured health and metrics endpoints',
    () async {
      final repoRoot = _resolveRepoRoot();
      final tempDir = await Directory.systemTemp.createTemp(
        'connectanum_auth_server_cli_metrics_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final configFile = File('${tempDir.path}/auth_service.json')
        ..writeAsStringSync(jsonEncode(_authServiceConfig(openMetrics: true)));

      final process = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          'run',
          'connectanum_auth_server:auth_server',
          '--config',
          configFile.path,
          '--native-lib',
          nativeLib!,
        ],
        workingDirectory: repoRoot.path,
        environment: <String, String>{
          ...Platform.environment,
          'CONNECTANUM_NATIVE_LIB': nativeLib,
        },
      );
      final stdoutLines = <String>[];
      final stderrBuffer = StringBuffer();
      final metricsLine = Completer<String>();
      final running = Completer<void>();
      final stdoutSubscription = utf8.decoder
          .bind(process.stdout)
          .transform(const LineSplitter())
          .listen((line) {
            stdoutLines.add(line);
            if (!metricsLine.isCompleted &&
                line.startsWith('OpenMetrics exporter listening on ')) {
              metricsLine.complete(line);
            }
            if (!running.isCompleted && line.contains('Auth server running.')) {
              running.complete();
            }
          });
      final stderrSubscription = utf8.decoder
          .bind(process.stderr)
          .listen(stderrBuffer.write);
      final exitFuture = process.exitCode.then(_ProcessExit.new);

      addTearDown(() async {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
      });

      final line = await _waitForProcessSignal(
        metricsLine.future,
        exitFuture,
        stdoutLines,
        stderrBuffer,
      );
      await _waitForProcessSignal(
        running.future,
        exitFuture,
        stdoutLines,
        stderrBuffer,
      );
      final match = RegExp(
        r'OpenMetrics exporter listening on ([^:]+):(\d+)(/\S*) ',
      ).firstMatch(line);
      expect(match, isNotNull, reason: line);
      final host = match!.group(1)!;
      final port = int.parse(match.group(2)!);
      final metricsPath = match.group(3)!;
      final client = HttpClient();
      addTearDown(() => client.close());

      final healthResponse = await _get(client, host, port, '/healthz');
      expect(healthResponse.statusCode, HttpStatus.ok);
      expect(healthResponse.body, 'ok');

      final metricsResponse = await _get(client, host, port, metricsPath);
      expect(metricsResponse.statusCode, HttpStatus.ok);
      expect(
        metricsResponse.headers.contentType?.mimeType,
        ContentType.text.mimeType,
      );
      expect(metricsResponse.body, contains('connectanum_router_realms'));
      expect(metricsResponse.body, contains('connectanum_router_process_info'));
    },
    skip: nativeSkipReason,
  );
}

Map<String, Object?> _authServiceConfig({bool openMetrics = false}) =>
    <String, Object?>{
      'router': <String, Object?>{
        'realms': <Object?>[
          <String, Object?>{
            'name': 'demo.realm',
            'auth': <String, Object?>{
              'authmethods': <Object?>['ticket'],
              'ticket': <String, Object?>{'authenticator': 'ticket-basic'},
            },
            'roles': <Object?>[
              <String, Object?>{
                'name': 'member',
                'permissions': <Object?>[
                  <String, Object?>{
                    'uri': 'demo.',
                    'match': 'prefix',
                    'allow': <Object?>['call', 'register', 'subscribe'],
                  },
                ],
              },
            ],
          },
          <String, Object?>{
            'name': 'connectanum.authenticate',
            'auth': <String, Object?>{
              'authmethods': <Object?>['anonymous'],
            },
            'roles': <Object?>[
              <String, Object?>{
                'name': 'anonymous',
                'permissions': <Object?>[
                  <String, Object?>{
                    'uri': 'authenticate.',
                    'match': 'prefix',
                    'allow': <Object?>['call'],
                  },
                ],
              },
              <String, Object?>{
                'name': 'internal',
                'permissions': <Object?>[
                  <String, Object?>{
                    'uri': 'authenticate.',
                    'match': 'prefix',
                    'allow': <Object?>['register', 'unregister', 'call'],
                  },
                ],
              },
            ],
          },
          if (openMetrics)
            <String, Object?>{
              'name': 'connectanum.metrics',
              'auth': <String, Object?>{
                'authmethods': <Object?>['anonymous'],
              },
              'roles': <Object?>[
                <String, Object?>{
                  'name': 'metrics',
                  'permissions': <Object?>[
                    <String, Object?>{
                      'uri': 'connectanum.metrics.',
                      'match': 'prefix',
                      'allow': <Object?>[
                        'register',
                        'unregister',
                        'call',
                        'subscribe',
                        'publish',
                      ],
                    },
                  ],
                },
              ],
            },
        ],
        'listeners': <Object?>[
          <String, Object?>{
            'endpoint': '127.0.0.1:0',
            'authmethods': <Object?>['anonymous'],
            'protocols': <Object?>['rawsocket'],
            'rawsocket': <String, Object?>{'max_rawsocket_size_exponent': 16},
          },
        ],
        'authenticators': <String, Object?>{
          'anonymous': <String, Object?>{'type': 'anonymous'},
          'ticket-basic': <String, Object?>{
            'type': 'ticket',
            'options': <String, Object?>{
              'secrets': <String, Object?>{
                'alice': <String, Object?>{
                  'ticket': 'ticket-secret',
                  'role': 'member',
                },
              },
            },
          },
        },
        if (openMetrics)
          'internal_realms': <Object?>[
            <String, Object?>{
              'name': 'connectanum.metrics',
              'auth_id': 'metrics-daemon',
              'auth_role': 'metrics',
              'services': <Object?>['metrics'],
            },
          ],
        if (openMetrics)
          'metrics': <String, Object?>{
            'open_metrics': <String, Object?>{
              'enabled': true,
              'listen': '127.0.0.1:0',
              'path': '/metrics',
              'realm': 'connectanum.metrics',
            },
          },
        'worker_pool': <String, Object?>{'min_workers': 1},
      },
    };

String _authServiceYamlConfig() => '''
router:
  realms:
    - name: demo.realm
      auth:
        authmethods:
          - ticket
        ticket:
          authenticator: ticket-basic
      roles:
        - name: member
          permissions:
            - uri: demo.
              match: prefix
              allow:
                - call
                - register
                - subscribe
    - name: connectanum.authenticate
      auth:
        authmethods:
          - anonymous
      roles:
        - name: anonymous
          permissions:
            - uri: authenticate.
              match: prefix
              allow:
                - call
        - name: internal
          permissions:
            - uri: authenticate.
              match: prefix
              allow:
                - register
                - unregister
                - call
  listeners:
    - endpoint: 127.0.0.1:0
      authmethods:
        - anonymous
      protocols:
        - rawsocket
      rawsocket:
        max_rawsocket_size_exponent: 16
  authenticators:
    anonymous:
      type: anonymous
    ticket-basic:
      type: ticket
      options:
        secrets:
          alice:
            ticket: ticket-secret
            role: member
  worker_pool:
    min_workers: 1
''';

Future<T> _waitForProcessSignal<T>(
  Future<T> signal,
  Future<_ProcessExit> exitFuture,
  List<String> stdoutLines,
  StringBuffer stderrBuffer,
) async {
  final result = await Future.any<Object?>(<Future<Object?>>[
    signal.then<Object?>((value) => value),
    exitFuture,
  ]).timeout(const Duration(seconds: 45));
  if (result case final _ProcessExit exit) {
    fail(
      'Auth server exited before readiness signal with code ${exit.code}.\n'
      'stdout:\n${stdoutLines.join('\n')}\n'
      'stderr:\n$stderrBuffer',
    );
  }
  return result as T;
}

Future<_HttpResponseBody> _get(
  HttpClient client,
  String host,
  int port,
  String path,
) async {
  final request = await client.get(host, port, path);
  final response = await request.close();
  final body = await utf8.decodeStream(response);
  return _HttpResponseBody(
    statusCode: response.statusCode,
    headers: response.headers,
    body: body,
  );
}

class _ProcessExit {
  const _ProcessExit(this.code);

  final int code;
}

class _HttpResponseBody {
  const _HttpResponseBody({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final String body;
}

String _processOutput(ProcessResult result) =>
    'stdout:\n${result.stdout}\nstderr:\n${result.stderr}';

Directory _resolveRepoRoot() {
  final candidates = <Directory>[
    Directory.current,
    Directory.current.parent,
    Directory.current.parent.parent,
  ];
  for (final candidate in candidates) {
    if (File('${candidate.path}/pubspec.yaml').existsSync() &&
        Directory(
          '${candidate.path}/packages/connectanum_auth_server',
        ).existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError(
    'Failed to locate repo root from ${Directory.current.path}.',
  );
}

String? _resolveNativeLib() {
  final envPath = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (envPath != null && File(envPath).existsSync()) {
    return File(envPath).absolute.path;
  }

  final libraryName = switch (Platform.operatingSystem) {
    'linux' => 'libct_ffi.so',
    'macos' => 'libct_ffi.dylib',
    'windows' => 'ct_ffi.dll',
    _ => 'libct_ffi.so',
  };
  final repoRoot = _resolveRepoRoot();
  final candidates = <File>[
    File(
      '${repoRoot.path}/native/transport/target/ffi-test/release/$libraryName',
    ),
    File('${repoRoot.path}/native/transport/target/release/$libraryName'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  return null;
}
