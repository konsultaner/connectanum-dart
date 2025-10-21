/// TLS handling mode for a router endpoint.
enum TlsMode {
  /// Transport Layer Security is disabled; the listener accepts plain TCP.
  disabled,

  /// TLS handshakes and decryption happen inside the Dart router.
  dart,

  /// TLS is delegated to the native runtime.
  native,
}

extension TlsModeWireFormat on TlsMode {
  /// Returns the string representation used in the native JSON payload.
  String get wireValue {
    switch (this) {
      case TlsMode.disabled:
        return 'disabled';
      case TlsMode.dart:
        return 'dart';
      case TlsMode.native:
        return 'native';
    }
  }

  /// Parses a wire value into a [TlsMode].
  static TlsMode parse(String value) {
    switch (value) {
      case 'disabled':
        return TlsMode.disabled;
      case 'dart':
        return TlsMode.dart;
      case 'native':
        return TlsMode.native;
    }
    throw ArgumentError.value(value, 'value', 'Unsupported TLS mode');
  }
}
