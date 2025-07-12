import 'abstract_message.dart';

import 'cancel.dart';
import 'message_types.dart';

/// Sent by a caller to interrupt a pending invocation.
class Interrupt extends AbstractMessage {
  /// ID of the call or invocation to cancel.
  int requestId;

  /// Additional cancellation options.
  InterruptOptions? options;

  /// Create an interrupt message for the given [requestId].
  Interrupt(this.requestId, {this.options}) {
    id = MessageTypes.codeInterrupt;
  }
}

/// Options for cancelling an invocation.
class InterruptOptions extends CancelOptions {}
