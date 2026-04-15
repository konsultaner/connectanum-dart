import 'message_types.dart';
import 'abstract_message.dart';
import 'custom_fields.dart';

/// The WAMP Abort massage
class Abort extends AbstractMessage {
  Abort(
    this.reason, {
    Map<String, Object?>? details,
    String? message,
    List<dynamic>? arguments,
    Map<String, Object?>? argumentsKeywords,
  }) : details = details == null
           ? <String, Object?>{}
           : details is LazyStringKeyMap
           ? details
           : Map<String, Object?>.from(details),
       arguments = arguments == null ? null : List<dynamic>.from(arguments),
       argumentsKeywords = argumentsKeywords == null
           ? null
           : Map<String, Object?>.from(argumentsKeywords) {
    id = MessageTypes.codeAbort;
    if (message != null) {
      this.message = Message(message);
      this.details['message'] = message;
    } else if (this.details.containsKey('message') &&
        this.details['message'] is String) {
      this.message = Message(this.details['message'] as String);
    }
  }

  final Map<String, Object?> details;
  final List<dynamic>? arguments;
  final Map<String, Object?>? argumentsKeywords;
  Message? message;
  String reason;
}

/// The message structure defined by the WAMP-Protocol
class Message {
  String message;

  Message(this.message);
}
