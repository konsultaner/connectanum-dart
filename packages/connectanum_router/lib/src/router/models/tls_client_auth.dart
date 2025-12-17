import 'package:meta/meta.dart';

import 'validators.dart';

/// Client certificate verification mode for native TLS listeners.
enum TlsClientAuthMode {
  /// Client certificates are neither requested nor verified.
  disabled,

  /// Client certificates are requested but not required.
  optional,

  /// Client certificates are required and must verify against the configured CA.
  required,
}

extension TlsClientAuthModeWireFormat on TlsClientAuthMode {
  String get wireValue {
    switch (this) {
      case TlsClientAuthMode.disabled:
        return 'disabled';
      case TlsClientAuthMode.optional:
        return 'optional';
      case TlsClientAuthMode.required:
        return 'required';
    }
  }

  static TlsClientAuthMode parse(String value) {
    switch (value) {
      case 'disabled':
      case 'none':
        return TlsClientAuthMode.disabled;
      case 'optional':
        return TlsClientAuthMode.optional;
      case 'required':
        return TlsClientAuthMode.required;
    }
    throw ArgumentError.value(value, 'value', 'Unsupported client auth mode');
  }
}

/// Client certificate authentication configuration for native TLS.
@immutable
class TlsClientAuth {
  factory TlsClientAuth({
    required TlsClientAuthMode mode,
    required String caCertificatesPem,
  }) {
    if (mode == TlsClientAuthMode.disabled) {
      throw ArgumentError.value(
        mode,
        'mode',
        'TlsClientAuthMode.disabled should omit client auth instead.',
      );
    }
    final normalizedPem = normalizePem(caCertificatesPem, 'caCertificatesPem');
    return TlsClientAuth._(mode: mode, caCertificatesPem: normalizedPem);
  }

  const TlsClientAuth._({required this.mode, required this.caCertificatesPem});

  final TlsClientAuthMode mode;
  final String caCertificatesPem;

  Map<String, Object?> toNativeJson() => {
    'mode': mode.wireValue,
    'ca_certificates_pem': caCertificatesPem,
  };

  @override
  int get hashCode => Object.hash(mode, caCertificatesPem);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TlsClientAuth &&
            other.mode == mode &&
            other.caCertificatesPem == caCertificatesPem;
  }

  @override
  String toString() =>
      'TlsClientAuth(mode: $mode, caCertificatesPem: <hidden>)';
}
