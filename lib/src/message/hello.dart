import 'abstract_message.dart';
import 'details.dart';
import 'message_types.dart';
import 'uri_pattern.dart';

class Hello extends AbstractMessage {
  String realm;
  Details details;

  Hello(this.realm, this.details)
      : assert(realm == null || UriPattern.match(realm)) {
    id = MessageTypes.CODE_HELLO;
  }
}
