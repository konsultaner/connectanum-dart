import 'dart:io';

import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/message/publish.dart' as publish_msg;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/router_config.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_client/connectanum.dart' as client_pkg;
import 'package:connectanum_client/src/transport/socket/socket_transport.dart'
    as socket_transport;
import 'package:connectanum_client/src/transport/socket/socket_helper.dart'
    as socket_helper;
import 'package:test/test.dart';

void main() {
  final nativeLib = resolveOrBuildNativeLib();
  if (nativeLib == null) {
    return;
  }

  test('rawsocket publish ack succeeds', () async {
    final runtime = NativeTransportRuntime(libraryPath: nativeLib)..start();
    addTearDown(() {
      runtime.shutdown();
      runtime.dispose();
    });

    final settings = RouterSettingsBuilder()
        .addRealmFromBuilder(
          RealmSettingsBuilder('bench.control')
            ..addAuthMethod('anonymous')
            ..addRoleFromBuilder(
              RoleSettingsBuilder('bench')..addPermissionFromBuilder(
                PermissionSettingsBuilder('')..allowOperations(const [
                  'register',
                  'unregister',
                  'subscribe',
                  'unsubscribe',
                  'publish',
                  'call',
                ]),
              ),
            ),
        )
        .addListenerFromBuilder(
          ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
            ..addAuthMethod('anonymous')
            ..setRawSocketOptions(
              const RawSocketListenerSettings(maxFrameExponent: 18),
            ),
        )
        .addAuthenticator(
          'anonymous',
          const AuthenticatorDefinition(type: 'anonymous'),
        )
        .build();

    final endpoint = Endpoint(
      host: '127.0.0.1',
      port: 0,
      tlsMode: TlsMode.disabled,
      maxRawSocketSizeExponent: 18,
    );
    final config = RouterConfig(endpoints: [endpoint]);

    final router = Router(config, settings: settings);
    final binding = router.start(runtime);
    addTearDown(binding.dispose);

    final listener = binding.listeners.single;
    expect(listener.port, greaterThan(0));

    final serializer = json_serializer.Serializer();
    final transport = socket_transport.SocketTransport(
      '127.0.0.1',
      listener.port,
      serializer,
      socket_helper.SocketHelper.serializationJson,
    );
    final client = client_pkg.Client(
      realm: 'bench.control',
      transport: transport,
    );

    final session = await client.connect().first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('connect timeout'),
    );
    addTearDown(() => session.close());

    await session.subscribe('bench.test.topic');
    await session
        .publish(
          'bench.test.topic',
          options: publish_msg.PublishOptions(acknowledge: true),
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('publish timeout'),
        );
  });
}
