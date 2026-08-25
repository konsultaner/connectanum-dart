import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  group('AccountProfile', () {
    test('round-trips bounded binary avatar data', () {
      final profile = AccountProfile(
        username: 'alice',
        displayName: 'Alice Example',
        status: 'Available',
        revision: 7,
        updatedAt: DateTime.utc(2026, 8, 25, 12, 30),
        avatarBytes: _pngHeader,
        avatarContentType: 'image/png',
      );

      final decoded = AccountProfile.fromWampKeywords(profile.toWampKeywords());

      expect(decoded.username, 'alice');
      expect(decoded.displayName, 'Alice Example');
      expect(decoded.status, 'Available');
      expect(decoded.revision, 7);
      expect(decoded.updatedAt, DateTime.utc(2026, 8, 25, 12, 30));
      expect(decoded.avatarBytes, _pngHeader);
      expect(decoded.avatarContentType, 'image/png');
    });

    test(
      'rejects avatar bytes that exceed the shared limit before copying',
      () {
        expect(
          () => AccountProfile.fromWampKeywords({
            'username': 'alice',
            'display_name': 'Alice',
            'status': '',
            'revision': 0,
            'updated_at': DateTime.utc(2026).toIso8601String(),
            'avatar_bytes': Uint8List(AccountProfileLimits.maxAvatarBytes + 1),
            'avatar_content_type': 'image/png',
          }),
          throwsFormatException,
        );
      },
    );

    test(
      'rejects mismatched image signatures and malformed optional fields',
      () {
        expect(
          () => AccountProfile(
            username: 'alice',
            displayName: 'Alice',
            status: '',
            revision: 0,
            updatedAt: DateTime.utc(2026),
            avatarBytes: Uint8List.fromList([0, 1, 2, 3]),
            avatarContentType: 'image/png',
          ),
          throwsFormatException,
        );
        expect(
          () => AccountProfile.fromWampKeywords({
            'username': 'alice',
            'display_name': 'Alice',
            'status': '',
            'revision': 0,
            'updated_at': DateTime.utc(2026).toIso8601String(),
            'avatar_content_type': 42,
          }),
          throwsFormatException,
        );
      },
    );
  });

  group('AccountProfileUpdate', () {
    test('round-trips explicit set and remove avatar actions', () {
      final set = AccountProfileUpdate(
        expectedRevision: 3,
        displayName: 'Alice',
        status: 'In a meeting',
        avatarAction: ProfileAvatarAction.set,
        avatarBytes: _pngHeader,
        avatarContentType: 'image/png',
      );
      final decoded = AccountProfileUpdate.fromWampKeywords(
        set.toWampKeywords(),
      );

      expect(decoded.expectedRevision, 3);
      expect(decoded.avatarAction, ProfileAvatarAction.set);
      expect(decoded.avatarBytes, _pngHeader);

      final remove = AccountProfileUpdate(
        expectedRevision: 4,
        displayName: 'Alice',
        status: '',
        avatarAction: ProfileAvatarAction.remove,
      );
      expect(
        AccountProfileUpdate.fromWampKeywords(
          remove.toWampKeywords(),
        ).avatarAction,
        ProfileAvatarAction.remove,
      );
    });

    test('rejects stale ranges, controls, and data on non-set actions', () {
      expect(
        () => AccountProfileUpdate(
          expectedRevision: -1,
          displayName: 'Alice',
          status: '',
        ),
        throwsFormatException,
      );
      expect(
        () => AccountProfileUpdate(
          expectedRevision: 0,
          displayName: 'Alice',
          status: 'two\nlines',
        ),
        throwsFormatException,
      );
      expect(
        () => AccountProfileUpdate(
          expectedRevision: 0,
          displayName: 'Alice',
          status: '',
          avatarBytes: _pngHeader,
          avatarContentType: 'image/png',
        ),
        throwsFormatException,
      );
    });
  });
}

final _pngHeader = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);
