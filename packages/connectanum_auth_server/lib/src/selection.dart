part of 'auth_server.dart';

class _AuthenticatorSelection {
  _AuthenticatorSelection({
    required this.method,
    required this.factory,
    required this.options,
  });

  final String method;
  final AuthenticatorFactory factory;
  final Map<String, Object?> options;
}

_AuthenticatorSelection? _selectAuthenticator({
  required RouterSettings settings,
  required RealmSettings realm,
  required List<String> clientMethods,
}) {
  final candidateOrders = <List<String>>[];
  if (clientMethods.isNotEmpty) {
    candidateOrders.add(clientMethods);
  }
  if (realm.auth.methods.isNotEmpty) {
    candidateOrders.add(realm.auth.methods);
  }
  candidateOrders.add(const ['anonymous']);

  for (final methods in candidateOrders) {
    for (final method in methods) {
      final selection = _createSelectionForMethod(
        settings: settings,
        realm: realm,
        method: method,
      );
      if (selection != null) {
        return selection;
      }
    }
  }
  return null;
}

_AuthenticatorSelection? _createSelectionForMethod({
  required RouterSettings settings,
  required RealmSettings realm,
  required String method,
}) {
  final options = <String, Object?>{};
  final realmOptions = realm.auth.optionsFor(method);
  String? authenticatorKey;
  if (realmOptions != null) {
    authenticatorKey =
        realmOptions['authenticator'] as String? ??
        realmOptions['use'] as String?;
    options.addAll(realmOptions);
    options.remove('authenticator');
    options.remove('use');
  }

  final definitionKey = authenticatorKey ?? method;
  final definition = settings.authenticators[definitionKey];
  final factoryKey = definition?.type ?? definitionKey;
  final factory = AuthenticatorRegistry.factoryFor(factoryKey);
  if (factory == null) {
    return null;
  }

  if (definition != null) {
    options.addAll(definition.options);
  }
  options['authenticator'] ??= definitionKey;

  return _AuthenticatorSelection(
    method: method,
    factory: factory,
    options: Map<String, Object?>.unmodifiable(options),
  );
}
