import 'package:connectanum_dart/src/message/abstract_message.dart';

abstract class AbstractTransport {
  bool close();
  bool isOpen();
  void send(AbstractMessage message);
}