import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/uri_pattern.dart';

import 'abstract_message.dart';
import 'details.dart';

class Hello extends AbstractMessage {
    String realm;
    Details details;
    Hello(this.realm, this.details) : assert (realm != null && UriPattern.match(realm)) {
        this.id = MessageTypes.CODE_HELLO;
    }
}
