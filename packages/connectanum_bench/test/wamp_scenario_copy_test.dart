@TestOn('vm')
library;

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:test/test.dart';

void main() {
  test('omitting every override preserves all nondefault settings', () {
    final source = _scenario();
    final copied = source.copyWith();
    expect(identical(source, copied), isFalse);
    expect(_values(copied), _expected);
    expect(_values(source), _expected);
  });

  test('copyWith overrides only realmUri', () {
    final source = _scenario();
    final copied = source.copyWith(realmUri: 'realm.changed');
    expect(_values(copied), {..._expected, 'realmUri': 'realm.changed'});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only authMethod', () {
    final source = _scenario();
    final copied = source.copyWith(authMethod: 'wampcra');
    expect(_values(copied), {..._expected, 'authMethod': 'wampcra'});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only authId', () {
    final source = _scenario();
    final copied = source.copyWith(authId: 'changed-user');
    expect(_values(copied), {..._expected, 'authId': 'changed-user'});
    expect(_values(source), _expected);
  });

  test('copyWith explicitly clears authId without clearing other fields', () {
    final source = _scenario();
    final cleared = source.copyWith(authId: null);
    expect(_values(cleared), {..._expected, 'authId': null});
    expect(_values(cleared.copyWith()), {..._expected, 'authId': null});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only authSecret', () {
    final source = _scenario();
    final copied = source.copyWith(authSecret: 'synthetic-changed-secret');
    expect(_values(copied), {
      ..._expected,
      'authSecret': 'synthetic-changed-secret',
    });
    expect(_values(source), _expected);
  });

  test(
    'copyWith explicitly clears authSecret without clearing other fields',
    () {
      final source = _scenario();
      final cleared = source.copyWith(authSecret: null);
      expect(_values(cleared), {..._expected, 'authSecret': null});
      expect(_values(cleared.copyWith()), {..._expected, 'authSecret': null});
      expect(_values(source), _expected);
    },
  );

  test('copyWith overrides only secureTransport', () {
    final source = _scenario();
    final copied = source.copyWith(secureTransport: false);
    expect(_values(copied), {..._expected, 'secureTransport': false});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only transport', () {
    final source = _scenario();
    final copied = source.copyWith(transport: WampTransport.rawsocket);
    expect(_values(copied), {
      ..._expected,
      'transport': WampTransport.rawsocket,
    });
    expect(_values(source), _expected);
  });

  test('copyWith overrides only clientImplementation', () {
    final source = _scenario();
    final copied = source.copyWith(
      clientImplementation: WampClientImplementation.dart,
    );
    expect(_values(copied), {
      ..._expected,
      'clientImplementation': WampClientImplementation.dart,
    });
    expect(_values(source), _expected);
  });

  test('copyWith overrides only serializer', () {
    final source = _scenario();
    final copied = source.copyWith(serializer: WampSerializer.json);
    expect(_values(copied), {..._expected, 'serializer': WampSerializer.json});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only peerSerializer', () {
    final source = _scenario();
    final copied = source.copyWith(peerSerializer: WampSerializer.cbor);
    expect(_values(copied), {
      ..._expected,
      'peerSerializer': WampSerializer.cbor,
    });
    expect(_values(source), _expected);
  });

  test(
    'copyWith explicitly clears peerSerializer without clearing other fields',
    () {
      final source = _scenario();
      final cleared = source.copyWith(peerSerializer: null);
      expect(_values(cleared), {..._expected, 'peerSerializer': null});
      expect(_values(cleared.copyWith()), {
        ..._expected,
        'peerSerializer': null,
      });
      expect(_values(source), _expected);
    },
  );

  test('copyWith overrides only mode', () {
    final source = _scenario();
    final copied = source.copyWith(mode: WampMode.publishAck);
    expect(_values(copied), {..._expected, 'mode': WampMode.publishAck});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only uri', () {
    final source = _scenario();
    final copied = source.copyWith(uri: 'com.changed');
    expect(_values(copied), {..._expected, 'uri': 'com.changed'});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only iterations', () {
    final source = _scenario();
    final copied = source.copyWith(iterations: 31);
    expect(_values(copied), {..._expected, 'iterations': 31});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only concurrency', () {
    final source = _scenario();
    final copied = source.copyWith(concurrency: 5);
    expect(_values(copied), {..._expected, 'concurrency': 5});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only inFlightPerSession', () {
    final source = _scenario();
    final copied = source.copyWith(inFlightPerSession: 11);
    expect(_values(copied), {..._expected, 'inFlightPerSession': 11});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only peerCount', () {
    final source = _scenario();
    final copied = source.copyWith(peerCount: 19);
    expect(_values(copied), {..._expected, 'peerCount': 19});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only payloadBytes', () {
    final source = _scenario();
    final copied = source.copyWith(payloadBytes: 0);
    expect(_values(copied), {..._expected, 'payloadBytes': 0});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only websocketFragmentSize', () {
    final source = _scenario();
    final copied = source.copyWith(websocketFragmentSize: 512);
    expect(_values(copied), {..._expected, 'websocketFragmentSize': 512});
    expect(_values(source), _expected);
  });

  test(
    'copyWith explicitly clears websocketFragmentSize without clearing other fields',
    () {
      final source = _scenario();
      final cleared = source.copyWith(websocketFragmentSize: null);
      expect(_values(cleared), {..._expected, 'websocketFragmentSize': null});
      expect(_values(cleared.copyWith()), {
        ..._expected,
        'websocketFragmentSize': null,
      });
      expect(_values(source), _expected);
    },
  );

  test('copyWith overrides only fileChunkBytes', () {
    final source = _scenario();
    final copied = source.copyWith(fileChunkBytes: 8192);
    expect(_values(copied), {..._expected, 'fileChunkBytes': 8192});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only eventTimeoutMs', () {
    final source = _scenario();
    final copied = source.copyWith(eventTimeoutMs: 6001);
    expect(_values(copied), {..._expected, 'eventTimeoutMs': 6001});
    expect(_values(source), _expected);
  });

  test(
    'copyWith explicitly clears eventTimeoutMs without clearing other fields',
    () {
      final source = _scenario();
      final cleared = source.copyWith(eventTimeoutMs: null);
      expect(_values(cleared), {..._expected, 'eventTimeoutMs': null});
      expect(_values(cleared.copyWith()), {
        ..._expected,
        'eventTimeoutMs': null,
      });
      expect(_values(source), _expected);
    },
  );

  test('copyWith overrides only callTimeoutMs', () {
    final source = _scenario();
    final copied = source.copyWith(callTimeoutMs: 8001);
    expect(_values(copied), {..._expected, 'callTimeoutMs': 8001});
    expect(_values(source), _expected);
  });

  test(
    'copyWith explicitly clears callTimeoutMs without clearing other fields',
    () {
      final source = _scenario();
      final cleared = source.copyWith(callTimeoutMs: null);
      expect(_values(cleared), {..._expected, 'callTimeoutMs': null});
      expect(_values(cleared.copyWith()), {
        ..._expected,
        'callTimeoutMs': null,
      });
      expect(_values(source), _expected);
    },
  );

  test('copyWith overrides only controlCustomFields', () {
    final source = _scenario();
    final copied = source.copyWith(controlCustomFields: false);
    expect(_values(copied), {..._expected, 'controlCustomFields': false});
    expect(_values(source), _expected);
  });

  test('copyWith overrides only pptScheme', () {
    final source = _scenario();
    final copied = source.copyWith(pptScheme: 'x_changed');
    expect(_values(copied), {..._expected, 'pptScheme': 'x_changed'});
    expect(_values(source), _expected);
  });

  test(
    'copyWith explicitly clears pptScheme without clearing other fields',
    () {
      final source = _scenario();
      final cleared = source.copyWith(pptScheme: null);
      expect(_values(cleared), {..._expected, 'pptScheme': null});
      expect(_values(cleared.copyWith()), {..._expected, 'pptScheme': null});
      expect(_values(source), _expected);
    },
  );

  test('copyWith overrides only pptSerializer', () {
    final source = _scenario();
    final copied = source.copyWith(pptSerializer: 'json');
    expect(_values(copied), {..._expected, 'pptSerializer': 'json'});
    expect(_values(source), _expected);
  });

  test(
    'copyWith explicitly clears pptSerializer without clearing other fields',
    () {
      final source = _scenario();
      final cleared = source.copyWith(pptSerializer: null);
      expect(_values(cleared), {..._expected, 'pptSerializer': null});
      expect(_values(cleared.copyWith()), {
        ..._expected,
        'pptSerializer': null,
      });
      expect(_values(source), _expected);
    },
  );

  test('copyWith overrides only pptCipher', () {
    final source = _scenario();
    final copied = source.copyWith(pptCipher: 'cipher-changed');
    expect(_values(copied), {..._expected, 'pptCipher': 'cipher-changed'});
    expect(_values(source), _expected);
  });

  test(
    'copyWith explicitly clears pptCipher without clearing other fields',
    () {
      final source = _scenario();
      final cleared = source.copyWith(pptCipher: null);
      expect(_values(cleared), {..._expected, 'pptCipher': null});
      expect(_values(cleared.copyWith()), {..._expected, 'pptCipher': null});
      expect(_values(source), _expected);
    },
  );

  test('copyWith overrides only pptKeyId', () {
    final source = _scenario();
    final copied = source.copyWith(pptKeyId: 'key-changed');
    expect(_values(copied), {..._expected, 'pptKeyId': 'key-changed'});
    expect(_values(source), _expected);
  });

  test('copyWith explicitly clears pptKeyId without clearing other fields', () {
    final source = _scenario();
    final cleared = source.copyWith(pptKeyId: null);
    expect(_values(cleared), {..._expected, 'pptKeyId': null});
    expect(_values(cleared.copyWith()), {..._expected, 'pptKeyId': null});
    expect(_values(source), _expected);
  });

  test(
    'copyWith can restore false flags and zero payload to nondefault values',
    () {
      final source = _scenario().copyWith(
        secureTransport: false,
        controlCustomFields: false,
        payloadBytes: 0,
      );
      expect(
        _values(
          source.copyWith(
            secureTransport: true,
            controlCustomFields: true,
            payloadBytes: 1027,
          ),
        ),
        _expected,
      );
      expect(_values(source), {
        ..._expected,
        'secureTransport': false,
        'controlCustomFields': false,
        'payloadBytes': 0,
      });
    },
  );
}

WampScenario _scenario() => WampScenario(
  realmUri: 'realm.original',
  authMethod: 'ticket',
  authId: 'original-user',
  authSecret: 'synthetic-original-secret',
  secureTransport: true,
  transport: WampTransport.websocket,
  clientImplementation: WampClientImplementation.native,
  serializer: WampSerializer.cbor,
  peerSerializer: WampSerializer.msgpack,
  mode: WampMode.rpc,
  uri: 'com.original',
  iterations: 17,
  concurrency: 3,
  inFlightPerSession: 7,
  peerCount: 13,
  payloadBytes: 1027,
  websocketFragmentSize: 256,
  fileChunkBytes: 4096,
  eventTimeoutMs: 3001,
  callTimeoutMs: 4001,
  controlCustomFields: true,
  pptScheme: 'x_original',
  pptSerializer: 'cbor',
  pptCipher: 'cipher-original',
  pptKeyId: 'key-original',
);

const _expected = <String, Object?>{
  'realmUri': 'realm.original',
  'authMethod': 'ticket',
  'authId': 'original-user',
  'authSecret': 'synthetic-original-secret',
  'secureTransport': true,
  'transport': WampTransport.websocket,
  'clientImplementation': WampClientImplementation.native,
  'serializer': WampSerializer.cbor,
  'peerSerializer': WampSerializer.msgpack,
  'mode': WampMode.rpc,
  'uri': 'com.original',
  'iterations': 17,
  'concurrency': 3,
  'inFlightPerSession': 7,
  'peerCount': 13,
  'payloadBytes': 1027,
  'websocketFragmentSize': 256,
  'fileChunkBytes': 4096,
  'eventTimeoutMs': 3001,
  'callTimeoutMs': 4001,
  'controlCustomFields': true,
  'pptScheme': 'x_original',
  'pptSerializer': 'cbor',
  'pptCipher': 'cipher-original',
  'pptKeyId': 'key-original',
};

Map<String, Object?> _values(WampScenario value) => {
  'realmUri': value.realmUri,
  'authMethod': value.authMethod,
  'authId': value.authId,
  'authSecret': value.authSecret,
  'secureTransport': value.secureTransport,
  'transport': value.transport,
  'clientImplementation': value.clientImplementation,
  'serializer': value.serializer,
  'peerSerializer': value.peerSerializer,
  'mode': value.mode,
  'uri': value.uri,
  'iterations': value.iterations,
  'concurrency': value.concurrency,
  'inFlightPerSession': value.inFlightPerSession,
  'peerCount': value.peerCount,
  'payloadBytes': value.payloadBytes,
  'websocketFragmentSize': value.websocketFragmentSize,
  'fileChunkBytes': value.fileChunkBytes,
  'eventTimeoutMs': value.eventTimeoutMs,
  'callTimeoutMs': value.callTimeoutMs,
  'controlCustomFields': value.controlCustomFields,
  'pptScheme': value.pptScheme,
  'pptSerializer': value.pptSerializer,
  'pptCipher': value.pptCipher,
  'pptKeyId': value.pptKeyId,
};
