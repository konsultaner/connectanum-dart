import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('MCP consent defaults to denied and round-trips updates', () {
    expect(WampAppMcpConsent.denied.profileReadAllowed, isFalse);
    expect(WampAppMcpConsent.denied.revision, 0);
    expect(WampAppMcpConsent.denied.updatedAt, isNull);

    final consent = WampAppMcpConsent(
      profileReadAllowed: true,
      revision: 2,
      updatedAt: DateTime.utc(2026, 8, 25, 12, 30),
    );
    final decoded = WampAppMcpConsent.fromWampKeywords(
      consent.toWampKeywords(),
    );
    expect(decoded.profileReadAllowed, isTrue);
    expect(decoded.revision, 2);
    expect(decoded.updatedAt, DateTime.utc(2026, 8, 25, 12, 30));

    final update = WampAppMcpConsentUpdate(
      expectedRevision: decoded.revision,
      profileReadAllowed: false,
    );
    final decodedUpdate = WampAppMcpConsentUpdate.fromWampKeywords(
      update.toWampKeywords(),
    );
    expect(decodedUpdate.expectedRevision, 2);
    expect(decodedUpdate.profileReadAllowed, isFalse);
  });

  test('MCP consent rejects malformed and inconsistent revisions', () {
    expect(
      () => WampAppMcpConsent.fromWampKeywords({
        'profile_read_allowed': true,
        'revision': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => WampAppMcpConsent.fromWampKeywords({
        'profile_read_allowed': false,
        'revision': 0,
        'updated_at': DateTime.utc(2026).toIso8601String(),
      }),
      throwsFormatException,
    );
    expect(
      () => WampAppMcpConsentUpdate(
        expectedRevision: -1,
        profileReadAllowed: true,
      ),
      throwsFormatException,
    );
  });
}
