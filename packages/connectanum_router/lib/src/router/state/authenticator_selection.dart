part of '../router_instance.dart';

class AuthenticatorSelection {
  AuthenticatorSelection._({
    required this.method,
    required this.factory,
    required Map<String, Object?> options,
  }) : options = Map<String, Object?>.unmodifiable(options);

  factory AuthenticatorSelection.anonymous() => AuthenticatorSelection._(
    method: 'anonymous',
    factory: null,
    options: const {},
  );

  factory AuthenticatorSelection({
    required String method,
    required AuthenticatorFactory factory,
    required Map<String, Object?> options,
  }) => AuthenticatorSelection._(
    method: method,
    factory: factory,
    options: options,
  );

  final String method;
  final AuthenticatorFactory? factory;
  final Map<String, Object?> options;

  bool get isAnonymous => factory == null;
}

AuthenticatorSelection? resolveAuthenticatorSelection({
  required RouterSettings settings,
  required ListenerSettings listenerSettings,
  required RealmSettings realmSettings,
  required Hello hello,
}) {
  final clientMethods = hello.details.authmethods ?? const <String>[];
  final realmMethods = realmSettings.auth.methods;
  final realmAllowed = realmMethods.toSet();
  final listenerAllowed = listenerSettings.authmethods.isEmpty
      ? null
      : listenerSettings.authmethods.toSet();

  bool listenerAllows(String method) =>
      listenerAllowed == null || listenerAllowed.contains(method);
  bool realmAllows(String method) {
    if (realmMethods.isEmpty) {
      return method == 'anonymous';
    }
    return realmAllowed.contains(method);
  }

  final Iterable<String> priority = clientMethods.isNotEmpty
      ? clientMethods
      : (realmMethods.isNotEmpty ? realmMethods : const ['anonymous']);

  for (final method in priority) {
    if (!realmAllows(method) || !listenerAllows(method)) {
      continue;
    }
    if (method == 'anonymous') {
      return AuthenticatorSelection.anonymous();
    }
    final selection = createAuthenticatorSelectionForMethod(
      settings: settings,
      realmSettings: realmSettings,
      method: method,
    );
    if (selection != null) {
      return selection;
    }
  }

  return null;
}

AuthenticatorSelection? createAuthenticatorSelectionForMethod({
  required RouterSettings settings,
  required RealmSettings realmSettings,
  required String method,
}) {
  final options = <String, Object?>{};
  final realmOptions = realmSettings.auth.optionsFor(method);
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

  return AuthenticatorSelection(
    method: method,
    factory: factory,
    options: options,
  );
}

TransportMetadata buildTransportMetadata({
  required RouterListener listener,
  required int connectionId,
}) {
  return TransportMetadata(
    connectionId: connectionId,
    peerAddress: null,
    isEncrypted: listener.endpoint.tlsMode != TlsMode.disabled,
  );
}

Map<String, Object?> helloDetailsToMap(Details details) {
  final map = <String, Object?>{};
  if (details.authid != null) {
    map['authid'] = details.authid;
  }
  if (details.authrole != null) {
    map['authrole'] = details.authrole;
  }
  if (details.authprovider != null) {
    map['authprovider'] = details.authprovider;
  }
  if (details.authmethod != null) {
    map['authmethod'] = details.authmethod;
  }
  if (details.authmethods != null) {
    map['authmethods'] = List<String>.from(details.authmethods!);
  }
  if (details.authextra != null) {
    map['authextra'] = Map<String, Object?>.from(details.authextra!);
  }
  if (details.nonce != null) {
    map['nonce'] = details.nonce;
  }
  if (details.challenge != null) {
    map['challenge'] = details.challenge;
  }
  if (details.iterations != null) {
    map['iterations'] = details.iterations;
  }
  if (details.keylen != null) {
    map['keylen'] = details.keylen;
  }
  return map;
}
