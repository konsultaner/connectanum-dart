/// Normalizes the legacy SCRAM configuration name, not the negotiated wire name.
String canonicalAuthMethod(String method) =>
    method == 'scram' ? 'wamp-scram' : method;

/// Returns the compatible SCRAM configuration name, or null for other methods.
String? authMethodAlias(String method) => switch (method) {
  'scram' => 'wamp-scram',
  'wamp-scram' => 'scram',
  _ => null,
};
