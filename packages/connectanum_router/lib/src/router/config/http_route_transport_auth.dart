import 'router_settings.dart';

class HttpRouteTransportAuthRequirements {
  const HttpRouteTransportAuthRequirements({
    this.requireBearer = false,
    this.requireTls = false,
    this.requireMutualTls = false,
  });

  final bool requireBearer;
  final bool requireTls;
  final bool requireMutualTls;

  bool get isConfigured => requireBearer || requireTls || requireMutualTls;

  Map<String, Object?> toNativeMap() {
    if (!isConfigured) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      if (requireBearer) 'require_bearer': true,
      if (requireTls) 'require_tls': true,
      if (requireMutualTls) 'require_mtls': true,
    };
  }
}

bool httpSessionProfileAllowsAnonymous(SessionProfileSettings? sessionProfile) {
  final methods = sessionProfile?.auth.methods;
  if (methods == null || methods.isEmpty) {
    return true;
  }
  return methods.contains('anonymous');
}

HttpRouteTransportAuthRequirements deriveHttpRouteTransportAuth({
  required HttpRouteAction action,
  required SessionProfileSettings? sessionProfile,
}) {
  final options = action.options;
  final explicitBearer = _boolOption(
    options['require_bearer'] ?? options['bearer_required'],
  );
  final explicitTls = _boolOption(
    options['require_tls'] ?? options['tls_required'],
  );
  final explicitMutualTls = _boolOption(
    options['require_mtls'] ??
        options['mtls_required'] ??
        options['require_mutual_tls'],
  );
  final allowInsecureTransport =
      _boolOption(options['allow_insecure_transport']) ?? false;

  final methods = sessionProfile?.auth.methods ?? const <String>[];
  final hasHttpProvider =
      sessionProfile?.auth.httpProvider?.trim().isNotEmpty == true;
  final allowsAnonymous = httpSessionProfileAllowsAnonymous(sessionProfile);
  final protectedProfile =
      !allowsAnonymous && (methods.isNotEmpty || hasHttpProvider);
  final requireBearer =
      explicitBearer ??
      (action.type == HttpRouteActionType.auth ? false : protectedProfile);
  final requireMutualTls = explicitMutualTls ?? false;
  final requireTls =
      explicitTls ??
      (requireMutualTls ||
          (!allowInsecureTransport &&
              (protectedProfile || action.type == HttpRouteActionType.auth)));

  return HttpRouteTransportAuthRequirements(
    requireBearer: requireBearer,
    requireTls: requireTls,
    requireMutualTls: requireMutualTls,
  );
}

bool? _boolOption(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  throw FormatException(
    'HTTP route transport auth flags must be bool or "true"/"false" strings',
  );
}
