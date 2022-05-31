import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:logging/logging.dart';

import '../../message/message_types.dart';
import '../../message/abstract_message.dart';
import '../../message/challenge.dart';

import '../abstract_serializer.dart';

/// This is a seralizer for msgpack messages.
/// It is used to initialize an [AbstractTransport] object.
class Serializer extends AbstractSerializer {
  static final Logger _logger = Logger('Serializer');

  @override
  AbstractMessage? deserialize(Uint8List? message) {
    if (message is List) {
      final decodedMessage = cbor.decode(message!.toList());
      if (decodedMessage is CborList) {
        final cborMessageId = decodedMessage[0];
        if (cborMessageId is CborInt) {
          final messageId = cborMessageId.toInt();
          if (messageId == MessageTypes.CODE_CHALLENGE) {
            return Challenge(
                (decodedMessage[1] as CborString).toString(),
                Extra(
                    challenge: (decodedMessage[2] as CborMap)[CborString('challenge')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('challenge')] as CborString).toString(),
                    salt: (decodedMessage[2] as CborMap)[CborString('salt')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('salt')] as CborString).toString(),
                    keylen: (decodedMessage[2] as CborMap)[CborString('keylen')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('keylen')] as CborInt).toInt(),
                    iterations: (decodedMessage[2] as CborMap)[CborString('iterations')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('iterations')] as CborInt).toInt(),
                    memory: (decodedMessage[2] as CborMap)[CborString('memory')] == null ? null : ((decodedMessage[2] as CborMap)[CborString('memory')] as CborInt).toInt(),
                    kdf: (decodedMessage[2] as CborMap)[CborString('kdf')] == null ? null :((decodedMessage[2] as CborMap)[CborString('kdf')] as CborString).toString(),
                    nonce: (decodedMessage[2] as CborMap)[CborString('nonce')] == null ? null :((decodedMessage[2] as CborMap)[CborString('nonce')] as CborString).toString()));
          }
        }
      }
      return null;
    }
    _logger.shout('Could not deserialize the message: ' + message.toString());
    // TODO respond with an error
    return null;
  }

  @override
  Uint8List serialize(AbstractMessage message) {
    return Uint8List(0);
  }

}