import 'abstract_message.dart';
import 'message_types.dart';

/// The WAMP Call massage
class Cancel extends AbstractMessage {
  int requestId;
  CancelOptions? options;

  /// Creates a WAMP Cancel message with the canceled calls [requestId] and
  /// some optional [options] to configure the cancel behavior
  Cancel(this.requestId, {this.options}) {
    id = MessageTypes.codeCancel;
  }
}

class CancelOptions {
  static final String modeSkip = 'skip';
  static final String modeKill = 'kill';
  static final String modeKillNoWait = 'killnowait';

  String? mode;
}
