import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

void main() {
  final serializers = <_SerializerHarness>[
    _SerializerHarness(
      'json',
      json_serializer.Serializer(),
      (bytes) => jsonDecode(utf8.decode(bytes)),
      (value) => Uint8List.fromList(utf8.encode(jsonEncode(value))),
      LazyPayloadEncoding.json,
    ),
    _SerializerHarness(
      'msgpack',
      msgpack_serializer.Serializer(),
      msgpack.deserialize,
      msgpack.serialize,
      LazyPayloadEncoding.messagePack,
    ),
    _SerializerHarness(
      'cbor',
      cbor_serializer.Serializer(),
      (bytes) => cbor.cbor.decode(bytes).toObject(),
      (value) => Uint8List.fromList(cbor.cbor.encode(cbor.CborValue(value))),
      LazyPayloadEncoding.cbor,
    ),
  ];
  final metadataCases = <String, Map<String, String>>{
    'absent': {},
    'scheme only': {'ppt_scheme': 'wamp'},
    'serializer only': {'ppt_serializer': 'cbor'},
    'cipher only': {'ppt_cipher': 'xsalsa20poly1305'},
    'key only': {'ppt_keyid': 'consumer-key-1'},
    'escaped key': {'ppt_keyid': 'consumer"key\\line\n\u00e4'},
    'empty strings': {
      'ppt_scheme': '',
      'ppt_serializer': '',
      'ppt_cipher': '',
      'ppt_keyid': '',
    },
    'complete': {
      'ppt_scheme': 'wamp',
      'ppt_serializer': 'cbor',
      'ppt_cipher': 'xsalsa20poly1305',
      'ppt_keyid': 'consumer-key-1',
    },
  };

  for (final harness in serializers) {
    group('${harness.name} independent outbound wire metadata', () {
      for (final entry in metadataCases.entries) {
        for (final type in [
          'CALL',
          'PUBLISH',
          'YIELD',
          'RESULT',
          'EVENT',
          'INVOCATION',
        ]) {
          test('$type preserves ${entry.key} PPT metadata', () {
            final fixture = _payloadMessage(type, entry.value);
            expect(
              harness.decode(harness.serializer.serialize(fixture.message)),
              fixture.prefix,
            );
          });
        }
        for (final type in ['CALL', 'PUBLISH']) {
          test(
            '$type segmented output preserves ${entry.key} metadata and bytes',
            () {
              final fixture = _payloadMessage(type, entry.value);
              final arguments = harness.encodeValue(['body', null, 17]);
              final keywords = harness.encodeValue({'flag': false});
              fixture.message.setLazyPayload(
                argumentsBytes: arguments,
                argumentsDecoder: (_) =>
                    throw StateError('must retain argument bytes'),
                argumentsKeywordsBytes: keywords,
                argumentsKeywordsDecoder: (_) =>
                    throw StateError('must retain keyword bytes'),
                encoding: harness.encoding,
              );
              final expected = [
                ...fixture.prefix,
                ['body', null, 17],
                {'flag': false},
              ];
              final fragments = harness.serializer.serializeFragments(
                fixture.message,
              );
              expect(fragments, isNotNull);
              expect(fragments, contains(same(arguments)));
              expect(fragments, contains(same(keywords)));
              final bytes = BytesBuilder(copy: false);
              for (final fragment in fragments!) {
                bytes.add(fragment);
              }
              expect(harness.decode(bytes.takeBytes()), expected);
              expect(
                harness.decode(harness.serializer.serialize(fixture.message)),
                expected,
              );
            },
          );
        }
      }

      for (final type in ['CALL', 'PUBLISH']) {
        for (final encodedArguments in [false, true]) {
          for (final materializedOther in [false, true]) {
            test(
              '$type mixed segments args=$encodedArguments other=$materializedOther',
              () {
                final fixture = _payloadMessage(type, {});
                final arguments = encodedArguments || materializedOther
                    ? <dynamic>['positional', false]
                    : null;
                final keywords = !encodedArguments || materializedOther
                    ? <String, dynamic>{'keyword': 73}
                    : null;
                fixture.message
                  ..arguments = arguments
                  ..argumentsKeywords = keywords;
                final retained = harness.encodeValue(
                  encodedArguments ? arguments : keywords,
                );
                fixture.message.setLazyPayload(
                  argumentsBytes: encodedArguments ? retained : null,
                  argumentsDecoder: encodedArguments
                      ? (_) => throw StateError('must retain argument bytes')
                      : null,
                  argumentsKeywordsBytes: encodedArguments ? null : retained,
                  argumentsKeywordsDecoder: encodedArguments
                      ? null
                      : (_) => throw StateError('must retain keyword bytes'),
                  encoding: harness.encoding,
                );
                final expected = [
                  ...fixture.prefix,
                  arguments ?? <Object?>[],
                  ?keywords,
                ];
                final fragments = harness.serializer.serializeFragments(
                  fixture.message,
                );
                expect(fragments, isNotNull);
                expect(fragments, contains(same(retained)));
                final bytes = BytesBuilder(copy: false);
                for (final fragment in fragments!) {
                  bytes.add(fragment);
                }
                expect(harness.decode(bytes.takeBytes()), expected);
                expect(
                  harness.decode(harness.serializer.serialize(fixture.message)),
                  expected,
                );
              },
            );
          }
        }

        for (final source in serializers.where((value) => value != harness)) {
          test(
            '$type transcodes lazy ${source.name} bytes rather than splicing them',
            () {
              final fixture = _payloadMessage(type, {});
              final arguments = <dynamic>['positional', false];
              final keywords = <String, dynamic>{'keyword': 73};
              fixture.message.setLazyPayload(
                argumentsBytes: source.encodeValue(arguments),
                argumentsDecoder: (_) => arguments,
                argumentsKeywordsBytes: source.encodeValue(keywords),
                argumentsKeywordsDecoder: (_) => keywords,
                encoding: source.encoding,
              );
              final fragments = harness.serializer.serializeFragments(
                fixture.message,
              );
              final Object? encoded;
              if (fragments == null) {
                encoded = harness.serializer.serialize(fixture.message);
              } else {
                final bytes = BytesBuilder(copy: false);
                for (final fragment in fragments) {
                  bytes.add(fragment);
                }
                encoded = bytes.takeBytes();
              }
              expect(() => harness.decode(encoded), returnsNormally);
              expect(harness.decode(encoded), [
                ...fixture.prefix,
                arguments,
                keywords,
              ]);
            },
          );
        }
      }

      for (final progress in <bool?>[null, false, true]) {
        test('YIELD preserves constructor progress=$progress', () {
          final options = YieldOptions(progress: progress);
          expect(
            harness.decode(
              harness.serializer.serialize(Yield(127, options: options)),
            ),
            [
              70,
              127,
              {'progress': progress ?? false},
            ],
          );
        });
        test(
          'RESULT keeps progress=$progress separate from custom metadata',
          () {
            final message = Result(
              123,
              ResultDetails(
                progress: progress,
                custom: {
                  'extension': {'flag': false},
                },
              ),
              arguments: [false],
            );
            expect(harness.decode(harness.serializer.serialize(message)), [
              50,
              123,
              {
                'progress': ?progress,
                'extension': {'flag': false},
              },
              [false],
            ]);
          },
        );
      }

      for (final (label, details, expected)
          in <(String, UnsubscribedDetails?, List<Object?>)>[
            ('absent', null, [35, 97]),
            ('empty', UnsubscribedDetails(null, null), [35, 97]),
            (
              'subscription',
              UnsubscribedDetails(41, null),
              [
                35,
                97,
                {'subscription': 41},
              ],
            ),
            (
              'reason',
              UnsubscribedDetails(null, 'com.example.revoked'),
              [
                35,
                97,
                {'reason': 'com.example.revoked'},
              ],
            ),
            (
              'both',
              UnsubscribedDetails(41, 'com.example.revoked'),
              [
                35,
                97,
                {'subscription': 41, 'reason': 'com.example.revoked'},
              ],
            ),
          ]) {
        test('UNSUBSCRIBED $label details have the correct frame shape', () {
          expect(
            harness.decode(
              harness.serializer.serialize(Unsubscribed(97, details)),
            ),
            expected,
          );
        });
      }

      for (final mode in <String?>[null, 'skip', 'kill', 'killnowait']) {
        test(
          'CANCEL and INTERRUPT preserve mode=$mode without null fields',
          () {
            final options = <String, Object?>{'mode': ?mode};
            expect(
              harness.decode(
                harness.serializer.serialize(
                  Cancel(131, options: CancelOptions()..mode = mode),
                ),
              ),
              [49, 131, options],
            );
            expect(
              harness.decode(
                harness.serializer.serialize(
                  Interrupt(139, options: InterruptOptions()..mode = mode),
                ),
              ),
              [69, 139, options],
            );
          },
        );
      }
      test('CANCEL and INTERRUPT without options use empty dictionaries', () {
        expect(harness.decode(harness.serializer.serialize(Cancel(131))), [
          49,
          131,
          {},
        ]);
        expect(harness.decode(harness.serializer.serialize(Interrupt(139))), [
          69,
          139,
          {},
        ]);
      });

      test(
        'UNSUBSCRIBED revocation keeps zero request ID and subscription ID',
        () {
          expect(
            harness.decode(
              harness.serializer.serialize(
                Unsubscribed(
                  0,
                  UnsubscribedDetails(41, 'wamp.error.authorization_failed'),
                ),
              ),
            ),
            [
              35,
              0,
              {'subscription': 41, 'reason': 'wamp.error.authorization_failed'},
            ],
          );
        },
      );
    });
  }
}

({AbstractMessageWithPayload message, List<Object?> prefix}) _payloadMessage(
  String type,
  Map<String, String> metadata,
) {
  final PPTOptions options;
  final AbstractMessageWithPayload message;
  final List<Object?> prefix;
  switch (type) {
    case 'CALL':
      final value = CallOptions();
      options = value;
      message = Call(17, 'com.example.procedure', options: value);
      prefix = [48, 17, metadata, 'com.example.procedure'];
    case 'PUBLISH':
      final value = PublishOptions();
      options = value;
      message = Publish(19, 'com.example.topic', options: value);
      prefix = [16, 19, metadata, 'com.example.topic'];
    case 'YIELD':
      final value = YieldOptions();
      options = value;
      message = Yield(23, options: value);
      prefix = [
        70,
        23,
        {'progress': false, ...metadata},
      ];
    case 'RESULT':
      final value = ResultDetails();
      options = value;
      message = Result(29, value);
      prefix = [50, 29, metadata];
    case 'EVENT':
      final value = EventDetails();
      options = value;
      message = Event(31, 37, value);
      prefix = [36, 31, 37, metadata];
    case 'INVOCATION':
      final value = InvocationDetails(null, null, null);
      options = value;
      message = Invocation(41, 43, value);
      prefix = [68, 41, 43, metadata];
    default:
      throw ArgumentError.value(type, 'type');
  }
  options
    ..pptScheme = metadata['ppt_scheme']
    ..pptSerializer = metadata['ppt_serializer']
    ..pptCipher = metadata['ppt_cipher']
    ..pptKeyId = metadata['ppt_keyid'];
  return (message: message, prefix: prefix);
}

class _SerializerHarness {
  const _SerializerHarness(
    this.name,
    this.serializer,
    this._decodeBytes,
    this.encodeValue,
    this.encoding,
  );

  final String name;
  final AbstractSerializer serializer;
  final Object? Function(Uint8List) _decodeBytes;
  final Uint8List Function(Object?) encodeValue;
  final LazyPayloadEncoding encoding;

  Object? decode(Object? value) => _decodeBytes(
    value is String
        ? Uint8List.fromList(utf8.encode(value))
        : value as Uint8List,
  );
}
