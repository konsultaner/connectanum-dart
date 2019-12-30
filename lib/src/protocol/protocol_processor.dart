import 'dart:async';

import 'package:connectanum_dart/src/authentication/abstract_authentication.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/protocol/session.dart';

import 'session_model.dart';
import '../message/error.dart';
import '../message/event.dart';
import '../message/published.dart';
import '../message/registered.dart';
import '../message/invocation.dart';
import '../message/subscribed.dart';
import '../message/unregistered.dart';
import '../message/unsubscribed.dart';

class ProtocolProcessor {
  final Completer<SessionModel> authenticateCompleter = new Completer<SessionModel>();

  ProtocolProcessor() {}

  process(AbstractMessage message, Session session, List<AbstractAuthentication> authenticationStore) async {
    if (message.id == MessageTypes.CODE_SUBSCRIBED) {
      session.subscribes[(message as Subscribed).subscribeRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_UNSUBSCRIBED) {
      session.unsubscribes[(message as Unsubscribed).unsubscribeRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_PUBLISHED) {
      session.publishes[(message as Published).publishRequestId].add(message);
    } else if (message.id == MessageTypes.CODE_EVENT) {
      session.events[(message as Event).subscriptionId].add(message);
    } else if (message.id == MessageTypes.CODE_GOODBYE) {

    } else if (message.id == MessageTypes.CODE_CANCEL) {

    } else if (message.id == MessageTypes.CODE_ABORT) {

    } else if (message.id == MessageTypes.CODE_ERROR) {
      final requestTypeId = (message as Error).requestTypeId;
      final requestId = (message as Error).requestId;
      if (requestTypeId == MessageTypes.CODE_SUBSCRIBED) {
        session.subscribes[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_UNSUBSCRIBED) {
        session.unsubscribes[requestId].addError(message);
      } else if (requestTypeId == MessageTypes.CODE_PUBLISHED) {
        session.publishes[requestId].addError(message);
      }
    }
  }
}
