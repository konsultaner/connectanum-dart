import 'dart:async';

import 'package:connectanum/src/message/goodbye.dart';
import 'package:logging/logging.dart';
import 'package:pedantic/pedantic.dart';

import '../src/message/abort.dart';
import '../src/message/error.dart';

import 'authentication/abstract_authentication.dart';
import 'transport/abstract_transport.dart';
import 'message/uri_pattern.dart';
import 'protocol/session.dart';

class Client {
  static final Logger _logger = Logger('Client');

  String? authId;
  String? realm;
  int isolateCount;
  final StreamController<ClientConnectOptions> _reconnectStreamController =
      StreamController<ClientConnectOptions>();
  AbstractTransport transport;
  List<AbstractAuthentication>? authenticationMethods;

  int _reconnectCount = 3;
  final StreamController<Session> _controller = StreamController<Session>();

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
      required this.realm,
      this.authenticationMethods,
      this.isolateCount = 1})
      : assert(transport != null),
        assert(realm == null || UriPattern.match(realm));

  /// if listened to this stream you will be noticed about reconnect tries. The passed
  /// integer will be the current retry counted down from where you started in the configured
  /// [reconnectCount] passed to the [connect] method. Be aware a zero is passed just
  /// before the [connect] streams [onError] will raise the abort message. So 0 means
  /// that the reconnect failed.
  Stream<ClientConnectOptions> get onNextTryToReconnect =>
      _reconnectStreamController.stream;

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
    _reconnectCount = options.reconnectCount;
    _connect(options);
    return _controller.stream;
  }

  void _connect(ClientConnectOptions options) async {
    await transport.open(pingInterval: options.pingInterval);
    if (transport.isOpen == true) {
      unawaited(transport.onConnectionLost.future.then((_) async {
        if(options.reconnectTime != null) await Future.delayed(options.reconnectTime as Duration);
        options.reconnectCount = _reconnectCount;
        _reconnectStreamController.add(options);
        _connect(options);
      }));
      try {
        var session = await Session.start(realm as String, transport,
            authId: authId,
            authMethods: authenticationMethods,
            reconnect: options.reconnectTime);
        _controller.add(session);
      } on Abort catch (abort) {
        if (abort.reason != Error.NOT_AUTHORIZED &&
            options.reconnectTime != null) {
          // if the router restarts we should wait until it has been initialized
          await Future.delayed(Duration(seconds: 2));
          options.reconnectCount = 0;
          _connect(options);
        } else {
          _controller.addError(abort);
        }
      } on Goodbye catch (goodbye) {
        _logger.shout(goodbye.reason);
        unawaited(_controller.close());
      }
    } else {
      if (options.reconnectTime != null &&
          transport.onConnectionLost.isCompleted == true) {
        _reconnectStreamController.add(options);
        if (options.reconnectCount == 0) {
          _controller.addError(Abort(Error.AUTHORIZATION_FAILED,
              message:
                  'Could not connect to server. Please configure reconnectTime to retry automatically.'));
        } else {
          if(options.reconnectTime != null) await Future.delayed(options.reconnectTime as Duration);
          options.reconnectCount =
              options.reconnectCount == -1 ? -1 : options.reconnectCount - 1;
          _connect(options);
        }
      } else {
        _controller.addError(Abort(Error.AUTHORIZATION_FAILED,
            message:
                'Could not connect to server. Please configure reconnectTime to retry automatically.'));
      }
    }
  }
}

class ClientConnectOptions {
  int reconnectCount;
  Duration? reconnectTime;
  Duration? pingInterval;

  ClientConnectOptions(
      {this.reconnectCount = 3, this.reconnectTime, this.pingInterval});
}
