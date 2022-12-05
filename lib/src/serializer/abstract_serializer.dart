import 'dart:typed_data';

import '../message/abstract_message.dart';
import '../message/ppt_payload.dart';

/// The custom serializer interface
abstract class AbstractSerializer {
  /// Serialize a given message
  Uint8List serialize(AbstractMessage message);

  /// Deserialize a given message
  AbstractMessage? deserialize(Uint8List? message);

  /// Serializer Payload for PPT Mode
  Uint8List serializePPT(PPTPayload pptPayload);

  /// Deserialize and prepare payload from PPT Mode
  PPTPayload? deserializePPT(Uint8List binPayload);
}
