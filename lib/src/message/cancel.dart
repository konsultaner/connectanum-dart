import 'abstract_message.dart';
import 'message_types.dart';

class Cancel extends AbstractMessage {
  @override
  int id;
  int requestId;
  CancelOptions options;

  Cancel(this.requestId, {this.options}) {
    id = MessageTypes.CODE_CANCEL;
  }
}

class CancelOptions {
  static final String MODE_SKIP = 'skip';
  static final String MODE_KILL = 'kill';
  static final String MODE_KILL_NO_WAIT = 'killnowait';

  String mode;
}
