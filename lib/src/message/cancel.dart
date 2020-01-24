import 'package:connectanum_dart/src/message/message_types.dart';

import 'abstract_message.dart';

class Cancel extends AbstractMessage {
  int id;
  int requestId;
  CancelOptions options;

  Cancel(this.requestId, {this.options}) {
    this.id = MessageTypes.CODE_CANCEL;
  }
}

class CancelOptions {
  static final String MODE_SKIP = "skip";
  static final String MODE_KILL = "kill";
  static final String MODE_KILL_NO_WAIT = "killnowait";

  String mode;
}
