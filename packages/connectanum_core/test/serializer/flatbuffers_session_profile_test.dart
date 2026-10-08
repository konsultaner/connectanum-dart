import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:test/test.dart';

void main() {
  final codec = flat.Serializer();
  core.Hello hello() => core.Hello('realm', core.Details.forHello());
  core.Welcome welcome() => core.Welcome(42, core.Details.forWelcome());
  core.Challenge challenge() => core.Challenge('ticket', core.Extra());
  core.Call call() => core.Call(1, 'com.proc');
  core.AbstractMessage wire(core.AbstractMessage message) =>
      codec.deserialize(codec.serialize(message))!;

  test('anonymous handshake offers and acknowledges each existing role', () {
    var client = const flat.FlatBuffersSessionProfile.client();
    var router = const flat.FlatBuffersSessionProfile.router();
    final offer = hello();
    client = client.prepareOutgoing(offer);
    router = router.acceptIncoming(wire(offer));
    final accepted = welcome();
    router = router.prepareOutgoing(accepted);
    client = client.acceptIncoming(wire(accepted));
    expect(client.isEstablished, isTrue);
    expect(router.isEstablished, isTrue);
    expect(client.prepareOutgoing(call()).isEstablished, isTrue);
    expect(router.acceptIncoming(call()).isEstablished, isTrue);
    final roles = codec.metadataFor(offer)['roles'] as Map;
    for (final name in ['caller', 'callee', 'publisher', 'subscriber']) {
      expect(roles[name]['features'][flat.flatBuffersMetadataFeature], isTrue);
    }
  });

  test(
    'credentials require a challenge and WELCOME requires fresh acknowledgement',
    () {
      var client = const flat.FlatBuffersSessionProfile.client();
      var router = const flat.FlatBuffersSessionProfile.router();
      final offer = hello();
      client = client.prepareOutgoing(offer);
      router = router.acceptIncoming(wire(offer));
      expect(
        () => client.prepareOutgoing(core.Authenticate(signature: 'secret')),
        throwsStateError,
      );
      final authChallenge = challenge();
      router = router.prepareOutgoing(authChallenge);
      client = client.acceptIncoming(wire(authChallenge));
      expect(() => client.acceptIncoming(welcome()), throwsStateError);
      final credentials = core.Authenticate(signature: 'secret');
      client = client.prepareOutgoing(credentials);
      router = router.acceptIncoming(wire(credentials));
      expect(() => client.acceptIncoming(welcome()), throwsUnsupportedError);
      expect(client.isEstablished, isFalse);
      final accepted = welcome();
      router = router.prepareOutgoing(accepted);
      expect(client.acceptIncoming(wire(accepted)).isEstablished, isTrue);
    },
  );

  for (final acknowledgement in [null, false, 1, 'true']) {
    test(
      'rejects challenge acknowledgement $acknowledgement before credentials',
      () {
        final client = const flat.FlatBuffersSessionProfile.client()
            .prepareOutgoing(hello());
        final incoming = challenge();
        if (acknowledgement != null) {
          codec.retainMetadataValues(incoming, {
            flat.flatBuffersMetadataFeature: acknowledgement,
          });
        }
        expect(
          () => client.acceptIncoming(wire(incoming)),
          throwsUnsupportedError,
        );
        expect(
          () => client.prepareOutgoing(core.Authenticate(signature: 'secret')),
          throwsStateError,
        );
      },
    );
  }

  test(
    'multiple authentication rounds each require acknowledged challenges',
    () {
      var client = const flat.FlatBuffersSessionProfile.client()
          .prepareOutgoing(hello());
      var router = const flat.FlatBuffersSessionProfile.router();
      final offer = hello();
      const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
      router = router.acceptIncoming(wire(offer));
      for (var round = 0; round < 2; round++) {
        final authChallenge = challenge();
        router = router.prepareOutgoing(authChallenge);
        client = client.acceptIncoming(wire(authChallenge));
        final credentials = core.Authenticate(signature: 'secret-$round');
        client = client.prepareOutgoing(credentials);
        router = router.acceptIncoming(credentials);
      }
      final accepted = welcome();
      router.prepareOutgoing(accepted);
      expect(client.acceptIncoming(wire(accepted)).isEstablished, isTrue);
    },
  );

  test(
    'partial router roles are valid but every existing role must acknowledge',
    () {
      final client = const flat.FlatBuffersSessionProfile.client()
          .prepareOutgoing(hello());
      final brokerOnly = welcome();
      brokerOnly.details.roles!.dealer = null;
      codec.retainMetadataValues(brokerOnly, {
        'roles': {
          'broker': {
            'features': {flat.flatBuffersMetadataFeature: true},
          },
        },
      });
      expect(client.acceptIncoming(wire(brokerOnly)).isEstablished, isTrue);
      final partial = welcome();
      codec.retainMetadataValues(partial, {
        'roles': {
          'broker': {
            'features': {flat.flatBuffersMetadataFeature: true},
          },
          'dealer': {'features': <String, dynamic>{}},
        },
      });
      expect(
        () => client.acceptIncoming(wire(partial)),
        throwsUnsupportedError,
      );
    },
  );

  test('pre-encoded bootstrap frames cannot gain missing capabilities', () {
    const initial = flat.FlatBuffersSessionProfile.client();
    expect(
      () => initial.prepareOutgoing(hello(), advertise: false),
      throwsUnsupportedError,
    );
    final offer = hello();
    initial.prepareOutgoing(offer);
    expect(
      initial.prepareOutgoing(wire(offer), advertise: false).isEstablished,
      isFalse,
    );
    expect(initial.isEstablished, isFalse);
  });

  test(
    'application traffic is blocked before establishment and after closure',
    () {
      const initial = flat.FlatBuffersSessionProfile.client();
      expect(() => initial.prepareOutgoing(call()), throwsStateError);
      expect(() => initial.acceptIncoming(call()), throwsStateError);
      final closed = initial.acceptIncoming(
        core.Abort('wamp.error.not_authorized'),
      );
      expect(() => closed.prepareOutgoing(hello()), throwsStateError);
      expect(() => closed.acceptIncoming(call()), throwsStateError);
    },
  );

  test('rejected prepare does not advance profile state', () {
    const initial = flat.FlatBuffersSessionProfile.router();
    expect(() => initial.acceptIncoming(hello()), throwsUnsupportedError);
    final offer = hello();
    const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
    expect(initial.acceptIncoming(wire(offer)).isEstablished, isFalse);
    expect(() => initial.prepareOutgoing(welcome()), throwsStateError);
  });

  test(
    'missing roles and empty role dictionaries cannot establish capability',
    () {
      const client = flat.FlatBuffersSessionProfile.client();
      for (final details in [
        core.Details(),
        core.Details()..roles = core.Roles(),
      ]) {
        expect(
          () => client.prepareOutgoing(core.Hello('realm', details)),
          throwsUnsupportedError,
        );
      }
      final offered = client.prepareOutgoing(hello());
      expect(
        () => offered.acceptIncoming(core.Welcome(42, core.Details())),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'bootstrap advertisement adds absent feature maps without losing metadata',
    () {
      final offer = core.Hello(
        'realm',
        core.Details()..roles = (core.Roles()..caller = core.Caller()),
      );
      codec.retainMetadataValues(offer, {
        'roles': {'caller': <String, dynamic>{}},
        'x_vendor': {'nested': 'keep'},
      });
      const flat.FlatBuffersSessionProfile.client().prepareOutgoing(offer);
      final metadata = codec.metadataFor(wire(offer));
      expect(
        metadata['roles']['caller']['features'][flat
            .flatBuffersMetadataFeature],
        isTrue,
      );
      expect(metadata['x_vendor'], {'nested': 'keep'});
      final router = const flat.FlatBuffersSessionProfile.router()
          .acceptIncoming(wire(offer));
      final accepted = core.Welcome(
        42,
        core.Details()..roles = (core.Roles()..broker = core.Broker()),
      );
      router.prepareOutgoing(accepted);
      expect(
        codec.metadataFor(
          wire(accepted),
        )['roles']['broker']['features'][flat.flatBuffersMetadataFeature],
        isTrue,
      );
    },
  );

  test('bootstrap messages reject the wrong direction and terminal ABORT', () {
    const client = flat.FlatBuffersSessionProfile.client();
    const router = flat.FlatBuffersSessionProfile.router();
    expect(() => client.acceptIncoming(hello()), throwsStateError);
    expect(() => router.prepareOutgoing(hello()), throwsStateError);
    expect(() => client.prepareOutgoing(challenge()), throwsStateError);
    expect(() => router.acceptIncoming(challenge()), throwsStateError);
    expect(() => client.prepareOutgoing(welcome()), throwsStateError);
    final offer = hello();
    final pending = client.prepareOutgoing(offer);
    final readyRouter = router.acceptIncoming(wire(offer));
    final accepted = welcome();
    readyRouter.prepareOutgoing(accepted);
    final established = pending.acceptIncoming(wire(accepted));
    expect(
      () => established.acceptIncoming(core.Abort('wamp.error.failed')),
      throwsStateError,
    );
    final closed = client.prepareOutgoing(core.Abort('wamp.error.failed'));
    expect(
      () => closed.acceptIncoming(core.Abort('wamp.error.failed')),
      throwsStateError,
    );
  });

  test('goodbye exchange blocks later application frames', () {
    final offer = hello();
    var client = const flat.FlatBuffersSessionProfile.client().prepareOutgoing(
      offer,
    );
    var router = const flat.FlatBuffersSessionProfile.router().acceptIncoming(
      wire(offer),
    );
    final accepted = welcome();
    router = router.prepareOutgoing(accepted);
    client = client.acceptIncoming(wire(accepted));
    final goodbye = core.Goodbye(null, 'wamp.close.normal');
    client = client.prepareOutgoing(goodbye);
    router = router.acceptIncoming(goodbye);
    expect(() => client.prepareOutgoing(call()), throwsStateError);
    router = router.prepareOutgoing(
      core.Goodbye(null, 'wamp.close.goodbye_and_out'),
    );
    client = client.acceptIncoming(
      core.Goodbye(null, 'wamp.close.goodbye_and_out'),
    );
    expect(() => client.acceptIncoming(call()), throwsStateError);
    expect(() => router.prepareOutgoing(call()), throwsStateError);
  });
}
