import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_router/src/router/auth/remote_wamp_delegate.dart';

// Run in a fresh VM with --root-certs-file so the default trust store is local
// to this probe, independent of the host's certificate store and TLS caches.
Future<void> main(List<String> arguments) async {
  final fixtures = Directory(arguments.single);
  String fixture(String name) => '${fixtures.path}/$name';
  final servers = <SecureServerSocket>[];
  final sockets = <SecureSocket>[];
  final subscriptions = <StreamSubscription<SecureSocket>>[];
  Future<int> serve(String certificate, String key) async {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChain(fixture(certificate))
      ..usePrivateKey(fixture(key));
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    servers.add(server);
    subscriptions.add(
      server.listen(
        (socket) {
          sockets.add(socket);
          socket.add([42]);
        },
        onError: (Object error) {
          // Rejected client handshakes are expected in the negative controls.
          if (error is! HandshakeException) throw error;
        },
      ),
    );
    return server.port;
  }

  Future<bool> accepts(int port, SecurityContext? context) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        InternetAddress.loopbackIPv4,
        port,
        context: context,
        timeout: const Duration(seconds: 5),
      );
      final bytes = await socket.first.timeout(const Duration(seconds: 5));
      if (bytes.length != 1 || bytes.single != 42) {
        throw StateError('Invalid TLS probe response');
      }
      return true;
    } on HandshakeException {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  try {
    final customPort = await serve(
      'remote_auth_server_cert.pem',
      'remote_auth_server_key.pem',
    );
    final defaultPort = await serve('http3_cert.pem', 'http3_key.pem');
    final results = <String, List<bool>>{};
    for (final customCa in [false, true]) {
      for (final clientCertificate in [false, true]) {
        final tls = RemoteWampTransportTlsConfig.parse({
          'tls': {
            if (customCa)
              'ca_certificates_file': fixture('remote_auth_ca_cert.pem'),
            if (clientCertificate) ...{
              'client_certificate_file': fixture('remote_auth_client_cert.pem'),
              'client_private_key_file': fixture('remote_auth_client_key.pem'),
            },
          },
        });
        final context = await tls.buildSecurityContext();
        results['customCa=$customCa,clientCertificate=$clientCertificate'] = [
          await accepts(customPort, context),
          await accepts(defaultPort, context),
        ];
      }
    }
    stdout.writeln(jsonEncode(results));
  } finally {
    for (final socket in sockets) {
      socket.destroy();
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final server in servers) {
      await server.close();
    }
  }
}
