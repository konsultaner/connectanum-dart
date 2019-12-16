import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:rxdart/src/subjects/behavior_subject.dart';

import 'abstract_message.dart';
import 'invocation.dart';

class Registered extends AbstractMessage {
  int registerRequestId;
  int registrationId;

  BehaviorSubject<Invocation> invocationStream;

  Registered(this.registerRequestId, this.registrationId) {
    this.id = MessageTypes.CODE_REGISTERED;
  }
}
