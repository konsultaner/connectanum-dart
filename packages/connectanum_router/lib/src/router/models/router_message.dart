import '../../native/runtime.dart';

import 'router_listener.dart';

/// Container that links a native message to its listener/connection context.
class RouterMessage {
  RouterMessage(this.listener, this.connectionId, this.message);

  final RouterListener listener;
  final int connectionId;
  final NativeIncomingMessage message;
}
