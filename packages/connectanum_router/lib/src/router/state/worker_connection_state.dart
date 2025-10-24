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
  RealmSettings? realmSettings;
  String? realmUri;
  int? sessionId;
  Details? welcomeDetails;
  String? authMethod;
  Authenticator? authenticator;
  AuthenticatorContext? authContext;
  Map<String, Object?>? pendingChallengeExtra;
}
