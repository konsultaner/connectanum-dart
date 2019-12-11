import 'package:connectanum_dart/src/authentication/abstract_authentication.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/authenticate.dart';
import 'package:connectanum_dart/src/message/challenge.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/protocol/session.dart';
import 'package:connectanum_dart/src/message/welcome.dart';
import 'package:rxdart/subjects.dart';

import 'session_model.dart';
import '../message/error.dart';
import '../message/event.dart';
import '../message/published.dart';
import '../message/registered.dart';
import '../message/result.dart';
import '../message/invocation.dart';
import '../message/subscribed.dart';
import '../message/unregistered.dart';
import '../message/unsubscribed.dart';

class ProtocolProcessor {
  final BehaviorSubject<AbstractMessage> messageSubject = new BehaviorSubject<AbstractMessage>();
  final BehaviorSubject<SessionModel> authenticateSubject = new BehaviorSubject<SessionModel>();

  ProtocolProcessor() {}

  process(AbstractMessage message, Session session, List<AbstractAuthentication> authenticationStore) async {
    if (message.id == MessageTypes.CODE_CHALLENGE) {
      final AbstractAuthentication foundAuthMethod = authenticationStore.where((authenticationMethod) => authenticationMethod.getName() == (message as Challenge).authMethod).first;
      if (foundAuthMethod != null) {
        Authenticate authenticate = await foundAuthMethod.challenge((message as Challenge).extra);
        messageSubject.add(authenticate);
      }
    } else if (message.id == MessageTypes.CODE_WELCOME) {
      final sessionData = new SessionModel();
      sessionData.id = (message as Welcome).sessionId;
      sessionData.authId = (message as Welcome).details.authid;
      sessionData.authMethod = (message as Welcome).details.authmethod;
      sessionData.authProvider = (message as Welcome).details.authprovider;
      sessionData.authRole = (message as Welcome).details.authrole;
      authenticateSubject.add(sessionData);
    } else if (message.id == MessageTypes.CODE_REGISTERED) {
      session.registers[(message as Registered).registerRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_UNREGISTERED) {
      session.unregisters[(message as Unregistered).unregisterRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_SUBSCRIBED) {
      session.subscribes[(message as Subscribed).subscribeRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_UNSUBSCRIBED) {
      session.unsubscribes[(message as Unsubscribed).unsubscribeRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_INVOCATION) {
      session.invocations[(message as Invocation).registrationId].add(message);
    } else if (message.id == MessageTypes.CODE_PUBLISHED) {
      session.publishes[(message as Published).publishRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_RESULT) {
      session.calls[(message as Result).callRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_EVENT) {
      session.events[(message as Event).subscriptionId].add(message);
    } else if (message.id == MessageTypes.CODE_GOODBYE) {

    } else if (message.id == MessageTypes.CODE_CANCEL) {

    } else if (message.id == MessageTypes.CODE_ABORT) {

    } else if (message.id == MessageTypes.CODE_ERROR) {
      final requestTypeId = (message as Error).requestTypeId;
      final requestId = (message as Error).requestId;
      if (requestTypeId == MessageTypes.CODE_REGISTERED) {
        session.registers[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNREGISTERED) {
        session.unregisters[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_SUBSCRIBED) {
        session.subscribes[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNSUBSCRIBED) {
        session.unsubscribes[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNSUBSCRIBED) {
        session.publishes[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNSUBSCRIBED) {
        session.calls[requestId].addError(message);
      }
    }
  }
}
