import 'package:connectanum_dart/src/message/message_types.dart';

import 'abstract_message.dart';
import 'details.dart';

class Welcome extends AbstractMessage {
    int sessionId;
    Details details;

    Welcome({this.sessionId, this.details}) {
        this.id = MessageTypes.CODE_WELCOME;
    }
}
