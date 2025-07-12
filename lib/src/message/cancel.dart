import 'abstract_message.dart';
import 'message_types.dart';

/// Cancel a pending call issued via [Call].
class Cancel extends AbstractMessage {
  int requestId;
  CancelOptions? options;

  /// Creates a WAMP Cancel message with the canceled calls [requestId] and
  /// some optional [options] to configure the cancel behavior
  Cancel(this.requestId, {this.options}) {
    id = MessageTypes.codeCancel;
  }
}

/// Options that control how the router should cancel the call.
class CancelOptions {
  static final String modeSkip = 'skip';
  static final String modeKill = 'kill';
  static final String modeKillNoWait = 'killnowait';

  /// Specifies how the invocation is cancelled. See WAMP spec for allowed
  /// values [modeSkip], [modeKill] and [modeKillNoWait].
  String? mode;
}
