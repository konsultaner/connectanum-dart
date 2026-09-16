import 'dart:collection';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  for (final hasCustom in [false, true]) {
    test('event views preserve metadata and anchors custom=$hasCustom', () {
      final event = Event(
        17,
        29,
        EventDetails(
          publisher: 31,
          trustlevel: 2,
          topic: 'com.example.events',
          custom: hasCustom ? {'trace': 'test-trace'} : null,
        ),
        arguments: ['body'],
        argumentsKeywords: {'worker': 7},
      );
      final anchor = Object();
      final eager = event.toPayload();
      final lazy = event.toLazyEventPayload(anchor: anchor);
      expect(lazy.payload.anchor, same(anchor));
      expect(event.toLazyEventPayload().payload.anchor, same(event));
      for (final view in [eager, lazy.toPayload()]) {
        expect(view.subscriptionId, 17);
        expect(view.publicationId, 29);
        expect(view.publisher, 31);
        expect(view.trustlevel, 2);
        expect(view.topic, 'com.example.events');
        expect(
          view.customDetails,
          hasCustom ? {'trace': 'test-trace'} : isNull,
        );
        expect(view.arguments, ['body']);
        expect(view.argumentsKeywords, {'worker': 7});
      }
    });
  }

  for (final args in <List<dynamic>?>[
    null,
    [],
    ['body'],
  ]) {
    for (final kwargs in <Map<String, dynamic>?>[
      null,
      {},
      {'worker': 7},
    ]) {
      test('eventFromPayload preserves absent/empty fields $args $kwargs', () {
        final custom = <String, dynamic>{'trace': 'test-trace'};
        final EventPayload payload = (
          subscriptionId: 17,
          publicationId: 29,
          publisher: 31,
          trustlevel: 2,
          topic: 'com.example.events',
          pptScheme: null,
          pptSerializer: null,
          pptCipher: null,
          pptKeyId: null,
          customDetails: custom,
          arguments: args,
          argumentsKeywords: kwargs,
        );
        late Event event;
        expect(() => event = eventFromPayload(payload), returnsNormally);
        expect(event.subscriptionId, 17);
        expect(event.publicationId, 29);
        expect(event.details.publisher, 31);
        expect(event.details.trustlevel, 2);
        expect(event.details.topic, 'com.example.events');
        expect(event.details.custom, {'trace': 'test-trace'});
        expect(event.arguments, args);
        expect(event.argumentsKeywords, kwargs);
        expect(event.details.custom, isNot(same(custom)));
        event.details.custom['trace'] = 'changed';
        expect(custom, {'trace': 'test-trace'});
        if (args != null) {
          expect(event.arguments, isNot(same(args)));
          event.arguments!.add('changed');
          expect(args, isNot(contains('changed')));
        }
        if (kwargs != null) {
          expect(event.argumentsKeywords, isNot(same(kwargs)));
          event.argumentsKeywords!['changed'] = true;
          expect(kwargs, isNot(contains('changed')));
        }
      });
    }
  }

  for (final encoding in LazyPayloadEncoding.values) {
    for (final alreadyDecoded in [false, true]) {
      for (final keywordsFirst in [false, true]) {
        test(
          'lazy event access stays independent $encoding '
          'decoded=$alreadyDecoded keywordsFirst=$keywordsFirst',
          () {
            final calls = <String>[];
            final argsBytes = Uint8List.fromList([1]);
            final kwargsBytes = Uint8List.fromList([2]);
            final event = LazyEventPayload(
              subscriptionId: 1,
              publicationId: 2,
              pptScheme: alreadyDecoded ? 'wamp' : null,
              payload: alreadyDecoded
                  ? LazyMessagePayload.materialized(
                      encoding: encoding,
                      pptDecoded: true,
                      arguments: ['body'],
                      argumentsKeywords: {'worker': 7},
                    )
                  : LazyMessagePayload.encoded(
                      encoding: encoding,
                      argumentsBytes: argsBytes,
                      argumentsKeywordsBytes: kwargsBytes,
                      argumentsDecoder: (_) {
                        calls.add('arguments');
                        return ['body'];
                      },
                      argumentsKeywordsDecoder: (_) {
                        calls.add('keywords');
                        return {'worker': 7};
                      },
                    ),
            );
            for (var read = 0; read < 2; read++) {
              if (keywordsFirst) {
                expect(event.argumentsKeywords, {'worker': 7});
              } else {
                expect(event.arguments, ['body']);
              }
              expect(
                calls,
                alreadyDecoded
                    ? isEmpty
                    : [keywordsFirst ? 'keywords' : 'arguments'],
              );
            }
            final full = event.toPayload();
            expect(full.arguments, ['body']);
            expect(full.argumentsKeywords, {'worker': 7});
            expect(event.arguments, ['body']);
            expect(event.argumentsKeywords, {'worker': 7});
            expect(
              calls,
              alreadyDecoded
                  ? isEmpty
                  : keywordsFirst
                  ? ['keywords', 'arguments']
                  : ['arguments', 'keywords'],
            );
            expect(
              event.argumentsBytes,
              alreadyDecoded ? isNull : same(argsBytes),
            );
            expect(
              event.argumentsKeywordsBytes,
              alreadyDecoded ? isNull : same(kwargsBytes),
            );
          },
        );
      }
    }
  }

  test('lazy event packed payload retains one shared decode', () {
    final calls = <String>[];
    final event = LazyEventPayload(
      subscriptionId: 1,
      publicationId: 2,
      payload: LazyMessagePayload.packed(
        encoding: LazyPayloadEncoding.cbor,
        packedPayloadBytes: Uint8List.fromList([1]),
        packedPayloadDecoder: (_) {
          calls.add('packed');
          return (arguments: ['body'], argumentsKeywords: {'worker': 7});
        },
      ),
    );
    expect(event.argumentsKeywords, {'worker': 7});
    expect(event.arguments, ['body']);
    expect(event.toPayload().argumentsKeywords, {'worker': 7});
    expect(calls, ['packed']);
  });

  for (final malformedArguments in [false, true]) {
    test(
      'lazy event defers unrelated invalid field args=$malformedArguments',
      () {
        final event = LazyEventPayload(
          subscriptionId: 1,
          publicationId: 2,
          payload: LazyMessagePayload.encoded(
            argumentsBytes: Uint8List.fromList([1]),
            argumentsKeywordsBytes: Uint8List.fromList([2]),
            argumentsDecoder: (_) {
              if (malformedArguments) {
                throw const FormatException('bad args');
              }
              return ['body'];
            },
            argumentsKeywordsDecoder: (_) {
              if (!malformedArguments) {
                throw const FormatException('bad kwargs');
              }
              return {'worker': 7};
            },
          ),
        );
        if (malformedArguments) {
          expect(event.argumentsKeywords, {'worker': 7});
          expect(() => event.arguments, throwsFormatException);
        } else {
          expect(event.arguments, ['body']);
          expect(() => event.argumentsKeywords, throwsFormatException);
        }
        expect(event.toPayload, throwsFormatException);
      },
    );
  }

  for (final runtimeAllowed in [false, true]) {
    test('lazy event E2EE access unwraps once runtime=$runtimeAllowed', () {
      final provider = _RuntimeProbe(runtimeAllowed);
      final calls = <String>[];
      final event = LazyEventPayload(
        subscriptionId: 1,
        publicationId: 2,
        pptScheme: 'wamp',
        pptSerializer: 'cbor',
        pptCipher: 'test-cipher',
        pptKeyId: 'test-key',
        payload: LazyMessagePayload.encoded(
          encoding: LazyPayloadEncoding.cbor,
          argumentsBytes: Uint8List.fromList([1]),
          argumentsDecoder: (_) {
            calls.add('arguments');
            return ['outer'];
          },
          e2eeProvider: provider,
          e2eeRuntimeContext: _context,
        ),
      );
      expect(event.argumentsKeywords, {'decoded': true});
      expect(event.arguments, ['from-provider']);
      expect(event.toPayload().argumentsKeywords, {'decoded': true});
      expect(provider.unpackCalls, 1);
      expect(calls, runtimeAllowed ? isEmpty : ['arguments']);
      expect(provider.lastContext, same(_context));
    });
  }

  test('lazy event custom PPT access still unwraps the shared envelope', () {
    final options = EventDetails(
      pptScheme: 'x_custom',
      pptSerializer: 'cbor',
    );
    final packed = PPTPayload.packPPTPayload(['body'], {'worker': 7}, options);
    final calls = <String>[];
    final event = LazyEventPayload(
      subscriptionId: 1,
      publicationId: 2,
      pptScheme: options.pptScheme,
      pptSerializer: options.pptSerializer,
      payload: LazyMessagePayload.encoded(
        argumentsBytes: Uint8List.fromList([1]),
        argumentsDecoder: (_) {
          calls.add('arguments');
          return packed;
        },
      ),
    );
    expect(event.argumentsKeywords, {'worker': 7});
    expect(event.arguments, ['body']);
    expect(event.toPayload().argumentsKeywords, {'worker': 7});
    expect(calls, ['arguments']);
  });

  test(
    'owned encoded views copy slices and preserve partially decoded state',
    () {
      final source = Uint8List.fromList([99, 1, 2, 3, 88]);
      final argsBytes = Uint8List.sublistView(source, 1, 3);
      final kwargsBytes = Uint8List.sublistView(source, 3, 4);
      final provider = _provider();
      var argsCalls = 0;
      var kwargsCalls = 0;
      final payload = LazyMessagePayload.encoded(
        transparentBinaryPayload: Uint8List.fromList([7]),
        encoding: LazyPayloadEncoding.cbor,
        argumentsBytes: argsBytes,
        argumentsKeywordsBytes: kwargsBytes,
        argumentsDecoder: (bytes) {
          argsCalls++;
          return [bytes.first];
        },
        argumentsKeywordsDecoder: (bytes) {
          kwargsCalls++;
          return {'value': bytes.first};
        },
        e2eeProvider: provider,
        e2eeRuntimeContext: _context,
        anchor: Object(),
      );
      expect(payload.arguments, [1]);
      final owned = payload.toOwned();
      expect(argsCalls, 1);
      expect(kwargsCalls, 0);
      source.fillRange(0, source.length, 0);
      payload.transparentBinaryPayload![0] = 0;
      payload.arguments![0] = 'changed';
      expect(owned.argumentsBytes, [1, 2]);
      expect(owned.argumentsKeywordsBytes, [3]);
      expect(owned.transparentBinaryPayload, [7]);
      expect(owned.arguments, [1]);
      expect(owned.argumentsKeywords, {'value': 3});
      expect(owned.argumentsKeywords, {'value': 3});
      expect(argsCalls, 1);
      expect(kwargsCalls, 1);
      expect(owned.encoding, LazyPayloadEncoding.cbor);
      expect(owned.pptDecoded, isFalse);
      expect(owned.e2eeProvider, same(provider));
      expect(owned.e2eeRuntimeContext, same(_context));
      expect(owned.anchor, isNull);
    },
  );

  test('owned packed views stay lazy and detach their wire bytes', () {
    var calls = 0;
    final bytes = Uint8List.fromList([1, 2]);
    final payload = LazyMessagePayload.packed(
      encoding: LazyPayloadEncoding.messagePack,
      packedPayloadBytes: bytes,
      packedPayloadDecoder: (bytes) {
        calls++;
        return (
          arguments: [bytes.first],
          argumentsKeywords: {'last': bytes.last},
        );
      },
    );
    final owned = payload.toOwned();
    expect(calls, 0);
    bytes[0] = 9;
    expect(owned.packedPayloadBytes, [1, 2]);
    expect(owned.pptDecoded, isTrue);
    expect(owned.argumentsKeywords, {'last': 2});
    expect(owned.arguments, [1]);
    expect(calls, 1);
    final cached = owned.toOwned();
    owned.arguments!.add('changed');
    owned.argumentsKeywords!['last'] = 9;
    expect(cached.arguments, [1]);
    expect(cached.argumentsKeywords, {'last': 2});
    expect(calls, 1);
  });

  test('metadata copies retain lazy fields without invoking decoders', () {
    var calls = 0;
    final provider = _provider();
    final anchor = Object();
    final bytes = Uint8List.fromList([1]);
    final payload = LazyMessagePayload.encoded(
      transparentBinaryPayload: bytes,
      encoding: LazyPayloadEncoding.json,
      argumentsBytes: bytes,
      argumentsKeywordsBytes: bytes,
      argumentsDecoder: (_) {
        calls++;
        return ['args'];
      },
      argumentsKeywordsDecoder: (_) {
        calls++;
        return {'kw': true};
      },
      e2eeProvider: provider,
      e2eeRuntimeContext: _context,
      anchor: anchor,
    );
    expect(payload.withE2eeProvider(provider), same(payload));
    expect(payload.withE2eeRuntimeContext(_context), same(payload));
    final copies = [
      payload.withAnchor(null),
      payload.withE2eeProvider(null),
      payload.withE2eeRuntimeContext(null),
    ];
    expect(calls, 0);
    expect(copies[0].anchor, isNull);
    expect(copies[1].e2eeProvider, isNull);
    expect(copies[2].e2eeRuntimeContext, isNull);
    expect(copies[1].anchor, same(anchor));
    expect(copies[2].e2eeProvider, same(provider));
    for (final copy in copies) {
      expect(copy.encoding, LazyPayloadEncoding.json);
      expect(copy.pptDecoded, isFalse);
      expect(copy.transparentBinaryPayload, same(bytes));
      expect(copy.argumentsBytes, same(bytes));
      expect(copy.argumentsKeywordsBytes, same(bytes));
      expect(copy.arguments, ['args']);
      expect(copy.argumentsKeywords, {'kw': true});
    }
    expect(calls, 6);
  });

  test('owned deeply nested values and non-string map keys are retained', () {
    final leaf = <int, dynamic>{
      1: Uint8List.fromList([7]),
    };
    dynamic current = leaf;
    for (var index = 0; index < 10000; index++) {
      current = <dynamic>[current];
    }
    final opaque = Object();
    final payload = LazyMessagePayload.materialized(
      arguments: [current, opaque],
    );
    final owned = payload.toOwned();
    leaf[1][0] = 9;
    dynamic restored = owned.arguments!.first;
    for (var index = 0; index < 10000; index++) {
      restored = (restored as List).single;
    }
    expect(restored, {
      1: Uint8List.fromList([7]),
    });
    expect(owned.arguments![1], same(opaque));
  });

  test('owned materialized payload detaches nested containers and bytes', () {
    final bytes = Uint8List.fromList([1, 2]);
    final nested = <String, dynamic>{
      'items': <dynamic>[bytes],
    };
    final arguments = <dynamic>[nested, bytes];
    final keywords = <String, dynamic>{'bytes': bytes, 'nested': nested};
    final payload = LazyMessagePayload.materialized(
      arguments: arguments,
      argumentsKeywords: keywords,
      anchor: Object(),
    );
    final owned = payload.toOwned();
    bytes[0] = 9;
    (nested['items'] as List).add('changed');
    arguments.add('changed');
    keywords['changed'] = true;
    expect(owned.anchor, isNull);
    expect(owned.arguments, [
      {
        'items': [
          Uint8List.fromList([1, 2]),
        ],
      },
      Uint8List.fromList([1, 2]),
    ]);
    expect(owned.argumentsKeywords!.keys, unorderedEquals(['bytes', 'nested']));
    expect(owned.argumentsKeywords!['nested'], same(owned.arguments!.first));
    expect(owned.argumentsKeywords!['bytes'], same(owned.arguments![1]));
    expect(owned.arguments![1], isNot(same(bytes)));
  });

  test('owned copies preserve cyclic container identity without recursion', () {
    // Detect runaway copying before exercising the ordinary cyclic container,
    // whose synchronous loop cannot be interrupted by browser test timeouts.
    for (final bounded in [true, false]) {
      final arguments = <dynamic>[];
      final keywords = bounded ? _TraversalBudgetMap() : <String, dynamic>{};
      keywords['args'] = arguments;
      arguments.add(keywords);
      final owned = LazyMessagePayload.materialized(
        arguments: arguments,
        argumentsKeywords: keywords,
      ).toOwned();
      expect(owned.arguments, isNot(same(arguments)));
      expect(owned.argumentsKeywords, isNot(same(keywords)));
      expect(owned.arguments!.single, same(owned.argumentsKeywords));
      expect(owned.argumentsKeywords!['args'], same(owned.arguments));
    }
  });

  test('copyPayloadTo detaches transparent and nested materialized bytes', () {
    final bytes = Uint8List.fromList([1, 2]);
    final source = Publish(
      1,
      'app.event',
      arguments: [bytes],
      argumentsKeywords: {
        'nested': [bytes],
      },
    )..transparentBinaryPayload = bytes;
    final target = Publish(2, 'app.copy');
    source.copyPayloadTo(target);
    bytes[0] = 9;
    expect(target.transparentBinaryPayload, [1, 2]);
    expect(target.arguments!.single, [1, 2]);
    expect(target.argumentsKeywords!['nested'], [
      [1, 2],
    ]);
    expect(target.arguments!.single, same(target.transparentBinaryPayload));
  });

  test('an empty packed envelope is decoded only once', () {
    var calls = 0;
    final encoded = Uint8List.fromList([0xa0]);
    final payload = LazyMessagePayload.packed(
      encoding: LazyPayloadEncoding.cbor,
      packedPayloadBytes: encoded,
      packedPayloadDecoder: (_) {
        calls++;
        return (arguments: null, argumentsKeywords: null);
      },
    );
    expect(payload.arguments, isNull);
    expect(payload.argumentsKeywords, isNull);
    expect(payload.arguments, isNull);
    expect(payload.argumentsKeywords, isNull);
    expect(calls, 1);
    expect(payload.packedPayloadBytes, same(encoded));
    expect(payload.hasPackedPayloadBytes, isTrue);
    for (final clone in [
      payload.toOwned(),
      payload.withAnchor(Object()),
      payload.withE2eeProvider(_provider()),
      payload.withE2eeRuntimeContext(_context),
    ]) {
      expect(clone.arguments, isNull);
      expect(clone.argumentsKeywords, isNull);
    }
    expect(calls, 1);
  });

  test('a failed packed decode can be retried without caching failure', () {
    var calls = 0;
    final payload = LazyMessagePayload.packed(
      encoding: LazyPayloadEncoding.cbor,
      packedPayloadBytes: Uint8List.fromList([0xa0]),
      packedPayloadDecoder: (_) {
        if (++calls == 1) throw FormatException('transient fixture failure');
        return (arguments: null, argumentsKeywords: null);
      },
    );
    expect(() => payload.arguments, throwsFormatException);
    expect(calls, 1);
    expect(payload.argumentsKeywords, isNull);
    expect(payload.arguments, isNull);
    expect(calls, 2);
  });

  for (final delta in [-256, 256]) {
    for (final aes in [false, true]) {
      test('lazy E2EE rejects byte narrowing $delta with AES=$aes', () {
        final provider = _provider(aes: aes);
        final options = PublishOptions();
        final bytes =
            (provider.packPayload(['secret'], null, options).single
                    as Uint8List)
                .toList();
        bytes[0] += delta;
        final payload = LazyMessagePayload.materialized(
          arguments: [bytes],
          e2eeProvider: provider,
        );
        expect(
          () => unwrapLazyPayloadView(
            payload,
            pptScheme: 'wamp',
            pptSerializer: options.pptSerializer,
            pptCipher: options.pptCipher,
            pptKeyId: options.pptKeyId,
          ).arguments,
          throwsFormatException,
        );
      });
    }
  }

  for (final serializer in ['json', 'msgpack', 'cbor']) {
    test(
      'unwrap $serializer keeps packed bytes lazy and preserves metadata',
      () {
        final options = PublishOptions(
          pptScheme: 'x_custom',
          pptSerializer: serializer,
        );
        final packed = PPTPayload.packPPTPayload(
          ['hello'],
          {'count': 2},
          options,
        );
        final anchor = Object();
        final transparent = Uint8List.fromList([9]);
        final provider = _provider();
        final bytes = packed.single as List<int>;
        for (final binary in [
          Uint8List.fromList(bytes),
          List<int>.from(bytes),
          List<dynamic>.from(bytes),
        ]) {
          final unwrapped = unwrapLazyPayloadView(
            LazyMessagePayload.materialized(
              arguments: [binary],
              argumentsKeywords: {},
              transparentBinaryPayload: transparent,
              anchor: anchor,
            ),
            pptScheme: 'x_custom',
            pptSerializer: serializer,
            e2eeProvider: provider,
            runtimeContext: _context,
          );
          expect(unwrapped.hasPackedPayloadBytes, isTrue);
          expect(unwrapped.packedPayloadBytes, bytes);
          expect(
            unwrapped.encoding,
            {
              'json': LazyPayloadEncoding.json,
              'msgpack': LazyPayloadEncoding.messagePack,
              'cbor': LazyPayloadEncoding.cbor,
            }[serializer],
          );
          expect(unwrapped.anchor, same(anchor));
          expect(unwrapped.transparentBinaryPayload, same(transparent));
          expect(unwrapped.e2eeProvider, same(provider));
          expect(unwrapped.e2eeRuntimeContext, same(_context));
          expect(unwrapped.arguments, ['hello']);
          expect(unwrapped.argumentsKeywords, {'count': 2});
          final decoded = decodeLazyPayloadView(unwrapped);
          expect(decoded.arguments, ['hello']);
          expect(decoded.argumentsKeywords, {'count': 2});
        }
      },
    );
  }

  test(
    'map-form PPT and empty payloads preserve context during unwrapping',
    () {
      final anchor = Object();
      final provider = _provider();
      for (final args in [null, <dynamic>[]]) {
        final unwrapped = unwrapLazyPayloadView(
          LazyMessagePayload.materialized(arguments: args, anchor: anchor),
          pptScheme: 'x_custom',
          e2eeProvider: provider,
          runtimeContext: _context,
        );
        expect(unwrapped.arguments, isEmpty);
        expect(unwrapped.argumentsKeywords, isEmpty);
        expect(unwrapped.pptDecoded, isTrue);
        expect(unwrapped.anchor, same(anchor));
        expect(unwrapped.e2eeProvider, same(provider));
        expect(unwrapped.e2eeRuntimeContext, same(_context));
      }
      final unwrapped = unwrapLazyPayloadView(
        LazyMessagePayload.materialized(
          arguments: [
            {
              'args': ['map'],
              'kwargs': {'value': 4},
            },
          ],
          anchor: anchor,
        ),
        pptScheme: 'x_custom',
      );
      expect(unwrapped.arguments, ['map']);
      expect(unwrapped.argumentsKeywords, {'value': 4});
      expect(unwrapped.pptDecoded, isTrue);
      expect(unwrapped.hasPackedPayloadBytes, isFalse);
      expect(unwrapped.anchor, same(anchor));
    },
  );

  test(
    'an unwrapped message without a retained view preserves its metadata',
    () {
      final provider = _provider();
      final binary = Uint8List.fromList([7]);
      final message = Publish(
        1,
        'app.event',
        arguments: ['decoded'],
        argumentsKeywords: {'count': 3},
      )..transparentBinaryPayload = binary;
      message.attachE2eeProvider(provider);
      message.attachE2eeRuntimeContext(_context);
      message.markPptPayloadDecoded();
      final anchor = Object();
      for (final view in [
        message.toLazyPayload(),
        message.toLazyPayload(anchor: anchor),
      ]) {
        expect(view.arguments, ['decoded']);
        expect(view.argumentsKeywords, {'count': 3});
        expect(view.pptDecoded, isTrue);
        expect(view.transparentBinaryPayload, same(binary));
        expect(view.e2eeProvider, same(provider));
        expect(view.e2eeRuntimeContext, same(_context));
        expect(view.hasPackedPayloadBytes, isFalse);
        expect(view.hasEncodedArguments, isFalse);
        expect(view.hasEncodedArgumentsKeywords, isFalse);
      }
      expect(message.toLazyPayload().anchor, same(message));
      expect(message.toLazyPayload(anchor: anchor).anchor, same(anchor));
    },
  );

  test('wire-first decoding caches arguments and keywords independently', () {
    final message = Publish(1, 'app.event');
    expect(message.wireArguments, isNull);
    expect(message.wireArgumentsKeywords, isNull);
    var argsCalls = 0;
    var kwargsCalls = 0;
    final argsBytes = Uint8List.fromList([2]);
    final kwargsBytes = Uint8List.fromList([5]);
    message.setLazyPayload(
      argumentsBytes: argsBytes,
      argumentsKeywordsBytes: kwargsBytes,
      argumentsDecoder: (bytes) {
        argsCalls++;
        expect(bytes, same(argsBytes));
        return [bytes.single];
      },
      argumentsKeywordsDecoder: (bytes) {
        kwargsCalls++;
        expect(bytes, same(kwargsBytes));
        return {'count': bytes.single};
      },
      encoding: LazyPayloadEncoding.cbor,
    );
    expect(argsCalls, 0);
    expect(kwargsCalls, 0);
    expect(message.wireArguments, [2]);
    expect(message.wireArguments, [2]);
    expect(argsCalls, 1);
    expect(kwargsCalls, 0);
    expect(message.wireArgumentsKeywords, {'count': 5});
    expect(message.wireArgumentsKeywords, {'count': 5});
    expect(message.arguments, [2]);
    expect(message.argumentsKeywords, {'count': 5});
    expect(argsCalls, 1);
    expect(kwargsCalls, 1);
  });

  for (final encoded in [false, true]) {
    for (final runtimeAllowed in [false, true]) {
      for (final override in [false, true]) {
        test(
          'decode chooses provider/context and runtime payload '
          'encoded=$encoded allowed=$runtimeAllowed override=$override',
          () {
            final provider = _RuntimeProbe(runtimeAllowed);
            final unusedProvider = _RuntimeProbe(!runtimeAllowed);
            final context = _context.copyWith(uri: 'app.selected');
            var argsCalls = 0;
            var kwargsCalls = 0;
            final payload = LazyMessagePayload.encoded(
              argumentsBytes: encoded ? Uint8List.fromList([1]) : null,
              argumentsKeywordsBytes: encoded ? Uint8List.fromList([2]) : null,
              arguments: encoded ? null : ['outer'],
              argumentsKeywords: encoded ? null : {'outer': true},
              argumentsDecoder: (_) {
                argsCalls++;
                return ['outer'];
              },
              argumentsKeywordsDecoder: (_) {
                kwargsCalls++;
                return {'outer': true};
              },
              e2eeProvider: override ? unusedProvider : provider,
              e2eeRuntimeContext: override ? _context : context,
            );
            final decoded = decodeLazyPayloadView(
              payload,
              pptScheme: 'wamp',
              pptSerializer: 'cbor',
              pptCipher: 'test-cipher',
              pptKeyId: 'test-key',
              e2eeProvider: override ? provider : null,
              runtimeContext: override ? context : null,
            );
            expect(decoded.arguments, ['from-provider']);
            expect(decoded.argumentsKeywords, {'decoded': true});
            expect(provider.unpackCalls, 1);
            expect(unusedProvider.unpackCalls, 0);
            expect(provider.lastContext, same(context));
            expect(provider.probeContexts, encoded ? [context] : isEmpty);
            expect(
              provider.lastArguments,
              encoded && runtimeAllowed ? isNull : ['outer'],
            );
            expect(argsCalls, encoded && !runtimeAllowed ? 1 : 0);
            expect(kwargsCalls, encoded && !runtimeAllowed ? 1 : 0);
          },
        );
      }
    }
  }

  test('runtime capability cannot suppress plain non-PPT payload decoding', () {
    final provider = _RuntimeProbe(true);
    final payload = LazyMessagePayload.encoded(
      argumentsBytes: Uint8List.fromList([3]),
      argumentsKeywordsBytes: Uint8List.fromList([4]),
      argumentsDecoder: (bytes) => [bytes.single],
      argumentsKeywordsDecoder: (bytes) => {'value': bytes.single},
      e2eeProvider: provider,
      e2eeRuntimeContext: _context,
    );
    final decoded = decodeLazyPayloadView(payload);
    expect(decoded.arguments, [3]);
    expect(decoded.argumentsKeywords, {'value': 4});
    expect(provider.probeContexts, isEmpty);
    expect(provider.unpackCalls, 0);
  });

  test('packed forwarding accepts both byte boundaries without decoding', () {
    final bytes = <dynamic>[0, 255];
    final payload = unwrapLazyPayloadView(
      LazyMessagePayload.materialized(arguments: [bytes]),
      pptScheme: 'x_custom',
      pptSerializer: 'cbor',
    );
    expect(payload.hasPackedPayloadBytes, isTrue);
    expect(payload.packedPayloadBytes, [0, 255]);
    bytes[0] = 20;
    expect(payload.packedPayloadBytes, [0, 255]);
  });

  test('packed views do not re-unwrap even when pptDecoded is false', () {
    var calls = 0;
    final payload = LazyMessagePayload.packed(
      encoding: LazyPayloadEncoding.json,
      pptDecoded: false,
      packedPayloadBytes: Uint8List.fromList([0]),
      packedPayloadDecoder: (_) {
        calls++;
        return (arguments: ['decoded'], argumentsKeywords: null);
      },
    );
    final result = unwrapLazyPayloadView(payload, pptScheme: 'x_custom');
    expect(calls, 0);
    expect(result, same(payload));
    expect(result.packedPayloadBytes, [0]);
    expect(result.arguments, ['decoded']);
    expect(calls, 1);
  });

  test('outer keywords prevent packed-only forwarding optimization', () {
    final options = PublishOptions(
      pptScheme: 'x_custom',
      pptSerializer: 'cbor',
    );
    final packed = PPTPayload.packPPTPayload(
      ['content'],
      {'inner': 1},
      options,
    );
    final result = unwrapLazyPayloadView(
      LazyMessagePayload.materialized(
        arguments: packed,
        argumentsKeywords: {'outer': 2},
      ),
      pptScheme: 'x_custom',
      pptSerializer: 'cbor',
    );
    expect(result.hasPackedPayloadBytes, isFalse);
    expect(result.arguments, ['content']);
    expect(result.argumentsKeywords, {'inner': 1});
    expect(result.pptDecoded, isTrue);
  });

  test(
    'runtime unwrapping requires encoded data, not just a capable provider',
    () {
      final provider = _RuntimeProbe(true);
      final result = unwrapLazyPayloadView(
        LazyMessagePayload.materialized(
          arguments: ['outer'],
          e2eeProvider: provider,
          e2eeRuntimeContext: _context,
        ),
        pptScheme: 'wamp',
        pptSerializer: 'cbor',
        pptCipher: 'test-cipher',
        pptKeyId: 'test-key',
      );
      expect(result.arguments, ['from-provider']);
      expect(result.argumentsKeywords, {'decoded': true});
      expect(result.pptDecoded, isTrue);
      expect(provider.unpackCalls, 1);
      expect(provider.probeContexts, isEmpty);
      expect(provider.lastArguments, ['outer']);
    },
  );

  for (final positional in [false, true]) {
    test(
      'orphan encoded bytes are not exposed as lazy positional=$positional',
      () {
        final message = Publish(1, 'app.event');
        message.setLazyPayload(
          argumentsBytes: positional ? Uint8List.fromList([1]) : null,
          argumentsKeywordsBytes: positional ? null : Uint8List.fromList([2]),
          encoding: LazyPayloadEncoding.cbor,
        );
        final view = message.toLazyPayload();
        expect(view.argumentsBytes, isNull);
        expect(view.argumentsKeywordsBytes, isNull);
        expect(view.hasEncodedArguments, isFalse);
        expect(view.hasEncodedArgumentsKeywords, isFalse);
        expect(view.arguments, isNull);
        expect(view.argumentsKeywords, isNull);
        expect(view.encoding, LazyPayloadEncoding.cbor);
      },
    );
  }

  test('setting positional arguments alone clears the decoded PPT marker', () {
    final message = Publish(1, 'app.event')..markPptPayloadDecoded();
    message.arguments = ['new'];
    expect(message.hasDecodedPptPayload, isFalse);
    expect(message.toLazyPayload().pptDecoded, isFalse);
    expect(message.arguments, ['new']);
  });

  for (final restore in [false, true]) {
    test(
      'payload ${restore ? 'restore' : 'retention'} keeps current identity',
      () {
        final provider = _provider();
        final previousProvider = _provider(aes: true);
        final previousContext = _context.copyWith(uri: 'app.previous');
        final message = Publish(1, 'app.event');
        message.attachE2eeProvider(previousProvider);
        message.attachE2eeRuntimeContext(_context);
        final payload = LazyMessagePayload.materialized(
          arguments: ['incoming'],
          argumentsKeywords: {'incoming': true},
          e2eeProvider: provider,
          e2eeRuntimeContext: previousContext,
        );
        if (restore) {
          message.restoreLazyPayload(payload);
          expect(message.arguments, ['incoming']);
          expect(message.argumentsKeywords, {'incoming': true});
          expect(message.hasDecodedPptPayload, isFalse);
        } else {
          message.retainLazyPayload(payload);
          expect(message.arguments, isNull);
        }
        expect(message.e2eeProvider, same(provider));
        expect(message.e2eeRuntimeContext, same(_context));
        final view = message.toLazyPayload();
        expect(view.e2eeProvider, same(provider));
        expect(view.e2eeRuntimeContext, same(_context));
        expect(view.anchor, same(message));
      },
    );
  }

  test('new encoded views do not reuse previously decoded mutable values', () {
    final message = Publish(1, 'app.event');
    message.setLazyPayload(
      argumentsBytes: Uint8List.fromList([4]),
      argumentsKeywordsBytes: Uint8List.fromList([5]),
      argumentsDecoder: (bytes) => [bytes.single],
      argumentsKeywordsDecoder: (bytes) => {'value': bytes.single},
      encoding: LazyPayloadEncoding.json,
    );
    message.arguments![0] = 'modified';
    message.argumentsKeywords!['value'] = 'modified';
    final anchor = Object();
    final view = message.toLazyPayload(anchor: anchor);
    expect(view.anchor, same(anchor));
    expect(view.arguments, [4]);
    expect(view.argumentsKeywords, {'value': 5});
    expect(message.arguments, ['modified']);
    expect(message.argumentsKeywords, {'value': 'modified'});
  });

  for (final positional in [false, true]) {
    test(
      'incomplete lazy configuration retains values positional=$positional',
      () {
        final message = Publish(
          1,
          'app.event',
          arguments: ['existing'],
          argumentsKeywords: {'existing': 1},
        );
        message.setLazyPayload(
          argumentsBytes: positional ? Uint8List.fromList([1]) : null,
          argumentsKeywordsBytes: positional ? null : Uint8List.fromList([2]),
        );
        expect(message.arguments, ['existing']);
        expect(message.argumentsKeywords, {'existing': 1});
        expect(message.wireArguments, ['existing']);
        expect(message.wireArgumentsKeywords, {'existing': 1});
        expect(message.hasLazyArguments, isFalse);
        expect(message.hasLazyArgumentsKeywords, isFalse);
      },
    );
  }

  test('PPT decoding preserves plain keywords and does not unwrap twice', () {
    final plain = Publish(
      1,
      'app.event',
      arguments: [
        [0, 255],
      ],
      argumentsKeywords: {'plain': true},
    );
    plain.ensureDecodedPayloadView(
      pptScheme: 'x_custom',
      pptSerializer: 'cbor',
      pptCipher: null,
      pptKeyId: null,
    );
    expect(plain.arguments, [
      [0, 255],
    ]);
    expect(plain.argumentsKeywords, {'plain': true});
    expect(plain.hasDecodedPptPayload, isTrue);
    final options = PublishOptions(
      pptScheme: 'x_custom',
      pptSerializer: 'cbor',
    );
    final message = Publish(
      2,
      'app.event',
      arguments: PPTPayload.packPPTPayload(
        [
          [0, 255],
        ],
        null,
        options,
      ),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      expect(
        () => message.ensureDecodedPayloadView(
          pptScheme: 'x_custom',
          pptSerializer: 'cbor',
          pptCipher: null,
          pptKeyId: null,
        ),
        returnsNormally,
      );
      expect(message.hasDecodedPptPayload, isTrue);
      expect(message.arguments, [
        [0, 255],
      ]);
    }
    final unmarked = Publish(
      3,
      'app.event',
      arguments: [
        [0, 255],
      ],
    );
    unmarked.ensureDecodedPayloadView(
      pptScheme: null,
      pptSerializer: 'cbor',
      pptCipher: null,
      pptKeyId: null,
    );
    expect(unmarked.hasDecodedPptPayload, isFalse);
    expect(unmarked.arguments, [
      [0, 255],
    ]);
  });

  test('message metadata attachment and wire forwarding stay lazy', () {
    final provider = _provider();
    final bytes = Uint8List.fromList([3]);
    var calls = 0;
    final payload = LazyMessagePayload.encoded(
      encoding: LazyPayloadEncoding.cbor,
      argumentsBytes: bytes,
      argumentsKeywordsBytes: bytes,
      argumentsDecoder: (bytes) {
        calls++;
        return [bytes.first];
      },
      argumentsKeywordsDecoder: (bytes) {
        calls++;
        return {'value': bytes.first};
      },
    );
    final message = Publish(1, 'app.event', arguments: ['materialized']);
    message.retainLazyPayload(payload);
    message.attachE2eeProvider(provider);
    message.attachE2eeRuntimeContext(_context);
    message.markPptPayloadDecoded();
    final target = Publish(2, 'app.copy');
    message.copyPayloadTo(target);
    expect(calls, 0);
    bytes[0] = 9;
    expect(target.arguments, ['materialized']);
    expect(target.wireArguments, [3]);
    expect(target.wireArgumentsKeywords, {'value': 3});
    expect(target.e2eeProvider, same(provider));
    expect(target.e2eeRuntimeContext, same(_context));
    expect(target.hasDecodedPptPayload, isTrue);
    expect(target.lazyPayloadEncoding, LazyPayloadEncoding.cbor);
    final view = target.toLazyPayload();
    expect(view.anchor, same(target));
    final customAnchor = Object();
    expect(
      target.toLazyPayload(anchor: customAnchor).anchor,
      same(customAnchor),
    );
    expect(view.arguments, [3]);
    expect(calls, 2);
    target.attachE2eeProvider(null);
    target.attachE2eeRuntimeContext(null);
    expect(target.e2eeProvider, isNull);
    expect(target.e2eeRuntimeContext, isNull);
    expect(target.toLazyPayload().e2eeProvider, isNull);
  });

  test('base decoded flag is false even when setters are overridden', () {
    expect(_CustomSetterPublish().hasDecodedPptPayload, isFalse);
  });

  test('in-place PPT decoding preserves absent and empty argument shapes', () {
    for (final args in [null, <dynamic>[]]) {
      final message = Publish(1, 'app.event', arguments: args);
      expect(
        () => message.ensureDecodedPayloadView(
          pptScheme: 'x_custom',
          pptSerializer: 'cbor',
          pptCipher: null,
          pptKeyId: null,
        ),
        returnsNormally,
      );
      expect(message.arguments, same(args));
      expect(message.argumentsKeywords, isNull);
      expect(message.hasDecodedPptPayload, isTrue);
    }
  });

  for (final serializer in ['json', 'msgpack', 'cbor', null, 'x_map']) {
    test('in-place PPT decoding recognizes serializer $serializer', () {
      final options = PublishOptions(
        pptScheme: 'x_custom',
        pptSerializer: serializer,
      );
      final packed = PPTPayload.packPPTPayload(
        ['content'],
        {'value': 4},
        options,
      );
      final message = Publish(1, 'app.event', arguments: packed);
      expect(
        () => message.ensureDecodedPayloadView(
          pptScheme: 'x_custom',
          pptSerializer: serializer,
          pptCipher: null,
          pptKeyId: null,
        ),
        returnsNormally,
      );
      expect(message.arguments, ['content']);
      expect(message.argumentsKeywords, {'value': 4});
      expect(message.hasDecodedPptPayload, isTrue);
      expect(message.wireArguments, packed);
    });
  }

  test(
    'in-place PPT decoding leaves multi-argument application maps alone',
    () {
      final args = [
        {
          'args': ['not-an-envelope'],
        },
        'second-argument',
      ];
      final message = Publish(1, 'app.event', arguments: args);
      message.ensureDecodedPayloadView(
        pptScheme: 'x_custom',
        pptSerializer: null,
        pptCipher: null,
        pptKeyId: null,
      );
      expect(message.arguments, same(args));
      expect(message.argumentsKeywords, isNull);
      expect(message.hasDecodedPptPayload, isTrue);
    },
  );

  test(
    'in-place WAMP detection uses binary payload with implicit serializer',
    () {
      final provider = _provider();
      final options = PublishOptions(pptScheme: 'wamp');
      final packed = provider.packPayload(['secret'], {'value': 8}, options);
      final message = Publish(1, 'app.event', arguments: packed)
        ..attachE2eeProvider(provider);
      message.ensureDecodedPayloadView(
        pptScheme: 'wamp',
        pptSerializer: null,
        pptCipher: options.pptCipher,
        pptKeyId: options.pptKeyId,
      );
      expect(message.arguments, ['secret']);
      expect(message.argumentsKeywords, {'value': 8});
      expect(message.hasDecodedPptPayload, isTrue);
    },
  );

  test('typed integer lists keep binary identity for PPT detection', () {
    final bytes = <int>[];
    final payload = unwrapLazyPayloadView(
      LazyMessagePayload.materialized(arguments: [bytes]),
      pptScheme: 'x_custom',
      pptSerializer: 'json',
    );
    expect(payload.hasPackedPayloadBytes, isTrue);
    expect(payload.packedPayloadBytes, isEmpty);
  });

  for (final positional in [false, true]) {
    test(
      'copy restores mixed encoded/materialized payload positional=$positional',
      () {
        final bytes = Uint8List.fromList([4]);
        final source = Publish(
          1,
          'app.event',
          arguments: ['plain'],
          argumentsKeywords: {'plain': true},
        );
        source.setLazyPayload(
          argumentsBytes: positional ? bytes : null,
          argumentsDecoder: positional ? (bytes) => [bytes.first] : null,
          argumentsKeywordsBytes: positional ? null : bytes,
          argumentsKeywordsDecoder: positional
              ? null
              : (bytes) => {'value': bytes.first},
          encoding: LazyPayloadEncoding.json,
        );
        final target = Publish(2, 'app.copy');
        source.copyPayloadTo(target);
        final restored = Publish(3, 'app.restored');
        restored.restoreLazyPayload(target.toLazyPayload());
        bytes[0] = 9;
        expect(restored.hasLazyArguments, positional);
        expect(restored.hasLazyArgumentsKeywords, !positional);
        expect(restored.lazyPayloadEncoding, LazyPayloadEncoding.json);
        expect(restored.arguments, positional ? [4] : ['plain']);
        expect(
          restored.argumentsKeywords,
          positional ? {'plain': true} : {'value': 4},
        );
        expect(restored.debugEncodedArgumentsBytes, positional ? [4] : null);
        expect(
          restored.debugEncodedArgumentsKeywordsBytes,
          positional ? null : [4],
        );
      },
    );
  }

  test('setting application payload clears old lazy/PPT wire state', () {
    final message = Publish(1, 'app.event');
    message.restoreLazyPayload(
      LazyMessagePayload.materialized(
        arguments: ['old'],
        argumentsKeywords: {'old': true},
        encoding: LazyPayloadEncoding.cbor,
        pptDecoded: true,
      ),
    );
    expect(message.hasDecodedPptPayload, isTrue);
    message.arguments = ['new'];
    message.argumentsKeywords = {'new': true};
    expect(message.hasDecodedPptPayload, isFalse);
    expect(message.hasLazyArguments, isFalse);
    expect(message.hasLazyArgumentsKeywords, isFalse);
    expect(message.wireArguments, ['new']);
    expect(message.wireArgumentsKeywords, {'new': true});
    final view = message.toLazyPayload(anchor: 'owner');
    expect(view.anchor, 'owner');
    expect(view.arguments, ['new']);
    expect(view.argumentsKeywords, {'new': true});
  });
}

class _TraversalBudgetMap extends MapBase<String, dynamic> {
  final _values = <String, dynamic>{};
  int _traversals = 0;

  @override
  dynamic operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, dynamic value) => _values[key] = value;

  @override
  Iterable<String> get keys => _values.keys;

  @override
  void clear() => _values.clear();

  @override
  dynamic remove(Object? key) => _values.remove(key);

  @override
  void forEach(void Function(String, dynamic) action) {
    if (++_traversals > 16) {
      fail(
        'Cyclic payload was repeatedly traversed instead of preserving identity',
      );
    }
    _values.forEach(action);
  }
}

class _CustomSetterPublish extends Publish {
  _CustomSetterPublish() : super(1, 'app.event');

  @override
  set arguments(List<dynamic>? value) {}

  @override
  set argumentsKeywords(Map<String, dynamic>? value) {}
}

class _RuntimeProbe
    implements WampE2eeProvider, WampE2eeRuntimePayloadProvider {
  _RuntimeProbe(this.runtimeAllowed);

  final bool runtimeAllowed;
  final probeContexts = <WampE2eeRuntimeContext?>[];
  // An event log preserves every call and its inputs. Dart 3.13.1 dart2js
  // incorrectly folds scalar spy-field reads after indirect provider dispatch.
  final unpackEvents = <(List<dynamic>?, WampE2eeRuntimeContext?)>[];
  int get unpackCalls => unpackEvents.length;
  List<dynamic>? get lastArguments => unpackEvents.last.$1;
  WampE2eeRuntimeContext? get lastContext => unpackEvents.last.$2;

  @override
  bool canUnpackFromRuntimeContext(WampE2eeRuntimeContext? runtimeContext) {
    probeContexts.add(runtimeContext);
    return runtimeAllowed;
  }

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => throw UnsupportedError('unpacking-only test provider');

  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) {
    unpackEvents.add((arguments, runtimeContext));
    expect(options.verify(), isTrue);
    expect(options.pptScheme, 'wamp');
    expect(options.pptSerializer, 'cbor');
    expect(options.pptCipher, 'test-cipher');
    expect(options.pptKeyId, 'test-key');
    return (arguments: ['from-provider'], argumentsKeywords: {'decoded': true});
  }
}

const _context = WampE2eeRuntimeContext(
  direction: WampE2eeDirection.inbound,
  messageType: WampE2eeMessageType.invocation,
  realm: 'realm',
  uri: 'app.echo',
);

WampE2eeProvider _provider({bool aes = false}) {
  final key = Uint8List.fromList(List.generate(32, (index) => index));
  return aes
      ? WampCborAes256GcmProvider.single(keyId: 'key', key: key)
      : WampCborXsalsa20Poly1305Provider.single(keyId: 'key', key: key);
}
