import 'package:connectanum_dart/src/message/abstract_message.dart';

abstract class AbstractSerializer<T> {
  T serialize(AbstractMessage message);
  AbstractMessage deserialize(T message);
}