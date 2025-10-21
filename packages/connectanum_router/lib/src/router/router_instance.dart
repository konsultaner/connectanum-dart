import 'dart:convert';
import 'dart:typed_data';

import 'models/router_config.dart';
import 'models/endpoint.dart';
import 'models/tls_mode.dart';
import '../native/runtime.dart';

/// Router façade that bridges the Dart configuration to the native runtime.
class RouterListener {
  const RouterListener({
    required this.listenerId,
    required this.endpoint,
    required this.port,
  });

  final int listenerId;
  final Endpoint endpoint;
  final int port;
}

class RouterBinding {
  const RouterBinding({required this.listeners, required this.configJson});

  final List<RouterListener> listeners;
  final Uint8List configJson;
}

class Router {
  Router(this.config) {
    _validateConfig();
  }

  final RouterConfig config;

  /// Builds the JSON payload expected by the native runtime.
  Uint8List buildNativeConfigJson() {
    final map = _buildNativeMap();
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  RouterBinding start(NativeRuntime runtime) {
    final configBytes = buildNativeConfigJson();
    try {
      runtime.applyRouterConfig(configBytes);
    } on UnsupportedError {
      // Ignore runtimes that do not yet support configuration wiring.
    }
    final listeners = <RouterListener>[];
    for (final endpoint in config.endpoints) {
      final listenerId = runtime.listen(endpoint.host, endpoint.port);
      final boundPort = runtime.getLocalPort(listenerId);
      listeners.add(
        RouterListener(
          listenerId: listenerId,
          endpoint: endpoint,
          port: boundPort,
        ),
      );
    }
    return RouterBinding(listeners: listeners, configJson: configBytes);
  }

  Map<String, Object?> _buildNativeMap() => {
    'schema': config.schema,
    'version': config.version,
    'endpoints': config.endpoints
        .map((endpoint) => endpoint.toNativeJson())
        .toList(),
  };

  void _validateConfig() {
    if (config.endpoints.isEmpty) {
      throw ArgumentError('Router requires at least one endpoint');
    }
    final tlsModes = <TlsMode>{};
    final sniHosts = <String>{};
    int? nativeExponent;
    for (final endpoint in config.endpoints) {
      tlsModes.add(endpoint.tlsMode);
      if (endpoint.tlsMode == TlsMode.native) {
        nativeExponent ??= endpoint.maxRawSocketSizeExponent;
        if (endpoint.maxRawSocketSizeExponent != nativeExponent) {
          throw ArgumentError(
            'All native TLS endpoints must share the same maxRawSocketSizeExponent. '
            'Expected $nativeExponent but found ${endpoint.maxRawSocketSizeExponent} on ${endpoint.host}:${endpoint.port}.',
          );
        }
      }
      for (final cert in endpoint.sniCertificates) {
        final key = cert.hostname.toLowerCase();
        if (!sniHosts.add(key)) {
          throw ArgumentError(
            'Duplicate SNI hostname "${cert.hostname}" detected across router endpoints',
          );
        }
      }
    }
    if (tlsModes.contains(TlsMode.native) && tlsModes.contains(TlsMode.dart)) {
      throw ArgumentError(
        'Mixing native and Dart TLS modes across endpoints is currently unsupported',
      );
    }
  }
}
