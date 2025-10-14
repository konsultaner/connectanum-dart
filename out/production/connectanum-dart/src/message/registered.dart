import 'e2ee_payload.dart';
import 'ppt_payload.dart';
import 'error.dart';
import 'message_types.dart';
import 'abstract_message.dart';
import 'invocation.dart';

class Registered extends AbstractMessage {
  int registerRequestId;
  int registrationId;
  String? procedure;

  Stream<Invocation>? _invocationStream;

  set invocationStream(Stream<Invocation> invocationStream) {
    _invocationStream = invocationStream;
  }

  /// sets the invocation handler, if an error is thrown within the handler this
  /// method will result an error message to the transport or router respectively
  void onInvoke(void Function(Invocation invocation) onInvoke) {
    if (_invocationStream != null) {
      _invocationStream!.listen((Invocation invocation) {
        try {
          var invocationUpdated = invocation;

          if (invocation.details.pptScheme == 'wamp') {
            // It's E2EE payload
            var e2eePayload = E2EEPayload.unpackE2EEPayload(
                invocation.arguments, invocation.details);

            invocationUpdated.arguments = e2eePayload.arguments;
            invocationUpdated.argumentsKeywords = e2eePayload.argumentsKeywords;
          } else if (invocation.details.pptScheme != null) {
            // It's some variation of PPT
            var pptPayload = PPTPayload.unpackPPTPayload(
                invocation.arguments, invocation.details);

            invocationUpdated.arguments = pptPayload.arguments;
            invocationUpdated.argumentsKeywords = pptPayload.argumentsKeywords;
          }

          onInvoke(invocationUpdated);
        } on Exception catch (e) {
          invocation.respondWith(
              isError: true,
              errorUri: Error.unknown,
              arguments: [e.toString()]);
        }
      });
    }
  }

  Registered(this.registerRequestId, this.registrationId) {
    id = MessageTypes.codeRegistered;
  }
}
