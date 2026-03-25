import 'dart:async';

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

  Stream<Invocation>? _invocationStreamOverride;
  StreamController<Invocation>? _invocationController;
  StreamSubscription<Invocation>? _streamInvocationSubscription;
  FutureOr<void> Function(Invocation invocation)? _onInvoke;

  set invocationStream(Stream<Invocation> invocationStream) {
    _invocationStreamOverride = invocationStream;
    _attachStreamInvocationHandlerIfNeeded();
  }

  Stream<Invocation>? get invocationStream {
    return _invocationStreamOverride ??
        (_invocationController ??= _newInvocationController()).stream;
  }

  /// sets the invocation handler, if an error is thrown within the handler this
  /// method will result an error message to the transport or router respectively
  void onInvoke(FutureOr<void> Function(Invocation invocation) onInvoke) {
    _onInvoke = onInvoke;
    _attachStreamInvocationHandlerIfNeeded();
  }

  Registered(this.registerRequestId, this.registrationId) {
    id = MessageTypes.codeRegistered;
  }

  void addInvocation(Invocation invocation) {
    final invocationUpdated = _prepareInvocation(invocation);
    final onInvoke = _onInvoke;
    if (onInvoke != null) {
      _deliverInvocation(onInvoke, invocation, invocationUpdated);
    }
    _invocationController?.add(invocationUpdated);
  }

  Future<void> closeInvocationStream() async {
    await _streamInvocationSubscription?.cancel();
    _streamInvocationSubscription = null;
    final controller = _invocationController;
    _invocationController = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  void _attachStreamInvocationHandlerIfNeeded() {
    if (_onInvoke == null ||
        _invocationStreamOverride == null ||
        _streamInvocationSubscription != null) {
      return;
    }
    _streamInvocationSubscription = _invocationStreamOverride!.listen(
      (invocation) => _deliverInvocation(
        _onInvoke!,
        invocation,
        _prepareInvocation(invocation),
      ),
    );
  }

  Invocation _prepareInvocation(Invocation invocation) {
    var invocationUpdated = invocation;

    if (invocation.details.pptScheme == 'wamp') {
      final e2eePayload = E2EEPayload.unpackE2EEPayload(
        invocation.arguments,
        invocation.details,
      );

      invocationUpdated.arguments = e2eePayload.arguments;
      invocationUpdated.argumentsKeywords = e2eePayload.argumentsKeywords;
    } else if (invocation.details.pptScheme != null) {
      final pptPayload = PPTPayload.unpackPPTPayload(
        invocation.arguments,
        invocation.details,
      );

      invocationUpdated.arguments = pptPayload.arguments;
      invocationUpdated.argumentsKeywords = pptPayload.argumentsKeywords;
    }
    return invocationUpdated;
  }

  void _deliverInvocation(
    FutureOr<void> Function(Invocation invocation) onInvoke,
    Invocation invocation,
    Invocation invocationUpdated,
  ) {
    unawaited(
      Future.sync(() => onInvoke(invocationUpdated)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (invocation.responseClosed) {
          return;
        }
        invocation.respondWith(
          isError: true,
          errorUri: Error.unknown,
          arguments: [error.toString()],
        );
      }),
    );
  }

  StreamController<Invocation> _newInvocationController() {
    return StreamController<Invocation>.broadcast(sync: true);
  }
}
