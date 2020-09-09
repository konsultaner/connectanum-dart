import 'abstract_message.dart';
import 'message_types.dart';

/// The WAMP Authenticate massage
class Authenticate extends AbstractMessage {
  String signature;
  Map<String, Object> extra;

  /// Creates a WAMP Authentication message with a [signature] that was
  /// cryptographically created by an authentication method of this package
  Authenticate({this.signature}) {
    id = MessageTypes.CODE_AUTHENTICATE;
  }

  /// A factory that creates an instance of a WAMP Authenticate massage by
  /// passing in a [signature] that was
  /// cryptographically created by an authentication method of this package
  factory Authenticate.signature(String signature) {
    final authenticate = Authenticate();
    authenticate.signature = signature;
    return authenticate;
  }
}
