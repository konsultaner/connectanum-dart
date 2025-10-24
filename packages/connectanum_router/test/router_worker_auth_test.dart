import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp_core show Error;
import 'package:connectanum_core/json_serializer.dart' as json_serializer;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/auth/default_authenticators.dart';
import 'package:connectanum_router/src/router/config/auth_registry.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:test/test.dart';

class _RecordingAuthenticatorFactory extends AuthenticatorFactory {
  _RecordingAuthenticatorFactory(this._method, this._builder);

  final String _method;
  final Authenticator Function(
    RealmSettings realm,
    Map<String, Object?> options,
  )
  _builder;

  Map<String, Object?>? lastOptions;

  @override
  String get method => _method;

  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    lastOptions = Map<String, Object?>.from(options);
    return _builder(realm, options);
  }
}

class _ChallengeAuthenticator extends Authenticator {
  _ChallengeAuthenticator({
    required String method,
    required this.challenge,
    required Future<AuthResult> Function(AuthenticateMessage message)
    onAuthenticate,
  }) : _method = method,
       _onAuthenticate = onAuthenticate;

  final String _method;
  final AuthChallenge challenge;
  final Future<AuthResult> Function(AuthenticateMessage message)
  _onAuthenticate;

  @override
  String get method => _method;

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async =>
      AuthResult.challenge(challenge);

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) => _onAuthenticate(message);
}

class _FailureAuthenticator extends Authenticator {
  _FailureAuthenticator({required String method, required this.failure})
    : _method = method;

  final String _method;
  final AuthFailure failure;

  @override
  String get method => _method;

  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async =>
      AuthResult.failure(failure);

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) async => AuthResult.failure(failure);
}

void main() {
  final serializer = json_serializer.Serializer();

  setUp(() {
    AuthenticatorRegistry.clear();
    registerDefaultAuthenticators();
  });

  tearDown(() {
    AuthenticatorRegistry.clear();
  });

  group('Router worker authentication', () {
    test('handles challenge and authenticate success', () async {
      final factory = _RecordingAuthenticatorFactory(
        'test-ticket',
        (realm, options) => _ChallengeAuthenticator(
          method: 'ticket',
          challenge: const AuthChallenge(
            challenge: {
              'challenge': 'nonce',
              'salt': 'salt',
              'keylen': 32,
              'iterations': 1000,
            },
            extra: {
              'authextra': {'fromChallenge': true},
            },
          ),
          onAuthenticate: (message) async {
            expect(message.signature, equals('signed-token'));
            expect(message.extra, containsPair('foo', 'bar'));
            return AuthResult.success(
              const AuthSuccess(
                authId: 'user-1',
                authRole: 'member',
                details: {
                  'authprovider': 'ticket-db',
                  'authextra': {'fromSuccess': 'yes'},
                },
              ),
            );
          },
        ),
      );
      AuthenticatorRegistry.registerFactory(factory);

      final routerSettings = _buildRouterSettings(
        realmMethods: ['ticket'],
        realmOptions: {
          'ticket': {'authenticator': 'ticket-basic', 'provider': 'primary'},
        },
        listenerMethods: ['ticket'],
        authenticators: {
          'ticket-basic': const AuthenticatorDefinition(type: 'test-ticket'),
        },
      );
      final listener = _buildListener();
      final state =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as dynamic;
      state.serializer = NativeMessageSerializer.json;

      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final stateCommands = <RouterStateCommand>[];
      var nextSessionId = 1;
      final statePort = ReceivePort()
        ..listen((message) {
          if (message is SessionAllocateIdCommand) {
            message.replyPort.send(nextSessionId++);
            return;
          }
          if (message is RouterStateCommand) {
            stateCommands.add(message);
          }
        });
      addTearDown(statePort.close);

      final helloDetails = Details.forHello()
        ..authmethods = ['ticket']
        ..authid = 'user-1';
      final hello = Hello('realm1', helloDetails);

      await handleHelloForTest(
        bossPort.sendPort,
        statePort.sendPort,
        routerSettings,
        state,
        hello,
        42,
        null,
        99,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        factory.lastOptions,
        containsPair('authenticator', 'ticket-basic'),
      );
      expect(factory.lastOptions, containsPair('provider', 'primary'));

      final challengeMessage = _extractSingleWorkerSend(bossMessages);
      final challenge =
          serializer.deserialize(challengeMessage['payload'] as Uint8List)
              as Challenge;
      expect(challenge.authMethod, equals('ticket'));
      expect(challenge.extra.challenge, equals('nonce'));
      expect(challenge.extra.salt, equals('salt'));
      expect(challenge.extra.keyLen, equals(32));
      expect(challenge.extra.iterations, equals(1000));

      expect(stateCommands.whereType<RealmEnsureCommand>(), hasLength(1));

      bossMessages.clear();

      final authenticate = Authenticate(signature: 'signed-token')
        ..extra = {'foo': 'bar'};
      await handleAuthenticateForTest(
        bossPort.sendPort,
        statePort.sendPort,
        null,
        state,
        authenticate,
        42,
        99,
      );
      await Future<void>.delayed(Duration.zero);

      final welcomeMessage = _extractSingleWorkerSend(bossMessages);
      final payload = welcomeMessage['payload'] as Uint8List;
      final welcome = serializer.deserialize(payload) as Welcome;
      expect(welcome.sessionId, equals(state.sessionId));
      expect(welcome.details.authid, equals('user-1'));
      expect(welcome.details.authprovider, equals('ticket-db'));
      expect(welcome.details.authextra, containsPair('fromSuccess', 'yes'));
      expect(welcome.details.authextra, containsPair('fromChallenge', true));

      final openCommand = stateCommands.whereType<SessionOpenCommand>().single;
      expect(openCommand.session.authId, equals('user-1'));
      expect(openCommand.session.authRole, equals('member'));
    });

    test('aborts when authenticator rejects HELLO', () async {
      final factory = _RecordingAuthenticatorFactory(
        'test-ticket',
        (realm, options) => _FailureAuthenticator(
          method: 'ticket',
          failure: const AuthFailure(
            reason: wamp_core.Error.notAuthorized,
            message: 'invalid user',
            details: {'code': 401},
            arguments: ['invalid'],
            argumentsKeywords: {'hint': 'check credentials'},
          ),
        ),
      );
      AuthenticatorRegistry.registerFactory(factory);

      final routerSettings = _buildRouterSettings(
        realmMethods: ['ticket'],
        realmOptions: {
          'ticket': {'authenticator': 'ticket-basic'},
        },
        listenerMethods: ['ticket'],
        authenticators: {
          'ticket-basic': const AuthenticatorDefinition(type: 'test-ticket'),
        },
      );
      final listener = _buildListener();
      final state =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as dynamic;
      state.serializer = NativeMessageSerializer.json;

      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final hello = Hello(
        'realm1',
        Details.forHello()..authmethods = ['ticket'],
      );

      await handleHelloForTest(
        bossPort.sendPort,
        null,
        routerSettings,
        state,
        hello,
        99,
        null,
        77,
      );
      await Future<void>.delayed(Duration.zero);

      final abortMessage = _extractSingleWorkerSend(bossMessages);
      final abort =
          serializer.deserialize(abortMessage['payload'] as Uint8List) as Abort;
      expect(abort.reason, equals(wamp_core.Error.notAuthorized));
      expect(abort.message?.message, equals('invalid user'));
    });

    test('aborts when no matching authentication method found', () async {
      final routerSettings = _buildRouterSettings(
        realmMethods: ['ticket'],
        realmOptions: const {},
        listenerMethods: ['ticket'],
        authenticators: const {},
      );
      final listener = _buildListener();
      final state =
          createWorkerStateForTest(
                listener: listener,
                listenerSettings: routerSettings.listeners.first,
              )
              as dynamic;
      state.serializer = NativeMessageSerializer.json;

      final bossMessages = <Map<String, Object?>>[];
      final bossPort = ReceivePort()
        ..listen((message) {
          if (message is Map<String, Object?>) {
            bossMessages.add(message);
          }
        });
      addTearDown(bossPort.close);

      final hello = Hello(
        'realm1',
        Details.forHello()..authmethods = ['ticket'],
      );

      await handleHelloForTest(
        bossPort.sendPort,
        null,
        routerSettings,
        state,
        hello,
        5,
        null,
        11,
      );
      await Future<void>.delayed(Duration.zero);

      final abortMessage = _extractSingleWorkerSend(bossMessages);
      final abort =
          serializer.deserialize(abortMessage['payload'] as Uint8List) as Abort;
      expect(abort.reason, equals(wamp_core.Error.notAuthorized));
    });
  });
}

Map<String, Object?> _extractSingleWorkerSend(
  List<Map<String, Object?>> messages,
) {
  final workerSend = messages
      .where((message) => message['type'] == 'worker_send')
      .toList();
  expect(workerSend, hasLength(1));
  return workerSend.single;
}

RouterSettings _buildRouterSettings({
  required List<String> realmMethods,
  required Map<String, Map<String, Object?>> realmOptions,
  required List<String> listenerMethods,
  required Map<String, AuthenticatorDefinition> authenticators,
}) {
  final realm = RealmSettings(
    name: 'realm1',
    autoCreate: false,
    auth: RealmAuthSettings(methods: realmMethods, methodOptions: realmOptions),
    roles: const [],
    limits: const RealmLimitSettings(),
  );

  final listener = ListenerSettings(
    type: 'rawsocket',
    endpoint: '127.0.0.1:7000',
    authmethods: listenerMethods,
    options: const {},
  );

  return RouterSettings(
    realms: [realm],
    listeners: [listener],
    metrics: null,
    authenticators: authenticators,
  );
}

RouterListener _buildListener() => RouterListener(
  listenerId: 1,
  endpoint: Endpoint(
    host: '127.0.0.1',
    port: 7000,
    tlsMode: TlsMode.disabled,
    maxRawSocketSizeExponent: 16,
  ),
  port: 7000,
);
