import 'dart:collection';
import 'dart:typed_data';

import 'package:connectanum/src/message/abort.dart';
import 'package:connectanum/src/message/authenticate.dart';
import 'package:connectanum/src/message/call.dart';
import 'package:connectanum/src/message/challenge.dart';
import 'package:connectanum/src/message/details.dart';
import 'package:connectanum/src/message/event.dart';
import 'package:connectanum/src/message/error.dart';
import 'package:connectanum/src/message/goodbye.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/message_types.dart';
import 'package:connectanum/src/message/publish.dart';
import 'package:connectanum/src/message/published.dart';
import 'package:connectanum/src/message/register.dart';
import 'package:connectanum/src/message/registered.dart';
import 'package:connectanum/src/message/result.dart';
import 'package:connectanum/src/message/subscribe.dart';
import 'package:connectanum/src/message/subscribed.dart';
import 'package:connectanum/src/message/unregister.dart';
import 'package:connectanum/src/message/unregistered.dart';
import 'package:connectanum/src/message/unsubscribe.dart';
import 'package:connectanum/src/message/unsubscribed.dart';
import 'package:connectanum/src/message/welcome.dart';
import 'package:connectanum/src/message/invocation.dart';
import 'package:connectanum/src/message/yield.dart';
import 'package:connectanum/msgpack.dart';
import 'package:test/test.dart';

void main() {
  var serializer = Serializer();
  group('serialize', () {
    test('Hello', () {
      expect(
          serializer.serialize(Hello('my.realm', Details.forHello())),
          equals(Uint8List.fromList([
            147, 1, 168, 109, 121, 46, 114, 101, 97, 108, //
            109, 145, 129, 165, 114, 111, 108, 101, 115, 132, //
            166, 99, 97, 108, 108, 101, 114, 129, 168, 102, //
            101, 97, 116, 117, 114, 101, 115, 133, 174, 99, //
            97, 108, 108, 95, 99, 97, 110, 99, 101, 108, //
            105, 110, 103, 194, 172, 99, 97, 108, 108, 95, //
            116, 105, 109, 101, 111, 117, 116, 194, 181, 99, //
            97, 108, 108, 101, 114, 95, 105, 100, 101, 110, //
            116, 105, 102, 105, 99, 97, 116, 105, 111, 110, //
            195, 180, 112, 97, 121, 108, 111, 97, 100, 95, //
            116, 114, 97, 110, 115, 112, 97, 114, 101, 110, //
            99, 121, 195, 184, 112, 114, 111, 103, 114, 101, //
            115, 115, 105, 118, 101, 95, 99, 97, 108, 108, //
            95, 114, 101, 115, 117, 108, 116, 115, 195, 166, //
            99, 97, 108, 108, 101, 101, 129, 168, 102, 101, //
            97, 116, 117, 114, 101, 115, 136, 181, 99, 97, //
            108, 108, 101, 114, 95, 105, 100, 101, 110, 116, //
            105, 102, 105, 99, 97, 116, 105, 111, 110, 195, //
            175, 99, 97, 108, 108, 95, 116, 114, 117, 115, //
            116, 108, 101, 118, 101, 108, 194, 186, 112, 97, //
            116, 116, 101, 114, 110, 95, 98, 97, 115, 101, //
            100, 95, 114, 101, 103, 105, 115, 116, 114, 97, //
            116, 105, 111, 110, 194, 179, 115, 104, 97, 114, //
            101, 100, 95, 114, 101, 103, 105, 115, 116, 114, //
            97, 116, 105, 111, 110, 194, 174, 99, 97, 108, //
            108, 95, 99, 97, 110, 99, 101, 108, 105, 110, //
            103, 194, 172, 99, 97, 108, 108, 95, 116, 105, //
            109, 101, 111, 117, 116, 194, 180, 112, 97, 121, //
            108, 111, 97, 100, 95, 116, 114, 97, 110, 115, //
            112, 97, 114, 101, 110, 99, 121, 195, 184, 112, //
            114, 111, 103, 114, 101, 115, 115, 105, 118, 101, //
            95, 99, 97, 108, 108, 95, 114, 101, 115, 117, //
            108, 116, 115, 195, 170, 115, 117, 98, 115, 99, //
            114, 105, 98, 101, 114, 129, 168, 102, 101, 97, //
            116, 117, 114, 101, 115, 133, 174, 99, 97, 108, //
            108, 95, 99, 97, 110, 99, 101, 108, 105, 110, //
            103, 194, 172, 99, 97, 108, 108, 95, 116, 105, //
            109, 101, 111, 117, 116, 194, 180, 112, 97, 121, //
            108, 111, 97, 100, 95, 116, 114, 97, 110, 115, //
            112, 97, 114, 101, 110, 99, 121, 195, 184, 112, //
            114, 111, 103, 114, 101, 115, 115, 105, 118, 101, //
            95, 99, 97, 108, 108, 95, 114, 101, 115, 117, //
            108, 116, 115, 194, 183, 115, 117, 98, 115, 99, //
            114, 105, 112, 116, 105, 111, 110, 95, 114, 101, //
            118, 111, 99, 97, 116, 105, 111, 110, 195, 169, //
            112, 117, 98, 108, 105, 115, 104, 101, 114, 129, //
            168, 102, 101, 97, 116, 117, 114, 101, 115, 132, //
            184, 112, 117, 98, 108, 105, 115, 104, 101, 114, //
            95, 105, 100, 101, 110, 116, 105, 102, 105, 99, //
            97, 116, 105, 111, 110, 195, 189, 115, 117, 98, //
            115, 99, 114, 105, 98, 101, 114, 95, 98, 108, //
            97, 99, 107, 119, 104, 105, 116, 101, 95, 108, //
            105, 115, 116, 105, 110, 103, 195, 179, 112, 117, //
            98, 108, 105, 115, 104, 101, 114, 95, 101, 120, //
            99, 108, 117, 115, 105, 111, 110, 195, 180, 112, //
            97, 121, 108, 111, 97, 100, 95, 116, 114, 97, //
            110, 115, 112, 97, 114, 101, 110, 99, 121, 195
          ])));
    });
    test('Hello with auth information', () {
      var authHello = Hello('my.realm', Details.forHello());
      authHello.details.authid = 'Richard';
      authHello.details.authmethods = ['WAMP-CRA'];
      authHello.details.authextra = HashMap();
      authHello.details.authextra['nonce'] = 'egVDf3DMJh0=';
      authHello.details.authextra['channel_binding'] = null;
      var message = serializer.serialize(authHello);
      expect(
          message,
          containsAllInOrder([
            147, 1, 168, 109, 121, 46, 114, 101, 97, 108, 109, 148, 129, //
            165, 114, 111, 108, 101, 115, 132, 166, 99, 97, 108, 108, 101, //
            114, 129, 168, 102, 101, 97, 116, 117, 114, 101, 115, 133, 174, //
            99, 97, 108, 108, 95, 99, 97, 110, 99, 101, 108, 105, 110, 103, //
            194, 172, 99, 97, 108, 108, 95, 116, 105, 109, 101, 111, 117, //
            116, 194, 181, 99, 97, 108, 108, 101, 114, 95, 105, 100, //
            101, 110, 116, 105, 102, 105, 99, 97, 116, 105, 111, 110, //
            195, 180, 112, 97, 121, 108, 111, 97, 100, 95, 116, 114, 97, 110, //
            115, 112, 97, 114, 101, 110, 99, 121, 195, 184, 112, 114, 111, //
            103, 114, 101, 115, 115, 105, 118, 101, 95, 99, 97, 108, 108, //
            95, 114, 101, 115, 117, 108, 116, 115, 195, 166, 99, 97, 108, //
            108, 101, 101, 129, 168, 102, 101, 97, 116, 117, 114, 101, 115, //
            136, 181, 99, 97, 108, 108, 101, 114, 95, 105, 100, 101, 110, //
            116, 105, 102, 105, 99, 97
          ]));
      expect(
          message,
          containsAllInOrder([
            175, 99, 104, 97, 110, 110, 101, 108, 95, 98, //
            105, 110, 100, 105, 110, 103, 192
          ]));
      expect(
          message,
          containsAllInOrder([
            165, 110, 111, 110, 99, 101, 172, 101, 103, 86, 68, //
            102, 51, 68, 77, 74, 104, 48, 61
          ]));
    });
    test('Authenticate', () {
      expect(serializer.serialize(Authenticate()),
          equals([147, MessageTypes.CODE_AUTHENTICATE, 160, 162, 123, 125]));
      expect(
          serializer.serialize(Authenticate.signature('someSignature')),
          equals(Uint8List.fromList([
            147, MessageTypes.CODE_AUTHENTICATE, 173, 115, 111, 109, 101, 83,
            105, 103, //
            110, 97, 116, 117, 114, 101, 162, 123, 125
          ])));
      var authenticate = Authenticate.signature('someSignature');
      authenticate.extra = HashMap<String, Object>();
      authenticate.extra['nonce'] = 'abc';
      expect(
          serializer.serialize(authenticate),
          equals(Uint8List.fromList([
            147, MessageTypes.CODE_AUTHENTICATE, 173, 115, 111, 109, 101, 83,
            105, 103, //
            110, 97, 116, 117, 114, 101, 129, 165, 110, 111, //
            110, 99, 101, 163, 97, 98, 99
          ])));
    });
    test('Register', () {
      expect(
          serializer.serialize(Register(25349185, 'com.myapp.myprocedure1')),
          equals(Uint8List.fromList([
            148, MessageTypes.CODE_REGISTER, 206, 1, 130, 204, 65, 128, 182,
            99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 112, 114, 111, 99, 101, 100, 117, 114, 101, //
            49
          ])));
      expect(
          serializer.serialize(Register(25349185, 'com.myapp.myprocedure1',
              options: RegisterOptions(
                  disclose_caller: true,
                  invoke: RegisterOptions.INVOCATION_POLICY_RANDOM,
                  match: RegisterOptions.MATCH_PREFIX))),
          equals(Uint8List.fromList([
            148, MessageTypes.CODE_REGISTER, 206, 1, 130, 204, 65, 131, 165, //
            109, 97, 116, 99, 104, 166, 112, 114, 101, 102, 105, //
            120, 175, 100, 105, 115, 99, 108, 111, 115, 101, //
            95, 99, 97, 108, 108, 101, 114, 195, 166, 105, //
            110, 118, 111, 107, 101, 166, 114, 97, 110, 100, //
            111, 109, 182, 99, 111, 109, 46, 109, 121, 97, //
            112, 112, 46, 109, 121, 112, 114, 111, 99, 101, //
            100, 117, 114, 101, 49
          ])));
      expect(
          serializer.serialize(Register(25349185, 'com.myapp.myprocedure2',
              options: RegisterOptions(disclose_caller: false))),
          equals(Uint8List.fromList([
            148, MessageTypes.CODE_REGISTER, 206, 1, 130, 204, 65, 129, 175, //
            100, 105, 115, 99, 108, 111, 115, 101, 95, 99, 97, //
            108, 108, 101, 114, 194, 182, 99, 111, 109, 46, //
            109, 121, 97, 112, 112, 46, 109, 121, 112, 114, //
            111, 99, 101, 100, 117, 114, 101, 50
          ])));
    });
    test('Unregister', () {
      expect(
          serializer.serialize(Unregister(25349185, 127981236)),
          equals(Uint8List.fromList([
            147, MessageTypes.CODE_UNREGISTER, 206, 1, 130, 204, 65, 206, 7, //
            160, 214, 180
          ])));
    });
    test('Call', () {
      expect(
          serializer.serialize(Call(7814135, 'com.myapp.ping')),
          equals(Uint8List.fromList([
            148, MessageTypes.CODE_CALL, 206, 0, 119, 59, 247, 128, 174, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 112, //
            105, 110, 103, 160
          ])));
      expect(
          serializer.serialize(
              Call(7814135, 'com.myapp.ping', options: CallOptions())),
          equals(Uint8List.fromList([
            148, MessageTypes.CODE_CALL, 206, 0, 119, 59, 247, 128, 174, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 112, //
            105, 110, 103, 160
          ])));
      expect(
          serializer.serialize(Call(7814135, 'com.myapp.ping',
              options: CallOptions(
                  receive_progress: true, disclose_me: true, timeout: 12))),
          equals(Uint8List.fromList([
            148, MessageTypes.CODE_CALL, 206, 0, 119, 59, 247, 131, 176, 114, //
            101, 99, 101, 105, 118, 101, 95, 112, 114, 111, //
            103, 114, 101, 115, 115, 195, 171, 100, 105, 115, //
            99, 108, 111, 115, 101, 95, 109, 101, 195, 167, //
            116, 105, 109, 101, 111, 117, 116, 12, 174, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 112, //
            105, 110, 103, 160
          ])));
      expect(
          serializer
              .serialize(Call(7814135, 'com.myapp.ping', arguments: ['hi', 2])),
          equals(Uint8List.fromList([
            149, MessageTypes.CODE_CALL, 206, 0, 119, 59, 247, 128, 174, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 112, //
            105, 110, 103, 146, 162, 104, 105, 2
          ])));
      expect(
          serializer.serialize(
              Call(7814135, 'com.myapp.ping', argumentsKeywords: {'hi': 12})),
          equals(Uint8List.fromList([
            150, MessageTypes.CODE_CALL, 206, 0, 119, 59, 247, 128, 174, //
            99, 111, 109, 46, 109, 121, 97, 112, 112, 46, 112, 105, 110, //
            103, 144, 129, 162, 104, 105, 12
          ])));
      expect(
          serializer.serialize(Call(7814135, 'com.myapp.ping',
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals(Uint8List.fromList([
            150, MessageTypes.CODE_CALL, 206, 0, 119, 59, 247, 128, 174, 99,
            111, 109, 46, 109, //
            121, 97, 112, 112, 46, 112, 105, 110, 103, 146, 162, 104, 105, 2, //
            129, 162, 104, 105, 12
          ])));
    });
    test('Yield', () {
      expect(
          serializer.serialize(Yield(6131533)),
          equals(Uint8List.fromList(
              [147, MessageTypes.CODE_YIELD, 206, 0, 93, 143, 77, 128, 160])));
      expect(
          serializer.serialize(Yield(6131533, options: YieldOptions(false))),
          equals(Uint8List.fromList([
            147, MessageTypes.CODE_YIELD, 206, 0, 93, 143, 77, 129, 168, 112, //
            114, 111, 103, 114, 101, 115, 115, 194, 160
          ])));
      expect(
          serializer.serialize(Yield(6131533, options: YieldOptions(true))),
          equals(Uint8List.fromList([
            147, MessageTypes.CODE_YIELD, 206, 0, 93, 143, 77, 129, 168, 112, //
            114, 111, 103, 114, 101, 115, 115, 195, 160
          ])));
      expect(
          serializer.serialize(Yield(6131533, arguments: ['hi', 2])),
          equals(Uint8List.fromList([
            148, MessageTypes.CODE_YIELD, 206, 0, 93, 143, 77, 128, 146, 162, //
            104, 105, 2
          ])));
      expect(
          serializer.serialize(Yield(6131533, argumentsKeywords: {'hi': 12})),
          equals(Uint8List.fromList([
            149, MessageTypes.CODE_YIELD, 206, 0, 93, 143, 77, 128, 144, //
            129, 162, 104, 105, 12
          ])));
      expect(
          serializer.serialize(Yield(6131533,
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals(Uint8List.fromList([
            149, MessageTypes.CODE_YIELD, 206, 0, 93, 143, 77, 128, 146, 162, //
            104, 105, 2, 129, 162, 104, 105, 12
          ])));
    });
    test('Error', () {
      expect(
          serializer.serialize(Error(
              MessageTypes.CODE_HELLO, 123422, HashMap(), 'wamp.unknown')),
          equals(Uint8List.fromList([
            149, MessageTypes.CODE_ERROR, MessageTypes.CODE_HELLO, 206, 0, 1,
            226, 30, 128, 172, //
            119, 97, 109, 112, 46, 117, 110, 107, 110, 111, //
            119, 110, 160
          ])));
      expect(
          serializer.serialize(Error(MessageTypes.CODE_HELLO, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown')),
          equals(Uint8List.fromList([
            149, MessageTypes.CODE_ERROR, MessageTypes.CODE_HELLO, 206, 0, 1,
            226, 30, 129, 165, //
            99, 97, 117, 115, 101, 164, 115, 111, 109, 101, //
            172, 119, 97, 109, 112, 46, 117, 110, 107, 110, //
            111, 119, 110, 160
          ])));
      expect(
          serializer.serialize(Error(MessageTypes.CODE_HELLO, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              arguments: ['hi', 2])),
          equals(Uint8List.fromList([
            150, MessageTypes.CODE_ERROR, MessageTypes.CODE_HELLO, 206, 0, 1,
            226, 30, 129, 165, //
            99, 97, 117, 115, 101, 164, 115, 111, 109, 101, //
            172, 119, 97, 109, 112, 46, 117, 110, 107, 110, //
            111, 119, 110, 146, 162, 104, 105, 2
          ])));
      expect(
          serializer.serialize(Error(MessageTypes.CODE_HELLO, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              argumentsKeywords: {'hi': 12})),
          equals(Uint8List.fromList([
            151, MessageTypes.CODE_ERROR, MessageTypes.CODE_HELLO, 206, 0, //
            1, 226, 30, 129, 165, 99, 97, 117, 115, 101, //
            164, 115, 111, 109, 101, 172, 119, 97, 109, 112, 46, 117, 110, //
            107, 110, 111, 119, 110, 144, 129, 162, 104, 105, 12
          ])));
      expect(
          serializer.serialize(Error(MessageTypes.CODE_HELLO, 123422,
              HashMap.from({'cause': 'some'}), 'wamp.unknown',
              arguments: ['hi', 2], argumentsKeywords: {'hi': 12})),
          equals(Uint8List.fromList([
            151, MessageTypes.CODE_ERROR, MessageTypes.CODE_HELLO, 206, 0, 1, //
            226, 30, 129, 165, 99, 97, 117, 115, 101, 164, 115, 111, 109, //
            101, 172, 119, 97, 109, 112, 46, 117, 110, 107, 110, 111, 119, //
            110, 146, 162, 104, 105, 2, 129, 162, 104, 105, 12
          ])));
    });
    test('Event', () {
      expect(
          serializer.serialize(Event(
              MessageTypes.CODE_EVENT,
              5512315355,
              EventDetails(
                  publisher: 1231412, topic: 'de.de.com', trustlevel: 1),
              arguments: ['johnny'],
              argumentsKeywords: {'firstname': 'John', 'surname': 'Doe'})),
          equals(Uint8List.fromList([
            149, 36, 36, 207, 0, 0, 0, 1, 72, 143, 65, 219, 145, 166, 106, //
            111, 104, 110, 110, 121, 130, 169, 102, 105, 114, 115, 116, 110, //
            97, 109, 101, 164, 74, 111, 104, 110, 167, 115, 117, 114, 110, //
            97, 109, 101, 163, 68, 111, 101
          ])));
    });
    test('Subscribe', () {
      expect(
          serializer.serialize(Subscribe(713845233, 'com.myapp.mytopic1')),
          equals(Uint8List.fromList([
            148, 32, 206, 42, 140, 105, 241, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49
          ])));
      expect(
          serializer.serialize(Subscribe(713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions())),
          equals(Uint8List.fromList([
            148, 32, 206, 42, 140, 105, 241, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49
          ])));
      expect(
          serializer.serialize(Subscribe(713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(match: SubscribeOptions.MATCH_PLAIN))),
          equals(Uint8List.fromList([
            148, 32, 206, 42, 140, 105, 241, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49
          ])));
      expect(
          serializer.serialize(Subscribe(713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(match: SubscribeOptions.MATCH_PREFIX))),
          equals(Uint8List.fromList([
            148, 32, 206, 42, 140, 105, 241, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49
          ])));
      expect(
          serializer.serialize(Subscribe(713845233, 'com.myapp.mytopic1',
              options:
                  SubscribeOptions(match: SubscribeOptions.MATCH_WILDCARD))),
          equals(Uint8List.fromList([
            148, 32, 206, 42, 140, 105, 241, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49
          ])));
      expect(
          serializer.serialize(Subscribe(713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(meta_topic: 'topic'))),
          equals(Uint8List.fromList([
            148, 32, 206, 42, 140, 105, 241, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49
          ])));
      expect(
          serializer.serialize(Subscribe(713845233, 'com.myapp.mytopic1',
              options: SubscribeOptions(
                  get_retained: true,
                  match: SubscribeOptions.MATCH_WILDCARD,
                  meta_topic: 'topic'))),
          equals(Uint8List.fromList([
            148, 32, 206, 42, 140, 105, 241, 131, 172, 103, //
            101, 116, 95, 114, 101, 116, 97, 105, 110, 101, //
            100, 195, 165, 109, 97, 116, 99, 104, 168, 119, //
            105, 108, 100, 99, 97, 114, 100, 170, 109, 101, //
            116, 97, 95, 116, 111, 112, 105, 99, 165, 116, //
            111, 112, 105, 99, 178, 99, 111, 109, 46, 109, //
            121, 97, 112, 112, 46, 109, 121, 116, 111, 112, //
            105, 99, 49
          ])));
    });
    test('Unsubscribe', () {
      expect(
          serializer.serialize(Unsubscribe(85346237, 5512315355)),
          equals(Uint8List.fromList([
            147, 34, 206, 5, 22, 71, 189, 207, 0, 0, //
            0, 1, 72, 143, 65, 219
          ])));
    });
    test('Publish', () {
      expect(
          serializer.serialize(Publish(239714735, 'com.myapp.mytopic1')),
          equals(Uint8List.fromList([
            148, 16, 206, 14, 73, 193, 175, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49, 160
          ])));
      expect(
          serializer.serialize(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions())),
          equals(Uint8List.fromList([
            148, 16, 206, 14, 73, 193, 175, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49, 160
          ])));
      expect(
          serializer.serialize(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions(
                  retain: true,
                  disclose_me: true,
                  acknowledge: true,
                  exclude_me: true,
                  eligible: [1],
                  eligible_authid: ['aaa'],
                  eligible_authrole: ['role'],
                  exclude: [2],
                  exclude_authid: ['bbb'],
                  exclude_authrole: ['admin']))),
          equals(Uint8List.fromList([
            148, 16, 206, 14, 73, 193, 175, 138, 166, 114, //
            101, 116, 97, 105, 110, 195, 171, 100, 105, 115, //
            99, 108, 111, 115, 101, 95, 109, 101, 195, 171, //
            97, 99, 107, 110, 111, 119, 108, 101, 100, 103, //
            101, 195, 170, 101, 120, 99, 108, 117, 100, 101, //
            95, 109, 101, 195, 167, 101, 120, 99, 108, 117, //
            100, 101, 145, 2, 174, 101, 120, 99, 108, 117, //
            100, 101, 95, 97, 117, 116, 104, 105, 100, 145, //
            163, 98, 98, 98, 177, 101, 120, 99, 108, 117, //
            100, 101, 95, 97, 117, 116, 104, 95, 114, 111, //
            108, 101, 145, 165, 97, 100, 109, 105, 110, 168, //
            101, 108, 105, 103, 105, 98, 108, 101, 145, 1, //
            177, 101, 108, 105, 103, 105, 98, 108, 101, 95, //
            97, 117, 116, 104, 114, 111, 108, 101, 145, 164, //
            114, 111, 108, 101, 175, 101, 108, 105, 103, 105, //
            98, 108, 101, 95, 97, 117, 116, 104, 105, 100, //
            145, 163, 97, 97, 97, 178, 99, 111, 109, 46, //
            109, 121, 97, 112, 112, 46, 109, 121, 116, 111, //
            112, 105, 99, 49, 160
          ])));
      expect(
          serializer.serialize(Publish(239714735, 'com.myapp.mytopic1',
              arguments: ['Hello, world!'])),
          equals(Uint8List.fromList([
            149, 16, 206, 14, 73, 193, 175, 128, 178, 99, //
            111, 109, 46, 109, 121, 97, 112, 112, 46, 109, //
            121, 116, 111, 112, 105, 99, 49, 145, 173, 72, //
            101, 108, 108, 111, 44, 32, 119, 111, 114, 108, //
            100, 33
          ])));
      expect(
          serializer.serialize(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions(exclude_me: false),
              arguments: ['Hello, world!'])),
          equals(Uint8List.fromList([
            149, 16, 206, 14, 73, 193, 175, 129, 170, 101, //
            120, 99, 108, 117, 100, 101, 95, 109, 101, 194, //
            178, 99, 111, 109, 46, 109, 121, 97, 112, 112, //
            46, 109, 121, 116, 111, 112, 105, 99, 49, 145, //
            173, 72, 101, 108, 108, 111, 44, 32, 119, 111, //
            114, 108, 100, 33
          ])));
      expect(
          serializer.serialize(
              Publish(239714735, 'com.myapp.mytopic1', argumentsKeywords: {
            'color': 'orange',
            'sizes': [23, 42, 7]
          })),
          equals(Uint8List.fromList([
            150, 16, 206, 14, 73, 193, 175, 128, 178, 99, 111, 109, 46, 109, //
            121, 97, 112, 112, 46, 109, 121, 116, 111, 112, 105, 99, 49, 144, //
            130, 165, 99, 111, 108, 111, 114, 166, 111, 114, 97, 110, 103, //
            101, 165, 115, 105, 122, 101, 115, 147, 23, 42, 7
          ])));
      expect(
          serializer.serialize(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions(exclude_me: false),
              argumentsKeywords: {
                'color': 'orange',
                'sizes': [23, 42, 7]
              })),
          equals(Uint8List.fromList([
            150, 16, 206, 14, 73, 193, 175, 129, 170, 101, 120, 99, 108, 117, //
            100, 101, 95, 109, 101, 194, 178, 99, 111, 109, 46, 109, 121, 97, //
            112, 112, 46, 109, 121, 116, 111, 112, 105, 99, 49, 144, 130, //
            165, 99, 111, 108, 111, 114, 166, 111, 114, 97, 110, 103, 101, //
            165, 115, 105, 122, 101, 115, 147, 23, 42, 7
          ])));
      expect(
          serializer
              .serialize(Publish(239714735, 'com.myapp.mytopic1', arguments: [
            'Hello, world!'
          ], argumentsKeywords: {
            'color': 'orange',
            'sizes': [23, 42, 7]
          })),
          equals(Uint8List.fromList([
            150, 16, 206, 14, 73, 193, 175, 128, 178, 99, 111, 109, 46, 109, //
            121, 97, 112, 112, 46, 109, 121, 116, 111, 112, 105, 99, 49, 145, //
            173, 72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33, //
            130, 165, 99, 111, 108, 111, 114, 166, 111, 114, 97, 110, 103, //
            101, 165, 115, 105, 122, 101, 115, 147, 23, 42, 7
          ])));
      expect(
          serializer.serialize(Publish(239714735, 'com.myapp.mytopic1',
              options: PublishOptions(exclude_me: false),
              arguments: [
                'Hello, world!'
              ],
              argumentsKeywords: {
                'color': 'orange',
                'sizes': [23, 42, 7]
              })),
          equals(Uint8List.fromList([
            150, 16, 206, 14, 73, 193, 175, 129, 170, 101, 120, 99, 108, 117, //
            100, 101, 95, 109, 101, 194, 178, 99, 111, 109, 46, 109, 121, 97, //
            112, 112, 46, 109, 121, 116, 111, 112, 105, 99, 49, 145, 173, 72, //
            101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33, 130, //
            165, 99, 111, 108, 111, 114, 166, 111, 114, 97, 110, 103, 101, //
            165, 115, 105, 122, 101, 115, 147, 23, 42, 7
          ])));
    });
    test('Goodbye', () {
      expect(
          serializer.serialize(
              Goodbye(GoodbyeMessage('cya'), Goodbye.REASON_GOODBYE_AND_OUT)),
          equals(Uint8List.fromList([
            147, 6, 129, 167, 109, 101, 115, 115, 97, 103, //
            101, 163, 99, 121, 97, 186, 119, 97, 109, 112, //
            46, 101, 114, 114, 111, 114, 46, 103, 111, 111, //
            100, 98, 121, 101, 95, 97, 110, 100, 95, 111, //
            117, 116
          ])));
      expect(
          serializer.serialize(
              Goodbye(GoodbyeMessage(null), Goodbye.REASON_CLOSE_REALM)),
          equals(Uint8List.fromList([
            147, 6, 129, 167, 109, 101, 115, 115, 97, 103, //
            101, 160, 182, 119, 97, 109, 112, 46, 101, 114, //
            114, 111, 114, 46, 99, 108, 111, 115, 101, 95, //
            114, 101, 97, 108, 109
          ])));
      expect(
          serializer.serialize(Goodbye(null, Goodbye.REASON_SYSTEM_SHUTDOWN)),
          equals(Uint8List.fromList([
            147, 6, 128, 186, 119, 97, 109, 112, 46, 101, //
            114, 114, 111, 114, 46, 115, 121, 115, 116, 101, //
            109, 95, 115, 104, 117, 116, 100, 111, 119, 110
          ])));
    });
    test('Abort', () {
      expect(
          serializer.serialize(
              Abort(Error.AUTHORIZATION_FAILED, message: 'Some Error')),
          equals(Uint8List.fromList([
            147, 3, 129, 167, 109, 101, 115, 115, 97, 103, //
            101, 170, 83, 111, 109, 101, 32, 69, 114, 114, //
            111, 114, 191, 119, 97, 109, 112, 46, 101, 114, //
            114, 111, 114, 46, 97, 117, 116, 104, 111, 114, //
            105, 122, 97, 116, 105, 111, 110, 95, 102, 97, //
            105, 108, 101, 100
          ])));
      expect(
          serializer.serialize(Abort(Error.AUTHORIZATION_FAILED, message: '')),
          equals(Uint8List.fromList([
            147, 3, 129, 167, 109, 101, 115, 115, 97, 103, //
            101, 160, 191, 119, 97, 109, 112, 46, 101, 114, //
            114, 111, 114, 46, 97, 117, 116, 104, 111, 114, //
            105, 122, 97, 116, 105, 111, 110, 95, 102, 97, //
            105, 108, 101, 100
          ])));
      expect(
          serializer.serialize(Abort(Error.AUTHORIZATION_FAILED)),
          equals(Uint8List.fromList([
            147, 3, 128, 191, 119, 97, 109, 112, 46, 101, //
            114, 114, 111, 114, 46, 97, 117, 116, 104, 111, //
            114, 105, 122, 97, 116, 105, 111, 110, 95, 102, //
            97, 105, 108, 101, 100
          ])));
    });
  });
  group('deserialize', () {
    test('Abort', () {
      var toDeserialize = serializer.serialize(Abort(Error.PROTOCOL_VIOLATION,
          message: 'Received HELLO message after session was established.'));
      Abort abort = serializer.deserialize(toDeserialize);
      expect(abort, isNotNull);
      expect(abort.id, equals(MessageTypes.CODE_ABORT));
      expect(abort.message.message,
          equals('Received HELLO message after session was established.'));
      expect(abort.reason, equals(Error.PROTOCOL_VIOLATION));
    });
    test('Error', () {
      var toDeserialize = serializer.serialize(Error(
          MessageTypes.CODE_HELLO,
          678887,
          {
            'detail1': [2, 4134]
          },
          Error.HIDDEN_ERROR_MESSAGE));
      Error err = serializer.deserialize(toDeserialize);
      expect(err, isNotNull);
      expect(err.id, equals(MessageTypes.CODE_ERROR));
      expect(err.details, isNotNull);

      toDeserialize = serializer.serialize(Error(
          MessageTypes.CODE_HELLO, 678887, {}, Error.INVALID_ARGUMENT,
          arguments: ['invalidArg']));
      err = serializer.deserialize(toDeserialize);
      expect(err, isNotNull);
      expect(err.id, equals(MessageTypes.CODE_ERROR));
      expect(err.details, isNotNull);
      expect(err.arguments, isNotNull);

      toDeserialize = serializer.serialize(Error(
          MessageTypes.CODE_HELLO, 678887, {}, Error.INVALID_ARGUMENT,
          arguments: ['invalidArg', 'invalidArg2'],
          argumentsKeywords: {'name': 'must be konsultaner'}));
      err = serializer.deserialize(toDeserialize);
      expect(err, isNotNull);
      expect(err.id, equals(MessageTypes.CODE_ERROR));
      expect(err.details, isNotNull);
      expect(err.arguments, isNotNull);
      expect(
          err.argumentsKeywords, containsPair('name', 'must be konsultaner'));
    });
    test('Challenge', () {
      Challenge challenge = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 3, 4, 167, 119, 97, 109, //
        112, 99, 114, 97, 223, 0, 0, 0, 4, 169, //
        99, 104, 97, 108, 108, 101, 110, 103, 101, 217, //
        172, 123, 34, 97, 117, 116, 104, 105, 100, 34, //
        58, 34, 82, 105, 99, 104, 105, 34, 44, 34, //
        97, 117, 116, 104, 114, 111, 108, 101, 34, 58, //
        34, 97, 100, 109, 105, 110, 34, 44, 34, 97, //
        117, 116, 104, 109, 101, 116, 104, 111, 100, 34, //
        58, 34, 119, 97, 109, 112, 99, 114, 97, 34, //
        44, 34, 97, 117, 116, 104, 112, 114, 111, 118, //
        105, 100, 101, 114, 34, 58, 34, 115, 101, 114, //
        118, 101, 114, 34, 44, 34, 110, 111, 110, 99, //
        101, 34, 58, 34, 53, 54, 51, 54, 49, 49, //
        55, 53, 54, 56, 55, 54, 56, 49, 50, 50, //
        34, 44, 34, 116, 105, 109, 101, 115, 116, 97, //
        109, 112, 34, 58, 34, 50, 48, 49, 56, 45, //
        48, 51, 45, 49, 54, 84, 48, 55, 58, 50, //
        57, 90, 34, 44, 34, 115, 101, 115, 115, 105, //
        111, 110, 34, 58, 34, 53, 55, 54, 56, 53, //
        48, 49, 48, 57, 57, 49, 51, 48, 56, 51, //
        54, 34, 125, 164, 115, 97, 108, 116, 178, 102, //
        104, 104, 105, 50, 57, 48, 102, 104, 55, 194, //
        167, 41, 71, 81, 41, 71, 41, 166, 107, 101, //
        121, 108, 101, 110, 35, 170, 105, 116, 101, 114, //
        97, 116, 105, 111, 110, 115, 205, 1, 154
      ]));
      expect(challenge, isNotNull);
      expect(challenge.id, equals(MessageTypes.CODE_CHALLENGE));
      expect(challenge.authMethod, equals('wampcra'));
      expect(
          challenge.extra.challenge,
          equals(
              '{\"authid\":\"Richi\",\"authrole\":\"admin\",\"authmethod\":\"wampcra\",\"authprovider\":\"server\",\"nonce\":\"5636117568768122\",\"timestamp\":\"2018-03-16T07:29Z\",\"session\":\"5768501099130836\"}'));
      expect(challenge.extra.salt, equals('fhhi290fh7§)GQ)G)'));
      expect(challenge.extra.keylen, equals(35));
      expect(challenge.extra.iterations, equals(410));
    });
    test('Welcome', () {
      Welcome welcome = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 3, 2, 206, 0, 1, 182, //
        105, 223, 0, 0, 0, 5, 166, 97, 117, 116, //
        104, 105, 100, 165, 82, 105, 99, 104, 105, 168, //
        97, 117, 116, 104, 114, 111, 108, 101, 165, 97, //
        100, 109, 105, 110, 170, 97, 117, 116, 104, 109, //
        101, 116, 104, 111, 100, 167, 119, 97, 109, 112, //
        99, 114, 97, 172, 97, 117, 116, 104, 112, 114, //
        111, 118, 105, 100, 101, 114, 168, 100, 97, 116, //
        97, 98, 97, 115, 101, 165, 114, 111, 108, 101, //
        115, 223, 0, 0, 0, 2, 166, 98, 114, 111, //
        107, 101, 114, 223, 0, 0, 0, 1, 168, 102, //
        101, 97, 116, 117, 114, 101, 115, 223, 0, 0, //
        0, 8, 184, 112, 117, 98, 108, 105, 115, 104, //
        101, 114, 95, 105, 100, 101, 110, 116, 105, 102, //
        105, 99, 97, 116, 105, 111, 110, 194, 186, 112, //
        97, 116, 116, 101, 114, 110, 95, 98, 97, 115, //
        101, 100, 95, 115, 117, 98, 115, 99, 114, 105, //
        112, 116, 105, 111, 110, 194, 181, 115, 117, 98, //
        115, 99, 114, 105, 112, 116, 105, 111, 110, 95, //
        109, 101, 116, 97, 95, 97, 112, 105, 194, 189, //
        115, 117, 98, 115, 99, 114, 105, 98, 101, 114, //
        95, 98, 108, 97, 99, 107, 119, 104, 105, 116, //
        101, 95, 108, 105, 115, 116, 105, 110, 103, 194, //
        176, 115, 101, 115, 115, 105, 111, 110, 95, 109, //
        101, 116, 97, 95, 97, 112, 105, 194, 179, 112, //
        117, 98, 108, 105, 115, 104, 101, 114, 95, 101, //
        120, 99, 108, 117, 115, 105, 111, 110, 194, 173, //
        101, 118, 101, 110, 116, 95, 104, 105, 115, 116, //
        111, 114, 121, 194, 180, 112, 97, 121, 108, 111, //
        97, 100, 95, 116, 114, 97, 110, 115, 112, 97, //
        114, 101, 110, 99, 121, 194, 166, 100, 101, 97, //
        108, 101, 114, 223, 0, 0, 0, 1, 168, 102, //
        101, 97, 116, 117, 114, 101, 115, 223, 0, 0, //
        0, 10, 181, 99, 97, 108, 108, 101, 114, 95, //
        105, 100, 101, 110, 116, 105, 102, 105, 99, 97, //
        116, 105, 111, 110, 194, 176, 99, 97, 108, 108, //
        95, 116, 114, 117, 115, 116, 108, 101, 118, 101, //
        108, 115, 194, 186, 112, 97, 116, 116, 101, 114, //
        110, 95, 98, 97, 115, 101, 100, 95, 114, 101, //
        103, 105, 115, 116, 114, 97, 116, 105, 111, 110, //
        194, 181, 114, 101, 103, 105, 115, 116, 114, 97, //
        116, 105, 111, 110, 95, 109, 101, 116, 97, 95, //
        97, 112, 105, 194, 179, 115, 104, 97, 114, 101, //
        100, 95, 114, 101, 103, 105, 115, 116, 114, 97, //
        116, 105, 111, 110, 194, 176, 115, 101, 115, 115, //
        105, 111, 110, 95, 109, 101, 116, 97, 95, 97, //
        112, 105, 194, 172, 99, 97, 108, 108, 95, 116, //
        105, 109, 101, 111, 117, 116, 194, 174, 99, 97, //
        108, 108, 95, 99, 97, 110, 99, 101, 108, 105, //
        110, 103, 194, 184, 112, 114, 111, 103, 114, 101, //
        115, 115, 105, 118, 101, 95, 99, 97, 108, 108, //
        95, 114, 101, 115, 117, 108, 116, 115, 194, 180, //
        112, 97, 121, 108, 111, 97, 100, 95, 116, 114, //
        97, 110, 115, 112, 97, 114, 101, 110, 99, 121, //
        194
      ]));
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.CODE_WELCOME));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals('Richi'));
      expect(welcome.details.authrole, equals('admin'));
      expect(welcome.details.authmethod, equals('wampcra'));
      expect(welcome.details.authprovider, equals('database'));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles.broker, isNotNull);
      expect(welcome.details.roles.broker.features, isNotNull);
      expect(
          welcome.details.roles.broker.features.payload_transparency, isFalse);
      expect(welcome.details.roles.broker.features.event_history, isFalse);
      expect(welcome.details.roles.broker.features.pattern_based_subscription,
          isFalse);
      expect(welcome.details.roles.broker.features.publication_trustlevels,
          isFalse);
      expect(
          welcome.details.roles.broker.features.publisher_exclusion, isFalse);
      expect(welcome.details.roles.broker.features.publisher_identification,
          isFalse);
      expect(welcome.details.roles.broker.features.session_meta_api, isFalse);
      expect(
          welcome.details.roles.broker.features.subscriber_blackwhite_listing,
          isFalse);
      expect(
          welcome.details.roles.broker.features.subscription_meta_api, isFalse);
      expect(welcome.details.roles.dealer, isNotNull);
      expect(welcome.details.roles.dealer.features, isNotNull);
      expect(
          welcome.details.roles.dealer.features.payload_transparency, isFalse);
      expect(welcome.details.roles.dealer.features.session_meta_api, isFalse);
      expect(welcome.details.roles.dealer.features.progressive_call_results,
          isFalse);
      expect(
          welcome.details.roles.dealer.features.caller_identification, isFalse);
      expect(welcome.details.roles.dealer.features.call_timeout, isFalse);
      expect(welcome.details.roles.dealer.features.call_canceling, isFalse);
      expect(welcome.details.roles.dealer.features.call_trustlevels, isFalse);
      expect(welcome.details.roles.dealer.features.pattern_based_registration,
          isFalse);
      expect(
          welcome.details.roles.dealer.features.registration_meta_api, isFalse);
      expect(
          welcome.details.roles.dealer.features.shared_registration, isFalse);

      welcome = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 3, 2, 206, 0, 1, 182, //
        105, 223, 0, 0, 0, 5, 166, 97, 117, 116, //
        104, 105, 100, 165, 82, 105, 99, 104, 105, 168, //
        97, 117, 116, 104, 114, 111, 108, 101, 165, 97, //
        100, 109, 105, 110, 170, 97, 117, 116, 104, 109, //
        101, 116, 104, 111, 100, 167, 119, 97, 109, 112, //
        99, 114, 97, 172, 97, 117, 116, 104, 112, 114, //
        111, 118, 105, 100, 101, 114, 168, 100, 97, 116, //
        97, 98, 97, 115, 101, 165, 114, 111, 108, 101, //
        115, 223, 0, 0, 0, 2, 166, 98, 114, 111, //
        107, 101, 114, 223, 0, 0, 0, 1, 168, 102, //
        101, 97, 116, 117, 114, 101, 115, 223, 0, 0, //
        0, 8, 184, 112, 117, 98, 108, 105, 115, 104, //
        101, 114, 95, 105, 100, 101, 110, 116, 105, 102, //
        105, 99, 97, 116, 105, 111, 110, 195, 186, 112, //
        97, 116, 116, 101, 114, 110, 95, 98, 97, 115, //
        101, 100, 95, 115, 117, 98, 115, 99, 114, 105, //
        112, 116, 105, 111, 110, 195, 181, 115, 117, 98, //
        115, 99, 114, 105, 112, 116, 105, 111, 110, 95, //
        109, 101, 116, 97, 95, 97, 112, 105, 195, 189, //
        115, 117, 98, 115, 99, 114, 105, 98, 101, 114, //
        95, 98, 108, 97, 99, 107, 119, 104, 105, 116, //
        101, 95, 108, 105, 115, 116, 105, 110, 103, 195, //
        176, 115, 101, 115, 115, 105, 111, 110, 95, 109, //
        101, 116, 97, 95, 97, 112, 105, 195, 179, 112, //
        117, 98, 108, 105, 115, 104, 101, 114, 95, 101, //
        120, 99, 108, 117, 115, 105, 111, 110, 195, 173, //
        101, 118, 101, 110, 116, 95, 104, 105, 115, 116, //
        111, 114, 121, 195, 180, 112, 97, 121, 108, 111, //
        97, 100, 95, 116, 114, 97, 110, 115, 112, 97, //
        114, 101, 110, 99, 121, 195, 166, 100, 101, 97, //
        108, 101, 114, 223, 0, 0, 0, 1, 168, 102, //
        101, 97, 116, 117, 114, 101, 115, 223, 0, 0, //
        0, 10, 181, 99, 97, 108, 108, 101, 114, 95, //
        105, 100, 101, 110, 116, 105, 102, 105, 99, 97, //
        116, 105, 111, 110, 195, 176, 99, 97, 108, 108, //
        95, 116, 114, 117, 115, 116, 108, 101, 118, 101, //
        108, 115, 195, 186, 112, 97, 116, 116, 101, 114, //
        110, 95, 98, 97, 115, 101, 100, 95, 114, 101, //
        103, 105, 115, 116, 114, 97, 116, 105, 111, 110, //
        195, 181, 114, 101, 103, 105, 115, 116, 114, 97, //
        116, 105, 111, 110, 95, 109, 101, 116, 97, 95, //
        97, 112, 105, 195, 179, 115, 104, 97, 114, 101, //
        100, 95, 114, 101, 103, 105, 115, 116, 114, 97, //
        116, 105, 111, 110, 195, 176, 115, 101, 115, 115, //
        105, 111, 110, 95, 109, 101, 116, 97, 95, 97, //
        112, 105, 195, 172, 99, 97, 108, 108, 95, 116, //
        105, 109, 101, 111, 117, 116, 195, 174, 99, 97, //
        108, 108, 95, 99, 97, 110, 99, 101, 108, 105, //
        110, 103, 195, 184, 112, 114, 111, 103, 114, 101, //
        115, 115, 105, 118, 101, 95, 99, 97, 108, 108, //
        95, 114, 101, 115, 117, 108, 116, 115, 195, 180, //
        112, 97, 121, 108, 111, 97, 100, 95, 116, 114, //
        97, 110, 115, 112, 97, 114, 101, 110, 99, 121, //
        195
      ]));
      expect(welcome, isNotNull);
      expect(welcome.id, equals(MessageTypes.CODE_WELCOME));
      expect(welcome.sessionId, equals(112233));
      expect(welcome.details.authid, equals('Richi'));
      expect(welcome.details.authrole, equals('admin'));
      expect(welcome.details.authmethod, equals('wampcra'));
      expect(welcome.details.authprovider, equals('database'));
      expect(welcome.details.roles, isNotNull);
      expect(welcome.details.roles.broker, isNotNull);
      expect(welcome.details.roles.broker.features, isNotNull);
      expect(
          welcome.details.roles.broker.features.payload_transparency, isTrue);
      expect(welcome.details.roles.broker.features.event_history, isTrue);
      expect(welcome.details.roles.broker.features.pattern_based_subscription,
          isTrue);
      expect(welcome.details.roles.broker.features.publication_trustlevels,
          isFalse); // not send
      expect(welcome.details.roles.broker.features.publisher_exclusion, isTrue);
      expect(welcome.details.roles.broker.features.publisher_identification,
          isTrue);
      expect(welcome.details.roles.broker.features.session_meta_api, isTrue);
      expect(
          welcome.details.roles.broker.features.subscriber_blackwhite_listing,
          isTrue);
      expect(
          welcome.details.roles.broker.features.subscription_meta_api, isTrue);
      expect(welcome.details.roles.dealer, isNotNull);
      expect(welcome.details.roles.dealer.features, isNotNull);
      expect(
          welcome.details.roles.dealer.features.payload_transparency, isTrue);
      expect(welcome.details.roles.dealer.features.session_meta_api, isTrue);
      expect(welcome.details.roles.dealer.features.progressive_call_results,
          isTrue);
      expect(
          welcome.details.roles.dealer.features.caller_identification, isTrue);
      expect(welcome.details.roles.dealer.features.call_timeout, isTrue);
      expect(welcome.details.roles.dealer.features.call_canceling, isTrue);
      expect(welcome.details.roles.dealer.features.call_trustlevels, isTrue);
      expect(welcome.details.roles.dealer.features.pattern_based_registration,
          isTrue);
      expect(
          welcome.details.roles.dealer.features.registration_meta_api, isTrue);
      expect(welcome.details.roles.dealer.features.shared_registration, isTrue);
    });
    test('Registered', () {
      Registered registered = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 3, 65, 206, 1, 130, 204, //
        65, 206, 125, 94, 81, 104
      ]));
      expect(registered, isNotNull);
      expect(registered.id, equals(MessageTypes.CODE_REGISTERED));
      expect(registered.registerRequestId, equals(25349185));
      expect(registered.registrationId, equals(2103333224));
    });
    test('Unregistered', () {
      Unregistered unregistered = serializer.deserialize(
          Uint8List.fromList([221, 0, 0, 0, 2, 67, 206, 47, 6, 4, 170]));
      expect(unregistered, isNotNull);
      expect(unregistered.id, equals(MessageTypes.CODE_UNREGISTERED));
      expect(unregistered.unregisterRequestId, equals(788923562));
    });
    test('Invocation', () {
      Invocation invocation = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 4, 68, 206, 0, 93, 143, //
        77, 206, 0, 149, 229, 38, 223, 0, 0, 0, //
        0
      ]));
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.CODE_INVOCATION));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823526));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receive_progress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments, isNull);
      expect(invocation.argumentsKeywords, isNull);

      invocation = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 5, 68, 206, 0, 93, 143, //
        77, 206, 0, 149, 229, 39, 223, 0, 0, 0, //
        0, 221, 0, 0, 0, 1, 173, 72, 101, 108, //
        108, 111, 44, 32, 119, 111, 114, 108, 100, 33
      ]));
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.CODE_INVOCATION));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823527));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receive_progress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments[0], equals('Hello, world!'));
      expect(invocation.argumentsKeywords, isNull);

      invocation = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 6, 68, 206, 0, 93, 143, //
        77, 206, 0, 149, 229, 41, 223, 0, 0, 0, //
        0, 221, 0, 0, 0, 1, 166, 106, 111, 104, //
        110, 110, 121, 223, 0, 0, 0, 2, 169, 102, //
        105, 114, 115, 116, 110, 97, 109, 101, 164, 74, //
        111, 104, 110, 167, 115, 117, 114, 110, 97, 109, //
        101, 163, 68, 111, 101
      ]));
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.CODE_INVOCATION));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823529));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receive_progress, isNull);
      expect(invocation.details.caller, isNull);
      expect(invocation.details.procedure, isNull);
      expect(invocation.arguments[0], equals('johnny'));
      expect(invocation.argumentsKeywords['firstname'], equals('John'));
      expect(invocation.argumentsKeywords['surname'], equals('Doe'));

      invocation = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 6, 68, 206, 0, 93, 143, //
        77, 206, 0, 149, 229, 41, 223, 0, 0, 0, //
        3, 176, 114, 101, 99, 101, 105, 118, 101, 95, //
        112, 114, 111, 103, 114, 101, 115, 115, 195, 166, //
        99, 97, 108, 108, 101, 114, 205, 51, 67, 169, //
        112, 114, 111, 99, 101, 100, 117, 114, 101, 176, //
        109, 121, 46, 112, 114, 111, 99, 101, 100, 117, //
        114, 101, 46, 99, 111, 109, 221, 0, 0, 0, //
        1, 166, 106, 111, 104, 110, 110, 121, 223, 0, //
        0, 0, 2, 169, 102, 105, 114, 115, 116, 110, //
        97, 109, 101, 164, 74, 111, 104, 110, 167, 115, //
        117, 114, 110, 97, 109, 101, 163, 68, 111, 101
      ]));
      expect(invocation, isNotNull);
      expect(invocation.id, equals(MessageTypes.CODE_INVOCATION));
      expect(invocation.requestId, equals(6131533));
      expect(invocation.registrationId, equals(9823529));
      expect(invocation.details, isNotNull);
      expect(invocation.details.receive_progress, isTrue);
      expect(invocation.details.caller, equals(13123));
      expect(invocation.details.procedure, equals('my.procedure.com'));
      expect(invocation.arguments[0], equals('johnny'));
      expect(invocation.argumentsKeywords['firstname'], equals('John'));
      expect(invocation.argumentsKeywords['surname'], equals('Doe'));
    });
    test('Result', () {
      Result result = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 3, 50, 206, 0, 119, 59, //
        247, 223, 0, 0, 0, 0
      ]));
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.CODE_RESULT));
      expect(result.callRequestId, equals(7814135));
      expect(result.details, isNotNull);
      expect(result.details.progress, isNull);
      expect(result.arguments, isNull);
      expect(result.argumentsKeywords, isNull);

      result = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 4, 50, 206, 0, 119, 59, //
        247, 223, 0, 0, 0, 0, 221, 0, 0, 0, //
        1, 30
      ]));
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.CODE_RESULT));
      expect(result.callRequestId, equals(7814135));
      expect(result.details, isNotNull);
      expect(result.details.progress, isNull);
      expect(result.arguments[0], equals(30));
      expect(result.argumentsKeywords, isNull);

      result = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 5, 50, 206, 0, 93, 143, //
        77, 223, 0, 0, 0, 0, 221, 0, 0, 0, //
        1, 166, 106, 111, 104, 110, 110, 121, 223, 0, //
        0, 0, 2, 166, 117, 115, 101, 114, 105, 100, //
        123, 165, 107, 97, 114, 109, 97, 10
      ]));
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.CODE_RESULT));
      expect(result.callRequestId, equals(6131533));
      expect(result.details, isNotNull);
      expect(result.details.progress, isNull);
      expect(result.arguments[0], equals('johnny'));
      expect(result.argumentsKeywords['userid'], equals(123));
      expect(result.argumentsKeywords['karma'], equals(10));

      result = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 5, 50, 206, 0, 93, 143, //
        77, 223, 0, 0, 0, 1, 168, 112, 114, 111, //
        103, 114, 101, 115, 115, 195, 221, 0, 0, 0, //
        1, 166, 106, 111, 104, 110, 110, 121, 223, 0, //
        0, 0, 2, 169, 102, 105, 114, 115, 116, 110, //
        97, 109, 101, 164, 74, 111, 104, 110, 167, 115, //
        117, 114, 110, 97, 109, 101, 163, 68, 111, 101
      ]));
      expect(result, isNotNull);
      expect(result.id, equals(MessageTypes.CODE_RESULT));
      expect(result.callRequestId, equals(6131533));
      expect(result.details, isNotNull);
      expect(result.details.progress, isTrue);
      expect(result.arguments[0], equals('johnny'));
      expect(result.argumentsKeywords['firstname'], equals('John'));
      expect(result.argumentsKeywords['surname'], equals('Doe'));
    });
    // PUB / SUB
    test('Subscribed', () {
      Subscribed subscribed = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 3, 33, 206, 42, 140, 105, //
        241, 207, 0, 0, 0, 1, 72, 143, 65, 219
      ]));
      expect(subscribed, isNotNull);
      expect(subscribed.id, equals(MessageTypes.CODE_SUBSCRIBED));
      expect(subscribed.subscribeRequestId, equals(713845233));
      expect(subscribed.subscriptionId, equals(5512315355));
    });
    test('Unsubscribed', () {
      Unsubscribed unsubscribed = serializer.deserialize(
          Uint8List.fromList([221, 0, 0, 0, 2, 35, 206, 5, 22, 71, 189]));
      expect(unsubscribed, isNotNull);
      expect(unsubscribed.id, equals(MessageTypes.CODE_UNSUBSCRIBED));
      expect(unsubscribed.unsubscribeRequestId, equals(85346237));
      expect(unsubscribed.details, isNull);

      unsubscribed = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 3, 35, 206, 5, 22, 71, //
        189, 223, 0, 0, 0, 2, 172, 115, 117, 98, //
        115, 99, 114, 105, 112, 116, 105, 111, 110, 206, //
        0, 1, 225, 186, 166, 114, 101, 97, 115, 111, //
        110, 184, 119, 97, 109, 112, 46, 97, 117, 116, //
        104, 101, 110, 116, 105, 99, 97, 116, 105, 111, //
        110, 46, 108, 111, 115, 116
      ]));
      expect(unsubscribed, isNotNull);
      expect(unsubscribed.id, equals(MessageTypes.CODE_UNSUBSCRIBED));
      expect(unsubscribed.unsubscribeRequestId, equals(85346237));
      expect(unsubscribed.details.reason, equals('wamp.authentication.lost'));
      expect(unsubscribed.details.subscription, equals(123322));
    });
    test('Published', () {
      Published published = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 3, 17, 206, 14, 73, 193, //
        175, 207, 0, 0, 0, 1, 8, 1, 246, 30
      ]));
      expect(published, isNotNull);
      expect(published.id, equals(MessageTypes.CODE_PUBLISHED));
      expect(published.publishRequestId, equals(239714735));
      expect(published.publicationId, equals(4429313566));
    });
    test('Event', () {
      Event event = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 4, 36, 207, 0, 0, 0, //
        1, 72, 143, 65, 219, 207, 0, 0, 0, 1, //
        8, 1, 246, 30, 223, 0, 0, 0, 0
      ]));
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments, isNull);
      expect(event.argumentsKeywords, isNull);

      event = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 5, 36, 207, 0, 0, 0, //
        1, 72, 143, 65, 219, 207, 0, 0, 0, 1, //
        8, 1, 246, 30, 223, 0, 0, 0, 0, 221, //
        0, 0, 0, 1, 30
      ]));
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments[0], equals(30));
      expect(event.argumentsKeywords, isNull);

      event = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 6, 36, 207, 0, 0, 0, //
        1, 72, 143, 65, 219, 207, 0, 0, 0, 1, //
        8, 1, 246, 30, 223, 0, 0, 0, 0, 221, //
        0, 0, 0, 1, 166, 106, 111, 104, 110, 110, //
        121, 223, 0, 0, 0, 2, 166, 117, 115, 101, //
        114, 105, 100, 123, 165, 107, 97, 114, 109, 97, //
        10,
      ]));
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, isNull);
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments[0], equals('johnny'));
      expect(event.argumentsKeywords['userid'], equals(123));
      expect(event.argumentsKeywords['karma'], equals(10));

      event = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 6, 36, 207, 0, 0, 0, //
        1, 72, 143, 65, 219, 207, 0, 0, 0, 1, //
        8, 1, 246, 30, 223, 0, 0, 0, 1, 169, //
        112, 117, 98, 108, 105, 115, 104, 101, 114, 206, //
        0, 18, 202, 52, 221, 0, 0, 0, 1, 166, //
        106, 111, 104, 110, 110, 121, 223, 0, 0, 0, //
        2, 169, 102, 105, 114, 115, 116, 110, 97, 109, //
        101, 164, 74, 111, 104, 110, 167, 115, 117, 114, //
        110, 97, 109, 101, 163, 68, 111, 101,
      ]));
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, equals(1231412));
      expect(event.details.topic, isNull);
      expect(event.details.trustlevel, isNull);
      expect(event.arguments[0], equals('johnny'));
      expect(event.argumentsKeywords['firstname'], equals('John'));
      expect(event.argumentsKeywords['surname'], equals('Doe'));

      event = serializer.deserialize(Uint8List.fromList([
        221, 0, 0, 0, 6, 36, 207, 0, 0, 0, //
        1, 72, 143, 65, 219, 207, 0, 0, 0, 1, //
        8, 1, 246, 30, 223, 0, 0, 0, 3, 169, //
        112, 117, 98, 108, 105, 115, 104, 101, 114, 206, //
        0, 18, 202, 52, 165, 116, 111, 112, 105, 99, //
        169, 100, 101, 46, 100, 101, 46, 99, 111, 109, //
        170, 116, 114, 117, 115, 116, 108, 101, 118, 101, //
        108, 1, 221, 0, 0, 0, 1, 166, 106, 111, //
        104, 110, 110, 121, 223, 0, 0, 0, 2, 169, //
        102, 105, 114, 115, 116, 110, 97, 109, 101, 164, //
        74, 111, 104, 110, 167, 115, 117, 114, 110, 97, //
        109, 101, 163, 68, 111, 101
      ]));
      expect(event, isNotNull);
      expect(event.id, equals(MessageTypes.CODE_EVENT));
      expect(event.subscriptionId, equals(5512315355));
      expect(event.publicationId, equals(4429313566));
      expect(event.details, isNotNull);
      expect(event.details.publisher, equals(1231412));
      expect(event.details.topic, equals('de.de.com'));
      expect(event.details.trustlevel, equals(1));
      expect(event.arguments[0], equals('johnny'));
      expect(event.argumentsKeywords['firstname'], equals('John'));
      expect(event.argumentsKeywords['surname'], equals('Doe'));
    });
    test('Goodbye', () {
      var toDeserialize = serializer.serialize(Goodbye(
          GoodbyeMessage('bye bye ms american pie'),
          Goodbye.REASON_GOODBYE_AND_OUT));
      Goodbye goodbye = serializer.deserialize(toDeserialize);
      expect(goodbye, isNotNull);
      expect(goodbye.id, MessageTypes.CODE_GOODBYE);
      expect(goodbye.message.message, equals('bye bye ms american pie'));
      expect(goodbye.reason, equals(Goodbye.REASON_GOODBYE_AND_OUT));
    });
  });
  group('string conversion', () {
    test('convert UTF-8', () {
      var invocation = Invocation(10, 10, InvocationDetails(1, '', false),
          arguments: [
            '𝄞 𝄢 Hello! Cześć! 你好! ご挨拶！Привет! ℌ𝔢𝔩𝔩𝔬! 🅗🅔🅛🅛🅞!'
          ]);
      Invocation deserializedInvocation =
          serializer.deserialize(serializer.serialize(invocation));
      expect(deserializedInvocation, equals(isNotNull));
      expect(deserializedInvocation.arguments[0],
          equals('𝄞 𝄢 Hello! Cześć! 你好! ご挨拶！Привет! ℌ𝔢𝔩𝔩𝔬! 🅗🅔🅛🅛🅞!'));
    });
  });
}
