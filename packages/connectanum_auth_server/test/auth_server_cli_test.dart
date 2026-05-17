@TestOn('vm')
library;

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
}

Map<String, Object?> _authServiceConfig() => <String, Object?>{
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
    'worker_pool': <String, Object?>{'min_workers': 1},
  },
};

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
