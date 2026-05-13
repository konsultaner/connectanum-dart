import 'authenticator.dart';

/// Registry for pluggable authenticator factories.
class AuthenticatorRegistry {
  AuthenticatorRegistry._();

  static final Map<String, AuthenticatorFactory> _factories = {};

  /// Registers a factory. Overwrites any existing factory for the same method.
  static void registerFactory(AuthenticatorFactory factory) {
    _factories[factory.method] = factory;
  }

  /// Registers multiple factories in one call.
  static void registerFactories(Iterable<AuthenticatorFactory> factories) {
    for (final factory in factories) {
      registerFactory(factory);
    }
  }

  /// Unregisters a factory.
  static void unregisterFactory(String method) {
    _factories.remove(method);
  }

  /// Retrieves a factory by method, or null if none registered.
  static AuthenticatorFactory? factoryFor(String method) => _factories[method];

  /// Returns an immutable view of the registered factories.
  static Map<String, AuthenticatorFactory> get factories =>
      Map.unmodifiable(_factories);

  /// Removes all registered factories (useful for tests).
  static void clear() => _factories.clear();
}
