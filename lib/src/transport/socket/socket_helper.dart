import 'dart:typed_data';
import 'dart:math';

class SocketHelper {
  static const int _META_HEADER = 0x7F;
  static const int _UPGRADE_HEADER = 0x3F;

  static const int SERIALIZATION_JSON = 1;
  static const int SERIALIZATION_MSGPACK = 2;

  static const int MESSAGE_WAMP = 0;
  static const int MESSAGE_PING = 1;
  static const int MESSAGE_PONG = 2;

  static const int ERROR_SERIALIZER_NOT_SUPPORTED = 1;
  static const int ERROR_MESSAGE_LENGTH_EXCEEDED = 2;
  static const int ERROR_USE_OF_RESERVED_BITS = 3;
  static const int ERROR_MAX_CONNECTION_COUNT_EXCEEDED = 4;

  /// Default wamp clients can only receive up to 16M of message length (2^24 octets)
  static const int MAX_MESSAGE_LENGTH_EXPONENT = 24;
  static int get MAX_MESSAGE_LENGTH => pow(2, MAX_MESSAGE_LENGTH_EXPONENT);

  /// Compare to the regular wamp definition, connectanum is able to send and receive up to 2^30 octets per message
  static const int MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT = 30;
  static int get _MAX_MESSAGE_LENGTH_CONNECTANUM =>
      pow(2, MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT);

  /// Sends a handshake of the morphology
  /// 0111 1111 LLLL SSSS RRRR RRRR RRRR RRRR
  /// LLLL = 2^(9+0bLLLL), the accepted message length
  /// SSSS = 0b0001 = JSON, 0b0010 = MsgPack
  /// RRRR are reserved bytes
  static List<int> getInitialHandshake(
      int messageLengthExponent, int serializerType) {
    var initialHandShake = Uint8List(4);
    initialHandShake[0] = SocketHelper._META_HEADER;
    initialHandShake[1] =
        ((max(0, min(15, messageLengthExponent - 9)) << 4) | serializerType);
    initialHandShake[2] = 0;
    initialHandShake[3] = 0;
    return initialHandShake.toList(growable: false);
  }

  /// Sends an upgrade handshake of the morphology
  /// 0011 1111 0000 LLLL
  /// LLLL = 2^(25 + LLLL), the accepted max message length
  /// If a router does not accept, this upgrade it will respond with an error.
  static List<int> getUpgradeHandshake(int messageLengthExponent) {
    var upgradeHandShake = Uint8List(2);
    upgradeHandShake[0] = SocketHelper._UPGRADE_HEADER;
    upgradeHandShake[1] = (max(0, min(15, messageLengthExponent - 25)) << 4);
    return upgradeHandShake.toList(growable: false);
  }

  static List<int> getError(int errorCode) {
    var errorHandShake = Uint8List(4);
    errorHandShake[0] = SocketHelper._META_HEADER;
    errorHandShake[1] = (errorCode << 4);
    errorHandShake[2] = 0;
    errorHandShake[3] = 0;
    return errorHandShake.toList(growable: false);
  }

  /// Get a pong message with a given [pingLength]. If the [isUpgradedProtocol]
  /// is true the header will have a size of 5 bytes otherwise 4.
  static List<int> getPong(int pingLength, isUpgradedProtocol) {
    return buildMessageHeader(MESSAGE_PONG, pingLength, isUpgradedProtocol);
  }

  /// Get a ping message without a body. If the [isUpgradedProtocol]
  /// is true the header will have a size of 5 bytes otherwise 4.
  static List<int> getPing(isUpgradedProtocol) {
    return buildMessageHeader(MESSAGE_PING, 0, isUpgradedProtocol);
  }

  /// get the [message] error number if [message] is an error.
  static int getErrorNumber(List<int> message) {
    if (message.length > 1) {
      if (message[0] == SocketHelper._UPGRADE_HEADER) return 0;
      var error = message[1];
      if ((((error & 0xFF) << 4) & 0xFF) > 0) return 0;
      return (error & 0xFF) >> 4;
    }
    return 0;
  }

  /// Builds a message header according to a given [headerType], [messageLength],
  /// an the information if it is an [upgradedProtocol]. If the [upgradedProtocol]
  /// is true the header will have a size of 5 bytes otherwise 4.
  static List<int> buildMessageHeader(
      int headerType, int messageLength, bool upgradedProtocol) {
    if (upgradedProtocol) {
      if (messageLength > _MAX_MESSAGE_LENGTH_CONNECTANUM) {
        throw Exception('Their should be no message length larger then 2^' +
            MAX_MESSAGE_LENGTH_CONNECTANUM_EXPONENT.toString());
      }
      var messageHeader = Uint8List(5);
      messageHeader[0] = headerType;
      messageHeader[1] = ((messageLength >> 24) & 0xFF);
      messageHeader[2] = ((messageLength >> 16) & 0xFF);
      messageHeader[3] = ((messageLength >> 8) & 0xFF);
      messageHeader[4] = (messageLength & 0xFF);
      return messageHeader.toList(growable: false);
    } else {
      if (messageLength > MAX_MESSAGE_LENGTH) {
        throw Exception('Their should be no message length larger then 2^' +
            MAX_MESSAGE_LENGTH_EXPONENT.toString());
      }
      var messageHeader = Uint8List(4);
      messageHeader[0] = headerType;
      messageHeader[1] = ((messageLength >> 16) & 0xFF);
      messageHeader[2] = ((messageLength >> 8) & 0xFF);
      messageHeader[3] = (messageLength & 0xFF);
      return messageHeader.toList(growable: false);
    }
  }

  /// Checks if the given [message] is a valid wamp message
  static bool isValidMessage(Uint8List message) {
    var messageType = message[0];
    return messageType != MESSAGE_WAMP ||
        messageType != MESSAGE_PING ||
        messageType != MESSAGE_PONG;
  }

  /// Gets the message type for the given [message].
  static int getMessageType(Uint8List message, {offset = 0}) {
    return message[offset + 0];
  }

  /// Checks if the passed [message] initializes the raw socket protocol
  static bool isRawSocket(Uint8List message) {
    return message[0] == _META_HEADER;
  }

  /// Checks if the passed [message] upgrades the protocoll to connectanum specific
  /// large size messages
  static bool isUpgrade(Uint8List message) {
    return message[0] == _UPGRADE_HEADER;
  }

  /// gets the max message size exponent of the given [message]
  static int getMaxMessageSizeExponent(Uint8List message) {
    return ((message[1] & 0xFF) >> 4) + 9;
  }

  /// gets the max upgrade message size exponent of the given [message]
  static int getMaxUpgradeMessageSizeExponent(Uint8List message) {
    return ((message[1] & 0xFF) >> 4) + 25;
  }

  /// calculates the [message] payload length for a given [headerLength]
  static int getPayloadLength(Uint8List message, int headerLength,
      {offset = 0}) {
    if (message.length >= headerLength) {
      if (headerLength == 5) {
        return (message[offset + 1] & 0xFF) << 24 |
            (message[offset + 2] & 0xFF) << 16 |
            (message[offset + 3] & 0xFF) << 8 |
            (message[offset + 4] & 0xFF);
      } else {
        return (message[offset + 1] & 0xFF) << 16 |
            (message[offset + 2] & 0xFF) << 8 |
            (message[offset + 3] & 0xFF);
      }
    }
    return 0;
  }
}
