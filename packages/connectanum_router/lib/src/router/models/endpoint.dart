import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'sni_certificate.dart';
import 'tls_mode.dart';
import 'validators.dart';

/// Immutable representation of a router endpoint configuration.
@immutable
class Endpoint {
  factory Endpoint({
    required String host,
    required int port,
    required TlsMode tlsMode,
    Duration? idleTimeout,
    Duration? handshakeTimeout,
    int? maxHttpContentLength,
    required int maxRawSocketSizeExponent,
    String? webSocketPath,
    List<SniCertificate> sniCertificates = const [],
  }) {
    final normalizedHost = normalizeHostname(host);
    final normalizedPort = normalizePort(port);
    final normalizedIdleTimeout = normalizeIdleTimeout(idleTimeout);
    final normalizedHandshakeTimeout = normalizeHandshakeTimeout(
      handshakeTimeout,
    );
    final normalizedMaxContentLength = normalizeMaxHttpContentLength(
      maxHttpContentLength,
    );
    final normalizedSocketSize = normalizeRawSocketSizeExponent(
      maxRawSocketSizeExponent,
    );
    final normalizedWebSocketPath = normalizeWebSocketPath(webSocketPath);

    final certs = List<SniCertificate>.unmodifiable(sniCertificates);
    final names = <String>{};
    for (final cert in certs) {
      final key = cert.hostname.toLowerCase();
      if (!names.add(key)) {
        throw ArgumentError.value(
          sniCertificates,
          'sniCertificates',
          'Duplicate SNI hostname "${cert.hostname}" detected',
        );
      }
    }

    return Endpoint._(
      host: normalizedHost,
      port: normalizedPort,
      tlsMode: tlsMode,
      idleTimeout: normalizedIdleTimeout,
      handshakeTimeout: normalizedHandshakeTimeout,
      maxHttpContentLength: normalizedMaxContentLength,
      maxRawSocketSizeExponent: normalizedSocketSize,
      webSocketPath: normalizedWebSocketPath,
      sniCertificates: certs,
    );
  }

  const Endpoint._({
    required this.host,
    required this.port,
    required this.tlsMode,
    required this.idleTimeout,
    required this.handshakeTimeout,
    required this.maxHttpContentLength,
    required this.maxRawSocketSizeExponent,
    required this.webSocketPath,
    required this.sniCertificates,
  });

  /// Hostname or IP address where the listener binds to.
  final String host;

  /// Port number (0 allows the OS to choose a free port).
  final int port;

  /// TLS handling mode.
  final TlsMode tlsMode;

  /// Optional idle timeout after which connections will be dropped (Dart-only).
  final Duration? idleTimeout;

  /// Optional handshake timeout for the initial RawSocket negotiation.
  final Duration? handshakeTimeout;

  /// Optional HTTP content length limit in bytes.
  final int? maxHttpContentLength;

  /// Connectanum-specific RawSocket size exponent.
  final int maxRawSocketSizeExponent;

  /// Optional WebSocket path (must start with `/`).
  final String? webSocketPath;

  /// SNI certificates handled by the native transport runtime.
  final List<SniCertificate> sniCertificates;

  /// Serialises the endpoint to a JSON structure suitable for the native layer.
  Map<String, Object?> toNativeJson() {
    final map = <String, Object?>{
      'host': host,
      'port': port,
      'tls_mode': tlsMode.wireValue,
      'max_rawsocket_size_exponent': maxRawSocketSizeExponent,
    };
    if (idleTimeout != null) {
      map['idle_timeout_ms'] = idleTimeout!.inMilliseconds;
    }
    if (handshakeTimeout != null) {
      map['handshake_timeout_ms'] = handshakeTimeout!.inMilliseconds;
    }
    if (maxHttpContentLength != null) {
      map['max_http_content_length'] = maxHttpContentLength;
    }
    if (webSocketPath != null) {
      map['websocket_path'] = webSocketPath;
    }
    if (sniCertificates.isNotEmpty) {
      map['sni_certificates'] = sniCertificates
          .map((cert) => cert.toNativeJson())
          .toList();
    }
    return map;
  }

  @override
  int get hashCode => Object.hash(
    host,
    port,
    tlsMode,
    idleTimeout?.inMilliseconds,
    handshakeTimeout?.inMilliseconds,
    maxHttpContentLength,
    maxRawSocketSizeExponent,
    webSocketPath,
    const DeepCollectionEquality().hash(sniCertificates),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Endpoint) {
      return false;
    }
    const deepEquality = DeepCollectionEquality();
    return other.host == host &&
        other.port == port &&
        other.tlsMode == tlsMode &&
        other.idleTimeout == idleTimeout &&
        other.handshakeTimeout == handshakeTimeout &&
        other.maxHttpContentLength == maxHttpContentLength &&
        other.maxRawSocketSizeExponent == maxRawSocketSizeExponent &&
        other.webSocketPath == webSocketPath &&
        deepEquality.equals(other.sniCertificates, sniCertificates);
  }

  @override
  String toString() => 'Endpoint(host: $host, port: $port, tlsMode: $tlsMode)';
}
