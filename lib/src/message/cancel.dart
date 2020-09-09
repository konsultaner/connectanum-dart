import 'abstract_message.dart';
import 'message_types.dart';

/// The WAMP Call massage
class Cancel extends AbstractMessage {
  @override
  int id;
  int requestId;
  CancelOptions options;

  /// Creates a WAMP Cancel message with the canceled calls [requestId] and
  /// some optional [options] to configure the cancel behavior
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
