import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:test/test.dart';

const _sha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

Map<String, dynamic> _wireMetadata() => {
  'version': 1,
  'name': 'data.bin',
  'size': 3,
  'chunk_size': 2,
};

WampFileMetadata _validMetadata(WampFileMetadata Function() create) {
  late WampFileMetadata metadata;
  expect(() => metadata = create(), returnsNormally);
  return metadata;
}

void main() {
  group('file metadata contract', () {
    test('round trip retains optional values and snapshots custom fields', () {
      final custom = <String, dynamic>{'category': 'document', 'revision': 3};
      final wire = _wireMetadata()
        ..['content_type'] = 'application/octet-stream'
        ..['sha256'] = _sha.toUpperCase()
        ..['custom'] = custom;
      final metadata = _validMetadata(() => WampFileMetadata.fromJson(wire));
      expect(metadata.name, 'data.bin');
      expect(metadata.size, 3);
      expect(metadata.chunkSize, 2);
      expect(metadata.contentType, 'application/octet-stream');
      expect(metadata.sha256Digest, _sha.toUpperCase());
      expect(metadata.custom, {'category': 'document', 'revision': 3});
      custom['category'] = 'changed';
      expect(metadata.custom['category'], 'document');
      expect(() => metadata.custom['extra'] = true, throwsUnsupportedError);
      expect(metadata.toJson(), {
        ..._wireMetadata(),
        'content_type': 'application/octet-stream',
        'sha256': _sha,
        'custom': {'category': 'document', 'revision': 3},
      });
    });

    test('absent optional fields stay absent and custom is immutable', () {
      final metadata = _validMetadata(
        () => WampFileMetadata.fromJson(_wireMetadata()),
      );
      expect(metadata.contentType, isNull);
      expect(metadata.sha256Digest, isNull);
      expect(metadata.custom, isEmpty);
      expect(() => metadata.custom['key'] = 1, throwsUnsupportedError);
      expect(metadata.toJson(), _wireMetadata());
    });

    test(
      'constructor copies caller custom map without dropping its values',
      () {
        final custom = <String, dynamic>{'kind': 'sample'};
        final metadata = _validMetadata(
          () => WampFileMetadata(
            name: 'x',
            size: 0,
            chunkSize: 1,
            custom: custom,
          ),
        );
        custom.clear();
        expect(metadata.custom, {'kind': 'sample'});
        expect(metadata.toJson()['custom'], {'kind': 'sample'});
        expect(() => metadata.custom.clear(), throwsUnsupportedError);
      },
    );

    for (final version in [null, 0, 2, -1, '1', true]) {
      test('rejects unsupported version $version', () {
        final wire = _wireMetadata()..['version'] = version;
        expect(
          () => WampFileMetadata.fromJson(wire),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Unsupported file metadata version',
            ),
          ),
        );
      });
    }

    for (final custom in <Object>['value', 1, false, <Object>[]]) {
      test('rejects non-object custom ${custom.runtimeType}', () {
        final wire = _wireMetadata()..['custom'] = custom;
        expect(
          () => WampFileMetadata.fromJson(wire),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'File metadata custom must be an object',
            ),
          ),
        );
      });
    }

    test('rejects non-string custom keys instead of dropping them', () {
      final wire = _wireMetadata()..['custom'] = {1: 'value'};
      expect(() => WampFileMetadata.fromJson(wire), throwsA(isA<TypeError>()));
    });

    for (final field in ['name', 'size', 'chunk_size']) {
      test('rejects missing required field $field', () {
        final wire = _wireMetadata()..remove(field);
        expect(() => WampFileMetadata.fromJson(wire), throwsArgumentError);
      });
    }

    for (final (field, value) in <(String, Object)>[
      ('name', 123),
      ('size', '3'),
      ('size', 3.5),
      ('chunk_size', '2'),
      ('content_type', 1),
      ('sha256', 123),
    ]) {
      test('rejects wrong type $field=$value', () {
        final wire = _wireMetadata()..[field] = value;
        expect(
          () => WampFileMetadata.fromJson(wire),
          throwsA(isA<TypeError>()),
        );
      });
    }

    for (final name in ['', 'x' * 1025, 'bad\u0000name']) {
      test('rejects unsafe name length=${name.length}', () {
        expect(
          () => WampFileMetadata(name: name, size: 0, chunkSize: 1),
          throwsArgumentError,
        );
      });
    }

    for (final (field, value) in <(String, Object)>[
      ('name', ''),
      ('name', 'unsafe\u0000name'),
      ('size', -1),
      ('chunk_size', 0),
      ('content_type', ''),
      ('sha256', 'invalid-hex'),
    ]) {
      test('wire metadata rejects invalid value $field=$value', () {
        final wire = _wireMetadata()..[field] = value;
        expect(() => WampFileMetadata.fromJson(wire), throwsArgumentError);
      });
    }
    test('accepts inclusive name/content-type bounds and empty file', () {
      final metadata = _validMetadata(
        () => WampFileMetadata(
          name: 'x' * 1024,
          size: 0,
          chunkSize: 1,
          contentType: 'x' * 255,
        ),
      );
      expect(metadata.toJson(), {
        'version': 1,
        'name': 'x' * 1024,
        'size': 0,
        'chunk_size': 1,
        'content_type': 'x' * 255,
      });
    });
    test('rejects negative size', () {
      expect(
        () => WampFileMetadata(name: 'x', size: -1, chunkSize: 1),
        throwsRangeError,
      );
    });
    for (final chunkSize in [0, -1]) {
      test('rejects chunk size $chunkSize', () {
        expect(
          () => WampFileMetadata(name: 'x', size: 0, chunkSize: chunkSize),
          throwsRangeError,
        );
      });
    }
    for (final type in ['', 'x' * 256]) {
      test('rejects content type length=${type.length}', () {
        expect(
          () => WampFileMetadata(
            name: 'x',
            size: 0,
            chunkSize: 1,
            contentType: type,
          ),
          throwsArgumentError,
        );
      });
    }
    for (final digest in ['', '0' * 63, '0' * 65, 'g' * 64]) {
      test('rejects non-SHA256 value length=${digest.length}', () {
        expect(
          () => WampFileMetadata(
            name: 'x',
            size: 0,
            chunkSize: 1,
            sha256Digest: digest,
          ),
          throwsArgumentError,
        );
      });
    }

    test(
      'byte source retains its metadata and streams exact binary content',
      () async {
        final bytes = Uint8List.fromList([0, 128, 255]);
        final source = WampFileSource.bytes(
          bytes,
          name: 'data.bin',
          contentType: 'application/octet-stream',
          sha256Digest: _sha,
          custom: {'category': 'binary'},
        );
        expect(source.name, 'data.bin');
        expect(source.length, 3);
        expect(source.contentType, 'application/octet-stream');
        expect(source.sha256Digest, _sha);
        expect(source.custom, {'category': 'binary'});
        expect(source.nativePath, isNull);
        expect(source.openReadChunks, isNull);
        expect(await source.openRead().toList(), [
          [0, 128, 255],
        ]);
      },
    );

    test(
      'receipt reports received bytes rather than declared metadata size',
      () {
        final receipt = WampFileReceipt(
          metadata: _validMetadata(
            () => WampFileMetadata(name: 'x', size: 4, chunkSize: 2),
          ),
          receivedBytes: 3,
          sha256Digest: _sha,
        );
        expect(receipt.toJson(), {'name': 'x', 'size': 3, 'sha256': _sha});
      },
    );

    test('transfer exception exposes its diagnostic message', () {
      const error = WampFileTransferException('truncated stream');
      expect(error.message, 'truncated stream');
      expect(error.toString(), 'WampFileTransferException: truncated stream');
    });
  });
}
