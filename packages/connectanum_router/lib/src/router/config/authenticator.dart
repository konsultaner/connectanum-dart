import '../config/router_settings.dart';

/// Contextual information passed to authenticators during the handshake.
class AuthenticatorContext {
  AuthenticatorContext({
    required this.realm,
    required this.sessionId,
    required this.transport,
    this.helloDetails = const {},
  });

  final RealmSettings realm;
  final int sessionId;
  final TransportMetadata transport;
  final Map<String, Object?> helloDetails;
}

/// Metadata describing the transport connection initiating authentication.
class TransportMetadata {
  const TransportMetadata({
    required this.connectionId,
    this.peerAddress,
    this.isEncrypted = false,
  });

  final int connectionId;
  final String? peerAddress;
  final bool isEncrypted;
}

/// Represents the AUTHENTICATE frame from a client.
class AuthenticateMessage {
  AuthenticateMessage({required this.signature, this.extra = const {}});

  final String signature;
  final Map<String, Object?> extra;
}

/// Base interface for all authenticators.
abstract class Authenticator {
  const Authenticator();

  /// Auth method name handled by this authenticator (e.g., 'ticket').
  String get method;

  /// Handles the HELLO frame and returns a result.
  Future<AuthResult> onHello(AuthenticatorContext context);

  /// Handles AUTHENTICATE response after a challenge.
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  );
}

/// Factory responsible for creating authenticators for specific methods.
abstract class AuthenticatorFactory {
  const AuthenticatorFactory();

  /// Method identifier handled by this factory.
  String get method;

  /// Builds an authenticator instance for the given realm and options.
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  );
}

/// Outcome of authentication handling.
class AuthResult {
  const AuthResult._({
    required this.status,
    this.challenge,
    this.success,
    this.failure,
  });

  factory AuthResult.challenge(AuthChallenge challenge) =>
      AuthResult._(status: AuthStatus.challenge, challenge: challenge);

  factory AuthResult.success(AuthSuccess success) =>
      AuthResult._(status: AuthStatus.success, success: success);

  factory AuthResult.failure(AuthFailure failure) =>
      AuthResult._(status: AuthStatus.failure, failure: failure);

  final AuthStatus status;
  final AuthChallenge? challenge;
  final AuthSuccess? success;
  final AuthFailure? failure;

  bool get isChallenge => status == AuthStatus.challenge;
  bool get isSuccess => status == AuthStatus.success;
  bool get isFailure => status == AuthStatus.failure;
}

enum AuthStatus { challenge, success, failure }

/// Represents a challenge that should be sent to the client.
class AuthChallenge {
  const AuthChallenge({required this.extra, this.challenge = const {}});

  final Map<String, Object?> challenge;
  final Map<String, Object?> extra;
}

/// Represents a successful authentication.
class AuthSuccess {
  const AuthSuccess({
    required this.authId,
    required this.authRole,
    this.details = const {},
  });

  final String authId;
  final String authRole;
  final Map<String, Object?> details;
}

/// Represents an authentication failure.
class AuthFailure {
  const AuthFailure({
    required this.reason,
    this.message,
    this.details = const {},
  });

  final String reason;
  final String? message;
  final Map<String, Object?> details;
}
