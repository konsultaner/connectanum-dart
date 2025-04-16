import 'dart:async';

import 'package:connectanum/connectanum.dart';

import '../message/authenticate.dart';

abstract class AbstractAuthentication {
  /// When the challenge starts the stream will provide the current [Extra] in
  /// case the client needs some additional information to challenge the server.
  Stream<Extra> get onChallenge;

  /// This method is called by the session to modify the hello [details] for
  /// a given [realm]. Since Ticket does not need to modify it.
  Future<void> hello(String? realm, Details details);

  /// This method is called by the session if the router returns the challenge or
  /// the challenges [extra] respectively.
  Future<Authenticate> challenge(Extra extra);

  /// This method is called by the session to identify the authentication name.
  String getName();

  static Future<T> streamAddAwaited<T>(
    StreamController<T> streamController,
    T value, {
    bool Function(T event)? predicate,
    Duration? timeout,
  }) {
    final completer = Completer<T>();
    late StreamSubscription<T> sub;

    sub = streamController.stream.listen(
      (event) {
        if (predicate != null) {
          if (predicate(event)) {
            completer.complete(event);
            sub.cancel();
          }
        } else {
          completer.complete(event);
          sub.cancel();
        }
      },
      onError: (e, s) {
        if (!completer.isCompleted) {
          completer.completeError(e, s);
        }
        sub.cancel();
      },
    );

    streamController.add(value);

    if (timeout != null) {
      return completer.future.timeout(timeout, onTimeout: () {
        sub.cancel();
        throw TimeoutException('Timeout while waiting for stream event');
      });
    }

    return completer.future;
  }
}
