import 'dart:io';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../config/router_settings.dart';
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
    if (tlsMode == TlsMode.native && certs.isEmpty) {
      throw ArgumentError.value(
        sniCertificates,
        'sniCertificates',
        'Native TLS requires at least one SNI certificate',
      );
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

  /// Builds an [Endpoint] from a parsed [ListenerSettings] entry.
  factory Endpoint.fromListenerSettings(ListenerSettings settings) {
    final parsed = _parseEndpoint(settings.endpoint);
    final options = settings.options;
    final maxExponent = _asInt(
      options['max_rawsocket_size_exponent'],
      defaultValue: 16,
    );
    final idleTimeout = _asDuration(options['idle_timeout_ms']);
    final handshakeTimeout = _asDuration(options['handshake_timeout_ms']);
    final maxHttpContentLength = options['max_http_content_length'] is int
        ? options['max_http_content_length'] as int
        : null;
    final tlsConfig = settings.tls;
    final tlsMode = _resolveTlsMode(tlsConfig);
    final sniCertificates = _resolveSniCertificates(tlsConfig);
    final webSocketPath = settings.path;
    return Endpoint(
      host: parsed.host,
      port: parsed.port,
      tlsMode: tlsMode,
      idleTimeout: idleTimeout,
      handshakeTimeout: handshakeTimeout,
      maxHttpContentLength: maxHttpContentLength,
      maxRawSocketSizeExponent: maxExponent,
      webSocketPath: webSocketPath,
      sniCertificates: sniCertificates,
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

class _ParsedEndpoint {
  const _ParsedEndpoint({required this.host, required this.port});

  final String host;
  final int port;
}

_ParsedEndpoint _parseEndpoint(String value) {
  Uri? uri;
  if (value.contains('://')) {
    uri = Uri.tryParse(value);
  }
  if (uri != null && uri.host.isNotEmpty) {
    final port = uri.hasPort ? uri.port : 0;
    return _ParsedEndpoint(host: uri.host, port: port);
  }
  final lastColon = value.lastIndexOf(':');
  if (lastColon == -1) {
    throw FormatException('Endpoint "$value" missing port separator');
  }
  final host = value.substring(0, lastColon);
  final portPart = value.substring(lastColon + 1);
  final port = int.parse(portPart);
  return _ParsedEndpoint(host: host, port: port);
}

TlsMode _resolveTlsMode(Map<String, Object?>? tls) {
  if (tls == null) {
    return TlsMode.disabled;
  }
  final mode = tls['mode'];
  if (mode is String) {
    switch (mode.toLowerCase()) {
      case 'native':
        return TlsMode.native;
      case 'disabled':
      case 'none':
        return TlsMode.disabled;
    }
  }
  return TlsMode.native;
}

List<SniCertificate> _resolveSniCertificates(Map<String, Object?>? tls) {
  if (tls == null) {
    return const [];
  }
  final entries = tls['sni_certificates'];
  if (entries is! List) {
    return const [];
  }
  return entries
      .map((entry) {
        if (entry is! Map<String, Object?>) {
          throw FormatException('sni_certificates entries must be maps');
        }
        final hostname = entry['hostname'];
        if (hostname is! String || hostname.trim().isEmpty) {
          throw FormatException('sni_certificates entries require hostname');
        }
        final certPem = _loadPem(
          inline: entry['certificate_chain_pem'],
          filePath: entry['certificate_chain_file'],
          description: 'certificate_chain',
        );
        final keyPem = _loadPem(
          inline: entry['private_key_pem'],
          filePath: entry['private_key_file'],
          description: 'private_key',
        );
        return SniCertificate(
          hostname: hostname,
          certificateChainPem: certPem,
          privateKeyPem: keyPem,
        );
      })
      .toList(growable: false);
}

String _loadPem({
  Object? inline,
  Object? filePath,
  required String description,
}) {
  if (inline is String && inline.trim().isNotEmpty) {
    return inline;
  }
  if (filePath is String && filePath.trim().isNotEmpty) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('SNI $description file not found', filePath);
    }
    return file.readAsStringSync();
  }
  throw FormatException(
    'SNI $description requires either *_pem or *_file entry',
  );
}

int _asInt(Object? value, {int? defaultValue}) {
  if (value == null) {
    if (defaultValue != null) {
      return defaultValue;
    }
    throw FormatException('Expected integer value');
  }
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.parse(value);
  }
  throw FormatException('Expected integer value');
}

Duration? _asDuration(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return Duration(milliseconds: value);
  }
  if (value is String) {
    return Duration(milliseconds: int.parse(value));
  }
  throw FormatException('Expected duration in milliseconds');
}
