import 'dart:convert';
import 'dart:io';

import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    throw ArgumentError(
      'Expected Python executable, peer script, bindings and transport',
    );
  }
  final transport = args[3];
  if (transport != 'rawsocket' && transport != 'websocket') {
    throw ArgumentError('Unsupported reference transport');
  }
  final library = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (library == null) throw StateError('CONNECTANUM_NATIVE_LIB is required');
  final settings =
      (RouterSettingsBuilder()
            ..addRealmFromBuilder(
              RealmSettingsBuilder('realm1')
                ..addAuthMethod(
                  'ticket',
                  options: const {'authenticator': 'profile-ticket'},
                )
                ..addRoleFromBuilder(
                  RoleSettingsBuilder('anonymous')..addPermissionFromBuilder(
                    PermissionSettingsBuilder('')
                      ..setMatchPolicy(PermissionMatchPolicy.prefix)
                      ..allowOperations([
                        'call',
                        'register',
                        'subscribe',
                        'publish',
                      ]),
                  ),
                ),
            )
            ..addListenerFromBuilder(
              ListenerSettingsBuilder(transport, '127.0.0.1:0')
                ..addAuthMethod('ticket')
                ..setOptions({'max_rawsocket_size_exponent': 20})
                ..setPath('/wamp')
                ..setWebSocketOptions(
                  const WebSocketListenerSettings(
                    subprotocols: ['wamp.2.flatbuffers'],
                  ),
                ),
            )
            ..addAuthenticator(
              'profile-ticket',
              const AuthenticatorDefinition(
                type: 'ticket',
                options: {
                  'secrets': {
                    'alice': {'ticket': 'profile-ticket', 'role': 'anonymous'},
                  },
                },
              ),
            ))
          .build();
  final runtime = NativeTransportRuntime(libraryPath: library)..start();
  final errors = <Object>[];
  final binding =
      Router(
        RouterConfig(
          endpoints: [
            Endpoint(
              host: '127.0.0.1',
              port: 0,
              tlsMode: TlsMode.disabled,
              maxRawSocketSizeExponent: 20,
              webSocketPath: '/wamp',
            ),
          ],
        ),
        settings: settings,
      ).start(
        runtime,
        onEvent: (event) {
          if (event is Map && event['type'] == 'worker_error') {
            errors.add(event);
          }
        },
      );
  try {
    final result = await Process.run(
      args[0],
      [args[1], args[2], '${binding.listeners.single.port}', transport],
      environment: {'PYTHONDONTWRITEBYTECODE': '1'},
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      throw StateError('Reference peer exited ${result.exitCode}');
    }
    final report = jsonDecode((result.stdout as String).trim()) as Map;
    if (report['status'] != 'passed' || errors.isNotEmpty) {
      throw StateError('Reference peer or router failed: $errors');
    }
  } finally {
    await binding.dispose();
    runtime.shutdown();
    runtime.dispose();
  }
}
