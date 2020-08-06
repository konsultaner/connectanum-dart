import 'dart:async';

import 'abstract_message.dart';
import 'event.dart';
import 'message_types.dart';

class Subscribed extends AbstractMessage {
  int subscribeRequestId;
  int subscriptionId;

  Subscribed(this.subscribeRequestId, this.subscriptionId) {
    id = MessageTypes.CODE_SUBSCRIBED;
  }

  /// Is created by the protocol processor and will receive an event object
  /// when the transport receives one
  Stream<Event> eventStream;
  final _revokeCompleter = Completer<String>();

  Future<String> get onRevoke {
    return _revokeCompleter.future;
  }

  void revoke(String reason) {
    _revokeCompleter.complete(reason);
  }
}
