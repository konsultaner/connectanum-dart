import 'e2ee_payload.dart';
import 'ppt_payload.dart';
import 'error.dart';
import 'message_types.dart';
import 'abstract_message.dart';
import 'invocation.dart';

/// Sent by the router to acknowledge a [Register] request.
class Registered extends AbstractMessage {
  /// The request ID that initiated the registration.
  int registerRequestId;

  /// The router assigned registration ID.
  int registrationId;

  /// The procedure URI that was registered.
  String? procedure;

  Stream<Invocation>? _invocationStream;

  /// Set the stream that delivers invocation requests from the router.
  set invocationStream(Stream<Invocation> invocationStream) {
    _invocationStream = invocationStream;
  }

  /// Register a callback that is executed whenever this procedure is invoked.
  /// If the callback throws an error the invocation is answered with an
  /// [Error] message.
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

  /// Create a [Registered] message for the given request and registration IDs.
  Registered(this.registerRequestId, this.registrationId) {
    id = MessageTypes.codeRegistered;
  }
}
