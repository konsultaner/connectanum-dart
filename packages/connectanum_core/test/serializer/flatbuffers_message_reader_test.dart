import 'dart:typed_data';
import 'dart:isolate';

import 'package:cbor/cbor.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/runtime.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';
import 'package:test/test.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/frame.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/message_projection.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/message_reader.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/cbor_encoding.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;

final codec = flatbuffers.Serializer();

Uint8List frameWithDictionary(
  String name,
  Map<String, Object?> body,
  Map<String, Object?> dictionary,
  int tag,
) {
  final builder = WampFlatBufferBuilder();
  builder.finish(
    writeWampFlatBufferFields({
      'msg_type': tag,
      'msg': {
        ...body,
        ...projectFlatBufferDictionary(name, dictionary),
      },
      'metadata': Uint8List.fromList(cbor.encode(CborValue(dictionary))),
    }, builder),
  );
  return builder.buffer;
}

void main() {
  test('public serializer handles null input and bounds malformed frames', () {
    expect(codec.deserialize(null), isNull);
    expect(() => codec.deserialize(Uint8List(0)), throwsFormatException);
  });

  test('typed PPT preserves the application byte buffer', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final payload = PPTPayload(arguments: [bytes]);
    expect(codec.serializePPT(payload), same(bytes));
    expect(codec.deserializePPT(bytes).arguments!.single, same(bytes));
    expect(codec.serializePPTFragments(arguments: [bytes]), same(bytes));
  });

  test('typed PPT rejects dynamic or encoded CBOR containers', () {
    expect(
      () => codec.serializePPT(PPTPayload(arguments: [1])),
      throwsUnsupportedError,
    );
    expect(
      () => codec.serializePPT(PPTPayload(arguments: [])),
      throwsUnsupportedError,
    );
    expect(() => codec.serializePPT(PPTPayload()), throwsUnsupportedError);
    expect(
      () => codec.serializePPT(
        PPTPayload(arguments: [Uint8List(0)], argumentsKeywords: {}),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => codec.serializePPTFragments(
        argumentsBytes: Uint8List.fromList([0x80]),
      ),
      throwsUnsupportedError,
    );
  });

  test('FlatBuffers PPT dispatch preserves bytes and rejects dynamic maps', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final options = CallOptions(
      pptScheme: 'x_flatbuffers',
      pptSerializer: 'flatbuffers',
    );
    final packed = PPTPayload.packPPTPayload([bytes], null, options);
    expect(packed.single, same(bytes));
    expect(
      PPTPayload.unpackPPTPayload(packed, options).arguments!.single,
      same(bytes),
    );
    expect(
      () => PPTPayload.packPPTPayload(
        [
          {'value': 1},
        ],
        null,
        options,
      ),
      throwsUnsupportedError,
    );
    expect(
      () => PPTPayload.packSerializedPayload(
        'flatbuffers',
        argumentsBytes: Uint8List.fromList([0x80]),
      ),
      throwsUnsupportedError,
    );
  });

  test('replacing features discards retained values in that branch', () {
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary(
                'Hello',
                {
                  'realm': 'realm',
                },
                {
                  'roles': {
                    'caller': {
                      '_role': true,
                      'features': {'call_timeout': null, '_old': true},
                    },
                    '_future_role': {},
                  },
                  '_root': true,
                },
                1,
              ),
            )
            as Hello;
    message.details.roles!.caller!.features = CallerFeatures()
      ..callTimeout = false;
    final result = readWampFlatBufferFrame(
      codec.serialize(message),
    ).dictionary!;
    final roles = result['roles'] as Map;
    final caller = roles['caller'] as Map;
    expect(caller['_role'], isTrue);
    expect(roles['_future_role'], {});
    expect(result['_root'], isTrue);
    expect((caller['features'] as Map)['call_timeout'], isFalse);
    expect((caller['features'] as Map).containsKey('_old'), isFalse);
  });

  test('replacing the metadata root discards its retained values', () {
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary(
                'Call',
                {
                  'request': 1,
                  'procedure': 'com.proc',
                },
                {'timeout': 10, '_old': true},
                16,
              ),
            )
            as Call;
    message.options = CallOptions(timeout: 25);
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'timeout': 25,
    });
  });

  test('binary custom mutations are compared against a detached baseline', () {
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary(
                'Call',
                {
                  'request': 1,
                  'procedure': 'com.proc',
                },
                {
                  '_binary': Uint8List.fromList([1, 2]),
                  '_null': null,
                },
                16,
              ),
            )
            as Call;
    (message.options!.custom['_binary'] as Uint8List)[0] = 7;
    final dictionary = readWampFlatBufferFrame(
      codec.serialize(message),
    ).dictionary!;
    expect(dictionary['_binary'], [7, 2]);
    expect(dictionary.containsKey('_null'), isTrue);
    expect(dictionary['_null'], isNull);
  });

  test('explicit false replaces null Yield progress', () {
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary(
                'Yield',
                {
                  'request': 1,
                },
                {'progress': null, '_old': true},
                25,
              ),
            )
            as Yield;
    message.options!.progress = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'progress': false,
      '_old': true,
    });
  });

  test('cyclic edited metadata fails before retention snapshots', () {
    final message =
        readWampFlatBufferMessage(
              codec.serialize(
                Call(
                  1,
                  'com.proc',
                  options: CallOptions(custom: {'_keep': true}),
                ),
              ),
            )
            as Call;
    final cycle = <Object?>[];
    cycle.add(cycle);
    message.options!.custom['_cycle'] = cycle;
    expect(() => codec.serialize(message), throwsArgumentError);
  });

  test('normalization leaves unchanged containers intact', () {
    final value = <Object?>[
      {
        'binary': Uint8List.fromList([1, 2]),
      },
    ];
    expect(normalizeWampFlatBufferCborInput(value), same(value));
  });

  test(
    'aliased transferable data is materialized once in nested arguments',
    () {
      final transfer = TransferableTypedData.fromList([
        Uint8List.fromList([1, 2]),
      ]);
      final message =
          readWampFlatBufferMessage(
                codec.serialize(
                  Call(
                    1,
                    'com.proc',
                    arguments: [
                      transfer,
                      {'nested': transfer},
                    ],
                  ),
                ),
              )
              as Call;
      expect(message.arguments![0], [1, 2]);
      expect(message.arguments![1], {
        'nested': [1, 2],
      });
    },
    testOn: 'vm',
  );

  for (final invalid in <List<int>>[
    [0xa1, 0x01, 0x01],
    [0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02],
  ]) {
    test('invalid kwargs root rejects before exposing a model: $invalid', () {
      final builder = WampFlatBufferBuilder();
      builder.finish(
        writeWampFlatBufferFields({
          'msg_type': 16,
          'msg': {
            'request': 1,
            'procedure': 'com.proc',
            'kwargs': Uint8List.fromList(invalid),
          },
          'metadata': Uint8List.fromList([0xa0]),
        }, builder),
      );
      expect(
        () => readWampFlatBufferMessage(builder.buffer),
        throwsFormatException,
      );
    });
    test('invalid retained kwargs rejects without decoding: $invalid', () {
      final message = Call(1, 'com.proc');
      message.restoreLazyPayload(
        LazyMessagePayload.encoded(
          encoding: LazyPayloadEncoding.cbor,
          argumentsKeywordsBytes: Uint8List.fromList(invalid),
          argumentsKeywordsDecoder: (_) => throw StateError('must stay lazy'),
        ),
      );
      expect(() => codec.serialize(message), throwsFormatException);
    });
  }

  test('nested application maps may have numeric keys', () {
    final message =
        readWampFlatBufferMessage(
              codec.serialize(
                Call(
                  1,
                  'com.proc',
                  argumentsKeywords: {
                    'nested': {7: 'value'},
                  },
                ),
              ),
            )
            as Call;
    expect(message.argumentsKeywords, {
      'nested': {7: 'value'},
    });
  });

  final messages = <String, AbstractMessage>{
    'Hello': Hello('realm', Details()),
    'Welcome': Welcome(123, Details()),
    'Abort': Abort('wamp.error.not_authorized'),
    'Challenge': Challenge('ticket', Extra()),
    'Authenticate': Authenticate(signature: 'secret'),
    'Goodbye': Goodbye(GoodbyeMessage('bye'), 'wamp.close.normal'),
    'Error': Error(48, 10, {}, 'wamp.error.runtime_error'),
    'Publish': Publish(11, 'com.topic'),
    'Published': Published(11, 123),
    'Subscribe': Subscribe(12, 'com.topic'),
    'Subscribed': Subscribed(12, 124),
    'Unsubscribe': Unsubscribe(13, 124),
    'Unsubscribed': Unsubscribed(13, null),
    'Event': Event(124, 123, EventDetails()),
    'Call': Call(14, 'com.proc'),
    'Cancel': Cancel(14),
    'Result': Result(14, ResultDetails()),
    'Register': Register(15, 'com.proc'),
    'Registered': Registered(15, 125),
    'Unregister': Unregister(16, 125),
    'Unregistered': Unregistered(16),
    'Invocation': Invocation(17, 125, InvocationDetails(null, null, null)),
    'Interrupt': Interrupt(17),
    'Yield': Yield(17),
    'Heartbeat': Heartbeat(ping: 0),
  };

  for (final entry in messages.entries) {
    test('reconstruct ${entry.key}', () {
      final decoded = codec.deserialize(codec.serialize(entry.value))!;
      expect(decoded.runtimeType, entry.value.runtimeType);
      expect(decoded.id, entry.value.id);
      final original = projectWampFlatBufferMessage(entry.value);
      final output = projectWampFlatBufferMessage(decoded);
      expect(output.fields, original.fields);
      expect(output.dictionary, original.dictionary);
    });
  }
  test('application payload remains lazy and retains original byte spans', () {
    final bytes = codec.serialize(
      Call(
        1,
        'com.payload',
        arguments: [
          Uint8List.fromList([0, 255]),
          DateTime.utc(2026, 10, 3),
          {7: 'non-string application key'},
        ],
        argumentsKeywords: {'name': 'example'},
      ),
    );
    final message = readWampFlatBufferMessage(bytes) as Call;
    expect(message.hasLazyArguments, isTrue);
    expect(message.hasLazyArgumentsKeywords, isTrue);
    expect(message.toLazyPayload().anchor, same(message));
    final fields = readWampFlatBufferFrame(bytes).fields;
    expect(
      message.debugEncodedArgumentsBytes!.offsetInBytes,
      (fields['args'] as Uint8List).offsetInBytes,
    );
    expect(message.arguments![0], isA<Uint8List>());
    expect(message.arguments![0], [0, 255]);
    expect(message.arguments![1], DateTime.utc(2026, 10, 3));
    expect(message.arguments![2], {7: 'non-string application key'});
    expect(message.argumentsKeywords, {'name': 'example'});
  });
  test('absent and empty application values remain different', () {
    final absent =
        readWampFlatBufferMessage(codec.serialize(Call(1, 'com.proc'))) as Call;
    final empty =
        readWampFlatBufferMessage(
              codec.serialize(
                Call(1, 'com.proc', arguments: [], argumentsKeywords: {}),
              ),
            )
            as Call;
    expect(absent.arguments, isNull);
    expect(absent.argumentsKeywords, isNull);
    expect(empty.hasLazyArguments, isTrue);
    expect(empty.hasLazyArgumentsKeywords, isTrue);
    expect(empty.arguments, isEmpty);
    expect(empty.argumentsKeywords, isEmpty);
  });

  test(
    'retain unknown roles/features and null/absent known feature values',
    () {
      final dictionary = <String, Object?>{
        'roles': {
          'caller': {
            '_role_flag': true,
            'features': {'call_timeout': null, '_future_feature': true},
          },
          '_future_role': {
            'features': {'_future_feature': true},
          },
        },
        'authid': null,
      };
      final message =
          readWampFlatBufferMessage(
                frameWithDictionary('Hello', {'realm': 'realm'}, dictionary, 1),
              )
              as Hello;
      final decoded = readWampFlatBufferFrame(codec.serialize(message));
      expect(decoded.dictionary, dictionary);
    },
  );
  test('retain null progress and unknown mode options', () {
    final dictionary = <String, Object?>{'progress': null, '_future': true};
    final message = readWampFlatBufferMessage(
      frameWithDictionary('Yield', {'request': 1}, dictionary, 25),
    );
    expect(
      readWampFlatBufferFrame(codec.serialize(message)).dictionary,
      dictionary,
    );
  });

  test('typed field mutation preserves unknown siblings', () {
    final original = <String, Object?>{
      'roles': {
        'caller': {
          'features': {
            'call_timeout': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.caller!.features!.callTimeout = true;
    final expected = {
      'roles': {
        'caller': {
          'features': {
            'call_timeout': true,
            '_future': true,
          },
        },
      },
    };
    expect(
      readWampFlatBufferFrame(codec.serialize(message)).dictionary,
      expected,
    );
    // A later write still compares against the original baseline.
    expect(
      readWampFlatBufferFrame(codec.serialize(message)).dictionary,
      expected,
    );
  });
  test('explicit default mutation replaces retained null with false', () {
    final original = <String, Object?>{
      'roles': {
        'caller': {
          'features': {
            'call_timeout': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.caller!.features!.callTimeout = false;
    final expected = {
      'roles': {
        'caller': {
          'features': {
            'call_timeout': false,
            '_future': true,
          },
        },
      },
    };
    expect(
      readWampFlatBufferFrame(codec.serialize(message)).dictionary,
      expected,
    );
  });

  test('explicit false replaces null: caller.caller_identification', () {
    final original = <String, Object?>{
      'roles': {
        'caller': {
          'features': {
            'caller_identification': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.caller!.features!.callerIdentification = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'caller': {
          'features': {'caller_identification': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: caller.call_timeout', () {
    final original = <String, Object?>{
      'roles': {
        'caller': {
          'features': {
            'call_timeout': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.caller!.features!.callTimeout = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'caller': {
          'features': {'call_timeout': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: caller.call_canceling', () {
    final original = <String, Object?>{
      'roles': {
        'caller': {
          'features': {
            'call_canceling': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.caller!.features!.callCanceling = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'caller': {
          'features': {'call_canceling': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: caller.progressive_call_invocations', () {
    final original = <String, Object?>{
      'roles': {
        'caller': {
          'features': {
            'progressive_call_invocations': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.caller!.features!.progressiveCallInvocations = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'caller': {
          'features': {'progressive_call_invocations': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: caller.progressive_call_results', () {
    final original = <String, Object?>{
      'roles': {
        'caller': {
          'features': {
            'progressive_call_results': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.caller!.features!.progressiveCallResults = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'caller': {
          'features': {'progressive_call_results': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: caller.payload_passthru_mode', () {
    final original = <String, Object?>{
      'roles': {
        'caller': {
          'features': {
            'payload_passthru_mode': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.caller!.features!.payloadPassThruMode = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'caller': {
          'features': {'payload_passthru_mode': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.caller_identification', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'caller_identification': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.callerIdentification = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'caller_identification': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.call_trustlevels', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'call_trustlevels': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.callTrustlevels = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'call_trustlevels': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.pattern_based_registration', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'pattern_based_registration': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.patternBasedRegistration = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'pattern_based_registration': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.shared_registration', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'shared_registration': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.sharedRegistration = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'shared_registration': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.call_timeout', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'call_timeout': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.callTimeout = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'call_timeout': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.call_canceling', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'call_canceling': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.callCanceling = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'call_canceling': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.progressive_call_invocations', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'progressive_call_invocations': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.progressiveCallInvocations = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'progressive_call_invocations': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.progressive_call_results', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'progressive_call_results': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.progressiveCallResults = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'progressive_call_results': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: callee.payload_passthru_mode', () {
    final original = <String, Object?>{
      'roles': {
        'callee': {
          'features': {
            'payload_passthru_mode': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.callee!.features!.payloadPassThruMode = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'callee': {
          'features': {'payload_passthru_mode': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: publisher.publisher_identification', () {
    final original = <String, Object?>{
      'roles': {
        'publisher': {
          'features': {
            'publisher_identification': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.publisher!.features!.publisherIdentification = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'publisher': {
          'features': {'publisher_identification': false, '_future': true},
        },
      },
    });
  });
  test(
    'explicit false replaces null: publisher.subscriber_blackwhite_listing',
    () {
      final original = <String, Object?>{
        'roles': {
          'publisher': {
            'features': {
              'subscriber_blackwhite_listing': null,
              '_future': true,
            },
          },
        },
      };
      final message =
          readWampFlatBufferMessage(
                frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
              )
              as Hello;
      message.details.roles!.publisher!.features!.subscriberBlackWhiteListing =
          false;
      expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
        'roles': {
          'publisher': {
            'features': {
              'subscriber_blackwhite_listing': false,
              '_future': true,
            },
          },
        },
      });
    },
  );
  test('explicit false replaces null: publisher.publisher_exclusion', () {
    final original = <String, Object?>{
      'roles': {
        'publisher': {
          'features': {
            'publisher_exclusion': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.publisher!.features!.publisherExclusion = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'publisher': {
          'features': {'publisher_exclusion': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: publisher.payload_passthru_mode', () {
    final original = <String, Object?>{
      'roles': {
        'publisher': {
          'features': {
            'payload_passthru_mode': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.publisher!.features!.payloadPassThruMode = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'publisher': {
          'features': {'payload_passthru_mode': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: subscriber.publisher_identification', () {
    final original = <String, Object?>{
      'roles': {
        'subscriber': {
          'features': {
            'publisher_identification': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.subscriber!.features!.publisherIdentification =
        false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'subscriber': {
          'features': {'publisher_identification': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: subscriber.publication_trustlevels', () {
    final original = <String, Object?>{
      'roles': {
        'subscriber': {
          'features': {
            'publication_trustlevels': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.subscriber!.features!.publicationTrustLevels = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'subscriber': {
          'features': {'publication_trustlevels': false, '_future': true},
        },
      },
    });
  });
  test(
    'explicit false replaces null: subscriber.pattern_based_subscription',
    () {
      final original = <String, Object?>{
        'roles': {
          'subscriber': {
            'features': {
              'pattern_based_subscription': null,
              '_future': true,
            },
          },
        },
      };
      final message =
          readWampFlatBufferMessage(
                frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
              )
              as Hello;
      message.details.roles!.subscriber!.features!.patternBasedSubscription =
          false;
      expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
        'roles': {
          'subscriber': {
            'features': {'pattern_based_subscription': false, '_future': true},
          },
        },
      });
    },
  );
  test('explicit false replaces null: subscriber.subscription_revocation', () {
    final original = <String, Object?>{
      'roles': {
        'subscriber': {
          'features': {
            'subscription_revocation': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.subscriber!.features!.subscriptionRevocation = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'subscriber': {
          'features': {'subscription_revocation': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: subscriber.payload_passthru_mode', () {
    final original = <String, Object?>{
      'roles': {
        'subscriber': {
          'features': {
            'payload_passthru_mode': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.subscriber!.features!.payloadPassThruMode = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'subscriber': {
          'features': {'payload_passthru_mode': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: subscriber.call_timeout', () {
    final original = <String, Object?>{
      'roles': {
        'subscriber': {
          'features': {
            'call_timeout': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.subscriber!.features!.callTimeout = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'subscriber': {
          'features': {'call_timeout': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: subscriber.call_canceling', () {
    final original = <String, Object?>{
      'roles': {
        'subscriber': {
          'features': {
            'call_canceling': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.subscriber!.features!.callCanceling = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'subscriber': {
          'features': {'call_canceling': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: subscriber.progressive_call_results', () {
    final original = <String, Object?>{
      'roles': {
        'subscriber': {
          'features': {
            'progressive_call_results': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.subscriber!.features!.progressiveCallResults = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'subscriber': {
          'features': {'progressive_call_results': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.caller_identification', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'caller_identification': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.callerIdentification = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'caller_identification': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.call_trustlevels', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'call_trustlevels': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.callTrustLevels = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'call_trustlevels': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.pattern_based_registration', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'pattern_based_registration': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.patternBasedRegistration = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'pattern_based_registration': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.registration_meta_api', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'registration_meta_api': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.registrationMetaApi = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'registration_meta_api': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.shared_registration', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'shared_registration': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.sharedRegistration = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'shared_registration': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.session_meta_api', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'session_meta_api': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.sessionMetaApi = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'session_meta_api': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.call_timeout', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'call_timeout': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.callTimeout = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'call_timeout': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.call_canceling', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'call_canceling': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.callCanceling = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'call_canceling': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.progressive_call_invocations', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'progressive_call_invocations': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.progressiveCallInvocations = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'progressive_call_invocations': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.progressive_call_results', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'progressive_call_results': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.progressiveCallResults = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'progressive_call_results': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: dealer.payload_passthru_mode', () {
    final original = <String, Object?>{
      'roles': {
        'dealer': {
          'features': {
            'payload_passthru_mode': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.dealer!.features!.payloadPassThruMode = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'dealer': {
          'features': {'payload_passthru_mode': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: broker.publisher_identification', () {
    final original = <String, Object?>{
      'roles': {
        'broker': {
          'features': {
            'publisher_identification': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.broker!.features!.publisherIdentification = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'broker': {
          'features': {'publisher_identification': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: broker.publication_trustlevels', () {
    final original = <String, Object?>{
      'roles': {
        'broker': {
          'features': {
            'publication_trustlevels': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.broker!.features!.publicationTrustLevels = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'broker': {
          'features': {'publication_trustlevels': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: broker.pattern_based_subscription', () {
    final original = <String, Object?>{
      'roles': {
        'broker': {
          'features': {
            'pattern_based_subscription': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.broker!.features!.patternBasedSubscription = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'broker': {
          'features': {'pattern_based_subscription': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: broker.subscription_meta_api', () {
    final original = <String, Object?>{
      'roles': {
        'broker': {
          'features': {
            'subscription_meta_api': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.broker!.features!.subscriptionMetaApi = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'broker': {
          'features': {'subscription_meta_api': false, '_future': true},
        },
      },
    });
  });
  test(
    'explicit false replaces null: broker.subscriber_blackwhite_listing',
    () {
      final original = <String, Object?>{
        'roles': {
          'broker': {
            'features': {
              'subscriber_blackwhite_listing': null,
              '_future': true,
            },
          },
        },
      };
      final message =
          readWampFlatBufferMessage(
                frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
              )
              as Hello;
      message.details.roles!.broker!.features!.subscriberBlackWhiteListing =
          false;
      expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
        'roles': {
          'broker': {
            'features': {
              'subscriber_blackwhite_listing': false,
              '_future': true,
            },
          },
        },
      });
    },
  );
  test('explicit false replaces null: broker.session_meta_api', () {
    final original = <String, Object?>{
      'roles': {
        'broker': {
          'features': {
            'session_meta_api': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.broker!.features!.sessionMetaApi = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'broker': {
          'features': {'session_meta_api': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: broker.publisher_exclusion', () {
    final original = <String, Object?>{
      'roles': {
        'broker': {
          'features': {
            'publisher_exclusion': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.broker!.features!.publisherExclusion = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'broker': {
          'features': {'publisher_exclusion': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: broker.event_history', () {
    final original = <String, Object?>{
      'roles': {
        'broker': {
          'features': {
            'event_history': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.broker!.features!.eventHistory = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'broker': {
          'features': {'event_history': false, '_future': true},
        },
      },
    });
  });
  test('explicit false replaces null: broker.payload_passthru_mode', () {
    final original = <String, Object?>{
      'roles': {
        'broker': {
          'features': {
            'payload_passthru_mode': null,
            '_future': true,
          },
        },
      },
    };
    final message =
        readWampFlatBufferMessage(
              frameWithDictionary('Hello', {'realm': 'realm'}, original, 1),
            )
            as Hello;
    message.details.roles!.broker!.features!.payloadPassThruMode = false;
    expect(readWampFlatBufferFrame(codec.serialize(message)).dictionary, {
      'roles': {
        'broker': {
          'features': {'payload_passthru_mode': false, '_future': true},
        },
      },
    });
  });
}
