import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

Map<String, dynamic> _profile() => {
  'username': 'alice',
  'display_name': 'Alice',
  'status': '',
  'revision': 0,
  'updated_at': '2026-09-15T12:30:00+02:00',
};

Map<String, dynamic> _update() => {
  'expected_revision': 0,
  'display_name': 'Alice',
  'status': '',
  'avatar_action': 'set',
};

void main() {
  group('registration wire contract', () {
    test(
      'receipt emits exact metadata and normalizes its timestamp to UTC',
      () {
        final receipt = RegistrationReceipt.fromWampKeywords({
          'username': 'alice',
          'display_name': 'Alice',
          'created_at': '2026-09-15T12:30:00+02:00',
        });
        expect(receipt.username, 'alice');
        expect(receipt.displayName, 'Alice');
        expect(receipt.createdAt, DateTime.utc(2026, 9, 15, 10, 30));
        expect(receipt.createdAt.isUtc, isTrue);
        expect(receipt.toWampKeywords(), {
          'username': 'alice',
          'display_name': 'Alice',
          'created_at': '2026-09-15T10:30:00.000Z',
          'realm': 'com.wampapp',
          'auth_method': 'scram',
        });
      },
    );

    test('rejects missing or mistyped receipt fields', () {
      expect(
        () => RegistrationReceipt.fromWampKeywords(null),
        throwsFormatException,
      );
      for (final field in ['username', 'display_name', 'created_at']) {
        for (final value in <Object?>[null, 42]) {
          expect(
            () => RegistrationReceipt.fromWampKeywords({
              'username': 'alice',
              'display_name': 'Alice',
              'created_at': '2026-09-15T10:30:00Z',
              field: value,
            }),
            throwsFormatException,
          );
        }
      }
    });

    test('registration validates each boundary independently', () {
      for (final length in [12, 1024]) {
        final wire = AccountRegistration(
          username: 'a' * 64,
          password: 'p' * length,
          displayName: 'D' * 80,
        ).toWampKeywords();
        expect(wire, {
          'username': 'a' * 64,
          'password': 'p' * length,
          'display_name': 'D' * 80,
        });
      }
      for (final invalid in [
        {'username': 'aa'},
        {'username': 'a' * 65},
        {'username': '.alice'},
        {'display_name': ''},
        {'display_name': ' '},
        {'display_name': 'D' * 81},
        {'password': 'p' * 11},
        {'password': 'p' * 1025},
      ]) {
        expect(
          () => AccountRegistration.fromWampKeywords({
            'username': 'alice',
            'display_name': 'Alice',
            'password': 'p' * 12,
            ...invalid,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => AccountRegistration.fromWampKeywords(null),
        throwsFormatException,
      );
      for (final field in ['username', 'display_name', 'password']) {
        expect(
          () => AccountRegistration.fromWampKeywords({
            'username': 'alice',
            'display_name': 'Alice',
            'password': 'p' * 12,
            field: 42,
          }),
          throwsFormatException,
        );
      }
    });
  });

  group('profile wire contract', () {
    final signatures = <String, List<int>>{
      'image/jpeg': [255, 216, 255],
      'image/png': [137, 80, 78, 71, 13, 10, 26, 10],
      'image/webp': [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80],
    };
    for (final entry in signatures.entries) {
      test('${entry.key} has isolated input and output byte snapshots', () {
        for (final typed in [false, true]) {
          final input = typed
              ? Uint8List.fromList(entry.value)
              : List<int>.of(entry.value);
          final profile = AccountProfile.fromWampKeywords({
            ..._profile(),
            'avatar_bytes': input,
            'avatar_content_type': entry.key,
          });
          expect(profile.hasAvatar, isTrue);
          expect(profile.updatedAt, DateTime.utc(2026, 9, 15, 10, 30));
          input[0] = 0;
          expect(profile.avatarBytes, entry.value);
          final output = profile.toWampKeywords();
          expect(output['avatar_bytes'], entry.value);
          (output['avatar_bytes'] as Uint8List)[0] = 0;
          expect(profile.avatarBytes, entry.value);

          final update = AccountProfileUpdate.fromWampKeywords({
            ..._update(),
            'avatar_bytes': List<int>.of(entry.value),
            'avatar_content_type': entry.key,
          });
          expect(update.avatarAction, ProfileAvatarAction.set);
          final updateWire = update.toWampKeywords();
          expect(updateWire['avatar_bytes'], entry.value);
          (updateWire['avatar_bytes'] as Uint8List)[0] = 0;
          expect(update.avatarBytes, entry.value);
        }
      });

      test(
        '${entry.key} rejects truncation and each required signature byte',
        () {
          for (final length in [0, entry.value.length - 1]) {
            expect(
              () => AccountProfile.fromWampKeywords({
                ..._profile(),
                'avatar_bytes': entry.value.sublist(0, length),
                'avatar_content_type': entry.key,
              }),
              throwsFormatException,
            );
          }
          for (var index = 0; index < entry.value.length; index++) {
            if (entry.key == 'image/webp' && index >= 4 && index <= 7) continue;
            final bytes = List<int>.of(entry.value);
            bytes[index] ^= 1;
            expect(
              () => AccountProfile.fromWampKeywords({
                ..._profile(),
                'avatar_bytes': bytes,
                'avatar_content_type': entry.key,
              }),
              throwsFormatException,
            );
          }
        },
      );
    }

    test('supports no avatar and exact size limit but not oversized lists', () {
      final empty = AccountProfile.fromWampKeywords(_profile());
      expect(empty.hasAvatar, isFalse);
      expect(empty.toWampKeywords().containsKey('avatar_bytes'), isFalse);
      expect(
        empty.toWampKeywords().containsKey('avatar_content_type'),
        isFalse,
      );
      final bytes = List<int>.filled(AccountProfileLimits.maxAvatarBytes, 0);
      bytes.setRange(0, 3, [255, 216, 255]);
      final profile = AccountProfile.fromWampKeywords({
        ..._profile(),
        'avatar_bytes': bytes,
        'avatar_content_type': 'image/jpeg',
      });
      expect(profile.avatarBytes, bytes);
      expect(
        () => AccountProfile.fromWampKeywords({
          ..._profile(),
          'avatar_bytes': [...bytes, 0],
          'avatar_content_type': 'image/jpeg',
        }),
        throwsFormatException,
      );
    });

    test(
      'public constructors enforce the avatar limit without wire decoding',
      () {
        for (final size in [
          AccountProfileLimits.maxAvatarBytes,
          AccountProfileLimits.maxAvatarBytes + 1,
        ]) {
          final bytes = Uint8List(size)..setRange(0, 3, [255, 216, 255]);
          AccountProfile profile() => AccountProfile(
            username: 'alice',
            displayName: 'Alice',
            status: '',
            revision: 0,
            updatedAt: DateTime.utc(2026),
            avatarBytes: bytes,
            avatarContentType: 'image/jpeg',
          );
          AccountProfileUpdate update() => AccountProfileUpdate(
            expectedRevision: 0,
            displayName: 'Alice',
            status: '',
            avatarAction: ProfileAvatarAction.set,
            avatarBytes: bytes,
            avatarContentType: 'image/jpeg',
          );
          if (size == AccountProfileLimits.maxAvatarBytes) {
            expect(profile().avatarBytes, bytes);
            expect(update().avatarBytes, bytes);
          } else {
            expect(profile, throwsFormatException);
            expect(update, throwsFormatException);
          }
        }
      },
    );

    test(
      'wire decoding accepts a full 256 KiB typed avatar, not one byte more',
      () {
        final bytes = Uint8List(262144)..setRange(0, 3, [255, 216, 255]);
        final profile = AccountProfile.fromWampKeywords({
          ..._profile(),
          'avatar_bytes': bytes,
          'avatar_content_type': 'image/jpeg',
        });
        expect(profile.avatarBytes, bytes);
        expect(
          () => AccountProfile.fromWampKeywords({
            ..._profile(),
            'avatar_bytes': Uint8List(262145)..setRange(0, 3, [255, 216, 255]),
            'avatar_content_type': 'image/jpeg',
          }),
          throwsFormatException,
        );
      },
    );

    test('rejects non-binary and unpaired avatar fields', () {
      for (final invalid in <Map<String, dynamic>>[
        {'avatar_bytes': 'bytes', 'avatar_content_type': 'image/jpeg'},
        {
          'avatar_bytes': <double>[255, 216, 255],
          'avatar_content_type': 'image/jpeg',
        },
        {
          'avatar_bytes': <int>[255, 216, 255],
        },
        {'avatar_content_type': 'image/jpeg'},
        {
          'avatar_bytes': <int>[255, 216, 255],
          'avatar_content_type': 'image/gif',
        },
      ]) {
        expect(
          () => AccountProfile.fromWampKeywords({..._profile(), ...invalid}),
          throwsFormatException,
        );
      }
    });

    test(
      'validates normalized names, text, revisions, and required fields',
      () {
        for (final invalid in <Map<String, dynamic>>[
          {'username': 'Alice'},
          {'username': 'ab'},
          {'display_name': ''},
          {'display_name': ' Alice'},
          {'display_name': 'A\u007F'},
          {'display_name': 'A' * 81},
          {'status': 'busy '},
          {'status': 'A\u0000'},
          {'status': 'A' * 281},
          {'revision': -1},
          {'revision': AccountProfileLimits.maxRevision + 1},
          {'updated_at': 42},
          {'updated_at': 'invalid'},
        ]) {
          expect(
            () => AccountProfile.fromWampKeywords({..._profile(), ...invalid}),
            throwsFormatException,
          );
        }
        expect(
          () => AccountProfile.fromWampKeywords(null),
          throwsFormatException,
        );
        for (final field in _profile().keys) {
          expect(
            () => AccountProfile.fromWampKeywords(_profile()..remove(field)),
            throwsFormatException,
          );
        }
        final max = AccountProfile.fromWampKeywords({
          ..._profile(),
          'display_name': 'A' * 80,
          'status': 'S' * 280,
          'revision': AccountProfileLimits.maxRevision,
        });
        expect(max.displayName.length, 80);
        expect(max.status.length, 280);
        expect(max.revision, AccountProfileLimits.maxRevision);
      },
    );

    test('update requires a valid action, fields, and explicit set bytes', () {
      expect(
        () => AccountProfileUpdate.fromWampKeywords(null),
        throwsFormatException,
      );
      for (final field in _update().keys) {
        expect(
          () => AccountProfileUpdate.fromWampKeywords(_update()..remove(field)),
          throwsFormatException,
        );
      }
      for (final action in <Object?>[null, 42, 'unknown']) {
        expect(
          () => AccountProfileUpdate.fromWampKeywords({
            ..._update(),
            'avatar_action': action,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => AccountProfileUpdate.fromWampKeywords(_update()),
        throwsFormatException,
      );
      for (final action in ['keep', 'remove']) {
        final update = AccountProfileUpdate.fromWampKeywords({
          ..._update(),
          'avatar_action': action,
        });
        expect(update.toWampKeywords(), {
          ..._update(),
          'avatar_action': action,
        });
        for (final invalid in [
          {
            'avatar_bytes': <int>[255, 216, 255],
          },
          {'avatar_content_type': 'image/jpeg'},
        ]) {
          expect(
            () => AccountProfileUpdate.fromWampKeywords({
              ..._update(),
              'avatar_action': action,
              ...invalid,
            }),
            throwsFormatException,
          );
        }
      }
    });
  });

  group('malformed account wire values', () {
    for (final timestamp in <Object?>[null, 42, true, [], {}, 'invalid']) {
      test('rejects registration timestamp $timestamp as a format error', () {
        expect(
          () => RegistrationReceipt.fromWampKeywords({
            'username': 'alice',
            'display_name': 'Alice',
            'created_at': timestamp,
          }),
          throwsFormatException,
        );
      });
    }

    for (final entry in <String, dynamic Function(Map<String, dynamic>)>{
      'profile': AccountProfile.fromWampKeywords,
      'update': AccountProfileUpdate.fromWampKeywords,
    }.entries) {
      for (final byte in [-1, 256, 511]) {
        test('${entry.key} rejects out-of-range avatar byte $byte', () {
          final wire = entry.key == 'profile' ? _profile() : _update();
          wire['avatar_content_type'] = 'image/jpeg';
          // A valid header isolates byte validation from image validation.
          wire['avatar_bytes'] = <int>[255, 216, 255, byte];
          expect(() => entry.value(wire), throwsFormatException);
        });
      }
    }
  });
}
