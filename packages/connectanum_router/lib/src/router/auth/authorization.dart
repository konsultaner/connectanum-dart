import 'dart:async';

import 'package:connectanum_core/connectanum_core.dart' as wamp_core;

import '../config/router_settings.dart';

/// Actions that can be authorized against a realm policy.
enum AuthorizationAction {
  subscribe,
  unsubscribe,
  publish,
  call,
  cancel,
  register,
  unregister,
}

extension AuthorizationActionX on AuthorizationAction {
  String get operationName => name;

  List<String> get operationCandidates => switch (this) {
    AuthorizationAction.subscribe => const <String>['subscribe'],
    AuthorizationAction.unsubscribe => const <String>[
      'unsubscribe',
      'subscribe',
    ],
    AuthorizationAction.publish => const <String>['publish'],
    AuthorizationAction.call => const <String>['call'],
    AuthorizationAction.cancel => const <String>['cancel', 'call'],
    AuthorizationAction.register => const <String>['register'],
    AuthorizationAction.unregister => const <String>['unregister', 'register'],
  };

  bool get usesTopicMatching => switch (this) {
    AuthorizationAction.subscribe ||
    AuthorizationAction.unsubscribe ||
    AuthorizationAction.publish => true,
    AuthorizationAction.call ||
    AuthorizationAction.cancel ||
    AuthorizationAction.register ||
    AuthorizationAction.unregister => false,
  };
}

/// Authorization request passed to static and dynamic authorizers.
class AuthorizationRequest {
  const AuthorizationRequest({
    required this.realmUri,
    required this.action,
    required this.uri,
    required this.sessionId,
    this.connectionId,
    this.authId,
    this.authRole,
    this.authMethod,
    this.authProvider,
    this.protocol,
    this.options = const <String, Object?>{},
    this.targetMatchPolicy,
    this.isInternal = false,
  });

  final String realmUri;
  final AuthorizationAction action;
  final String uri;
  final int sessionId;
  final int? connectionId;
  final String? authId;
  final String? authRole;
  final String? authMethod;
  final String? authProvider;
  final ListenerProtocol? protocol;
  final Map<String, Object?> options;
  final PermissionMatchPolicy? targetMatchPolicy;
  final bool isInternal;
}

/// Final allow/deny decision returned by the authorizer.
class AuthorizationDecision {
  const AuthorizationDecision.allow({this.message})
    : allowed = true,
      reason = '';

  const AuthorizationDecision.deny({
    this.reason = wamp_core.Error.notAuthorized,
    this.message,
  }) : allowed = false;

  final bool allowed;
  final String reason;
  final String? message;
}

/// Optional dynamic provider that can supplement static realm permissions.
abstract class AuthorizationProvider {
  FutureOr<AuthorizationDecision?> authorize(AuthorizationRequest request);
}

/// Global registry for optional authorization providers.
class AuthorizationProviderRegistry {
  AuthorizationProviderRegistry._();

  static AuthorizationProvider? _provider;

  static void registerProvider(AuthorizationProvider provider) {
    _provider = provider;
  }

  static void clear() {
    _provider = null;
  }

  static AuthorizationProvider? get provider => _provider;
}

/// Shared realm authorizer that combines static role permissions with an
/// optional dynamic provider.
class RealmAuthorizer {
  RealmAuthorizer._();

  static Future<AuthorizationDecision> authorize({
    required RealmSettings realmSettings,
    required AuthorizationRequest request,
  }) async {
    final hasStaticPolicy = realmSettings.roles.any(
      (role) => role.permissions.isNotEmpty,
    );
    final staticDecision = _evaluateStaticPermissions(
      realmSettings: realmSettings,
      request: request,
    );
    if (staticDecision != null && !staticDecision.allowed) {
      return staticDecision;
    }

    final provider = AuthorizationProviderRegistry.provider;
    final providerDecision = provider == null
        ? null
        : await provider.authorize(request);
    if (providerDecision != null) {
      if (!providerDecision.allowed) {
        return providerDecision;
      }
      return providerDecision;
    }

    if (staticDecision != null) {
      return staticDecision;
    }

    if (!hasStaticPolicy) {
      return const AuthorizationDecision.allow();
    }

    return AuthorizationDecision.deny(
      message:
          'Not authorized to ${request.action.operationName} ${request.uri} '
          'in realm ${request.realmUri}',
    );
  }

  static AuthorizationDecision? _evaluateStaticPermissions({
    required RealmSettings realmSettings,
    required AuthorizationRequest request,
  }) {
    final authRole = request.authRole;
    if (authRole == null || authRole.isEmpty) {
      return null;
    }

    RoleSettings? role;
    for (final candidate in realmSettings.roles) {
      if (candidate.name == authRole) {
        role = candidate;
        break;
      }
    }
    if (role == null) {
      return null;
    }

    final matches = <_PermissionMatch>[];
    for (var i = 0; i < role.permissions.length; i += 1) {
      final permission = role.permissions[i];
      if (_permissionMatches(request, permission)) {
        matches.add(_PermissionMatch(permission: permission, index: i));
      }
    }
    if (matches.isEmpty) {
      return null;
    }

    matches.sort(_comparePermissionMatches);
    for (final match in matches) {
      final permission = match.permission;
      for (final operation in request.action.operationCandidates) {
        if (_containsOperation(permission.deny, operation)) {
          return AuthorizationDecision.deny(
            message:
                'Role $authRole may not ${request.action.operationName} '
                '${request.uri}',
          );
        }
        if (_containsOperation(permission.allow, operation)) {
          return const AuthorizationDecision.allow();
        }
      }
    }
    return null;
  }
}

class _PermissionMatch {
  const _PermissionMatch({required this.permission, required this.index});

  final PermissionSettings permission;
  final int index;
}

int _comparePermissionMatches(_PermissionMatch left, _PermissionMatch right) {
  final priority = _policyPriority(
    left.permission.matchPolicy,
  ).compareTo(_policyPriority(right.permission.matchPolicy));
  if (priority != 0) {
    return priority;
  }

  final specificity = _policySpecificity(
    left.permission,
  ).compareTo(_policySpecificity(right.permission));
  if (specificity != 0) {
    return -specificity;
  }

  return left.index.compareTo(right.index);
}

int _policyPriority(PermissionMatchPolicy policy) => switch (policy) {
  PermissionMatchPolicy.exact => 0,
  PermissionMatchPolicy.prefix => 1,
  PermissionMatchPolicy.wildcard => 2,
};

int _policySpecificity(PermissionSettings permission) =>
    switch (permission.matchPolicy) {
      PermissionMatchPolicy.exact ||
      PermissionMatchPolicy.prefix => permission.uri.length,
      PermissionMatchPolicy.wildcard =>
        permission.uri.split('.').where((segment) => segment.isNotEmpty).length,
    };

bool _permissionMatches(
  AuthorizationRequest request,
  PermissionSettings permission,
) {
  if (request.action.usesTopicMatching) {
    return _matchesTopicUri(permission, request.uri);
  }
  return _matchesProcedureUri(permission, request.uri);
}

bool _matchesTopicUri(PermissionSettings permission, String candidate) {
  switch (permission.matchPolicy) {
    case PermissionMatchPolicy.exact:
      return permission.uri == candidate;
    case PermissionMatchPolicy.prefix:
      return candidate.startsWith(permission.uri);
    case PermissionMatchPolicy.wildcard:
      return _matchesWildcardUri(permission.uri, candidate);
  }
}

bool _matchesProcedureUri(PermissionSettings permission, String candidate) {
  switch (permission.matchPolicy) {
    case PermissionMatchPolicy.exact:
      return permission.uri == candidate;
    case PermissionMatchPolicy.prefix:
      if (permission.uri.isEmpty) {
        return true;
      }
      if (!candidate.startsWith(permission.uri)) {
        return false;
      }
      if (candidate.length == permission.uri.length) {
        return true;
      }
      if (permission.uri.endsWith('.')) {
        return true;
      }
      return candidate.length > permission.uri.length &&
          candidate[permission.uri.length] == '.';
    case PermissionMatchPolicy.wildcard:
      return _matchesWildcardUri(permission.uri, candidate);
  }
}

bool _matchesWildcardUri(String pattern, String candidate) {
  final patternParts = pattern.split('.');
  final candidateParts = candidate.split('.');
  if (patternParts.length != candidateParts.length) {
    return false;
  }
  for (var index = 0; index < patternParts.length; index += 1) {
    final patternPart = patternParts[index];
    if (patternPart.isEmpty) {
      continue;
    }
    if (patternPart != candidateParts[index]) {
      return false;
    }
  }
  return true;
}

bool _containsOperation(List<String> operations, String candidate) {
  final normalizedCandidate = candidate.toLowerCase();
  for (final operation in operations) {
    if (operation.toLowerCase() == normalizedCandidate) {
      return true;
    }
  }
  return false;
}
