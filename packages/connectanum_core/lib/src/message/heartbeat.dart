import 'abstract_message.dart';
import 'message_types.dart';

class Heartbeat extends AbstractMessage {
  Heartbeat({
    Map<String, Object?>? details,
    this.ping,
    this.incoming,
    this.outgoing,
  }) : details = Map<String, Object?>.from(details ?? const {}) {
    id = MessageTypes.codeHeartbeat;
  }

  final Map<String, Object?> details;
  final int? ping;
  final int? incoming;
  final int? outgoing;
}
