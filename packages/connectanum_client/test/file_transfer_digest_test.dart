import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_client/src/file/file_transfer_digest.dart';
import 'package:connectanum_client/src/file/file_transfer_digest_stub.dart'
    as portable;
import 'package:test/test.dart';

const _emptySha =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const _abcSha =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

void main() {
  group('portable file digest', () {
    test('empty digest is stable after finish and abort', () {
      final digest = DartFileTransferDigest();
      expect(digest.finish(), _emptySha);
      expect(digest.finish(), _emptySha);
      digest.abort();
      expect(digest.finish(), _emptySha);
      expect(() => digest.add(Uint8List(0)), throwsStateError);
    });

    test('chunk boundaries, empty chunks and views preserve SHA-256', () {
      final digest = DartFileTransferDigest();
      final buffer = Uint8List.fromList(ascii.encode('!abc?'));
      digest.add(Uint8List.sublistView(buffer, 1, 2));
      digest.add(Uint8List(0));
      digest.add(
        Uint8List.sublistView(buffer, 2, 4),
        anchor: buffer,
        consumeNativeOwnership: true,
      );
      expect(digest.finish(), _abcSha);
      expect(buffer, ascii.encode('!abc?'));
      expect(() => digest.add(Uint8List.fromList([100])), throwsStateError);
      expect(digest.finish(), _abcSha);
    });

    test('abort is idempotent and permanently rejects further chunks', () {
      final digest = DartFileTransferDigest();
      digest.add(Uint8List.fromList(ascii.encode('abc')));
      digest.abort();
      digest.abort();
      expect(() => digest.add(Uint8List(0)), throwsStateError);
      expect(() => digest.add(Uint8List.fromList([100])), throwsStateError);
      final next = DartFileTransferDigest();
      expect(next.finish(), _emptySha);
    });

    test('independent transfers do not mix interleaved chunks', () {
      final first = DartFileTransferDigest();
      final second = DartFileTransferDigest();
      first.add(Uint8List.fromList([97]));
      second.add(Uint8List.fromList(ascii.encode('he')));
      first.add(Uint8List.fromList([98, 99]));
      second.add(Uint8List.fromList(ascii.encode('llo')));
      expect(
        second.finish(),
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
      expect(first.finish(), _abcSha);
    });

    test('hex encoding preserves leading zeroes and uses lowercase', () {
      expect(
        encodeSha256Digest(Uint8List.fromList([0, 1, 15, 16, 128, 254, 255])),
        '00010f1080feff',
      );
    });

    for (final allowNative in [false, true]) {
      test('portable factory and release helpers allowNative=$allowNative', () {
        final anchor = Object();
        final bytes = Uint8List.fromList(ascii.encode('abc'));
        final digest = portable.createFileTransferDigest(
          anchor: anchor,
          allowNative: allowNative,
        );
        digest.add(bytes, anchor: anchor, consumeNativeOwnership: true);
        expect(digest.finish(), _abcSha);
        expect(portable.nativeFileChunkBytes(anchor), isNull);
        expect(portable.nativeFileChunkBytes(null), isNull);
        expect(portable.releaseNativeFileChunkMessage(anchor), isFalse);
        expect(portable.releaseNativeFileChunkMessage(null), isFalse);
        expect(portable.releaseNativeFileChunkBytes(bytes), isFalse);
        expect(bytes, ascii.encode('abc'));
      });
    }
  });
}
