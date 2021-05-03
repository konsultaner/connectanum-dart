import 'cancel.dart';
import 'message_types.dart';

class Interrupt {
  int id = MessageTypes.CODE_INTERRUPT;
  int requestId;
  InterruptOptions? options;

  Interrupt(this.requestId, {this.options}) {
    id = MessageTypes.CODE_INTERRUPT;
  }
}

class InterruptOptions extends CancelOptions {}
