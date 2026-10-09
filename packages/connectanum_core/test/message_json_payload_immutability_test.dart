import 'dart:typed_data';
import 'dart:convert';
import 'dart:isolate';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' as json;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flat;
import 'package:test/test.dart';

void main() {
  final messages = <String, AbstractMessageWithPayload Function()>{
    'CALL': () => Call(7, 'com.immutable'),
    'INVOCATION': () => Invocation(7, 8, InvocationDetails(null, null, null)),
    'YIELD': () => Yield(7),
    'RESULT': () => Result(7, ResultDetails()),
    'PUBLISH': () => Publish(7, 'com.immutable'),
    'EVENT': () => Event(7, 8, EventDetails()),
    'ERROR': () => Error(MessageTypes.codeCall, 7, {}, 'com.failure'),
  };
  for (final entry in messages.entries) {
    for (final asString in [false, true]) {
      test(
        'JSON ${entry.key} string=$asString consumes shared transfer once',
        () {
          final bytes = Uint8List.fromList([0, 255]);
          final transferred = TransferableTypedData.fromList([bytes]);
          final shared = <String, Object?>{'binary': transferred};
          final arguments = <Object?>[shared, shared];
          final keywords = <String, Object?>{'shared': shared};
          final message = entry.value()
            ..arguments = arguments
            ..argumentsKeywords = keywords;
          final codec = json.Serializer();
          final wire = asString
              ? codec.serializeToString(message)
              : utf8.decode(
                  (codec.serializeFragments(message) ??
                          [
                            Uint8List.fromList(
                              utf8.encode(codec.serializeToString(message)),
                            ),
                          ])
                      .expand((part) => part)
                      .toList(),
                );
          final decoded =
              codec.deserializeFromString(wire) as AbstractMessageWithPayload;
          expect(decoded.arguments, [
            {'binary': bytes},
            {'binary': bytes},
          ]);
          expect(decoded.argumentsKeywords, {
            'shared': {'binary': bytes},
          });
          expect(message.arguments, same(arguments));
          expect(message.argumentsKeywords, same(keywords));
          expect(arguments.first, same(shared));
          expect(shared['binary'], same(transferred));
          // The transfer is one-shot; aliases in this serialization share its
          // encoded value, without replacing entries in caller-owned containers.
          expect(transferred.materialize, throwsArgumentError);
        },
        testOn: 'vm',
      );
      test(
        'JSON ${entry.key} string=$asString leaves typed payload inputs reusable',
        () {
          final bytes = Uint8List.fromList([0, 1, 127, 255]);
          final sliced = Uint8List.sublistView(
            Uint8List.fromList([9, 2, 3, 9]),
            1,
            3,
          );
          final arguments = <Uint8List>[bytes, sliced];
          final keywords = <String, Uint8List>{'binary': bytes};
          final message = entry.value()
            ..arguments = arguments
            ..argumentsKeywords = keywords;
          final codec = json.Serializer();
          final decoded =
              (asString
                      ? codec.deserializeFromString(
                          codec.serializeToString(message),
                        )
                      : codec.deserialize(
                          Uint8List.fromList(
                            (codec.serializeFragments(message) ??
                                    [
                                      Uint8List.fromList(
                                        utf8.encode(
                                          codec.serializeToString(message),
                                        ),
                                      ),
                                    ])
                                .expand((part) => part)
                                .toList(),
                          ),
                        ))
                  as AbstractMessageWithPayload;
          expect(message.arguments, same(arguments));
          expect(message.argumentsKeywords, same(keywords));
          expect(arguments.first, same(bytes));
          expect(arguments.last, same(sliced));
          expect(keywords['binary'], same(bytes));
          expect(bytes, [0, 1, 127, 255]);
          expect(sliced, [2, 3]);
          expect(decoded.arguments, [bytes, sliced]);
          expect(decoded.argumentsKeywords, {'binary': bytes});
          final binaryCodec = flat.Serializer();
          final binaryDecoded =
              binaryCodec.deserialize(binaryCodec.serialize(message))
                  as AbstractMessageWithPayload;
          expect(binaryDecoded.arguments, [bytes, sliced]);
          expect(binaryDecoded.argumentsKeywords, {'binary': bytes});
        },
      );
    }
  }
  test('JSON encoding preserves immutable nested payload containers', () {
    final bytes = Uint8List.fromList([0, 255]);
    final nested = Map<String, Object?>.unmodifiable({'bytes': bytes});
    final arguments = List<Object?>.unmodifiable([nested, bytes]);
    final keywords = Map<String, Object?>.unmodifiable({'nested': arguments});
    final message = Call(
      7,
      'com.immutable',
      arguments: arguments,
      argumentsKeywords: keywords,
    );
    final codec = json.Serializer();
    final decoded =
        codec.deserializeFromString(codec.serializeToString(message)) as Call;
    expect(message.arguments, same(arguments));
    expect(message.argumentsKeywords, same(keywords));
    expect(nested['bytes'], same(bytes));
    expect(decoded.arguments, arguments);
    expect(decoded.argumentsKeywords, keywords);
  });
}
