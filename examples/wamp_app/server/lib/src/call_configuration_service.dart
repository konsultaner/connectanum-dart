import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'server_config.dart';

final class CallConfigurationService {
  CallConfigurationService({
    Iterable<String> stunUrls = const [],
    TurnRestConfig? turnRest,
    this.staticConfigurationTtl = const Duration(hours: 1),
  }) : _stunUrls = List<String>.unmodifiable(stunUrls),
       _turnUrls = turnRest == null
           ? const []
           : List<String>.unmodifiable(turnRest.urls),
       _turnSharedSecret = turnRest?.sharedSecret,
       _turnCredentialTtl = turnRest?.credentialTtl;

  final List<String> _stunUrls;
  final List<String> _turnUrls;
  final String? _turnSharedSecret;
  final Duration? _turnCredentialTtl;
  final Duration staticConfigurationTtl;

  CallConfiguration forAccount(String username, {DateTime? now}) {
    final normalized = AccountRegistration.normalizeUsername(username);
    if (normalized.isEmpty) {
      throw const FormatException('ICE configuration account is invalid.');
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final servers = <CallIceServer>[
      for (final url in _stunUrls) CallIceServer(urls: [url]),
    ];
    final secret = _turnSharedSecret;
    final ttl = _turnCredentialTtl;
    if (secret != null && ttl != null) {
      final expiresAt = timestamp.add(ttl);
      final expiresSeconds = expiresAt.millisecondsSinceEpoch ~/ 1000;
      final turnUsername = '$expiresSeconds:$normalized';
      final credential = base64.encode(
        Hmac(
          sha1,
          utf8.encode(secret),
        ).convert(utf8.encode(turnUsername)).bytes,
      );
      servers.add(
        CallIceServer(
          urls: _turnUrls,
          username: turnUsername,
          credential: credential,
        ),
      );
      return CallConfiguration(iceServers: servers, expiresAt: expiresAt);
    }
    return CallConfiguration(
      iceServers: servers,
      expiresAt: timestamp.add(staticConfigurationTtl),
    );
  }
}
