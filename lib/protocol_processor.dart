import 'package:connectanum_dart/src/authentication/abstract_authentication.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/authentication/session.dart';
import 'package:connectanum_dart/src/message/welcome.dart';
import 'package:rxdart/subjects.dart';

import 'src/transport/abstract_transport.dart';

class ProtocolProcessor {

  final messageSubject = new BehaviorSubject<AbstractMessage>();
  final authenticateSubject = new BehaviorSubject<Session>();

  Map<String, AbstractAuthentication> _authenticationStore;
  Session _session;

  ProtocolProcessor(this._authenticationStore) {}

  process(AbstractMessage message) async {
    if (message.id == MessageTypes.CODE_CHALLENGE) {
      if (this._authenticationStore.containsKey((message as Challenge).authMethod)) {
        AbstractAuthentication authentication = this._authenticationStore[(message as Challenge).authMethod];
        Authenticate authenticate = await authentication.challenge((message as Challenge).extra);
        messageSubject.add(authenticate);
      }
    } else if (message.id == MessageTypes.CODE_WELCOME) {
      _session = new Session();
      _session.id = (message as Welcome).sessionId;
      _session.authId = (message as Welcome).details.authid;
      _session.authMethod = (message as Welcome).details.authmethod;
      _session.authProvider = (message as Welcome).details.authprovider;
      _session.authRole = (message as Welcome).details.authrole;
      authenticateSubject.add(_session);
    }
  }
}