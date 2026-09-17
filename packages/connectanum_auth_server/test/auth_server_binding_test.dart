import 'dart:async';
import 'dart:core' as core;
import 'dart:core';

import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_core/connectanum_core.dart' as wamp;
import 'package:connectanum_router/auth.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

import 'support/callback_entry.dart';

void main() {
  late AuthServer server;
  late _Factory factory;
  late _Session first;
  late _Session second;
  late AuthServerProcedureBinding firstBinding;
  late AuthServerProcedureBinding secondBinding;

  setUp(() async {
    AuthenticatorRegistry.clear();
    AuthSecurityTracker.reset();
    factory = _Factory();
    AuthenticatorRegistry.registerFactory(factory);
    final settings =
        (RouterSettingsBuilder()..addRealmFromBuilder(
              RealmSettingsBuilder('realm')..addAuthMethod('controlled'),
            ))
            .build();
    server = AuthServer(settings: settings);
    first = _Session();
    second = _Session();
    firstBinding = await AuthServerProcedureBinding.bind(
      server: server,
      session: first,
    );
    secondBinding = await AuthServerProcedureBinding.bind(
      server: server,
      session: second,
    );
  });

  tearDown(() async {
    await firstBinding.close();
    await secondBinding.close();
    await server.close();
    AuthenticatorRegistry.clear();
    AuthSecurityTracker.reset();
  });

  test('a second binding cannot authenticate or abort another owner', () async {
    expect(
      (await first.rpc('hello', _hello('owned'))).argumentsKeywords?['status'],
      'challenge',
    );
    expect(
      (await second.rpc(
        'authenticate',
        _authenticate('owned'),
      )).argumentsKeywords?['status'],
      'failure',
    );
    expect(factory.authenticator.authenticateCalls, 0);
    expect(
      (await second.rpc('abort', {
        'transactionId': 'owned',
      })).argumentsKeywords?['status'],
      'ok',
    );
    expect(server.pendingAuthenticationCounts, {'realm': 1});
    expect(factory.authenticator.aborts, 0);
    expect(
      (await first.rpc(
        'authenticate',
        _authenticate('owned'),
      )).argumentsKeywords?['status'],
      'success',
    );
    expect(factory.authenticator.authenticateCalls, 1);
    await Future<void>.delayed(Duration.zero);
    expect(factory.authenticator.aborts, 0);
    expect(server.pendingAuthenticationCounts, isEmpty);
  });

  test(
    'closing a binding invalidates only its own pending transactions',
    () async {
      await first.rpc('hello', _hello('first'));
      await second.rpc('hello', _hello('second'));
      expect(server.pendingAuthenticationCounts, {'realm': 2});
      await firstBinding.close();
      await Future<void>.delayed(Duration.zero);
      expect(server.pendingAuthenticationCounts, {'realm': 1});
      expect(factory.authenticator.aborts, 1);
      expect(first.unregistered, [3, 2, 1]);
      expect(
        (await second.rpc(
          'authenticate',
          _authenticate('second'),
        )).argumentsKeywords?['status'],
        'success',
      );
      await firstBinding.close();
      expect(first.unregistered, [3, 2, 1]);
    },
  );

  test(
    'late in-flight provider completion preserves the cancellation reason',
    () async {
      final completion = Completer<AuthResult>();
      factory.authenticator.result = completion.future;
      await first.rpc('hello', _hello('pending'));
      final pending = first.rpc('authenticate', _authenticate('pending'));
      wamp.AbstractMessageWithPayload? closedResult;
      unawaited(
        pending.then((value) {
          closedResult = value;
        }),
      );
      await expectCallbackEntry(factory.authenticator.entered.future, pending);
      await firstBinding.close();
      try {
        await Future<void>.delayed(Duration.zero);
        expect(
          closedResult,
          isNotNull,
          reason:
              'Closing a binding must respond before its provider completes',
        );
        expect(closedResult!.argumentsKeywords?['status'], 'failure');
        expect(closedResult!.argumentsKeywords?['message'], contains('closed'));
      } finally {
        completion.completeError(StateError('late provider error'));
      }
      await Future<void>.delayed(Duration.zero);
      expect(factory.authenticator.aborts, 1);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );

  test('schema errors never create pending authentication state', () async {
    for (final payload in <Map<String, Object?>>[
      {},
      {'transactionId': 1},
      {'transactionId': ''},
      _hello(''),
      {'transactionId': 'x', 'hello': false},
      {
        'transactionId': 'x',
        'hello': {1: 'invalid key'},
      },
      {
        'transactionId': 'x',
        'hello': {'': 'invalid key'},
      },
      {
        'transactionId': 'x',
        'hello': {'realm': 'unknown'},
      },
      {
        'transactionId': 'x',
        'hello': {'realm': 'realm'},
      },
      {
        'transactionId': 'x',
        'hello': {'realm': 'realm', 'sessionId': 1},
      },
      {..._hello('x'), 'option': Object()},
      {
        ..._hello('x'),
        'option': {1: 'bad'},
      },
      {
        ..._hello('x'),
        'option': {'': 'bad'},
      },
      {
        ..._hello('x'),
        'option': [Object()],
      },
    ]) {
      final response = await first.rpc('hello', payload);
      expect(response, isA<wamp.Error>());
      expect((response as wamp.Error).error, wamp.Error.invalidArgument);
      expect(server.pendingAuthenticationCounts, isEmpty);
    }
    expect(factory.calls, 0);
  });

  test(
    'positional RPC payloads preserve successful authentication details',
    () async {
      factory.authenticator.helloResult = AuthResult.success(
        const AuthSuccess(
          authId: 'user',
          authRole: 'member',
          details: {'provider': 'controlled'},
        ),
      );
      final hello = _hello('positional');
      (hello['hello']! as Map<String, Object?>)['sessionId'] = 1.0;
      (hello['hello']! as Map<String, Object?>)['details'] = {
        'authid': 'user',
        'authmethod': 'controlled',
      };
      final result = await first.rpc('hello', {}, arguments: [hello]);
      expect(result.argumentsKeywords, {
        'status': 'success',
        'authId': 'user',
        'authRole': 'member',
        'details': {'provider': 'controlled'},
      });
      expect(factory.authenticator.lastContext?.sessionId, 1);
      expect(factory.authenticator.lastContext?.transport.connectionId, 1);
      expect(
        factory.authenticator.lastContext?.transport.peerAddress,
        '127.0.0.1',
      );
      expect(factory.authenticator.lastContext?.transport.isEncrypted, isTrue);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );

  test(
    'challenge, success and failure envelopes retain optional fields',
    () async {
      factory.authenticator.helloResult = AuthResult.challenge(
        const AuthChallenge(extra: {'nonce': 'test-nonce'}),
      );
      expect(
        (await first.rpc('hello', _hello('extra'))).argumentsKeywords?['extra'],
        {'nonce': 'test-nonce'},
      );
      factory.authenticator.result = Future.value(
        AuthResult.success(
          const AuthSuccess(
            authId: 'user',
            authRole: 'member',
            details: {'server_signature': 'test-signature'},
          ),
        ),
      );
      expect(
        (await first.rpc(
          'authenticate',
          _authenticate('extra'),
        )).argumentsKeywords?['details'],
        {'server_signature': 'test-signature'},
      );
      factory.authenticator.helloResult = AuthResult.failure(
        const AuthFailure(
          reason: 'wamp.error.not_authorized',
          message: 'rejected',
          details: {'provider': 'controlled'},
          arguments: ['public reason'],
          argumentsKeywords: {'retry': false},
        ),
      );
      expect((await first.rpc('hello', _hello('failure'))).argumentsKeywords, {
        'status': 'failure',
        'reason': 'wamp.error.not_authorized',
        'message': 'rejected',
        'details': {'provider': 'controlled'},
        'arguments': ['public reason'],
        'argumentsKeywords': {'retry': false},
      });
    },
  );

  test('malformed positional maps fail closed in every RPC handler', () async {
    for (final method in ['hello', 'authenticate', 'abort']) {
      final result = await first.rpc(
        method,
        {},
        arguments: [
          {1: 'invalid top-level key'},
        ],
      );
      expect(result, isA<wamp.Error>());
      expect((result as wamp.Error).error, wamp.Error.notAuthorized);
      expect(server.pendingAuthenticationCounts, isEmpty);
    }
    expect(factory.calls, 0);
  });

  test(
    'late registration callbacks fail closed after binding shutdown',
    () async {
      await firstBinding.close();
      final responses = [
        first.rpc('hello', _hello('closing')),
        first.rpc('authenticate', _authenticate('closing')),
        first.rpc('abort', {'transactionId': 'closing'}),
      ];
      for (final response in await Future.wait(responses)) {
        expect(response.argumentsKeywords?['status'], 'failure');
        expect(response.argumentsKeywords?['message'], contains('closed'));
      }
      expect(factory.calls, 0);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );

  test('an owner can abort its challenge through the public RPC', () async {
    await first.rpc('hello', _hello('aborted'));
    expect(
      (await first.rpc('abort', {
        'transactionId': 'aborted',
        'reason': 'client cancelled',
      })).argumentsKeywords,
      {'status': 'ok'},
    );
    await Future<void>.delayed(Duration.zero);
    expect(factory.authenticator.aborts, 1);
    expect(server.pendingAuthenticationCounts, isEmpty);
    expect(
      (await first.rpc(
        'authenticate',
        _authenticate('aborted'),
      )).argumentsKeywords?['status'],
      'failure',
    );
    expect(factory.authenticator.authenticateCalls, 0);
  });

  test(
    'service-token admission precedes RPC schema and pending-state access',
    () async {
      final protected = AuthServer(
        settings: server.settings,
        authTokens: const ['service-secret'],
      );
      final session = _Session();
      final binding = await AuthServerProcedureBinding.bind(
        server: protected,
        session: session,
      );
      addTearDown(protected.close);
      addTearDown(binding.close);
      for (final token in [null, 42, 'wrong']) {
        for (final method in ['hello', 'authenticate', 'abort']) {
          final response = await session.rpc(method, {'auth_token': token});
          expect(response, isNot(isA<wamp.Error>()));
          expect(response.argumentsKeywords?['status'], 'failure');
          expect(
            response.argumentsKeywords?['reason'],
            wamp.Error.notAuthorized,
          );
          expect(
            response.argumentsKeywords?['message'],
            'Remote authenticator token rejected',
          );
        }
      }
      expect(factory.calls, 0);
      expect(
        (await session.rpc('hello', {
          ..._hello('protected'),
          'auth_token': 'service-secret',
        })).argumentsKeywords?['status'],
        'challenge',
      );
      for (final method in ['authenticate', 'abort']) {
        await session.rpc(method, {
          ..._authenticate('protected'),
          'auth_token': 'wrong',
        });
        expect(protected.pendingAuthenticationCounts, {'realm': 1});
        expect(factory.authenticator.authenticateCalls, 0);
        expect(factory.authenticator.aborts, 0);
      }
      expect(
        (await session.rpc('abort', {
          'transactionId': 'protected',
          'auth_token': 'service-secret',
        })).argumentsKeywords,
        {'status': 'ok'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(protected.pendingAuthenticationCounts, isEmpty);
      expect(factory.authenticator.aborts, 1);
    },
  );

  test(
    'authenticate and abort schemas reject malformed values without consuming challenge',
    () async {
      await first.rpc('hello', _hello('pending'));
      for (final payload in <Map<String, Object?>>[
        {},
        {'transactionId': 'pending'},
        {'transactionId': 'pending', 'authenticate': []},
        {
          'transactionId': 'pending',
          'authenticate': {'signature': 42},
        },
        {
          'transactionId': 'pending',
          'authenticate': {'signature': ''},
        },
        {
          'transactionId': 'pending',
          'authenticate': {'signature': 'proof', 'extra': false},
        },
      ]) {
        final response = await first.rpc('authenticate', payload);
        expect(response, isA<wamp.Error>());
        expect((response as wamp.Error).error, wamp.Error.invalidArgument);
        expect(server.pendingAuthenticationCounts, {'realm': 1});
      }
      final abort = await first.rpc('abort', {
        'transactionId': 'pending',
        'reason': 1,
      });
      expect(abort, isA<wamp.Error>());
      expect((abort as wamp.Error).error, wamp.Error.invalidArgument);
      expect(factory.authenticator.aborts, 0);
      expect(
        (await first.rpc(
          'authenticate',
          _authenticate('pending'),
        )).argumentsKeywords?['status'],
        'success',
      );
    },
  );

  test(
    'RPC envelopes stay out of custom service-admission options',
    () async {
      final inspected = _InspectingAuthServer(settings: server.settings);
      final session = _Session();
      final binding = await AuthServerProcedureBinding.bind(
        server: inspected,
        session: session,
      );
      addTearDown(() async {
        await binding.close();
        await inspected.close();
      });
      const options = <String, Object?>{
        'auth_token': 'service-token',
        'extension': {
          'scopes': ['authenticate'],
          'required': true,
        },
      };
      for (final (method, payload, status) in [
        ('hello', _hello('success'), 'challenge'),
        ('authenticate', _authenticate('success'), 'success'),
        ('hello', _hello('aborted'), 'challenge'),
        (
          'abort',
          <String, Object?>{
            'transactionId': 'aborted',
            'reason': 'wamp.close.normal',
          },
          'ok',
        ),
      ]) {
        inspected.options.clear();
        final response = await session.rpc(method, {...payload, ...options});
        expect(response.argumentsKeywords?['status'], status);
        expect(inspected.options, isNotEmpty);
        expect(inspected.options, everyElement(equals(options)));
      }
      await Future<void>.delayed(Duration.zero);
      expect(inspected.pendingAuthenticationCounts, isEmpty);
      expect(factory.authenticator.authenticateCalls, 1);
      expect(factory.authenticator.aborts, 1);
    },
  );

  test(
    'ordinary provider exceptions fail closed and release capacity',
    () async {
      factory.authenticator.result = Future<AuthResult>.sync(
        () => throw StateError('provider failed'),
      );
      // Attach the failing future only when onAuthenticate can consume it.
      factory.authenticator.result!.ignore();
      await first.rpc('hello', _hello('error'));
      expect(
        (await first.rpc(
          'authenticate',
          _authenticate('error'),
        )).argumentsKeywords?['status'],
        'failure',
      );
      await Future<void>.delayed(Duration.zero);
      expect(factory.authenticator.aborts, 1);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );
}

Map<String, Object?> _hello(String id) => {
  'transactionId': id,
  'hello': {
    'realm': 'realm',
    'sessionId': 1,
    'transport': {
      'connectionId': 1,
      'peerAddress': '127.0.0.1',
      'isEncrypted': true,
    },
    'details': {
      'authid': 'user',
      'authmethods': ['controlled'],
    },
  },
};

Map<String, Object?> _authenticate(String id) => {
  'transactionId': id,
  'authenticate': {'signature': 'proof'},
};

// Deliver actual WAMP Invocation/Registered objects to the public binding API.
// Only the router's registration transport is replaced, not authentication.
class _Session implements RouterSession {
  final registrations = <String, wamp.Registered>{};
  final unregistered = <int>[];

  @override
  Future<wamp.Registered> register(
    String procedure, {
    wamp.RegisterOptions? options,
  }) async {
    final id = registrations.length + 1;
    return registrations[procedure] = wamp.Registered(id, id);
  }

  @override
  Future<void> unregister(int registrationId) async {
    unregistered.add(registrationId);
    final registration = registrations.values.singleWhere(
      (r) => r.registrationId == registrationId,
    );
    await registration.closeInvocationStream();
  }

  Future<wamp.AbstractMessageWithPayload> rpc(
    String method,
    Map<String, Object?> payload, {
    List<Object?>? arguments,
  }) {
    final registration = registrations['authenticate.$method']!;
    final response = Completer<wamp.AbstractMessageWithPayload>();
    final invocation = wamp.Invocation(
      1,
      registration.registrationId,
      wamp.InvocationDetails(null, null, false),
      arguments: arguments,
      argumentsKeywords: payload,
    );
    invocation.onResponse(response.complete);
    registration.addInvocation(invocation);
    return response.future.timeout(const Duration(seconds: 1));
  }

  @override
  dynamic noSuchMethod(core.Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _InspectingAuthServer extends AuthServer {
  _InspectingAuthServer({required super.settings});

  final options = <Map<String, Object?>>[];

  @override
  AuthFailure? validateAuthToken(Map<String, Object?> options) {
    this.options.add(Map<String, Object?>.from(options));
    return super.validateAuthToken(options);
  }
}

class _Factory extends AuthenticatorFactory {
  final authenticator = _Authenticator();
  int calls = 0;
  @override
  String get method => 'controlled';
  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    calls++;
    return authenticator;
  }
}

class _Authenticator extends Authenticator {
  int authenticateCalls = 0;
  int aborts = 0;
  final entered = Completer<void>();
  Future<AuthResult>? result;
  AuthResult? helloResult;
  AuthenticatorContext? lastContext;
  @override
  String get method => 'controlled';
  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    lastContext = context;
    return helloResult ?? AuthResult.challenge(const AuthChallenge(extra: {}));
  }

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) async {
    authenticateCalls++;
    if (!entered.isCompleted) entered.complete();
    return result ??
        AuthResult.success(
          const AuthSuccess(authId: 'user', authRole: 'member'),
        );
  }

  @override
  Future<void> onAbort(AuthenticatorContext context, {String? reason}) async {
    aborts++;
  }
}
