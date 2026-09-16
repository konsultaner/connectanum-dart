import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

Map<String, dynamic> _receipt() => {
  'message_id': 'm' * 16,
  'attachment_id': 'a' * 16,
  'chunk_index': 0,
  'ciphertext_sha256': 'AB' * 32,
  'duplicate': false,
  'complete': false,
};

Map<String, dynamic> _status() => {
  'message_id': 'm' * 16,
  'attachment_id': 'a' * 16,
  'chunk_count': 2,
  'received_chunks': <int>[0],
  'complete': false,
};

void main() {
  group('attachment receipt', () {
    for (final duplicate in [false, true]) {
      for (final complete in [false, true]) {
        test('preserves duplicate=$duplicate and complete=$complete', () {
          final receipt = AttachmentChunkReceipt.fromWampKeywords({
            ..._receipt(),
            'duplicate': duplicate,
            'complete': complete,
          });
          expect(receipt.messageId, 'm' * 16);
          expect(receipt.attachmentId, 'a' * 16);
          expect(receipt.chunkIndex, 0);
          expect(receipt.ciphertextSha256, 'AB' * 32);
          expect(receipt.duplicate, duplicate);
          expect(receipt.complete, complete);
          expect(receipt.toWampKeywords(), {
            ..._receipt(),
            'ciphertext_sha256': 'ab' * 32,
            'duplicate': duplicate,
            'complete': complete,
          });
        });
      }
    }

    test('rejects missing, mistyped, and invalid fields independently', () {
      expect(
        () => AttachmentChunkReceipt.fromWampKeywords(null),
        throwsFormatException,
      );
      for (final field in _receipt().keys) {
        for (final invalid in <Object?>[null, [], {}]) {
          expect(
            () => AttachmentChunkReceipt.fromWampKeywords({
              ..._receipt(),
              field: invalid,
            }),
            throwsFormatException,
          );
        }
      }
      for (final invalid in <Map<String, dynamic>>[
        {'message_id': 'm' * 15},
        {'message_id': 'm' * 129},
        {'message_id': '!' * 16},
        {'attachment_id': 'a' * 15},
        {'attachment_id': 'a' * 129},
        {'chunk_index': -1},
        {'chunk_index': 0.5},
        {'ciphertext_sha256': 'a' * 63},
        {'ciphertext_sha256': 'a' * 65},
        {'ciphertext_sha256': 'z' * 64},
        {'duplicate': 0},
        {'complete': 'false'},
      ]) {
        expect(
          () => AttachmentChunkReceipt.fromWampKeywords({
            ..._receipt(),
            ...invalid,
          }),
          throwsFormatException,
        );
      }
    });
  });

  group('attachment upload status', () {
    test('snapshots sorted indexes and computes exact completion', () {
      final indexes = <int>[0];
      final status = AttachmentUploadStatus.fromWampKeywords({
        ..._status(),
        'received_chunks': indexes,
      });
      indexes.add(1);
      expect(status.receivedChunks, [0]);
      expect(status.complete, isFalse);
      expect(() => status.receivedChunks.add(1), throwsUnsupportedError);
      expect(status.toWampKeywords(), _status());
      final complete = AttachmentUploadStatus.fromWampKeywords({
        ..._status(),
        'received_chunks': [0, 1],
        'complete': true,
      });
      expect(complete.complete, isTrue);
      expect(complete.toWampKeywords()['received_chunks'], [0, 1]);
      expect(complete.toWampKeywords()['complete'], isTrue);
    });

    test('rejects untrusted ordering, bounds, completion, and field types', () {
      expect(
        () => AttachmentUploadStatus.fromWampKeywords(null),
        throwsFormatException,
      );
      for (final invalid in <Map<String, dynamic>>[
        {'received_chunks': null},
        {'received_chunks': '0'},
        {
          'received_chunks': [0, '1'],
        },
        {
          'received_chunks': [-1],
        },
        {
          'received_chunks': [2],
        },
        {
          'received_chunks': [0, 0],
        },
        {
          'received_chunks': [1, 0],
        },
        {
          'received_chunks': [0, 1],
          'complete': false,
        },
        {'chunk_count': 0},
        {'chunk_count': WampAppAttachmentLimits.maxChunkCount + 1},
        {'chunk_count': '2'},
        {'complete': 1},
        {'complete': true},
      ]) {
        expect(
          () => AttachmentUploadStatus.fromWampKeywords({
            ..._status(),
            ...invalid,
          }),
          throwsFormatException,
        );
      }
    });
  });
}
