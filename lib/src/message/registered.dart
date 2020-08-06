import 'error.dart';
import 'message_types.dart';
import 'abstract_message.dart';
import 'invocation.dart';

class Registered extends AbstractMessage {
  int registerRequestId;
  int registrationId;
  String procedure;

  Stream<Invocation> _invocationStream;

  set invocationStream(Stream<Invocation> invocationStream) {
    _invocationStream = invocationStream;
  }

  /// sets the invocation handler, if an error is thrown within the handler this
  /// method will result an error message to the transport or router respectively
  void onInvoke(void Function(Invocation invocation) onInvoke) {
    if (_invocationStream != null) {
      _invocationStream.listen((Invocation invocation) {
        try {
          onInvoke(invocation);
        } on Exception catch (e) {
          invocation.respondWith(
              isError: true,
              errorUri: Error.UNKNOWN,
              arguments: [e.toString()]);
        }
      });
    }
    return null;
  }

  Registered(this.registerRequestId, this.registrationId) {
    id = MessageTypes.CODE_REGISTERED;
  }
}
