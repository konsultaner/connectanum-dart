import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:rxdart/subjects.dart';

abstract class AbstractTransport {
  BehaviorSubject messages;
  bool close();
  bool isOpen();
  void send(AbstractMessage message);
}