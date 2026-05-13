import 'dart:async';

import 'package:connectanum_core/src/message/authenticate.dart';
import 'package:connectanum_core/src/message/challenge.dart';
import 'package:connectanum_core/src/message/details.dart';

abstract class AbstractAuthentication {
  /// When the challenge starts the stream will provide the current [Extra] in
  /// case the client needs some additional information to challenge the server.
  Stream<Extra> get onChallenge;

  /// This method is called to modify the hello [details] for a given [realm].
  Future<void> hello(String? realm, Details details);

  /// Called when the router sends a challenge (CHALLENGE frame).
  Future<Authenticate> challenge(Extra extra);

  /// Authentication method name used in HELLO (e.g. 'ticket').
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
      return completer.future.timeout(
        timeout,
        onTimeout: () {
          sub.cancel();
          throw TimeoutException('Timeout while waiting for stream event');
        },
      );
    }

    return completer.future;
  }
}
