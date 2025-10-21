import 'dart:async';

import 'package:connectanum/src/message/goodbye.dart';
import 'package:logging/logging.dart';

import '../src/message/abort.dart';
import '../src/message/error.dart';

import 'authentication/abstract_authentication.dart';
import 'transport/abstract_transport.dart';
import 'message/uri_pattern.dart';
import 'protocol/session.dart';
import 'network/network_connectivity_stub.dart'
    if (dart.library.io) 'network/network_connectivity_io.dart'
    if (dart.library.js_interop) 'network/network_connectivity_web.dart'
    as connectivity;

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
  final AbstractTransport transport;
  List<AbstractAuthentication>? authenticationMethods;

  final StreamController<Session> _controller = StreamController<Session>();

  // Broadcast stream emitting current online state during waiting periods
  final StreamController<bool> _onlineStateController =
      StreamController<bool>.broadcast();
  StreamSubscription<bool>? _onlineStreamSub;

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
  Client({
    required this.transport,
    this.authId,
    this.authRole,
    this.realm,
    this.authenticationMethods,
    this.authExtra,
    this.isolateCount = 1,
  }) : assert(realm == null || UriPattern.match(realm)) {
    _connectStreamSubscription = _connectStreamController.stream.listen(
      _connect,
    );
  }

  /// if listened to this stream you will be noticed about reconnect tries. The passed
  /// integer will be the current retry counted down from where you started in the configured
  /// [ClientConnectOptions.reconnectCount] passed to the [connect] method. Be aware a zero is passed just
  /// before the [connect] streams [onError] will raise the abort message. So 0 means
  /// that the reconnect failed.
  Stream<ClientConnectOptions> get onNextTryToReconnect =>
      _connectStreamController.stream;

  /// Broadcast stream emitting current online state while the client is waiting
  /// to reconnect (e.g., during network wait or reconnect delay).
  Stream<bool> get onOnlineState => _onlineStateController.stream;

  /// Calling this method will start the authentication process and result into
  /// a [Session] object on success. If a [ClientConnectOptions.pingInterval] is
  /// given and the underlying transport supports sending of ping messages. the
  /// given duration is used by the transport to send ping messages every
  /// [ClientConnectOptions.pingInterval]. [SocketTransport] and
  /// [WebSocketTransport] not within the browser support ping messages. The
  /// browser API does not allow to control ping messages. If
  /// [ClientConnectOptions.reconnectCount] and the
  /// [ClientConnectOptions.reconnectTime] is set the client will try to
  /// reestablish the session. Setting [ClientConnectOptions.reconnectCount] to
  /// -1 will infinite times reconnect the client or until the stack overflows
  Stream<Session> connect({ClientConnectOptions? options}) {
    options ??= ClientConnectOptions();

    _changeState(_ClientState.waiting);

    /// Increment reconnectCount by 1 because we use one for initial connect
    options.reconnectCount = options.reconnectCount == -1
        ? -1
        : options.reconnectCount + 1;
    _connectStreamController.add(options);

    return _controller.stream;
  }

  /// Close connection.
  ///
  /// After calling the method, this instance of Client can no longer be used.
  Future<void> disconnect() async {
    _logger.shout('Disconnecting');
    _changeState(_ClientState.done);
    _stopOnlineTicker();
    await _connectStreamSubscription?.cancel();
    if (!_connectStreamController.isClosed) {
      await _connectStreamController.close();
    }
    if (!_controller.isClosed) {
      await _controller.close();
    }
    if (!_onlineStateController.isClosed) {
      await _onlineStateController.close();
    }
    if (transport.isOpen) {
      await transport.close();
    }
  }

  Future<void> _reconnect(
    ClientConnectOptions options, {
    Duration? duration,
  }) async {
    if (options.reconnectCount == 0 || options.reconnectTime == null) {
      return await _onNoReconnectsLeft('Ran out of reconnect attempts');
    }

    _changeState(_ClientState.waiting);

    // Start online-state ticker during waiting
    _startOnlineTicker(
      options.networkCheckInterval,
      options.connectivityTestAddress,
    );

    try {
      // Optionally wait for network to be online before attempting reconnect
      if (options.waitForNetwork) {
        try {
          final online = await connectivity.NetworkConnectivity.instance
              .isOnline(testAddress: options.connectivityTestAddress);
          if (!online) {
            _logger.info('Network offline detected. Waiting until online...');
            await connectivity.NetworkConnectivity.instance.waitUntilOnline(
              pollInterval: options.networkCheckInterval,
              timeout: options.networkWaitTimeout,
              testAddress: options.connectivityTestAddress,
            );
          }
        } catch (e) {
          _logger.fine('Connectivity check failed: $e');
        }
      }

      if (duration != null) {
        _logger.info('Waiting for (overridden) $duration before reconnecting');
        await Future.delayed(duration);
      } else {
        _logger.info(
          'Waiting for ${options.reconnectTime!} before reconnecting',
        );
        await Future.delayed(options.reconnectTime!);
      }

      // Check in case the client has been closed while we were waiting;
      if (_state == _ClientState.done) return;
      return _connectStreamController.add(options);
    } finally {
      // Stop ticker when leaving waiting phase
      _stopOnlineTicker();
    }
  }

  void _changeState(_ClientState newState) {
    if (_state != newState) {
      _logger.info('Changed state: $_state -> $newState');
    }
    _state = newState;
  }

  void _startOnlineTicker(Duration interval, String? testAddress) {
    _stopOnlineTicker();
    _onlineStreamSub = connectivity.NetworkConnectivity.instance
        .watch(interval: interval, testAddress: testAddress)
        .listen(
          (online) {
            if (!_onlineStateController.isClosed) {
              _onlineStateController.add(online);
            }
          },
          onError: (_) {
            if (!_onlineStateController.isClosed) {
              _onlineStateController.add(false);
            }
          },
        );
  }

  void _stopOnlineTicker() {
    _onlineStreamSub?.cancel();
    _onlineStreamSub = null;
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
          'Please configure reconnectTime to retry automatically',
        );
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

    _controller.addError(Abort(Error.couldNotConnect, message: errorMessage));
    return await disconnect();
  }

  Future<void> _onSessionAbort(
    Abort abort,
    ClientConnectOptions options,
  ) async {
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

  // New options for network-aware reconnect
  bool waitForNetwork;
  Duration networkCheckInterval;
  Duration? networkWaitTimeout;

  /// Host:port to probe when checking connectivity on IO (e.g., 'example.com:80').
  /// If null, a reasonable default will be used by the platform implementation.
  String? connectivityTestAddress;

  ClientConnectOptions({
    this.reconnectCount = 3,
    this.reconnectTime,
    this.pingInterval,
    this.waitForNetwork = false,
    this.networkCheckInterval = const Duration(seconds: 2),
    this.networkWaitTimeout,
    this.connectivityTestAddress,
  });

  ClientConnectOptions minusReconnectRetry() {
    reconnectCount = reconnectCount == -1 ? -1 : reconnectCount - 1;
    return this;
  }
}
