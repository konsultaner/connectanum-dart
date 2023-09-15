import 'dart:async';

import 'package:connectanum/src/message/goodbye.dart';
import 'package:logging/logging.dart';

import '../src/message/abort.dart';
import '../src/message/error.dart';

import 'authentication/abstract_authentication.dart';
import 'transport/abstract_transport.dart';
import 'message/uri_pattern.dart';
import 'protocol/session.dart';

enum _ClientState {
  /// Client is idle and not connected
  none,

  /// Client is connecting and waiting for a session
  waiting,

  /// Client has connected and session is active, transport is open
  active,

  /// Client has finished or is in process of disconnecting, cleaning up, closing transports etc
  done,
}

class Client {
  static const _abortReasons = [
    Error.notAuthorized,
    Error.noPrincipal,
    Error.authorizationFailed,
    Error.noSuchRealm,
    Error.protocolViolation,
  ];

  static final Logger _logger = Logger('Connectanum.Client');

  String? authId;
  String? authRole;
  String? realm;
  Map<String, dynamic>? authExtra;
  int isolateCount;

  _ClientState _state = _ClientState.none;

  final StreamController<ClientConnectOptions> _connectStreamController =
      StreamController<ClientConnectOptions>.broadcast();
  AbstractTransport transport;
  List<AbstractAuthentication>? authenticationMethods;

  final StreamController<Session> _controller = StreamController<Session>();

  StreamSubscription<ClientConnectOptions>? _connectStreamSubscription;

  /// The client connects to the wamp server by using the given [transport] and
  /// the given [authenticationMethods]. Passing more then one [AbstractAuthentication]
  /// to the client will make the router choose which method to choose.
  /// The [authId] and the [realm] will be used for all given [authenticationMethods]
  ///
  /// Example:
  /// ```dart
  /// import 'package:connectanum/connectanum.dart';
  /// import 'package:connectanum/socket.dart';
  ///
  /// final client = Client(
  ///   realm: "test.realm",
  ///   transport: SocketTransport(
  ///     'localhost',
  ///     8080,
  ///     Serializer(),
  ///     SocketHelper.SERIALIZATION_JSON
  ///   )
  /// );
  ///
  /// final Session session = await client.connect();
  /// ```
  Client(
      {required this.transport,
      this.authId,
      this.authRole,
      this.realm,
      this.authenticationMethods,
      this.authExtra,
      this.isolateCount = 1})
      : assert(realm == null || UriPattern.match(realm)) {
    _connectStreamSubscription =
        _connectStreamController.stream.listen(_connect);
  }

  /// if listened to this stream you will be noticed about reconnect tries. The passed
  /// integer will be the current retry counted down from where you started in the configured
  /// [reconnectCount] passed to the [connect] method. Be aware a zero is passed just
  /// before the [connect] streams [onError] will raise the abort message. So 0 means
  /// that the reconnect failed.
  Stream<ClientConnectOptions> get onNextTryToReconnect =>
      _connectStreamController.stream;

  /// Calling this method will start the authentication process and result into
  /// a [Session] object on success. If a [pingInterval] is given and the underlying transport
  /// supports sending of ping messages. the given duration is used by the transport
  /// to send ping messages every [pingInterval]. [SocketTransport] and [WebSocketTransport] not
  /// within the browser support ping messages. The browser API does not allow to control
  /// ping messages. If [reconnectCount] and the [reconnectTime] is set
  /// the client will try to reestablish the session. Setting [reconnectCount] to -1 will infinite
  /// times reconnect the client or until the stack overflows
  Stream<Session> connect({ClientConnectOptions? options}) {
    options ??= ClientConnectOptions();

    _changeState(_ClientState.waiting);

    /// Increment reconnectCount by 1 because we use one for initial connect
    options.reconnectCount =
        options.reconnectCount == -1 ? -1 : options.reconnectCount + 1;
    _connectStreamController.add(options);

    return _controller.stream;
  }

  /// Close connection.
  ///
  /// After calling the method, this instance of Client can no longer be used.
  Future<void> disconnect() async {
    _logger.shout('Disconnecting');
    _changeState(_ClientState.done);
    await _connectStreamSubscription?.cancel();
    await _connectStreamController.close();
    await _controller.close();
    await transport.close();
  }

  Future<void> _reconnect(ClientConnectOptions options,
      {Duration? duration}) async {
    if (options.reconnectCount == 0) {
      return await _onNoReconnectsLeft('Ran out of reconnect attempts');
    }

    _changeState(_ClientState.waiting);

    if (duration != null) {
      _logger.info('Waiting for (overridden) $duration before reconnecting');
      await Future.delayed(duration);
    } else {
      _logger.info('Waiting for ${options.reconnectTime!} before reconnecting');
      await Future.delayed(options.reconnectTime!);
    }

    // Check in case the client has been closed while we were waiting;
    if (_state == _ClientState.done) return;
    return _connectStreamController.add(options);
  }

  void _changeState(_ClientState newState) {
    if (_state != newState) {
      _logger.info('Changed state: $_state -> $newState');
    }
    _state = newState;
  }

  Future<void> _connect(ClientConnectOptions options) async {
    _logger.info('Connecting, attempts remaining: ${options.reconnectCount}');
    await transport.open(pingInterval: options.pingInterval);

    /// Transport failed opening / initializing
    if (!transport.isOpen || transport.onConnectionLost == null) {
      if (options.reconnectTime == null || options.reconnectCount == 0) {
        _logger.shout(
          'Unable to reconnect - reconnectTime is null or reconnectCount is 0',
        );
        return await _onNoReconnectsLeft(
            'Please configure reconnectTime to retry automatically');
      }

      return _reconnect(options.minusReconnectRetry());
    }

    /// Listen to on connection lost
    transport.onConnectionLost!.future.then((_) {
      if (_state == _ClientState.done) return;
      _logger.info('Transport connection lost, client state is: $_state');

      _reconnect(options.minusReconnectRetry());
    });

    try {
      final session = await Session.start(
        realm,
        transport,
        authId: authId,
        authRole: authRole,
        authMethods: authenticationMethods,
        reconnect: options.reconnectTime,
      );
      _controller.add(session);
      _changeState(_ClientState.active);
    } on Abort catch (abort) {
      _onSessionAbort(abort, options);
    } on Goodbye catch (goodbye) {
      _onSessionGoodbye(goodbye);
    }
  }

  Future<void> _onNoReconnectsLeft(String reason) async {
    String errorMessage = 'Could not connect to server. $reason.';

    // Check if we can propagate an error from transport
    final connectionErrorFuture = transport.onConnectionLost;
    if (connectionErrorFuture != null && connectionErrorFuture.isCompleted) {
      final error = await connectionErrorFuture.future;
      errorMessage += ' Underlying error: $error';
    }

    _controller.addError(
      Abort(
        Error.couldNotConnect,
        message: errorMessage,
      ),
    );
    return await disconnect();
  }

  Future<void> _onSessionAbort(
      Abort abort, ClientConnectOptions options) async {
    _logger.shout('Abort reason: ${abort.reason}');
    _controller.addError(abort);

    if (_abortReasons.contains(abort.reason) || options.reconnectTime == null) {
      _logger.info('Disconnecting because of reason received: ${abort.reason}');
      return await disconnect();
    }

    // if the router restarts we should wait until it has been initialized, hence custom duration
    _reconnect(options.minusReconnectRetry(), duration: Duration(seconds: 2));
  }

  Future<void> _onSessionGoodbye(Goodbye goodbye) async {
    _logger.shout('Goodbye reason: ${goodbye.reason}');
    await disconnect();
  }
}

class ClientConnectOptions {
  int reconnectCount;
  Duration? reconnectTime;
  Duration? pingInterval;

  ClientConnectOptions({
    this.reconnectCount = 3,
    this.reconnectTime,
    this.pingInterval,
  });

  ClientConnectOptions minusReconnectRetry() {
    reconnectCount = reconnectCount == -1 ? -1 : reconnectCount - 1;
    return this;
  }
}
