part of '../router_instance.dart';

enum HandshakePhase { awaitingHello, awaitingAuthenticate, open, aborted }

class WorkerConnectionState {
  WorkerConnectionState({
    required this.listener,
    required this.listenerSettings,
  });

  final RouterListener listener;
  final ListenerSettings listenerSettings;
  HandshakePhase phase = HandshakePhase.awaitingHello;
  NativeMessageSerializer? serializer;

  /// Negotiated transport protocol for this connection. Currently assumed to
  /// be RawSocket until the native runtime reports negotiation results.
  ListenerProtocol? protocol;
  String? websocketProtocol;
  String? websocketSerializer;
  RealmSettings? realmSettings;
  String? realmUri;
  int? sessionId;
  Details? welcomeDetails;
  String? authMethod;
  Authenticator? authenticator;
  AuthenticatorContext? authContext;
  Map<String, Object?>? pendingChallengeExtra;
  String? pendingAuthId;
  DateTime? challengeIssuedAt;

  Map<String, Object?>? toTransferData() {
    if (phase != HandshakePhase.open ||
        sessionId == null ||
        realmUri == null ||
        authenticator != null ||
        authContext != null) {
      return null;
    }
    return <String, Object?>{
      'phase': phase.name,
      'serializer': serializer?.name,
      'protocol': protocol == null ? null : listenerProtocolToString(protocol!),
      'websocketProtocol': websocketProtocol,
      'websocketSerializer': websocketSerializer,
      'realmUri': realmUri,
      'sessionId': sessionId,
      'authMethod': authMethod,
      'welcomeDetails': _detailsToTransferData(welcomeDetails),
    };
  }

  void applyTransferData(Map<Object?, Object?> data) {
    final phaseName = data['phase'] as String?;
    phase = HandshakePhase.values.firstWhere(
      (value) => value.name == phaseName,
      orElse: () => HandshakePhase.awaitingHello,
    );
    final serializerName = data['serializer'] as String?;
    serializer = serializerName == null
        ? null
        : _serializerFromName(serializerName);
    final protocolName = data['protocol'] as String?;
    protocol = protocolName == null
        ? null
        : listenerProtocolFromString(protocolName);
    websocketProtocol = data['websocketProtocol'] as String?;
    websocketSerializer = data['websocketSerializer'] as String?;
    realmUri = data['realmUri'] as String?;
    sessionId = data['sessionId'] as int?;
    authMethod = data['authMethod'] as String?;
    final rawWelcomeDetails = data['welcomeDetails'];
    if (rawWelcomeDetails is Map<Object?, Object?>) {
      welcomeDetails = _detailsFromTransferData(rawWelcomeDetails);
    }
  }
}

Map<String, Object?>? _detailsToTransferData(Details? details) {
  if (details == null) {
    return null;
  }
  return <String, Object?>{
    'realm': details.realm,
    'authid': details.authid,
    'authmethod': details.authmethod,
    'authprovider': details.authprovider,
    'authrole': details.authrole,
    'authextra': details.authextra == null
        ? null
        : Map<String, dynamic>.from(details.authextra!),
    'custom': Map<String, dynamic>.from(details.custom),
  };
}

Details _detailsFromTransferData(Map<Object?, Object?> data) {
  final rawAuthExtra = data['authextra'];
  final details = Details.forWelcome(
    realm: data['realm'] as String?,
    authId: data['authid'] as String?,
    authMethod: data['authmethod'] as String?,
    authProvider: data['authprovider'] as String?,
    authRole: data['authrole'] as String?,
    authExtra: rawAuthExtra is Map
        ? Map<String, dynamic>.from(rawAuthExtra)
        : null,
  );
  final rawCustom = data['custom'];
  if (rawCustom is Map) {
    details.custom.addAll(Map<String, dynamic>.from(rawCustom));
  }
  return details;
}
