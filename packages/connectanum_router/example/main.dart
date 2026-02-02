// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';

const String _realm = 'demo.realm';

Future<void> main(List<String> args) async {
  // Register demo hooks before the worker isolates spin up.
  registerDefaultAuthenticators();
  AuthCredentialRegistry.registerProvider(DemoCredentialProvider());
  AuthCredentialRegistry.registerListener(_logCredentialLookupEvent);
  AuthAuditLogger.registerSink(_logAuditEvent);
  RemoteAuthenticatorRegistry.register(DemoRemoteDelegate());

  late final NativeTransportRuntime runtime;
  try {
    runtime = NativeTransportRuntime(
      libraryPath: args.isNotEmpty ? args.first : null,
    );
  } on ArgumentError catch (error) {
    stderr.writeln(
      'Failed to load the native transport runtime: ${error.message}\n'
      'Ensure ct_ffi is available (build hooks compile it automatically during `dart run`/`dart test` '
      'when a Rust toolchain is installed), set CONNECTANUM_NATIVE_LIB, or pass an explicit path as '
      'the first argument.',
    );
    return;
  }

  runtime.setListenerCallbacks(
    onStarted: (listenerId, status) {
      if (status == NativeTransportErrorCode.success) {
        print('Listener $listenerId started');
      } else {
        print('Listener $listenerId failed with status $status');
      }
    },
    onConnection: (listenerId, connectionId) {
      print('Listener $listenerId accepted connection $connectionId');
    },
  );

  runtime.start();
  print('Native runtime started');

  final router = Router(
    RouterConfig(
      endpoints: [
        Endpoint(
          host: '127.0.0.1',
          port: 0,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
        ),
      ],
    ),
    settings: _buildRouterSettings(),
  );

  final binding = router.start(runtime);
  final listeners = binding.listeners;
  for (final listener in listeners) {
    print(
      'Listener ${listener.listenerId} bound to '
      '${listener.endpoint.host}:${listener.port}',
    );
  }

  print('Configured realm: $_realm');
  print('Authentication methods: ticket, wampcra, scram, remote');
  print('Demo users:');
  print('  • ticket.alice → signature "ticket-alice-secret"');
  print('  • ticket.suspended → rejected with payment_required');
  print('  • cra.alice → CRA with derived key (authextra nonce required)');
  print('  • scram.alice → SCRAM PBKDF2 (authextra nonce required)');
  print('  • remote.alice → remote delegate, send signature "delegate-token"');

  final subscription = binding
      .watchNativeMessages(
        pollInterval: const Duration(milliseconds: 5),
        maxMessagesPerTick: 128,
      )
      .listen((routerMessage) {
        print(
          'Received message on connection ${routerMessage.connectionId} '
          '(${routerMessage.listener.endpoint.host}:${routerMessage.listener.port}) '
          'with serializer ${routerMessage.message.serializer}',
        );
        routerMessage.message.dispose();
      });

  print('Router running. Press Ctrl+C to stop.');

  final sigint = ProcessSignal.sigint.watch().first;
  final sigterm = ProcessSignal.sigterm.watch().first;
  await Future.any([sigint, sigterm]);

  await subscription.cancel();
  await binding.dispose();
  runtime.shutdown();
  runtime.dispose();

  // Clean up global hooks so subsequent runs/tests start from a clean slate.
  AuthCredentialRegistry.reset();
  AuthAuditLogger.clearSink();
  RemoteAuthenticatorRegistry.clear();
  RemoteAuthenticator.resetRateLimiter();

  print('Router stopped.');
}

RouterSettings _buildRouterSettings() {
  final settings = RouterSettingsBuilder()
    ..addAuthenticator(
      'ticket-basic',
      const AuthenticatorDefinition(
        type: 'ticket',
        options: {
          'secrets': {}, // real secrets resolved via AuthCredentialRegistry
          'challenge': {'motd': 'Present a valid ticket'},
        },
      ),
    )
    ..addAuthenticator(
      'cra-basic',
      const AuthenticatorDefinition(
        type: 'wampcra',
        options: {
          'challenge': {
            'info': 'Derived keys only – see docs/router_auth_credentials.md',
          },
        },
      ),
    )
    ..addAuthenticator(
      'scram-basic',
      const AuthenticatorDefinition(type: 'scram', options: {}),
    )
    ..addAuthenticator(
      'remote-basic',
      const AuthenticatorDefinition(
        type: 'remote',
        options: {
          'method': 'remote',
          'allowed_roles': ['remote-member'],
          'rate_limit_max_attempts': 5,
          'rate_limit_window_ms': 60000,
          'backoff_base_ms': 500,
          'backoff_factor': 2.0,
          'backoff_max_ms': 60000,
        },
      ),
    );

  final realmBuilder = RealmSettingsBuilder(_realm)
    ..addAuthMethod('ticket', options: {'authenticator': 'ticket-basic'})
    ..addAuthMethod('wampcra', options: {'authenticator': 'cra-basic'})
    ..addAuthMethod('scram', options: {'authenticator': 'scram-basic'})
    ..addAuthMethod('remote', options: {'authenticator': 'remote-basic'})
    ..addRoleFromBuilder(
      RoleSettingsBuilder('member')..addPermissionFromBuilder(
        PermissionSettingsBuilder('com.demo.')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const [
            'subscribe',
            'publish',
            'call',
            'register',
            'unregister',
          ]),
      ),
    )
    ..addRoleFromBuilder(
      RoleSettingsBuilder('remote-member')..addPermissionFromBuilder(
        PermissionSettingsBuilder('com.demo.remote.')
          ..setMatchPolicy(PermissionMatchPolicy.prefix)
          ..allowOperations(const ['call', 'register']),
      ),
    )
    ..setLimits(const RealmLimitSettings(maxFailedAuth: 3, lockoutMs: 30000));

  settings.addRealmFromBuilder(realmBuilder);

  settings.addListenerFromBuilder(
    ListenerSettingsBuilder('rawsocket', '127.0.0.1:0')
      ..addAuthMethod('ticket')
      ..addAuthMethod('wampcra')
      ..addAuthMethod('scram')
      ..addAuthMethod('remote')
      ..setOptions(const {'max_rawsocket_size_exponent': 16}),
  );

  return settings.build();
}

void _logCredentialLookupEvent(CredentialLookupEvent event) {
  final prefix = event.hit ? 'lookup hit' : 'lookup MISS';
  final suffix = event.reason == null
      ? ''
      : ' → ${event.reason} (${event.message ?? 'no message'})';
  print('[credentials] $prefix for ${event.method}/${event.authId}$suffix');
}

void _logAuditEvent(AuthAuditEvent event) {
  print(
    '[audit] ${event.outcome.name} realm=${event.realmUri} '
    'method=${event.method} authid=${event.authId ?? '-'} '
    '${event.message ?? ''}',
  );
}

class DemoCredentialProvider extends AuthCredentialProvider {
  DemoCredentialProvider() {
    // Ticket samples.
    _ticketCredentials[_key(_realm, 'ticket.alice')] = TicketCredential(
      ticket: 'ticket-alice-secret',
      role: 'member',
      provider: 'static-config',
      authExtra: const {'tier': 'standard'},
    );
    _ticketRejections[_key(_realm, 'ticket.suspended')] = CredentialRejection(
      reason: 'wamp.error.payment_required',
      message: 'Subscription overdrawn – contact billing',
      arguments: const ['PAYWALL'],
      argumentsKeywords: const {'retry_after_ms': 60000},
    );

    // CRA sample with derived key only.
    final craSaltBytes = List<int>.generate(16, (i) => i + 1);
    final craSalt = base64.encode(craSaltBytes);
    final craDerived = base64.encode(
      CraAuthentication.deriveKey(
        'cra-alice-secret',
        craSaltBytes,
        iterations: 2000,
        keylen: CraAuthentication.defaultKeyLength,
      ),
    );
    _craCredentials[_key(_realm, 'cra.alice')] = CraCredential(
      derivedKey: craDerived,
      salt: craSalt,
      iterations: 2000,
      keyLen: CraAuthentication.defaultKeyLength,
      role: 'member',
      provider: 'derived-demo',
      authExtra: const {'note': 'derived key'},
      challenge: const {'demo': 'nonce appended server-side'},
    );

    // SCRAM sample using PBKDF2.
    final scramSaltBytes = List<int>.generate(16, (i) => i + 33);
    final scramSalt = base64.encode(scramSaltBytes);
    final scramSecrets = ScramAuthentication.deriveServerSecrets(
      secret: 'scram-alice-secret',
      salt: scramSalt,
      iterations: 4096,
    );
    _scramCredentials[_key(_realm, 'scram.alice')] = ScramCredential(
      storedKey: scramSecrets.storedKey,
      serverKey: scramSecrets.serverKey,
      salt: scramSalt,
      iterations: 4096,
      role: 'member',
      provider: 'scram-demo',
      authExtra: const {'region': 'eu-central'},
    );
  }

  final Map<String, TicketCredential> _ticketCredentials = {};
  final Map<String, CredentialRejection> _ticketRejections = {};
  final Map<String, CraCredential> _craCredentials = {};
  final Map<String, CredentialRejection> _craRejections = {};
  final Map<String, ScramCredential> _scramCredentials = {};
  final Map<String, CredentialRejection> _scramRejections = {};

  static String _key(String realm, String authId) => '$realm::$authId';

  @override
  Future<TicketCredential?> loadTicket({
    required String realmUri,
    required String authId,
  }) async {
    final rejection = _ticketRejections[_key(realmUri, authId)];
    if (rejection != null) {
      throw rejection;
    }
    return _ticketCredentials[_key(realmUri, authId)];
  }

  @override
  Future<CraCredential?> loadCra({
    required String realmUri,
    required String authId,
  }) async {
    final rejection = _craRejections[_key(realmUri, authId)];
    if (rejection != null) {
      throw rejection;
    }
    return _craCredentials[_key(realmUri, authId)];
  }

  @override
  Future<ScramCredential?> loadScram({
    required String realmUri,
    required String authId,
  }) async {
    final rejection = _scramRejections[_key(realmUri, authId)];
    if (rejection != null) {
      throw rejection;
    }
    return _scramCredentials[_key(realmUri, authId)];
  }
}

class DemoRemoteDelegate extends RemoteAuthenticatorDelegate {
  final Map<String, String> _pending = {};

  @override
  Future<RemoteHelloResponse> onHello(RemoteHelloRequest request) async {
    final authId =
        request.context.helloDetails['authid'] as String? ?? 'unknown';
    if (authId == 'remote.banned') {
      return RemoteHelloResponse.failure(
        const AuthFailure(
          reason: 'wamp.error.not_authorized',
          message: 'Remote service reports account ban',
        ),
      );
    }
    _pending[request.transactionId] = authId;
    return RemoteHelloResponse.challenge(
      RemoteChallenge(
        authId: authId,
        challenge: const {
          'challenge': 'delegate-challenge',
          'hint': 'reply with delegate-token',
        },
        extra: const {'required': 'delegate-token'},
      ),
    );
  }

  @override
  Future<RemoteAuthenticateResponse> onAuthenticate(
    RemoteAuthenticateRequest request,
  ) async {
    final expectedAuthId = _pending.remove(request.transactionId);
    if (expectedAuthId == null) {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: 'wamp.error.protocol_violation',
          message: 'Unknown transaction',
        ),
      );
    }
    if (request.authenticate.signature != 'delegate-token') {
      return RemoteAuthenticateResponse.failure(
        const AuthFailure(
          reason: 'wamp.error.not_authorized',
          message: 'Delegate rejected the provided token',
          arguments: ['INVALID_TOKEN'],
        ),
      );
    }
    return RemoteAuthenticateResponse.success(
      AuthSuccess(
        authId: request.authId,
        authRole: 'remote-member',
        details: const {'authprovider': 'remote-demo'},
      ),
    );
  }
}
