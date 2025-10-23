import 'dart:async';

import 'package:connectanum_core/src/message/authenticate.dart';
import 'package:connectanum_core/src/message/challenge.dart';
import 'package:connectanum_core/src/message/details.dart';

import 'abstract_authentication.dart';

/// Ticket-based authentication implementation shared by client and router.
class TicketAuthentication extends AbstractAuthentication {
  TicketAuthentication(this.password);

  final StreamController<Extra> _challengeStreamController =
      StreamController.broadcast();
  String password;

  @override
  Stream<Extra> get onChallenge => _challengeStreamController.stream;

  @override
  Future<void> hello(String? realm, Details details) => Future.value();

  @override
  Future<Authenticate> challenge(Extra extra) async {
    await AbstractAuthentication.streamAddAwaited<Extra>(
      _challengeStreamController,
      extra,
    );
    return Authenticate(signature: password);
  }

  @override
  String getName() => 'ticket';
}
