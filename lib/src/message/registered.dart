import 'package:connectanum_dart/src/message/error.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:rxdart/src/subjects/behavior_subject.dart';

import 'abstract_message.dart';
import 'invocation.dart';

class Registered extends AbstractMessage {
  int registerRequestId;
  int registrationId;

  BehaviorSubject<Invocation> _invocationStream;

  set invocationStream(BehaviorSubject<Invocation> invocationStream) {
    _invocationStream = invocationStream;
  }

  void onInvocation(void onData(Invocation invocation)) {
    if (_invocationStream != null && !_invocationStream.isClosed) {
      _invocationStream.listen((Invocation invocation) {
        try {
          onData(invocation);
        } on Exception catch (e) {
          invocation.respondWith(isError: true, errorUri: Error.UNKNOWN, arguments: [e.toString()]);
        }
      });
    }
  }

  Registered(this.registerRequestId, this.registrationId) {
    this.id = MessageTypes.CODE_REGISTERED;
  }
}
