part of '../router_instance.dart';

/// High-level router builder that applies configuration to the native runtime
/// and returns a ready-to-use [RouterBinding].
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

  RouterBinding start(
    NativeRuntime runtime, {
    RouterWorkerEntryPoint? workerEntryPoint,
    Duration workerPollInterval = const Duration(milliseconds: 1),
    void Function(Object event)? onEvent,
    bool activateListeners = true,
  }) {
    final configBytes = buildNativeConfigJson();
    try {
      runtime.applyRouterConfig(configBytes);
    } on UnsupportedError {
      // Ignore runtimes that do not yet support configuration wiring.
    }
    final binding = RouterBinding(
      runtime: runtime,
      endpoints: config.endpoints,
      configJson: configBytes,
      workerEntryPoint: workerEntryPoint ?? _routerWorkerEntryPoint,
      workerPollInterval: workerPollInterval,
      onEvent: onEvent,
    );
    if (activateListeners) {
      binding.activateListeners();
    }
    return binding;
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
