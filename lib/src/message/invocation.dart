import 'dart:async';
import 'dart:collection';

import 'e2ee_payload.dart';
import 'ppt_payload.dart';
import 'abstract_message_with_payload.dart';
import 'abstract_ppt_options.dart';
import 'message_types.dart';
import 'uri_pattern.dart';
import 'error.dart';
import 'yield.dart';

/// Represents an invocation of a registered procedure.
class Invocation extends AbstractMessageWithPayload {
  /// The ID used to match requests and responses.
  int requestId;

  /// The registration ID of the invoked procedure.
  int registrationId;

  /// Additional invocation details provided by the router.
  InvocationDetails details;

  late StreamController<AbstractMessageWithPayload> _responseStreamController;

  /// Respond to this invocation either with a [Yield] or [Error] message.
  void respondWith(
      {List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords,
      bool isError = false,
      String? errorUri,
      YieldOptions? options}) {
    if (isError) {
      if (options != null) {
        assert(options.progress == false);
      }
      assert(UriPattern.match(errorUri!));
      final error = Error(
          MessageTypes.codeInvocation, requestId, HashMap(), errorUri,
          arguments: arguments, argumentsKeywords: argumentsKeywords);
      _responseStreamController.add(error);
    } else {
      var invokeArguments = arguments;
      var invokeArgumentsKeywords = argumentsKeywords;

      if (options?.pptScheme == 'wamp') {
        // It's E2EE payload
        invokeArguments =
            E2EEPayload.packE2EEPayload(arguments, argumentsKeywords, options!);
        invokeArgumentsKeywords = null;
      } else if (options?.pptScheme != null) {
        // It's some variation of PPT
        invokeArguments =
            PPTPayload.packPPTPayload(arguments, argumentsKeywords, options!);
        invokeArgumentsKeywords = null;
      }

      final yield = Yield(requestId,
          options: options,
          arguments: invokeArguments,
          argumentsKeywords: invokeArgumentsKeywords);
      _responseStreamController.add(yield);
    }
    if (options != null && !options.progress) {
      _responseStreamController.close();
    }
  }

  /// Create an [Invocation] referencing a [requestId] and [registrationId].
  Invocation(this.requestId, this.registrationId, this.details,
      {List<dynamic>? arguments, Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.codeInvocation;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  /// True if the caller requested progressive results.
  bool isProgressive() {
    return details.receiveProgress ?? false;
  }

  /// Listen for responses (either [Yield] or [Error]) for this invocation.
  void onResponse(
      void Function(AbstractMessageWithPayload invocationResultMessage)
          onData) {
    _responseStreamController = StreamController<AbstractMessageWithPayload>();
    _responseStreamController.stream.listen(onData);
  }
}

class InvocationDetails extends PPTOptions {
  // caller_identification == true
  int? caller;

  // pattern_based_registration == true
  String? procedure;

  // pattern_based_registration == true
  bool? receiveProgress;

  InvocationDetails(this.caller, this.procedure, this.receiveProgress,
      [String? pptScheme,
      String? pptSerializer,
      String? pptCipher,
      String? pptKeyId]) {
    this.pptScheme = pptScheme;
    this.pptSerializer = pptSerializer;
    this.pptCipher = pptCipher;
    this.pptKeyId = pptKeyId;
  }

  @override
  /// Validates PPT parameters provided with this invocation.
  bool verify() {
    return verifyPPT();
  }
}
