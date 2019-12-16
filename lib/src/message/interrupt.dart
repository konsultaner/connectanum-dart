import 'cancel.dart';
import 'message_types.dart';

class Interrupt extends Cancel {
  Interrupt() {
    this.id = MessageTypes.CODE_INTERRUPT;
  }
}
