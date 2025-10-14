import 'dart:typed_data';

import '../message/abstract_message.dart';
import '../message/ppt_payload.dart';

/// The custom serializer interface
abstract class AbstractSerializer {
  /// Serialize a given message, should return a String or a UInt8List. The
  /// return type is dynamic, because the socket class takes a dynamic type to
  /// send either a string or a binary message.
  dynamic serialize(AbstractMessage message);

  /// Deserialize a given message
  AbstractMessage? deserialize(Uint8List? message);

  /// Serializer Payload for PPT Mode
  Uint8List serializePPT(PPTPayload pptPayload);

  /// Deserialize and prepare payload from PPT Mode
  PPTPayload? deserializePPT(Uint8List binPayload);
}
