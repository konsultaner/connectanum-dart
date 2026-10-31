import 'dart:isolate';

const internalSessionLazyPayloadKey = 'lazyPayload';

/// Forward a private reply snapshot, then retire the received envelope's data.
/// Returns whether this is an error or a final result.
bool forwardInternalSessionReply(
  SendPort replyPort,
  Map<Object?, Object?> response,
) {
  // Mutable message graphs are copied synchronously by SendPort.send, including
  // same-isolate ports. Never retire the envelope before a successful send.
  replyPort.send(response);
  final type = response['type'];
  final progress = type == 'result' && (response['progress'] as bool? ?? false);
  try {
    response.remove(internalSessionLazyPayloadKey);
    response.remove('arguments');
    response.remove('argumentsKeywords');
  } on UnsupportedError {
    // Immutable envelopes still forward normally.
  }
  return type == 'error' || (type == 'result' && !progress);
}
