import 'package:connectanum_core/connectanum_core.dart' as wamp_core;
import 'package:logging/logging.dart';

wamp_core.YieldOptions? yieldOptionsFromLazyInvocation(
  wamp_core.LazyInvocationPayload invocation,
) {
  if (invocation.pptScheme == null) {
    return null;
  }
  return wamp_core.YieldOptions(
    pptScheme: invocation.pptScheme,
    pptSerializer: invocation.pptSerializer,
    pptCipher: invocation.pptCipher,
    pptKeyId: invocation.pptKeyId,
    custom: invocation.customDetails,
  );
}

void respondEchoLazyInvocation(
  wamp_core.LazyInvocationPayload invocation, {
  Logger? logger,
}) {
  logger?.fine(
    'RPC echo invoked requestId=${invocation.requestId} '
    'args_encoded=${invocation.argumentsBytes != null} '
    'kwargs_encoded=${invocation.argumentsKeywordsBytes != null} '
    'packed=${invocation.packedPayloadBytes != null}',
  );
  invocation.respondWith(
    lazyPayload: invocation.payload,
    options: yieldOptionsFromLazyInvocation(invocation),
  );
  logger?.fine('RPC echo responded requestId=${invocation.requestId}');
}
