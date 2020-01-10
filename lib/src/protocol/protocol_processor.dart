import 'dart:async';

import 'package:connectanum_dart/src/authentication/abstract_authentication.dart';
import 'package:connectanum_dart/src/message/abstract_message.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/protocol/session.dart';

import 'session_model.dart';

class ProtocolProcessor {
  final Completer<SessionModel> authenticateCompleter = new Completer<SessionModel>();

  ProtocolProcessor() {}

  process(AbstractMessage message, Session session, List<AbstractAuthentication> authenticationStore) async {
    if (message.id == MessageTypes.CODE_GOODBYE) {

    } else if (message.id == MessageTypes.CODE_CANCEL) {

    } else if (message.id == MessageTypes.CODE_ABORT) {

    }
  }
}
