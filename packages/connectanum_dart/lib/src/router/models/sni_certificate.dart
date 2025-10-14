import 'package:meta/meta.dart';

import 'validators.dart';

/// TLS certificate bundle assigned to a specific SNI hostname.
@immutable
class SniCertificate {
  factory SniCertificate({
    required String hostname,
    required String certificateChainPem,
    required String privateKeyPem,
  }) {
    final normalizedHostname = normalizeHostname(hostname);
    final normalizedChain =
        normalizePem(certificateChainPem, 'certificateChainPem');
    final normalizedKey = normalizePem(privateKeyPem, 'privateKeyPem');
    return SniCertificate._(
      hostname: normalizedHostname,
      certificateChainPem: normalizedChain,
      privateKeyPem: normalizedKey,
    );
  }

  const SniCertificate._({
    required this.hostname,
    required this.certificateChainPem,
    required this.privateKeyPem,
  });

  /// Hostname the certificate is valid for.
  final String hostname;

  /// Certificate chain in PEM format.
  final String certificateChainPem;

  /// Private key in PEM format.
  final String privateKeyPem;

  Map<String, Object?> toNativeJson() => {
        'hostname': hostname,
        'certificate_chain_pem': certificateChainPem,
        'private_key_pem': privateKeyPem,
      };

  @override
  int get hashCode => Object.hash(
        hostname,
        certificateChainPem,
        privateKeyPem,
      );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SniCertificate &&
            other.hostname == hostname &&
            other.certificateChainPem == certificateChainPem &&
            other.privateKeyPem == privateKeyPem;
  }

  @override
  String toString() =>
      'SniCertificate(hostname: $hostname, certificateChainPem: <hidden>, privateKeyPem: <hidden>)';
}
