import 'dart:async';

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
  FutureOr<void> Function(InvocationPayload invocation)? _onInvokePayload;
  FutureOr<void> Function(LazyInvocationPayload invocation)?
  _onLazyInvokePayload;

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

  void onInvokePayload(
    FutureOr<void> Function(InvocationPayload invocation) onInvoke,
  ) {
    _onInvokePayload = onInvoke;
  }

  void onLazyInvokePayload(
    FutureOr<void> Function(LazyInvocationPayload invocation) onInvoke,
  ) {
    _onLazyInvokePayload = onInvoke;
  }

  Registered(this.registerRequestId, this.registrationId) {
    id = MessageTypes.codeRegistered;
  }

  bool get hasMaterializedInvocationConsumers =>
      _onInvoke != null || _invocationController != null;

  bool get hasPayloadInvocationHandler => _onInvokePayload != null;

  bool get hasLazyPayloadInvocationHandler => _onLazyInvokePayload != null;

  void addInvocation(Invocation invocation) {
    final invocationUpdated = invocation;
    final onLazyInvokePayload = _onLazyInvokePayload;
    if (onLazyInvokePayload != null) {
      _deliverLazyInvocationPayload(
        onLazyInvokePayload,
        invocationUpdated.toLazyInvocationPayload(anchor: invocationUpdated),
      );
    }
    final onInvokePayload = _onInvokePayload;
    if (onInvokePayload != null) {
      _deliverInvocationPayload(onInvokePayload, invocationUpdated.toPayload());
    }
    final onInvoke = _onInvoke;
    if (onInvoke != null) {
      _deliverInvocation(onInvoke, invocation, invocationUpdated);
    }
    _invocationController?.add(invocationUpdated);
  }

  void addInvocationPayload(InvocationPayload invocation) {
    final onInvokePayload = _onInvokePayload;
    if (onInvokePayload == null) {
      return;
    }
    _deliverInvocationPayload(onInvokePayload, invocation);
  }

  void addLazyInvocationPayload(LazyInvocationPayload invocation) {
    final onLazyInvokePayload = _onLazyInvokePayload;
    if (onLazyInvokePayload != null) {
      _deliverLazyInvocationPayload(onLazyInvokePayload, invocation);
    }
    final onInvokePayload = _onInvokePayload;
    if (onInvokePayload != null) {
      _deliverInvocationPayload(onInvokePayload, invocation.toPayload());
    }
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
      (invocation) => _deliverInvocation(_onInvoke!, invocation, invocation),
    );
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

  void _deliverInvocationPayload(
    FutureOr<void> Function(InvocationPayload invocation) onInvoke,
    InvocationPayload invocation,
  ) {
    unawaited(
      Future.sync(() => onInvoke(invocation)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (invocation.isResponseClosed()) {
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

  void _deliverLazyInvocationPayload(
    FutureOr<void> Function(LazyInvocationPayload invocation) onInvoke,
    LazyInvocationPayload invocation,
  ) {
    unawaited(
      Future.sync(() => onInvoke(invocation)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (invocation.isResponseClosed()) {
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
