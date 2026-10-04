@TestOn('vm')
library;

import 'package:test/test.dart';

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as fb;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/auth/default_authenticators.dart';
import 'package:connectanum_router/src/router/config/auth_registry.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';

final codec = fb.Serializer();
void check(bool condition, String message) {
  expect(condition, isTrue, reason: message);
}

Future<void> turn() => Future<void>.delayed(Duration.zero);

final class SpyFactory extends AuthenticatorFactory {
  int created = 0, hello = 0, authenticated = 0, aborted = 0;
  @override
  String get method => 'ticket';
  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    created++;
    return SpyAuth(this);
  }
}

final class SpyAuth extends Authenticator {
  SpyAuth(this.spy);
  final SpyFactory spy;
  @override
  String get method => 'ticket';
  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async {
    spy.hello++;
    return AuthResult.challenge(
      const AuthChallenge(
        extra: {},
        challenge: {'challenge': 'native-profile'},
      ),
    );
  }

  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) async {
    spy.authenticated++;
    return AuthResult.success(
      const AuthSuccess(authId: 'bob', authRole: 'user'),
    );
  }

  @override
  Future<void> onAbort(AuthenticatorContext context, {String? reason}) async {
    spy.aborted++;
  }
}

final class Harness {
  Harness({
    String method = 'ticket',
    this.holdWelcome = false,
    this.accept = true,
  }) {
    AuthenticatorRegistry.clear();
    registerDefaultAuthenticators();
    AuthenticatorRegistry.registerFactory(spy);
    settings = RouterSettings(
      realms: [
        RealmSettings(
          name: 'realm1',
          autoCreate: false,
          auth: RealmAuthSettings(methods: [method], methodOptions: const {}),
          roles: const [],
          limits: const RealmLimitSettings(),
        ),
      ],
      listeners: [
        ListenerSettings(
          type: 'rawsocket',
          endpoint: '127.0.0.1:7000',
          authmethods: [method],
          options: const {},
        ),
      ],
      sessionProfiles: const [],
      metrics: null,
      authenticators: const {},
    );
    state = createWorkerStateForTest(
      listener: RouterListener(
        listenerId: 1,
        endpoint: Endpoint(
          host: '127.0.0.1',
          port: 7000,
          tlsMode: TlsMode.disabled,
          maxRawSocketSizeExponent: 16,
        ),
        port: 7000,
        http3Port: 0,
      ),
      listenerSettings: settings.listeners.first,
    );
    state.serializer = NativeMessageSerializer.flatbuffers;
    boss.listen((dynamic value) {
      if (value is! Map || value['type'] != 'worker_send') return;
      final frame = codec.deserialize(value['payload'] as Uint8List)!;
      frames.add(frame);
      final reply = value['acceptedReply'] as SendPort?;
      if (holdWelcome && frame is Welcome) {
        heldReply = reply;
        welcomeSeen.complete();
      } else {
        reply?.send({'accepted': accept && !rejectNext});
      }
    });
    store.listen((dynamic value) {
      if (value is SessionAllocateIdCommand) value.replyPort.send(101);
      if (value is SessionOpenCommand) opened++;
      if (value is SessionCloseCommand) closed++;
    });
  }
  final spy = SpyFactory();
  final boss = ReceivePort(), store = ReceivePort();
  final frames = <AbstractMessage>[];
  final bool holdWelcome, accept;
  final welcomeSeen = Completer<void>();
  SendPort? heldReply;
  late final RouterSettings settings;
  late final dynamic state;
  int opened = 0;
  int closed = 0;
  bool rejectNext = false;
  Future<void> hello(Hello message) => handleHelloForTest(
    boss.sendPort,
    store.sendPort,
    settings,
    state,
    message,
    10,
    null,
    11,
  );
  Future<void> authenticate(Authenticate message) => handleAuthenticateForTest(
    boss.sendPort,
    store.sendPort,
    null,
    state,
    message,
    10,
    11,
  );
  void close() {
    boss.close();
    store.close();
    AuthenticatorRegistry.clear();
  }
}

(Hello, fb.FlatBuffersSessionProfile) offered(String method) {
  final hello = Hello(
    'realm1',
    Details.forHello()
      ..authmethods = [method]
      ..authid = 'bob',
  );
  final profile = const fb.FlatBuffersSessionProfile.client().prepareOutgoing(
    hello,
  );
  return (codec.deserialize(codec.serialize(hello))! as Hello, profile);
}

void main() {
  test('rejects unoffered HELLO before authenticator allocation', () async {
    final h = Harness();
    try {
      await h.hello(
        Hello(
          'realm1',
          Details.forHello()
            ..authmethods = ['ticket']
            ..authid = 'bob',
        ),
      );
      await turn();
      check(h.frames.single is Abort, 'unoffered HELLO must abort');
      check(
        h.spy.created == 0 && h.spy.hello == 0 && h.opened == 0,
        'capability rejected before auth allocation',
      );
    } finally {
      h.close();
    }
  });
  test('anonymous WELCOME acknowledges the profile', () async {
    final h = Harness(method: 'anonymous');
    try {
      final (hello, client) = offered('anonymous');
      await h.hello(hello);
      await turn();
      final welcome = h.frames.single as Welcome;
      check(
        client.acceptIncoming(welcome).isEstablished,
        'anonymous WELCOME carries ack',
      );
      check(
        h.opened == 1 && h.state.phase == HandshakePhase.open,
        'anonymous opens after accepted WELCOME',
      );
    } finally {
      h.close();
    }
  });
  test(
    'authenticated WELCOME independently acknowledges the profile',
    () async {
      final h = Harness();
      try {
        final (hello, initial) = offered('ticket');
        await h.hello(hello);
        await turn();
        final challenge = h.frames.single as Challenge;
        var client = initial.acceptIncoming(challenge);
        check(
          h.spy.created == 1 && h.spy.hello == 1 && h.opened == 0,
          'challenge requires no open session',
        );
        final auth = Authenticate(signature: 'credentials');
        client = client.prepareOutgoing(auth);
        await h.authenticate(
          codec.deserialize(codec.serialize(auth))! as Authenticate,
        );
        await turn();
        final welcome = h.frames.last as Welcome;
        check(
          client.acceptIncoming(welcome).isEstablished,
          'authenticated WELCOME carries independent ack',
        );
        check(
          h.spy.authenticated == 1 &&
              h.opened == 1 &&
              h.state.phase == HandshakePhase.open,
          'authenticated session opens',
        );
      } finally {
        h.close();
      }
    },
  );
  for (final method in ['anonymous', 'ticket']) {
    test('waits for native WELCOME acceptance: $method', () async {
      final h = Harness(method: method, holdWelcome: true);
      try {
        final (hello, initial) = offered(method);
        Future<void> pending;
        if (method == 'anonymous') {
          pending = h.hello(hello);
        } else {
          await h.hello(hello);
          await turn();
          final client = initial.acceptIncoming(h.frames.single);
          final auth = Authenticate(signature: 'credentials');
          client.prepareOutgoing(auth);
          pending = h.authenticate(auth);
        }
        await h.welcomeSeen.future.timeout(const Duration(seconds: 2));
        check(
          h.opened == 0 &&
              h.state.phase != HandshakePhase.open &&
              !h.state.flatBuffersProfile.isEstablished,
          '$method cannot open before native enqueue acceptance',
        );
        h.heldReply!.send({'accepted': true});
        await pending;
        await turn();
        check(
          h.opened == 1 &&
              h.state.phase == HandshakePhase.open &&
              h.state.flatBuffersProfile.isEstablished,
          '$method opens after acceptance',
        );
      } finally {
        h.close();
      }
    });
  }
  test('rejected anonymous WELCOME never opens a session', () async {
    final h = Harness(method: 'anonymous', accept: false);
    try {
      final (hello, _) = offered('anonymous');
      try {
        await h.hello(hello);
      } catch (_) {}
      await turn();
      check(
        h.opened == 0 &&
            h.state.phase != HandshakePhase.open &&
            !h.state.flatBuffersProfile.isEstablished,
        'rejected WELCOME never establishes session',
      );
    } finally {
      h.close();
    }
  });
  for (final rejectChallenge in [true, false]) {
    test('cleans rejected authentication sends: $rejectChallenge', () async {
      final h = Harness(accept: !rejectChallenge);
      try {
        final (hello, initial) = offered('ticket');
        try {
          await h.hello(hello);
        } catch (_) {}
        await turn();
        if (!rejectChallenge) {
          final client = initial.acceptIncoming(h.frames.single);
          final auth = Authenticate(signature: 'credentials');
          client.prepareOutgoing(auth);
          // Reject only the subsequent WELCOME and fallback ABORT.
          h.rejectNext = true;
          try {
            await h.authenticate(auth);
          } catch (_) {}
          await turn();
        }
        check(
          h.opened == 0 && h.state.phase == HandshakePhase.aborted,
          'rejected auth frame terminates handshake',
        );
        check(
          h.spy.aborted == 1 &&
              h.state.authenticator == null &&
              h.state.authContext == null,
          'rejected auth frame cleans exactly once',
        );
        check(
          h.spy.authenticated == (rejectChallenge ? 0 : 1),
          'credentials only run after accepted challenge',
        );
      } finally {
        h.close();
      }
    });
  }
  for (final method in ['anonymous', 'ticket']) {
    test(
      'disconnect during WELCOME never reopens a session: $method',
      () async {
        final h = Harness(method: method, holdWelcome: true);
        try {
          final (hello, initial) = offered(method);
          Future<void> pending;
          if (method == 'anonymous') {
            pending = h.hello(hello);
          } else {
            await h.hello(hello);
            await turn();
            final client = initial.acceptIncoming(h.frames.single);
            final auth = Authenticate(signature: 'credentials');
            client.prepareOutgoing(auth);
            pending = h.authenticate(auth);
          }
          await h.welcomeSeen.future.timeout(const Duration(seconds: 2));
          await handleRemoveConnectionForTest(
            connectionId: 10,
            connections: <int, int>{10: 1},
            connectionStates: <int, WorkerConnectionState>{
              10: h.state as WorkerConnectionState,
            },
            statePort: h.store.sendPort,
            realmContexts: null,
          );
          h.heldReply!.send({'accepted': true});
          try {
            await pending;
          } catch (_) {}
          await turn();
          check(
            h.opened == 0 &&
                h.state.phase == HandshakePhase.aborted &&
                !h.state.flatBuffersProfile.isEstablished,
            '$method disconnect during enqueue must not reopen session',
          );
          check(
            h.spy.aborted == (method == 'ticket' ? 1 : 0),
            'disconnect auth cleanup exactly once',
          );
        } finally {
          h.close();
        }
      },
    );
  }
  test('failed GOODBYE still releases the open session', () async {
    final h = Harness(method: 'anonymous');
    try {
      final (hello, _) = offered('anonymous');
      await h.hello(hello);
      await turn();
      expect(h.opened, 1);
      h.rejectNext = true;
      await expectLater(
        initiateServerGoodbyeForTest(
          bossPort: h.boss.sendPort,
          statePort: h.store.sendPort,
          realmContexts: null,
          state: h.state as WorkerConnectionState,
          connectionId: 10,
        ),
        throwsStateError,
      );
      await turn();
      expect(h.state.phase, HandshakePhase.aborted);
      expect(h.state.sessionId, isNull);
      expect(h.closed, 1);
    } finally {
      h.close();
    }
  });
}
