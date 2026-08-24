import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:pinenacl/ed25519.dart';

import 'abstract_transport.dart';

class LocalTransport extends AbstractTransport {
  final _receiveController = StreamController<AbstractMessage?>.broadcast();
  final _sentMessagesController = StreamController<AbstractMessage>.broadcast();

  final Completer<void> _onReady = Completer<void>();
  final Completer _onDisconnect = Completer<void>();
  final Completer _onConnectionLost = Completer<void>();

  String authenticationPassword;
  late SigningKey authenticationKey;
  Hello? _hello;
  AbstractAuthentication? _authentication;
  String? _signature;
  Extra? _scramChallenge;
  String? _scramClientNonce;
  bool _isOpen = false;

  LocalTransport({
    this.authenticationPassword = "password",
    SigningKey? authenticationKey,
  }) {
    this.authenticationKey =
        authenticationKey ??
        SigningKey.fromSeed(
          Uint8List.fromList("PasswordPasswordPasswordPassword".codeUnits),
        );
  }

  /// Allow tests to listen to what was sent via the transport
  Stream<AbstractMessage> get sentMessages => _sentMessagesController.stream;

  /// Allow tests to inject messages into the receive stream
  void injectIncomingMessage(AbstractMessage message) {
    _receiveController.add(message);
  }

  @override
  Future<void>? close({error}) async {
    _isOpen = false;
    await _authentication?.dispose();
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
      var ticketAuthentication = TicketAuthentication(authenticationPassword);
      var craAuthentication = CraAuthentication(authenticationPassword);
      var scramAuthentication = ScramAuthentication(authenticationPassword);
      var cryptosignAuthentication = CryptosignAuthentication(
        authenticationKey,
        null,
      );
      if (message.details.authmethods?.contains(
            ticketAuthentication.getName(),
          ) ??
          false) {
        var extra = Extra();
        ticketAuthentication.challenge(extra).then((authenticate) {
          _hello = message;
          _signature = authenticate.signature;
          _authentication = ticketAuthentication;
          _receiveController.add(
            Challenge(ticketAuthentication.getName(), extra),
          );
        });
      } else if (message.details.authmethods?.contains(
            craAuthentication.getName(),
          ) ??
          false) {
        var extra = Extra(
          salt: message.details.salt ?? 'salt',
          keyLen: 32,
          iterations: 1000,
          challenge:
              '{"authid":"${message.details.authid}","authrole":"client","authmethod":"${craAuthentication.getName()}","authprovider":"local","nonce":"local","timestamp":"1970-01-01T12:00Z","session":1}',
        );
        craAuthentication.challenge(extra).then((authenticate) {
          _hello = message;
          _signature = authenticate.signature;
          _authentication = craAuthentication;
          _receiveController.add(Challenge(craAuthentication.getName(), extra));
        });
      } else if (message.details.authmethods?.contains(
            scramAuthentication.getName(),
          ) ??
          false) {
        var extra = Extra(
          iterations: 1,
          memory: 100,
          salt: 'AQ==',
          nonce: '${message.details.authextra?['nonce']}AQ==',
          kdf: ScramAuthentication.kdfArgon,
        );
        _hello = message;
        _authentication = scramAuthentication;
        _scramChallenge = extra;
        _scramClientNonce = message.details.authextra?['nonce'] as String?;
        _receiveController.add(Challenge(scramAuthentication.getName(), extra));
      } else if (message.details.authmethods?.contains(
            cryptosignAuthentication.getName(),
          ) ??
          false) {
        var extra = Extra();
        extra.challenge = "11";
        cryptosignAuthentication.challenge(extra).then((authenticate) {
          _hello = message;
          _signature = authenticate.signature;
          _authentication = cryptosignAuthentication;
          _receiveController.add(
            Challenge(cryptosignAuthentication.getName(), extra),
          );
        });
      } else {
        _receiveController.add(
          Welcome(
            1,
            Details.forWelcome(
              authId: _hello?.details.authid,
              authMethod: _authentication?.getName(),
              authProvider: 'local',
              authRole: 'client',
              realm: _hello?.realm,
            ),
          ),
        );
      }
    } else if (message is Authenticate) {
      unawaited(_handleAuthenticate(message));
    }
    _sentMessagesController.add(message);
  }

  Future<void> _handleAuthenticate(Authenticate message) async {
    if (_authentication is ScramAuthentication) {
      final challenge = _scramChallenge;
      final clientNonce = _scramClientNonce;
      final authId = _hello?.details.authid;
      if (challenge == null || clientNonce == null || authId == null) {
        _sendAuthenticationFailure();
        return;
      }
      final authExtra = HashMap<String, Object?>.from(
        message.extra ?? const <String, Object?>{},
      );
      try {
        final secrets = await ScramAuthentication.deriveServerSecretsAsync(
          secret: authenticationPassword,
          salt: challenge.salt!,
          kdf: challenge.kdf!,
          iterations: challenge.iterations!,
          memory: challenge.memory,
        );
        final storedKey = Uint8List.fromList(base64.decode(secrets.storedKey));
        final serverKey = Uint8List.fromList(base64.decode(secrets.serverKey));
        try {
          final authMessage = ScramAuthentication.createAuthMessage(
            authId,
            clientNonce,
            authExtra,
            challenge,
          );
          final proof = base64.decode(message.signature ?? '');
          if (!ScramAuthentication.verifyClientProof(
            proof,
            storedKey,
            authMessage,
          )) {
            _sendAuthenticationFailure();
            return;
          }
          final verifier = ScramAuthentication.createServerSignature(
            serverKey: serverKey,
            authMessage: authMessage,
          );
          _sendWelcome(verifier: verifier);
        } finally {
          storedKey.fillRange(0, storedKey.length, 0);
          serverKey.fillRange(0, serverKey.length, 0);
        }
      } on Object {
        _sendAuthenticationFailure();
      }
      return;
    }

    final supportsAuthentication =
        _authentication is TicketAuthentication ||
        _authentication is CraAuthentication ||
        _authentication is CryptosignAuthentication;
    if (supportsAuthentication && message.signature == _signature) {
      _sendWelcome();
    } else {
      _sendAuthenticationFailure();
    }
  }

  void _sendWelcome({String? verifier}) {
    _receiveController.add(
      Welcome(
        1,
        Details.forWelcome(
          authId: _hello?.details.authid,
          authMethod: _authentication?.getName(),
          authProvider: 'local',
          authRole: 'client',
          realm: _hello?.realm,
          authExtra: verifier == null
              ? null
              : <String, dynamic>{'verifier': verifier},
        ),
      ),
    );
  }

  void _sendAuthenticationFailure() {
    _receiveController.add(
      Abort(
        Error.authorizationFailed,
        message: 'Authentication process failed!',
      ),
    );
  }
}
