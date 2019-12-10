import 'package:rxdart/src/subjects/behavior_subject.dart';

import 'abstract_message.dart';
import 'invocation.dart';

class Registered extends AbstractMessage {
  int registerRequestId;
  int registrationId;

  BehaviorSubject<Invocation> invocationStream;
}
