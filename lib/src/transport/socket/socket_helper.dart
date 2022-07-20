import 'dart:typed_data';
import 'dart:math';

class SocketHelper {
  static const int _metaHeader = 0x7F;
  static const int _upgradeHeader = 0x3F;

  static const int serializationJson = 1;
  static const int serializationMsgpack = 2;
  static const int serializationCbor = 3;
  static const int serializationUbjson = 4;
  static const int serializationFlatBuffers = 5;

  static const int messageWamp = 0;
  static const int messagePing = 1;
  static const int messagePong = 2;

  static const int errorSerializerNotSupported = 1;
  static const int errorMessageLengthExceeded = 2;
  static const int errorUseOfReservedBits = 3;
  static const int errorMaxConnectionCountExceeded = 4;

  /// Default wamp clients can only receive up to 16M of message length (2^24 octets)
  static const int maxMessageLengthExponent = 24;
  static int get maxMessageLength =>
      pow(2, maxMessageLengthExponent) as int;

  /// Compare to the regular wamp definition, connectanum is able to send and receive up to 2^30 octets per message
  static const int maxMessageLengthConnectanumExponent = 30;
  static int get _maxMessageLengthConnectanum =>
      pow(2, maxMessageLengthConnectanumExponent) as int;

  /// Sends a handshake of the morphology
  /// 0111 1111 LLLL SSSS RRRR RRRR RRRR RRRR
  /// LLLL = 2^(9+0bLLLL), the accepted message length
  /// SSSS = 0b0001 = JSON, 0b0010 = MsgPack
  /// RRRR are reserved bytes
  static List<int> getInitialHandshake(
      int messageLengthExponent, int serializerType) {
    var initialHandShake = Uint8List(4);
    initialHandShake[0] = SocketHelper._metaHeader;
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
    upgradeHandShake[0] = SocketHelper._upgradeHeader;
    upgradeHandShake[1] = (max(0, min(15, messageLengthExponent - 25)) << 4);
    return upgradeHandShake.toList(growable: false);
  }

  static List<int> getError(int errorCode) {
    var errorHandShake = Uint8List(4);
    errorHandShake[0] = SocketHelper._metaHeader;
    errorHandShake[1] = (errorCode << 4);
    errorHandShake[2] = 0;
    errorHandShake[3] = 0;
    return errorHandShake.toList(growable: false);
  }

  /// Get a pong message with a given [pingLength]. If the [isUpgradedProtocol]
  /// is true the header will have a size of 5 bytes otherwise 4.
  static List<int> getPong(int pingLength, isUpgradedProtocol) {
    return buildMessageHeader(messagePong, pingLength, isUpgradedProtocol);
  }

  /// Get a ping message without a body. If the [isUpgradedProtocol]
  /// is true the header will have a size of 5 bytes otherwise 4.
  static List<int> getPing(isUpgradedProtocol) {
    return buildMessageHeader(messagePing, 0, isUpgradedProtocol);
  }

  /// get the [message] error number if [message] is an error.
  static int getErrorNumber(List<int> message) {
    if (message.length > 1) {
      if (message[0] == SocketHelper._upgradeHeader) return 0;
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
      if (messageLength > _maxMessageLengthConnectanum) {
        throw Exception('Their should be no message length larger then 2^$maxMessageLengthConnectanumExponent');
      }
      var messageHeader = Uint8List(5);
      messageHeader[0] = headerType;
      messageHeader[1] = ((messageLength >> 24) & 0xFF);
      messageHeader[2] = ((messageLength >> 16) & 0xFF);
      messageHeader[3] = ((messageLength >> 8) & 0xFF);
      messageHeader[4] = (messageLength & 0xFF);
      return messageHeader.toList(growable: false);
    } else {
      if (messageLength > maxMessageLength) {
        throw Exception('Their should be no message length larger then 2^$maxMessageLengthExponent');
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
    return messageType != messageWamp ||
        messageType != messagePing ||
        messageType != messagePong;
  }

  /// Gets the message type for the given [message].
  static int getMessageType(Uint8List message, {offset = 0}) {
    return message[offset + 0];
  }

  /// Checks if the passed [message] initializes the raw socket protocol
  static bool isRawSocket(Uint8List message) {
    return message[0] == _metaHeader;
  }

  /// Checks if the passed [message] upgrades the protocoll to connectanum specific
  /// large size messages
  static bool isUpgrade(Uint8List message) {
    return message[0] == _upgradeHeader;
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
