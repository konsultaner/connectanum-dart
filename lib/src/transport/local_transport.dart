import 'dart:async';
import 'dart:collection';

import 'package:connectanum/authentication.dart';
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/src/message/hello.dart';
import 'package:connectanum/src/message/welcome.dart';

class LocalTransport extends AbstractTransport {
  final _receiveController = StreamController<AbstractMessage?>.broadcast();
  final _sentMessagesController = StreamController<AbstractMessage>.broadcast();

  final Completer<void> _onReady = Completer<void>();
  final Completer _onDisconnect = Completer<void>();
  final Completer _onConnectionLost = Completer<void>();

  String authenticationPassword;
  Hello? _hello;
  AbstractAuthentication? _authentication;
  String? _signature;
  bool _isOpen = false;

  LocalTransport({this.authenticationPassword = "password"});

  /// Allow tests to listen to what was sent via the transport
  Stream<AbstractMessage> get sentMessages => _sentMessagesController.stream;

  /// Allow tests to inject messages into the receive stream
  void injectIncomingMessage(AbstractMessage message) {
    _receiveController.add(message);
  }

  @override
  Future<void>? close({error}) async {
    _isOpen = false;
    _receiveController.close();
    _sentMessagesController.close();
    if (!_onDisconnect.isCompleted) _onDisconnect.complete();
    if (!_onConnectionLost.isCompleted) _onConnectionLost.complete();
  }

  @override
  bool get isOpen => _isOpen;

  @override
  bool get isReady => _isOpen;

  @override
  Completer get onConnectionLost => _onConnectionLost;

  @override
  Completer get onDisconnect => _onDisconnect;

  @override
  Future<void> get onReady => _onReady.future;

  @override
  Future<void>? open({Duration? pingInterval}) async {
    _isOpen = true;
    if (!_onReady.isCompleted) _onReady.complete();
  }

  @override
  Stream<AbstractMessage?> receive() {
    return _receiveController.stream;
  }

  @override
  void send(AbstractMessage message) {
    if (message is Hello) {
      var craAuthentication = CraAuthentication(authenticationPassword);
      var scramAuthentication = ScramAuthentication(authenticationPassword);
      if (message.details.authmethods?.contains(craAuthentication.getName()) ?? false) {
        var extra = Extra(
            salt: message.details.salt ?? 'salt',
            keyLen: 32,
            iterations: 1000,
            challenge: '{"authid":"${message.details.authid}","authrole":"client","authmethod":"${craAuthentication.getName()}","authprovider":"local","nonce":"local","timestamp":"1970-01-01T12:00Z","session":1}'
        );
        craAuthentication.challenge(extra).then((authenticate) {
          _hello = message;
          _signature = authenticate.signature;
          _authentication = craAuthentication;
          _receiveController.add(Challenge(craAuthentication.getName(), extra));
        });
      } else if (message.details.authmethods?.contains(scramAuthentication.getName()) ?? false) {
        var extra = Extra(
            iterations: 1,
            memory: 100,
            salt: 'AQ==',
            nonce: '${message.details.authextra?['nonce']}AQ==',
            kdf: ScramAuthentication.kdfArgon);
        var authExtra = HashMap<String, Object?>();
        authExtra['nonce'] = extra.nonce;
        authExtra['channel_binding'] = null;
        authExtra['cbind_data'] = null;
        _hello = message;
        _authentication = scramAuthentication;
        _signature = scramAuthentication.createSignature(
            message.details.authid ?? '',
            message.details.authextra?['nonce'],
            extra,
            authExtra);
        _receiveController.add(Challenge(scramAuthentication.getName(), extra));
      } else {
        _receiveController.add(Welcome(1, Details.forWelcome(
          authId: _hello?.details.authid,
          authMethod: _authentication?.getName(),
          authProvider: 'local',
          authRole: 'client',
          realm: _hello?.realm,
        )));
      }
    } else if (message is Authenticate) {
      bool success = false;
      if (_authentication is CraAuthentication) {
        success = message.signature == _signature;
      }
      if (_authentication is ScramAuthentication) {
        success = message.signature == _signature;
      }
      if (success) {
        _receiveController.add(Welcome(1, Details.forWelcome(
          authId: _hello?.details.authid,
          authMethod: _authentication?.getName(),
          authProvider: 'local',
          authRole: 'client',
          realm: _hello?.realm,
        )));
      } else {
        _receiveController.add(Abort("Wrong password", message: "Authentication process failed!"));
      }
    }
    _sentMessagesController.add(message);
  }
}
