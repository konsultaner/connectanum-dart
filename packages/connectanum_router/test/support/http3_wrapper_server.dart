import 'dart:io';
import 'package:connectanum_router/connectanum_router.dart';

Future<void> main(List<String> args) async {
  final certs = Directory(args[1]);
  String pem(String name) => File('${certs.path}/$name').readAsStringSync();
  final settings = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('fixture')
        ..addAuthMethod('anonymous')
        ..addRoleFromBuilder(
          RoleSettingsBuilder('internal')..addPermissionFromBuilder(
            PermissionSettingsBuilder('echo')
              ..allowOperations(['register', 'call', 'unregister']),
          ),
        ),
    )
    ..addListenerFromBuilder(
      ListenerSettingsBuilder('fixture', '127.0.0.1:0')
        ..addAuthMethod('anonymous')
        ..addProtocol(ListenerProtocol.http)
        ..addProtocol(ListenerProtocol.http3)
        ..setHttpOptions(
          HttpListenerSettings(
            routes: [
              HttpRouteSettings(
                match: HttpRouteMatch(path: '/echo'),
                action: HttpRouteAction(
                  type: HttpRouteActionType.rpc,
                  realm: 'fixture',
                  procedure: 'echo',
                ),
              ),
            ],
          ),
        ),
    );
  final runtime = NativeTransportRuntime(libraryPath: args[0]);
  runtime.start();
  final router = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 0,
          maxRawSocketSizeExponent: 16,
          tlsMode: TlsMode.native,
          sniCertificates: [
            SniCertificate(
              hostname: 'localhost',
              certificateChainPem: pem('http3_cert.pem'),
              privateKeyPem: pem('http3_key.pem'),
            ),
          ],
        ),
      ],
    ),
    settings: settings.build(),
  );
  final binding = router.start(runtime);
  try {
    final session = await binding.createInternalSession(
      realmUri: 'fixture',
      authRole: 'internal',
    );
    final registration = await session.register('echo');
    registration.onInvoke((invocation) {
      final context = HttpInvocationContext.maybeFromInvocation(invocation)!;
      final body = context.request.body;
      final stream = context.streamResponse(
        status: 207,
        headers: {'x-fixture': 'echo'},
      );
      stream.close(body);
    });
    stdout.writeln(binding.listeners.single.http3Port);
    await stdin.first;
    await session.close();
  } finally {
    await binding.dispose();
    runtime.shutdown();
    runtime.dispose();
  }
}
