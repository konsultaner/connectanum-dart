import 'package:connectanum_dart/src/authentication/abstract_authentication.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/authentication/session.dart';
import 'package:connectanum_dart/src/message/welcome.dart';
import 'package:rxdart/subjects.dart';

import 'src/message/error.dart';
import 'src/message/event.dart';
import 'src/message/published.dart';
import 'src/message/registered.dart';
import 'src/message/result.dart';
import 'src/message/invocation.dart';
import 'src/message/subscribed.dart';
import 'src/message/unregistered.dart';
import 'src/message/unsubscribed.dart';

class ProtocolProcessor {
  final messageSubject = new BehaviorSubject<AbstractMessage>();
  final authenticateSubject = new BehaviorSubject<Session>();

  final Map<String, AbstractAuthentication> _authenticationStore;
  Session _session;

  ProtocolProcessor(this._authenticationStore) {}

  process(AbstractMessage message) async {
    if (message.id == MessageTypes.CODE_CHALLENGE) {
      if (this
          ._authenticationStore
          .containsKey((message as Challenge).authMethod)) {
        AbstractAuthentication authentication =
            this._authenticationStore[(message as Challenge).authMethod];
        Authenticate authenticate =
            await authentication.challenge((message as Challenge).extra);
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
    } else if (message.id == MessageTypes.CODE_REGISTERED) {
      _session.registers[(message as Registered).registerRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_UNREGISTERED) {
      _session.unregisters[(message as Unregistered).unregisterRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_SUBSCRIBED) {
      _session.subscribes[(message as Subscribed).subscribeRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_UNSUBSCRIBED) {
      _session.unsubscribes[(message as Unsubscribed).unsubscribeRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_INVOCATION) {
      _session.invocations[(message as Invocation).registrationId].add(message);
    } else if (message.id == MessageTypes.CODE_PUBLISHED) {
      _session.publishes[(message as Published).publishRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_RESULT) {
      _session.calls[(message as Result).callRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_EVENT) {
      _session.events[(message as Event).subscriptionId].add(message);
    } else if (message.id == MessageTypes.CODE_GOODBYE) {

    } else if (message.id == MessageTypes.CODE_CANCEL) {

    } else if (message.id == MessageTypes.CODE_ABORT) {

    } else if (message.id == MessageTypes.CODE_ERROR) {
      final requestTypeId = (message as Error).requestTypeId;
      final requestId = (message as Error).requestId;
      if (requestTypeId == MessageTypes.CODE_REGISTERED) {
        _session.registers[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNREGISTERED) {
        _session.unregisters[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_SUBSCRIBED) {
        _session.subscribes[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNSUBSCRIBED) {
        _session.unsubscribes[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNSUBSCRIBED) {
        _session.publishes[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNSUBSCRIBED) {
        _session.calls[requestId].addError(message);
      }
    }
  }
}
