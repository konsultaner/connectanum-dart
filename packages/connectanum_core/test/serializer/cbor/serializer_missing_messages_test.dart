import 'package:cbor/cbor.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart';
import 'package:test/test.dart';

void main() {
  final serializer = Serializer();

  List<dynamic> decodeList(List<int> encoded) =>
      (cbor.decode(encoded) as CborList).toObject() as List<dynamic>;

  group('cbor serializer router message coverage', () {
    test('serializes challenge and welcome frames', () {
      expect(
        decodeList(
          serializer.serialize(Challenge('ticket', Extra(challenge: 'abc'))),
        ),
        equals([
          MessageTypes.codeChallenge,
          'ticket',
          {'challenge': 'abc'},
        ]),
      );

      final welcome = decodeList(
        serializer.serialize(
          Welcome(
            12345,
            Details.forWelcome(
              authId: 'bench',
              authRole: 'bench',
              authMethod: 'anonymous',
              authProvider: 'bench-router',
            ),
          ),
        ),
      );
      expect(welcome[0], MessageTypes.codeWelcome);
      expect(welcome[1], 12345);
      expect((welcome[2] as Map)['authid'], 'bench');
    });

    test('serializes result and interrupt frames', () {
      expect(
        decodeList(
          serializer.serialize(
            Result(
              734573,
              ResultDetails(
                progress: true,
                pptScheme: 'aes',
                pptSerializer: 'json',
                pptCipher: 'gcm',
                pptKeyId: 'k1',
                custom: {'custom': 1},
              ),
              arguments: const ['ok'],
              argumentsKeywords: const {'answer': 42},
            ),
          ),
        ),
        equals([
          MessageTypes.codeResult,
          734573,
          {
            'progress': true,
            'ppt_scheme': 'aes',
            'ppt_serializer': 'json',
            'ppt_cipher': 'gcm',
            'ppt_keyid': 'k1',
            'custom': 1,
          },
          ['ok'],
          {'answer': 42},
        ]),
      );

      expect(
        decodeList(
          serializer.serialize(
            Interrupt(
              101,
              options: InterruptOptions()..mode = CancelOptions.modeKill,
            ),
          ),
        ),
        equals([
          MessageTypes.codeInterrupt,
          101,
          {'mode': CancelOptions.modeKill},
        ]),
      );
    });

    test(
      'serializes published subscription and registration acknowledgements',
      () {
        expect(
          decodeList(serializer.serialize(Published(239714735, 4429313566))),
          equals([MessageTypes.codePublished, 239714735, 4429313566]),
        );
        expect(
          decodeList(serializer.serialize(Subscribed(713845233, 5512315355))),
          equals([MessageTypes.codeSubscribed, 713845233, 5512315355]),
        );
        expect(
          decodeList(serializer.serialize(Registered(25349185, 2103333224))),
          equals([MessageTypes.codeRegistered, 25349185, 2103333224]),
        );
        expect(
          decodeList(serializer.serialize(Unregistered(788923562))),
          equals([MessageTypes.codeUnregistered, 788923562]),
        );
      },
    );

    test(
      'serializes unsubscribe acknowledgements with and without details',
      () {
        expect(
          decodeList(serializer.serialize(Unsubscribed(85346237, null))),
          equals([MessageTypes.codeUnsubscribed, 85346237]),
        );
        expect(
          decodeList(
            serializer.serialize(
              Unsubscribed(
                85346237,
                UnsubscribedDetails(123322, 'wamp.authentication.lost'),
              ),
            ),
          ),
          equals([
            MessageTypes.codeUnsubscribed,
            85346237,
            {'subscription': 123322, 'reason': 'wamp.authentication.lost'},
          ]),
        );
      },
    );
  });
}
