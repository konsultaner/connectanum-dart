import 'package:connectanum_core/connectanum_core.dart' as wamp_core show Error;
import '../config/auth_registry.dart';
import '../config/authenticator.dart';
import '../config/router_settings.dart';

bool _defaultsRegistered = false;

/// Registers the built-in authenticator factories. This should be invoked in
/// every isolate that intends to use [AuthenticatorRegistry].
void registerDefaultAuthenticators() {
  if (_defaultsRegistered &&
      AuthenticatorRegistry.factoryFor(
            const _AnonymousAuthenticatorFactory().method,
          ) !=
          null) {
    return;
  }
  AuthenticatorRegistry.registerFactory(const _AnonymousAuthenticatorFactory());
  _defaultsRegistered = true;
}

class _AnonymousAuthenticatorFactory extends AuthenticatorFactory {
  const _AnonymousAuthenticatorFactory();

  @override
  String get method => 'anonymous';

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    return _AnonymousAuthenticator(options);
  }
}

class _AnonymousAuthenticator extends Authenticator {
  _AnonymousAuthenticator(this._options);

  final Map<String, Object?> _options;

  @override
  String get method => 'anonymous';

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    final authId =
        _options['authid'] as String? ??
        context.helloDetails['authid'] as String? ??
        'anonymous';
    final authRole = _options['authrole'] as String? ?? 'anonymous';
    final authProvider = _options['authprovider'] as String? ?? 'static';

    return AuthResult.success(
      AuthSuccess(
        authId: authId,
        authRole: authRole,
        details: <String, Object?>{'authprovider': authProvider},
      ),
    );
  }

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) async {
    return AuthResult.failure(
      const AuthFailure(
        reason: wamp_core.Error.protocolViolation,
        message: 'AUTHENTICATE is not expected for anonymous sessions',
      ),
    );
  }
}
