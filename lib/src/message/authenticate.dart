import 'abstract_message.dart';
import 'message_types.dart';

class Authenticate extends AbstractMessage {
  String signature;
  Map<String, Object> extra;

  Authenticate({this.signature}) {
    id = MessageTypes.CODE_AUTHENTICATE;
  }

  factory Authenticate.signature(String signature) {
    final authenticate = Authenticate();
    authenticate.signature = signature;
    return authenticate;
  }
}
