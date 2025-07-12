import 'abstract_message.dart';
import 'details.dart';
import 'message_types.dart';
import 'uri_pattern.dart';

/// Initial message sent to open a WAMP session.
class Hello extends AbstractMessage {
  /// The realm to join on the router.
  String? realm;

  /// Client and authentication details.
  Details details;

  /// Create a [Hello] message for the given [realm] and [details].
  Hello(this.realm, this.details)
      : assert(realm == null || UriPattern.match(realm)) {
    id = MessageTypes.codeHello;
  }
}
