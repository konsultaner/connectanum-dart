import 'dart:convert';

import 'abstract_message_with_payload.dart';
import 'message_types.dart';
import 'abstract_ppt_options.dart';
import 'custom_fields.dart';

/// The WAMP Call massage
class Call extends AbstractMessageWithPayload {
  int requestId;
  CallOptions? options;
  String procedure;

  /// Creates a WAMP Call message with a [requestId] that is kind of like a
  /// transaction identifier and a [procedure] that was registered to the router
  /// before. The [options] field may be passed to configure the call
  Call(
    this.requestId,
    this.procedure, {
    this.options,
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
  }) {
    id = MessageTypes.codeCall;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

/// Options used influence the call behavior
class CallOptions extends PPTOptions with CustomFieldContainer {
  static const String transactionHashWireField = 'transaction_hash';
  static const int maxTransactionHashBytes = 256;

  // progressive_call_invocations == true
  bool? progress;

  // progressive_call_results == true
  bool? receiveProgress;

  // call_timeout == true
  int? timeout;

  // caller_identification == true
  bool? discloseMe;

  CallOptions({
    this.progress,
    this.receiveProgress,
    this.timeout,
    this.discloseMe,
    String? transactionHash,
    String? pptScheme,
    String? pptSerializer,
    String? pptCipher,
    String? pptKeyId,
    Map<String, dynamic>? custom,
  }) {
    this.pptScheme = pptScheme;
    this.pptSerializer = pptSerializer;
    this.pptCipher = pptCipher;
    this.pptKeyId = pptKeyId;
    if (custom != null) {
      this.custom.addAll(custom);
    }
    if (transactionHash != null) {
      this.transactionHash = transactionHash;
    }
  }

  String? get transactionHash {
    final value = custom[transactionHashWireField];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw ArgumentError.value(
        value,
        transactionHashWireField,
        'must be a string',
      );
    }
    _verifyTransactionHash(value);
    return value;
  }

  set transactionHash(String? value) {
    if (value == null) {
      custom.remove(transactionHashWireField);
      return;
    }
    _verifyTransactionHash(value);
    custom[transactionHashWireField] = value;
  }

  @override
  bool verify() {
    if (timeout != null && timeout! < 0) {
      throw RangeError.value(timeout!, 'timeoutError', 'timeout must be >= 0');
    }
    transactionHash;
    return verifyPPT();
  }

  static void _verifyTransactionHash(String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(
        value,
        transactionHashWireField,
        'must not be empty',
      );
    }
    if (utf8.encode(value).length > maxTransactionHashBytes) {
      throw ArgumentError.value(
        value,
        transactionHashWireField,
        'must contain at most $maxTransactionHashBytes UTF-8 bytes',
      );
    }
  }
}
