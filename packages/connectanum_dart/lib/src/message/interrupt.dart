import 'abstract_message.dart';

import 'cancel.dart';
import 'message_types.dart';

class Interrupt extends AbstractMessage {
  int requestId;
  InterruptOptions? options;

  Interrupt(this.requestId, {this.options}) {
    id = MessageTypes.codeInterrupt;
  }
}

class InterruptOptions extends CancelOptions {}
