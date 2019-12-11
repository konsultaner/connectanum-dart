import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:rxdart/subjects.dart';

abstract class AbstractTransport {
  final BehaviorSubject<AbstractMessage> inbound = new BehaviorSubject();

  void onMessage(void onData(AbstractMessage event)) {
    inbound.listen(onData);
  }
  Future<void> open();
  Future<void> close();
  bool isOpen();
  void send(AbstractMessage message);
}