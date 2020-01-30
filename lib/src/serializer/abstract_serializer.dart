import 'dart:typed_data';

import 'package:connectanum_dart/src/message/abstract_message.dart';

abstract class AbstractSerializer {
  Uint8List serialize(AbstractMessage message);
  AbstractMessage deserialize(Uint8List message);
}