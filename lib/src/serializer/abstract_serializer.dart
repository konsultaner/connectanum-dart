import 'dart:typed_data';

import '../message/abstract_message.dart';

/// The custom serializer interface
abstract class AbstractSerializer {
  /// Serialize a given message
  Uint8List serialize(AbstractMessage message);

  /// Deserialize a given message
  AbstractMessage deserialize(Uint8List message);
}
