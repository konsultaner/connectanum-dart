import 'dart:async';

import '../config/authenticator.dart';

/// Details describing why a credential lookup deliberately rejected access.
class CredentialRejection implements Exception {
  CredentialRejection({
    required this.reason,
    this.message,
    this.arguments,
    this.argumentsKeywords,
  });

  final String reason;
  final String? message;
  final List<dynamic>? arguments;
  final Map<String, Object?>? argumentsKeywords;
}

/// Credential payload returned by [AuthCredentialProvider.loadTicket].
class TicketCredential {
  TicketCredential({
    required this.ticket,
    this.role,
    this.provider,
    this.authExtra,
    this.challenge,
  });

  final String ticket;
  final String? role;
  final String? provider;
  final Map<String, Object?>? authExtra;
  final Map<String, Object?>? challenge;
}

/// Credential payload returned by [AuthCredentialProvider.loadCra].
class CraCredential {
  CraCredential({
    this.secret,
    this.derivedKey,
    this.salt,
    this.iterations,
    this.keyLen,
    this.role,
    this.provider,
    this.authExtra,
    this.challenge,
  }) : assert(
         secret != null || derivedKey != null,
         'Provide either secret or derivedKey for CRA credentials.',
       );

  final String? secret;
  final String? derivedKey;
  final String? salt;
  final int? iterations;
  final int? keyLen;
  final String? role;
  final String? provider;
  final Map<String, Object?>? authExtra;
  final Map<String, Object?>? challenge;
}

/// Credential payload returned by [AuthCredentialProvider.loadScram].
class ScramCredential {
  ScramCredential({
    this.secret,
    this.storedKey,
    this.serverKey,
    this.salt,
    this.iterations,
    this.memory,
    this.kdf,
    this.role,
    this.provider,
    this.authExtra,
  }) : assert(
         secret != null || (storedKey != null && storedKey.isNotEmpty),
         'Provide either secret or storedKey for SCRAM credentials.',
       );

  final String? secret;
  final String? storedKey;
  final String? serverKey;
  final String? salt;
  final int? iterations;
  final int? memory;
  final String? kdf;
  final String? role;
  final String? provider;
  final Map<String, Object?>? authExtra;
}

/// Credential payload returned by [AuthCredentialProvider.loadCryptosign].
class CryptosignCredential {
  CryptosignCredential({
    required this.publicKey,
    this.channelBinding,
    this.role,
    this.provider,
    this.authExtra,
  });

  final String publicKey;
  final String? channelBinding;
  final String? role;
  final String? provider;
  final Map<String, Object?>? authExtra;
}

/// Optional hook for delivering lookup result information to observers.
class CredentialLookupEvent {
  CredentialLookupEvent({
    required this.method,
    required this.realmUri,
    required this.authId,
    required this.hit,
    this.reason,
    this.message,
    this.arguments,
    this.argumentsKeywords,
  });

  final String method;
  final String realmUri;
  final String authId;
  final bool hit;
  final String? reason;
  final String? message;
  final List<dynamic>? arguments;
  final Map<String, Object?>? argumentsKeywords;
}

AuthFailure authFailureFromRejection(CredentialRejection rejection) =>
    AuthFailure(
      reason: rejection.reason,
      message: rejection.message,
      arguments: rejection.arguments,
      argumentsKeywords: rejection.argumentsKeywords,
    );

/// Pluggable credential provider used by router authenticators.
abstract class AuthCredentialProvider {
  const AuthCredentialProvider();

  Future<TicketCredential?> loadTicket({
    required String realmUri,
    required String authId,
  }) async => null;

  Future<CraCredential?> loadCra({
    required String realmUri,
    required String authId,
  }) async => null;

  Future<ScramCredential?> loadScram({
    required String realmUri,
    required String authId,
  }) async => null;

  Future<CryptosignCredential?> loadCryptosign({
    required String realmUri,
    required String authId,
  }) async => null;
}

typedef CredentialLookupListener = void Function(CredentialLookupEvent event);

/// Global registry for router authentication credential providers.
class AuthCredentialRegistry {
  AuthCredentialRegistry._();

  static AuthCredentialProvider? _provider;
  static final List<CredentialLookupListener> _listeners = [];

  /// Registers a credential provider that the router authenticators can use.
  static void registerProvider(AuthCredentialProvider provider) {
    _provider = provider;
  }

  /// Removes any previously registered credential provider.
  static void clearProvider() {
    _provider = null;
  }

  /// Registers a listener that is invoked after each credential lookup.
  static void registerListener(CredentialLookupListener listener) {
    _listeners.add(listener);
  }

  /// Clears all registered listeners.
  static void clearListeners() {
    _listeners.clear();
  }

  static AuthCredentialProvider? get provider => _provider;

  static void _emit({
    required String method,
    required String realmUri,
    required String authId,
    required bool hit,
    CredentialRejection? rejection,
  }) {
    if (_listeners.isEmpty) {
      return;
    }
    final event = CredentialLookupEvent(
      method: method,
      realmUri: realmUri,
      authId: authId,
      hit: hit,
      reason: rejection?.reason,
      message: rejection?.message,
      arguments: rejection?.arguments,
      argumentsKeywords: rejection?.argumentsKeywords,
    );
    for (final listener in _listeners.toList()) {
      listener(event);
    }
  }

  static Future<TicketCredential?> loadTicket({
    required String realmUri,
    required String authId,
  }) async {
    final repo = _provider;
    if (repo == null) {
      return null;
    }
    try {
      final credential = await repo.loadTicket(
        realmUri: realmUri,
        authId: authId,
      );
      _emit(
        method: 'ticket',
        realmUri: realmUri,
        authId: authId,
        hit: credential != null,
      );
      return credential;
    } on CredentialRejection catch (rejection) {
      _emit(
        method: 'ticket',
        realmUri: realmUri,
        authId: authId,
        hit: false,
        rejection: rejection,
      );
      rethrow;
    }
  }

  static Future<CraCredential?> loadCra({
    required String realmUri,
    required String authId,
  }) async {
    final repo = _provider;
    if (repo == null) {
      return null;
    }
    try {
      final credential = await repo.loadCra(realmUri: realmUri, authId: authId);
      _emit(
        method: 'wampcra',
        realmUri: realmUri,
        authId: authId,
        hit: credential != null,
      );
      return credential;
    } on CredentialRejection catch (rejection) {
      _emit(
        method: 'wampcra',
        realmUri: realmUri,
        authId: authId,
        hit: false,
        rejection: rejection,
      );
      rethrow;
    }
  }

  static Future<ScramCredential?> loadScram({
    required String realmUri,
    required String authId,
  }) async {
    final repo = _provider;
    if (repo == null) {
      return null;
    }
    try {
      final credential = await repo.loadScram(
        realmUri: realmUri,
        authId: authId,
      );
      _emit(
        method: 'scram',
        realmUri: realmUri,
        authId: authId,
        hit: credential != null,
      );
      return credential;
    } on CredentialRejection catch (rejection) {
      _emit(
        method: 'scram',
        realmUri: realmUri,
        authId: authId,
        hit: false,
        rejection: rejection,
      );
      rethrow;
    }
  }

  static Future<CryptosignCredential?> loadCryptosign({
    required String realmUri,
    required String authId,
  }) async {
    final repo = _provider;
    if (repo == null) {
      return null;
    }
    try {
      final credential = await repo.loadCryptosign(
        realmUri: realmUri,
        authId: authId,
      );
      _emit(
        method: 'cryptosign',
        realmUri: realmUri,
        authId: authId,
        hit: credential != null,
      );
      return credential;
    } on CredentialRejection catch (rejection) {
      _emit(
        method: 'cryptosign',
        realmUri: realmUri,
        authId: authId,
        hit: false,
        rejection: rejection,
      );
      rethrow;
    }
  }

  /// Clears all registered providers and listeners (useful for tests).
  static void reset() {
    clearProvider();
    clearListeners();
  }
}
