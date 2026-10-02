import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:core' as core;
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'valid payload assertion evaluates once and preserves nullable identity',
    () {
      final value = <Object>[];
      var calls = 0;
      expect(
        _validPayload(() {
          calls++;
          return value;
        }),
        same(value),
      );
      expect(calls, 1);
      expect(_validPayload<Object?>(() => null), isNull);
    },
  );

  for (final error in <Object>[
    const FormatException('invalid payload'),
    ArgumentError('invalid byte'),
    StateError('missing decoder'),
    TypeError(),
    NoSuchMethodError.withInvocation(null, core.Invocation.method(#decode, [])),
    WampE2eeProviderUnavailableException(
      'unpack',
      options: PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
    ),
    WampE2eeInvalidPayloadException(
      'unpack',
      options: PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor'),
    ),
  ]) {
    test('valid payload assertion reports ${error.runtimeType}', () {
      var calls = 0;
      expect(
        () => _validPayload<void>(() {
          calls++;
          throw error;
        }),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            contains('Valid payload operation must succeed'),
          ),
        ),
      );
      expect(calls, 1);
    });
  }

  for (final error in <Object>[
    TimeoutException('deadline'),
    UnsupportedError('unavailable infrastructure'),
    const StackOverflowError(),
    const OutOfMemoryError(),
    TestFailure('an existing assertion'),
    Object(),
  ]) {
    test('valid payload assertion does not credit ${error.runtimeType}', () {
      expect(
        () => _validPayload<void>(() => throw error),
        throwsA(same(error)),
      );
    });
  }

  test('plain lazy views preserve values without assuming PPT', () {
    final args = <dynamic>['body'];
    final kwargs = <String, dynamic>{'worker': 7};
    final payload = LazyMessagePayload.materialized(
      arguments: args,
      argumentsKeywords: kwargs,
    );
    final decoded = _validPayload(() => decodeLazyPayloadView(payload));
    expect(decoded.arguments, same(args));
    expect(decoded.argumentsKeywords, same(kwargs));
    expect(_validPayload(() => unwrapLazyPayloadView(payload)), same(payload));
  });

  test('packed forwarding never decodes already packed or boundary bytes', () {
    var calls = 0;
    final packed = LazyMessagePayload.packed(
      encoding: LazyPayloadEncoding.cbor,
      pptDecoded: false,
      packedPayloadBytes: Uint8List.fromList([0, 255]),
      packedPayloadDecoder: (_) {
        calls++;
        return (arguments: ['decoded'], argumentsKeywords: null);
      },
    );
    expect(
      _validPayload(
        () => unwrapLazyPayloadView(packed, pptScheme: 'x_contract'),
      ),
      same(packed),
    );
    expect(calls, 0);
    for (final bytes in <List<dynamic>>[
      <int>[0, 255],
      <dynamic>[0, 255],
    ]) {
      final view = _validPayload(
        () => unwrapLazyPayloadView(
          LazyMessagePayload.materialized(arguments: [bytes]),
          pptScheme: 'x_contract',
          pptSerializer: 'cbor',
        ),
      );
      expect(view.hasPackedPayloadBytes, isTrue);
      expect(view.packedPayloadBytes, [0, 255]);
      bytes[0] = 17;
      expect(view.packedPayloadBytes, [0, 255]);
    }
    expect(calls, 0);
  });

  test(
    'outer keywords keep binary arguments plain instead of unpacking PPT',
    () {
      final args = <dynamic>[
        Uint8List.fromList([0, 255]),
      ];
      final kwargs = <String, dynamic>{'plain': true};
      final message = Publish(
        1,
        'app.data',
        arguments: args,
        argumentsKeywords: kwargs,
      );
      for (var access = 0; access < 2; access++) {
        _validPayload(
          () => message.ensureDecodedPayloadView(
            pptScheme: 'x_contract',
            pptSerializer: 'cbor',
            pptCipher: null,
            pptKeyId: null,
          ),
        );
        expect(message.arguments, same(args));
        expect(message.argumentsKeywords, same(kwargs));
        expect(message.wireArguments, same(args));
        expect(message.wireArgumentsKeywords, same(kwargs));
        expect(message.hasDecodedPptPayload, isTrue);
      }
    },
  );

  for (final positional in [false, true]) {
    for (final keywords in [false, true]) {
      for (final wireFirst in [false, true]) {
        test(
          'message decode cache args=$positional kw=$keywords wire=$wireFirst',
          () {
            var argsCalls = 0;
            var kwargsCalls = 0;
            final message = Publish(1, 'app.data');
            _validPayload(
              () => message.setLazyPayload(
                argumentsBytes: positional ? Uint8List.fromList([7]) : null,
                argumentsKeywordsBytes: keywords
                    ? Uint8List.fromList([9])
                    : null,
                argumentsDecoder: (bytes) {
                  argsCalls++;
                  expect(bytes, [7]);
                  return ['value', bytes.single];
                },
                argumentsKeywordsDecoder: (bytes) {
                  kwargsCalls++;
                  expect(bytes, [9]);
                  return {'count': bytes.single};
                },
                encoding: LazyPayloadEncoding.json,
              ),
            );
            expect(argsCalls, 0);
            expect(kwargsCalls, 0);
            final expectedArgs = positional ? ['value', 7] : null;
            final expectedKwargs = keywords ? {'count': 9} : null;
            if (wireFirst) {
              expect(_validPayload(() => message.wireArguments), expectedArgs);
              expect(
                _validPayload(() => message.wireArgumentsKeywords),
                expectedKwargs,
              );
            }
            for (var read = 0; read < 2; read++) {
              expect(_validPayload(() => message.arguments), expectedArgs);
              expect(
                _validPayload(() => message.argumentsKeywords),
                expectedKwargs,
              );
              expect(_validPayload(() => message.wireArguments), expectedArgs);
              expect(
                _validPayload(() => message.wireArgumentsKeywords),
                expectedKwargs,
              );
            }
            expect(argsCalls, positional ? 1 : 0);
            expect(kwargsCalls, keywords ? 1 : 0);
            expect(message.hasLazyArguments, positional);
            expect(message.hasLazyArgumentsKeywords, keywords);
          },
        );
      }
    }
  }

  test(
    'new lazy views decode their own values rather than a modified cache',
    () {
      final message = Publish(1, 'app.data');
      message.setLazyPayload(
        argumentsBytes: Uint8List.fromList([4]),
        argumentsKeywordsBytes: Uint8List.fromList([5]),
        argumentsDecoder: (bytes) => [bytes.single],
        argumentsKeywordsDecoder: (bytes) => {'value': bytes.single},
      );
      final args = _validPayload(() => message.arguments);
      final kwargs = _validPayload(() => message.argumentsKeywords);
      expect(args, [4]);
      expect(kwargs, {'value': 5});
      args![0] = 'changed';
      kwargs!['value'] = 'changed';
      final view = _validPayload(message.toLazyPayload);
      expect(_validPayload(() => view.arguments), [4]);
      expect(_validPayload(() => view.argumentsKeywords), {'value': 5});
      expect(message.arguments, same(args));
      expect(message.argumentsKeywords, same(kwargs));
    },
  );

  for (final empty in [false, true]) {
    test(
      'packed view decodes once across fields and owned copies empty=$empty',
      () {
        var calls = 0;
        final bytes = Uint8List.fromList([1]);
        final payload = LazyMessagePayload.packed(
          encoding: LazyPayloadEncoding.cbor,
          packedPayloadBytes: bytes,
          packedPayloadDecoder: (input) {
            calls++;
            expect(input, [1]);
            return (
              arguments: empty ? null : ['body'],
              argumentsKeywords: empty ? null : {'worker': 7},
            );
          },
        );
        final owned = _validPayload(payload.toOwned);
        expect(calls, 0);
        expect(owned.packedPayloadBytes, isNot(same(bytes)));
        bytes[0] = 2;
        expect(owned.packedPayloadBytes, [1]);
        for (var read = 0; read < 2; read++) {
          expect(
            _validPayload(() => owned.argumentsKeywords),
            empty ? null : {'worker': 7},
          );
          expect(_validPayload(() => owned.arguments), empty ? null : ['body']);
        }
        final cached = _validPayload(owned.toOwned);
        expect(_validPayload(() => cached.arguments), empty ? null : ['body']);
        expect(
          _validPayload(() => cached.argumentsKeywords),
          empty ? null : {'worker': 7},
        );
        expect(calls, 1);
      },
    );
  }

  test(
    'owned materialized copy preserves aliases but detaches all byte types',
    () {
      final bytes = Uint8List.fromList([0, 255]);
      final opaque = Object();
      final nested = <dynamic, dynamic>{7: bytes, 'opaque': opaque};
      final source = Publish(
        1,
        'app.data',
        arguments: [nested, bytes],
        argumentsKeywords: {'nested': nested, 'bytes': bytes},
      )..transparentBinaryPayload = bytes;
      final target = Publish(2, 'app.copy');
      _validPayload(() => source.copyPayloadTo(target));
      final view = _validPayload(() => source.toLazyPayload().toOwned());
      expect(
        target.transparentBinaryPayload,
        isNot(same(view.transparentBinaryPayload)),
      );
      bytes[0] = 9;
      nested[8] = 'changed';
      for (final copy in [target.toLazyPayload(), view]) {
        final args = _validPayload(() => copy.arguments);
        final kwargs = _validPayload(() => copy.argumentsKeywords);
        expect(args, hasLength(2));
        expect(kwargs, containsPair('bytes', [0, 255]));
        expect(args!.first, {
          7: [0, 255],
          'opaque': same(opaque),
        });
        expect(args[1], same(kwargs!['bytes']));
        expect(args.first, same(kwargs['nested']));
        expect(copy.transparentBinaryPayload, same(args[1]));
        expect(copy.transparentBinaryPayload, isNot(same(bytes)));
      }
    },
  );

  for (final positional in [false, true]) {
    test('copy mixes encoded and materialized fields args=$positional', () {
      final bytes = Uint8List.fromList(
        utf8.encode(positional ? '["encoded"]' : '{"encoded":1}'),
      );
      var calls = 0;
      final source = Publish(
        1,
        'app.data',
        arguments: ['materialized'],
        argumentsKeywords: {'materialized': 2},
      );
      source.setLazyPayload(
        argumentsBytes: positional ? bytes : null,
        argumentsKeywordsBytes: positional ? null : bytes,
        argumentsDecoder: (value) {
          calls++;
          return jsonDecode(utf8.decode(value)) as List<dynamic>;
        },
        argumentsKeywordsDecoder: (value) {
          calls++;
          return jsonDecode(utf8.decode(value)) as Map<String, dynamic>;
        },
        encoding: LazyPayloadEncoding.json,
      );
      final target = Publish(2, 'app.copy');
      _validPayload(() => source.copyPayloadTo(target));
      expect(calls, 0);
      bytes.fillRange(0, bytes.length, 0);
      expect(
        _validPayload(() => target.arguments),
        positional ? ['encoded'] : ['materialized'],
      );
      expect(
        _validPayload(() => target.argumentsKeywords),
        positional ? {'materialized': 2} : {'encoded': 1},
      );
      expect(calls, 1);
      expect(target.lazyPayloadEncoding, LazyPayloadEncoding.json);
    });
  }

  for (final serializer in ['json', 'msgpack', 'cbor']) {
    for (final binaryKind in ['typed', 'int', 'dynamic']) {
      test(
        'custom PPT $serializer/$binaryKind survives restore and forwarding',
        () {
          final options = PublishOptions(
            pptScheme: 'x_contract',
            pptSerializer: serializer,
          );
          final packed = PPTPayload.packPPTPayload(
            ['body'],
            {'worker': 7},
            options,
          );
          final bytes = packed.single as List<int>;
          final Object binary = switch (binaryKind) {
            'typed' => Uint8List.fromList(bytes),
            'int' => List<int>.of(bytes),
            _ => List<dynamic>.of(bytes),
          };
          final lazy = _validPayload(
            () => unwrapLazyPayloadView(
              LazyMessagePayload.materialized(arguments: [binary]),
              pptScheme: options.pptScheme,
              pptSerializer: options.pptSerializer,
            ),
          );
          expect(lazy.hasPackedPayloadBytes, isTrue);
          expect(lazy.packedPayloadBytes, bytes);
          final message = Publish(1, 'app.data', options: options);
          _validPayload(() => message.restoreLazyPayload(lazy));
          expect(_validPayload(() => message.wireArguments), [bytes]);
          _validPayload(
            () => message.ensureDecodedPayloadView(
              pptScheme: options.pptScheme,
              pptSerializer: options.pptSerializer,
              pptCipher: options.pptCipher,
              pptKeyId: options.pptKeyId,
            ),
          );
          expect(_validPayload(() => message.arguments), ['body']);
          expect(_validPayload(() => message.argumentsKeywords), {'worker': 7});
          expect(
            _validPayload(() => message.toLazyPayload().packedPayloadBytes),
            bytes,
          );
          final decoded = _validPayload(() => decodeLazyPayloadView(lazy));
          expect(decoded.arguments, ['body']);
          expect(decoded.argumentsKeywords, {'worker': 7});
        },
      );
    }
  }

  test(
    'map-form custom PPT restores plain fields with implicit serializer',
    () {
      final decoded = _validPayload(
        () => unwrapLazyPayloadView(
          LazyMessagePayload.materialized(
            arguments: [
              {
                'args': ['body'],
                'kwargs': {'worker': 7},
              },
            ],
          ),
          pptScheme: 'x_contract',
        ),
      );
      expect(decoded.arguments, ['body']);
      expect(decoded.argumentsKeywords, {'worker': 7});
    },
  );

  test('encrypted lazy envelope uses its provider and retains ciphertext', () {
    final provider = WampCborXsalsa20Poly1305Provider.single(
      keyId: 'key',
      key: Uint8List.fromList(List.generate(32, (i) => i)),
    );
    final options = PublishOptions(pptScheme: 'wamp', pptSerializer: 'cbor');
    final ciphertext = provider.packPayload(
      ['private'],
      {'worker': 7},
      options,
    );
    final message = Publish(1, 'app.data', options: options);
    final lazy = LazyMessagePayload.materialized(
      arguments: ciphertext,
      e2eeProvider: provider,
    );
    _validPayload(() => message.restoreLazyPayload(lazy));
    expect(message.e2eeProvider, same(provider));
    _validPayload(
      () => message.ensureDecodedPayloadView(
        pptScheme: options.pptScheme,
        pptSerializer: options.pptSerializer,
        pptCipher: options.pptCipher,
        pptKeyId: options.pptKeyId,
      ),
    );
    expect(_validPayload(() => message.arguments), ['private']);
    expect(_validPayload(() => message.argumentsKeywords), {'worker': 7});
    expect(_validPayload(() => message.wireArguments), ciphertext);
    final decoded = _validPayload(
      () => decodeLazyPayloadView(
        lazy,
        pptScheme: options.pptScheme,
        pptSerializer: options.pptSerializer,
        pptCipher: options.pptCipher,
        pptKeyId: options.pptKeyId,
      ),
    );
    expect(decoded.arguments, ['private']);
    expect(decoded.argumentsKeywords, {'worker': 7});
  });
}

// Only known synchronous payload-contract failures become success assertions.
// Process failures, timeouts, resource exhaustion and unknown errors stay raw.
T _validPayload<T>(T Function() operation) {
  try {
    return operation();
  } on FormatException catch (error) {
    fail('Valid payload operation must succeed: $error');
  } on ArgumentError catch (error) {
    fail('Valid payload operation must succeed: $error');
  } on StateError catch (error) {
    fail('Valid payload operation must succeed: $error');
  } on TypeError catch (error) {
    fail('Valid payload operation must succeed: $error');
  } on NoSuchMethodError catch (error) {
    fail('Valid payload operation must succeed: $error');
  } on WampE2eeProviderUnavailableException catch (error) {
    fail('Valid payload operation must succeed: $error');
  } on WampE2eeInvalidPayloadException catch (error) {
    fail('Valid payload operation must succeed: $error');
  }
}
