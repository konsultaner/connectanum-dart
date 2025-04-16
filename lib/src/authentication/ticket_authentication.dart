import 'dart:async';

import 'abstract_authentication.dart';
import '../message/authenticate.dart';
import '../message/challenge.dart';
import '../message/details.dart';

/// This is the ticket based authentication implementation for this package.
/// Use it with the [Client].
class TicketAuthentication extends AbstractAuthentication {
  final StreamController<Extra> _challengeStreamController =
      StreamController.broadcast();
  String password;

  TicketAuthentication(this.password);

  /// When the challenge starts the stream will provide the current [Extra] in
  /// case the client needs some additional information to challenge the server.
  @override
  Stream<Extra> get onChallenge => _challengeStreamController.stream;

  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. Since Ticket does not need to modify it. This method returns
  /// a completed future
  @override
  Future<void> hello(String? realm, Details details) {
    return Future.value();
  }

  /// This method is called by the session if the router returns the challenge or
  /// the challenges [extra] respectively. This method only returns the plain
  /// password as a signature.
  @override
  Future<Authenticate> challenge(Extra extra) async {
    await AbstractAuthentication.streamAddAwaited<Extra>(
        _challengeStreamController, extra);
    return Authenticate(signature: password);
  }

  /// This method is called by the session to identify the authentication name.
  @override
  String getName() {
    return 'ticket';
  }
}
