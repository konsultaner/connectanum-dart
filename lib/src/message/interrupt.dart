import 'abstract_message.dart';

import 'cancel.dart';
import 'message_types.dart';

class Interrupt extends AbstractMessage{
  int requestId;
  InterruptOptions? options;

  Interrupt(this.requestId, {this.options}) {
    id = MessageTypes.CODE_INTERRUPT;
  }
}

class InterruptOptions extends CancelOptions {}
