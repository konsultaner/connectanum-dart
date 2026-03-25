import 'dart:collection';

import 'e2ee_payload.dart';
import 'ppt_payload.dart';
import 'abstract_message_with_payload.dart';
import 'abstract_ppt_options.dart';
import 'custom_fields.dart';
import 'message_types.dart';
import 'uri_pattern.dart';
import 'error.dart';
import 'yield.dart';

class Invocation extends AbstractMessageWithPayload {
  int requestId;
  int registrationId;
  InvocationDetails details;
  void Function(AbstractMessageWithPayload invocationResultMessage)?
  _onResponse;
  bool _responseClosed = false;

  bool get responseClosed => _responseClosed;

  void respondWith({
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    bool isError = false,
    String? errorUri,
    YieldOptions? options,
  }) {
    if (isError) {
      if (options != null) {
        assert(options.progress == false);
      }
      assert(UriPattern.match(errorUri!));
      final error = Error(
        MessageTypes.codeInvocation,
        requestId,
        HashMap(),
        errorUri,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
      );
      _emitResponse(error);
    } else {
      var invokeArguments = arguments;
      var invokeArgumentsKeywords = argumentsKeywords;

      if (options?.pptScheme == 'wamp') {
        // It's E2EE payload
        invokeArguments = E2EEPayload.packE2EEPayload(
          arguments,
          argumentsKeywords,
          options!,
        );
        invokeArgumentsKeywords = null;
      } else if (options?.pptScheme != null) {
        // It's some variation of PPT
        invokeArguments = PPTPayload.packPPTPayload(
          arguments,
          argumentsKeywords,
          options!,
        );
        invokeArgumentsKeywords = null;
      }

      final yield = Yield(
        requestId,
        options: options,
        arguments: invokeArguments,
        argumentsKeywords: invokeArgumentsKeywords,
      );
      _emitResponse(yield);
    }
  }

  Invocation(
    this.requestId,
    this.registrationId,
    this.details, {
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    id = MessageTypes.codeInvocation;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  bool isProgressive() {
    return details.receiveProgress ?? false;
  }

  void onResponse(
    void Function(AbstractMessageWithPayload invocationResultMessage) onData,
  ) {
    _onResponse = onData;
  }

  void _emitResponse(AbstractMessageWithPayload response) {
    if (_responseClosed) {
      throw StateError('Invocation response handler already completed');
    }
    final onResponse = _onResponse;
    if (onResponse == null) {
      throw StateError('Invocation response handler not attached');
    }
    onResponse(response);
    if (response is Error) {
      _responseClosed = true;
      return;
    }
    if (response is Yield && response.options?.progress == true) {
      return;
    }
    _responseClosed = true;
  }
}

class InvocationDetails extends PPTOptions with CustomFieldContainer {
  // caller_identification == true
  int? caller;

  // pattern_based_registration == true
  String? procedure;

  // pattern_based_registration == true
  bool? receiveProgress;

  InvocationDetails(
    this.caller,
    this.procedure,
    this.receiveProgress, [
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyId,
    Map<String, dynamic>? custom,
  ]) {
    this.pptScheme = pptScheme;
    this.pptSerializer = pptSerializer;
    this.pptCipher = pptCipher;
    this.pptKeyId = pptKeyId;
    if (custom != null) {
      this.custom.addAll(custom);
    }
  }

  @override
  bool verify() {
    return verifyPPT();
  }
}
