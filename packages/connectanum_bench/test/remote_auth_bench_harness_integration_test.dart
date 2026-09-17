@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_bench/src/remote_auth_bench_harness.dart';
import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_client/socket.dart' as socket;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_router/connectanum_router.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  final nativeLib = _nativeLibrary();
  final skipReason = nativeLib == null
      ? 'Native transport library missing; build the ffi-test library first.'
      : null;

  test(
    'remote auth harness serves TLS tickets and releases its listener',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'remote-auth-bench-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final runtime = NativeTransportRuntime(libraryPath: nativeLib!)..start();
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });
      expect(
        await RemoteAuthBenchHarness.maybeStart(
          settings: const RouterSettings(realms: [], listeners: []),
          runtime: runtime,
        ),
        isNull,
      );

      final reservation = await ServerSocket.bind('127.0.0.1', 0);
      final port = reservation.port;
      await reservation.close();
      final tokenFile = File('${directory.path}/nested/credentials/token.txt');
      final serviceFile = File(
        '${directory.path}/nested/credentials/service.txt',
      );
      final settings = _settings(port, tokenFile.path, serviceFile.path);
      final logger = Logger.detached('remote-auth-harness-test')
        ..level = Level.ALL;
      final records = <LogRecord>[];
      final logSubscription = logger.onRecord.listen(records.add);
      addTearDown(logSubscription.cancel);
      RemoteAuthBenchHarness? harness = await RemoteAuthBenchHarness.maybeStart(
        settings: settings,
        runtime: runtime,
        logger: logger,
      );
      addTearDown(() async => await harness?.close());
      expect(harness, isNotNull);
      expect(
        await tokenFile.readAsString(),
        RemoteAuthBenchHarness.defaultAuthToken,
      );
      expect(
        await serviceFile.readAsString(),
        RemoteAuthBenchHarness.defaultServiceTicket,
      );

      final peers = <client.Client>[];
      addTearDown(() async {
        for (final peer in peers) {
          await peer.disconnect();
        }
      });
      Future<client.Session> connect(String ticket) async {
        final tls = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates(_certificate('remote_auth_ca_cert.pem'))
          ..useCertificateChain(_certificate('remote_auth_client_cert.pem'))
          ..usePrivateKey(_certificate('remote_auth_client_key.pem'));
        final peer = client.Client(
          realm: 'bench.auth.service',
          authId: 'bench-service',
          authenticationMethods: [client.TicketAuthentication(ticket)],
          transport: socket.SocketTransport(
            '127.0.0.1',
            port,
            json.Serializer(),
            1,
            ssl: true,
            tlsSecurityContext: tls,
          ),
        );
        peers.add(peer);
        return peer.connect().first.timeout(const Duration(seconds: 5));
      }

      await expectLater(
        connect('wrong-service-ticket'),
        throwsA(
          isA<core.Abort>().having(
            (abort) => abort.reason,
            'reason',
            core.Error.notAuthorized,
          ),
        ),
      );
      final caller = await connect(RemoteAuthBenchHarness.defaultServiceTicket);
      Future<Map<String, dynamic>> rpc(
        String method,
        String transaction,
        Map<String, Object?> payload, {
        String token = RemoteAuthBenchHarness.defaultAuthToken,
      }) async {
        final result = await caller
            .call(
              'authenticate.$method',
              argumentsKeywords: {
                'transactionId': transaction,
                'auth_token': token,
                ...payload,
              },
            )
            .first
            .timeout(const Duration(seconds: 5));
        return result.argumentsKeywords!;
      }

      var sequence = 0;
      for (final realm in ['bench.first', 'bench.second']) {
        for (final identity in ['', 'missing-user']) {
          final transaction = 'denied-${sequence++}';
          final challenge = await rpc('hello', transaction, {
            'hello': {
              'realm': realm,
              'sessionId': sequence,
              'transport': {'connectionId': sequence},
              'details': {
                'authid': identity,
                'authmethods': ['ticket'],
              },
            },
          });
          expect(challenge['status'], 'challenge');
          final denied = await rpc('authenticate', transaction, {
            'authenticate': {
              'signature': RemoteAuthBenchHarness.defaultAuthSecret,
            },
          });
          expect(denied['status'], 'failure');
          expect(denied.containsKey('authRole'), isFalse);
        }
        for (final correct in [true, false]) {
          final transaction = 'attempt-${sequence++}';
          final hello = <String, Object?>{
            'realm': realm,
            'sessionId': sequence,
            'transport': {'connectionId': sequence},
            'details': {
              'authid': RemoteAuthBenchHarness.defaultAuthId,
              'authmethods': ['ticket'],
            },
          };
          final unauthorized = await rpc(
            'hello',
            transaction,
            {'hello': hello},
            token: 'wrong-token',
          );
          expect(unauthorized['status'], 'failure');
          expect(unauthorized['reason'], core.Error.notAuthorized);
          final challenge = await rpc('hello', transaction, {'hello': hello});
          expect(challenge['status'], 'challenge');
          expect(challenge['authId'], RemoteAuthBenchHarness.defaultAuthId);
          final result = await rpc('authenticate', transaction, {
            'authenticate': {
              'signature': correct
                  ? RemoteAuthBenchHarness.defaultAuthSecret
                  : 'wrong-ticket',
            },
          });
          expect(result['status'], correct ? 'success' : 'failure');
          if (correct) {
            expect(result['authId'], RemoteAuthBenchHarness.defaultAuthId);
            expect(result['authRole'], RemoteAuthBenchHarness.defaultAuthRole);
            expect(
              (result['details'] as Map)['authprovider'],
              'bench-remote-auth-server',
            );
          } else {
            expect(result.containsKey('authRole'), isFalse);
          }
        }
      }

      await expectLater(
        caller.register('authenticate.forbidden'),
        throwsA(
          isA<core.Error>().having(
            (error) => error.error,
            'reason',
            core.Error.notAuthorized,
          ),
        ),
      );
      await expectLater(
        caller.call('outside.allowed.prefix').first,
        throwsA(
          isA<core.Error>().having(
            (error) => error.error,
            'reason',
            core.Error.notAuthorized,
          ),
        ),
      );

      final pendingHello = <String, Object?>{
        'realm': 'bench.first',
        'sessionId': 98,
        'transport': {'connectionId': 98},
        'details': {
          'authid': RemoteAuthBenchHarness.defaultAuthId,
          'authmethods': ['ticket'],
        },
      };
      expect(
        (await rpc('hello', 'before-restart', {
          'hello': pendingHello,
        }))['status'],
        'challenge',
      );

      for (final peer in peers) {
        await peer.disconnect();
      }
      peers.clear();
      await harness!.close();
      harness = null;
      expect(records.map((record) => record.message), [
        'Starting remote auth bench harness on 127.0.0.1:$port',
        'Stopping remote auth bench harness',
      ]);
      final rebound = await ServerSocket.bind('127.0.0.1', port);
      expect(rebound.port, port);
      await rebound.close();

      // Restart uses the same endpoint and existing files, without stale state.
      harness = await RemoteAuthBenchHarness.maybeStart(
        settings: settings,
        runtime: runtime,
      );
      expect(harness, isNotNull);
      final reconnected = await connect(await serviceFile.readAsString());
      final stale = await reconnected
          .call(
            'authenticate.authenticate',
            argumentsKeywords: {
              'transactionId': 'before-restart',
              'auth_token': await tokenFile.readAsString(),
              'authenticate': {
                'signature': RemoteAuthBenchHarness.defaultAuthSecret,
              },
            },
          )
          .first
          .timeout(const Duration(seconds: 5));
      expect(stale.argumentsKeywords?['status'], 'failure');
      expect(stale.argumentsKeywords!.containsKey('authRole'), isFalse);
      final challenge = await reconnected
          .call(
            'authenticate.hello',
            argumentsKeywords: {
              'transactionId': 'reconnected',
              'auth_token': await tokenFile.readAsString(),
              'hello': {
                'realm': 'bench.first',
                'sessionId': 99,
                'transport': {'connectionId': 99},
                'details': {
                  'authid': RemoteAuthBenchHarness.defaultAuthId,
                  'authmethods': ['ticket'],
                },
              },
            },
          )
          .first
          .timeout(const Duration(seconds: 5));
      expect(challenge.argumentsKeywords?['status'], 'challenge');
      final authenticated = await reconnected
          .call(
            'authenticate.authenticate',
            argumentsKeywords: {
              'transactionId': 'reconnected',
              'auth_token': await tokenFile.readAsString(),
              'authenticate': {
                'signature': RemoteAuthBenchHarness.defaultAuthSecret,
              },
            },
          )
          .first
          .timeout(const Duration(seconds: 5));
      expect(authenticated.argumentsKeywords?['status'], 'success');
      expect(
        authenticated.argumentsKeywords?['authRole'],
        RemoteAuthBenchHarness.defaultAuthRole,
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

RouterSettings _settings(int port, String tokenFile, String serviceFile) =>
    (RouterSettingsBuilder()
          ..addAuthenticator(
            'remote',
            AuthenticatorDefinition(
              type: 'remote',
              options: {
                'auth_token_file': tokenFile,
                'rpc': {
                  'realm': 'bench.auth.service',
                  'service_auth_id': 'bench-service',
                  'service_auth_secret_file': serviceFile,
                  'transport': {
                    'type': 'rawsocket',
                    'host': '127.0.0.1',
                    'port': port,
                  },
                },
              },
            ),
          )
          ..addRealmFromBuilder(
            RealmSettingsBuilder('bench.first')
              ..addAuthMethod('ticket', options: {'authenticator': 'remote'}),
          )
          ..addRealmFromBuilder(
            RealmSettingsBuilder('bench.second')
              ..addAuthMethod('ticket', options: {'authenticator': 'remote'}),
          ))
        .build();

String _certificate(String name) {
  for (final root in [
    '../connectanum_router/test/certs',
    'packages/connectanum_router/test/certs',
  ]) {
    final file = File('$root/$name');
    if (file.existsSync()) return file.absolute.path;
  }
  throw StateError('Missing test certificate $name');
}

String? _nativeLibrary() {
  final name = switch (Platform.operatingSystem) {
    'linux' => 'libct_ffi.so',
    'macos' => 'libct_ffi.dylib',
    'windows' => 'ct_ffi.dll',
    _ => null,
  };
  if (name == null) return null;
  for (final path in [
    if (Platform.environment['CONNECTANUM_NATIVE_LIB'] case final String path)
      path,
    for (final root in ['../../native/transport', 'native/transport'])
      for (final profile in ['ffi-test/release', 'release'])
        '$root/target/$profile/$name',
  ]) {
    if (File(path).existsSync()) return File(path).absolute.path;
  }
  return null;
}
