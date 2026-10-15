import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart' hide Error;
import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_core/json_serializer.dart' as json_codec;
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

void main() {
  final factories =
      <String, AbstractMessageWithPayload Function(List<dynamic>?)>{
        'call': (args) => Call(
          7,
          'com.json.echo',
          options: CallOptions(
            pptScheme: 'x_bytes',
            pptSerializer: 'flatbuffers',
            custom: {'_trace': 'call'},
          ),
          arguments: args,
        ),
        'publish': (args) => Publish(
          7,
          'com.json.topic',
          options: PublishOptions(
            pptScheme: 'x_bytes',
            pptSerializer: 'flatbuffers',
            custom: {'_trace': 'publish'},
          ),
          arguments: args,
        ),
        'invocation': (args) => Invocation(
          7,
          11,
          InvocationDetails(
            null,
            'com.json.echo',
            false,
            'x_bytes',
            'flatbuffers',
          ),
          arguments: args,
        ),
        'event': (args) => Event(
          7,
          11,
          EventDetails(
            pptScheme: 'x_bytes',
            pptSerializer: 'flatbuffers',
            custom: {'_trace': 'event'},
          ),
          arguments: args,
        ),
        'result': (args) => Result(
          7,
          ResultDetails(
            progress: true,
            pptScheme: 'x_bytes',
            pptSerializer: 'flatbuffers',
            custom: {'_trace': 'result'},
          ),
          arguments: args,
        ),
        'yield': (args) => core.Yield(
          7,
          options: YieldOptions(
            progress: true,
            pptScheme: 'x_bytes',
            pptSerializer: 'flatbuffers',
            custom: {'_trace': 'yield'},
          ),
          arguments: args,
        ),
        'error': (args) => core.Error(
          MessageTypes.codeInvocation,
          7,
          {
            'ppt_scheme': 'x_bytes',
            'ppt_serializer': 'flatbuffers',
            '_trace': 'error',
          },
          'com.json.error',
          arguments: args,
        ),
      };
  for (final entry in factories.entries) {
    for (final size in [0, 4096]) {
      test('JSON transcode wraps ${entry.key} opaque span size=$size', () {
        final storage = Uint8List(size + 7);
        for (var i = 0; i < size; i++) {
          storage[i + 3] = i % 251;
        }
        final body = Uint8List.sublistView(
          storage,
          3,
          size + 3,
        ).asUnmodifiableView();
        final message = entry.value(null)..transparentBinaryPayload = body;
        final expected = json_codec.Serializer().serializeToString(
          entry.value([body]),
        );
        final actual = utf8.decode(
          encodeMessage(NativeMessageSerializer.json, message),
        );
        expect(actual, expected);
        final wire = jsonDecode(actual) as List;
        expect(wire.last, isA<List>());
        expect((wire.last as List), hasLength(1));
        expect(message.transparentBinaryPayload, same(body));
        expect(message.wireArguments, isNull);
        expect(message.wireArgumentsKeywords, isNull);
        final fragments = flatbuffers.Serializer().serializeFragments(message)!;
        expect(
          fragments.any((part) => identical(part, body)),
          isTrue,
          reason:
              'fan-out to another serializer keeps the original owner and representation',
        );
      });
    }
  }
}
