import 'package:connectanum_client/connectanum.dart' as wamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('classifies WAMP message-send failures without exposing payloads', () {
    MessageSendException classified(String? uri) =>
        MessageSendException.fromWampError(wamp.Error(48, 1, const {}, uri));

    expect(
      classified(WampAppProtocol.errorMessageConflict).kind,
      MessageSendFailureKind.conflict,
    );
    expect(
      classified(WampAppProtocol.errorInvalidMessage).kind,
      MessageSendFailureKind.rejected,
    );
    expect(
      classified(wamp.Error.notAuthorized).kind,
      MessageSendFailureKind.rejected,
    );
    expect(
      classified(WampAppProtocol.errorMessageUnavailable).kind,
      MessageSendFailureKind.retryable,
    );
    expect(
      classified('com.example.unknown').kind,
      MessageSendFailureKind.retryable,
    );
    expect(
      classified(null).toString(),
      'Message delivery is temporarily unavailable.',
    );
  });
}
