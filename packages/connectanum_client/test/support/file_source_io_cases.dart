part of '../file_transfer_test.dart';

void _fileSourceIoCases() {
  group('IO file source buffer ownership', () {
    test(
      'real file chunks stay stable after later reads and a reopen',
      () async {
        const size = 4 * 1024 * 1024;
        final directory = await Directory.systemTemp.createTemp(
          'wamp-owned-file-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/source.bin');
        final writer = await file.open(mode: FileMode.write);
        try {
          await writer.writeFrom(Uint8List(size)..fillRange(0, size, 17));
          await writer.writeFrom(Uint8List(size)..fillRange(0, size, 93));
          await writer.writeFrom(Uint8List.fromList([201, 202, 203]));
        } finally {
          await writer.close();
        }
        final source = await wampFileSourceFromPath(file.path);
        final chunks = await source.openReadChunks!(size).toList();
        expect(chunks.map((chunk) => chunk.length), [size, size, 3]);
        expect(chunks[0], everyElement(17));
        expect(chunks[1], everyElement(93));
        expect(chunks[2], [201, 202, 203]);
        final reopened = await source.openReadChunks!(size).toList();
        reopened[0].fillRange(0, size, 0);
        expect(chunks[0], everyElement(17));
        expect(chunks[1], everyElement(93));
        expect(chunks[2], [201, 202, 203]);
      },
    );

    test(
      'complete reads keep owned storage and independent later chunks',
      () async {
        const size = 4 * 1024 * 1024;
        final file = _ReadFixtureFile([
          Uint8List(size)..[0] = 41,
          Uint8List(size)..[0] = 73,
        ]);
        await IOOverrides.runZoned(() async {
          final source = await wampFileSourceFromPath(file.path);
          final chunks = await source.openReadChunks!(size).toList();
          expect(chunks.map((chunk) => chunk.length), [size, size]);
          final opened = file.opened.single;
          expect(chunks[0], same(opened.returned[0]));
          expect(chunks[1], same(opened.returned[1]));
          expect(opened.copiedBytes, 0);
          chunks[0][0] = 99;
          expect(chunks[1][0], 73);
          expect(opened.closeCalls, 1);
        }, createFile: (_) => file);
      },
    );

    for (final pieces in <List<List<int>>>[
      [],
      [
        [1],
      ],
      [
        [1],
        [2, 3, 4],
      ],
      [
        [1],
        [2, 3],
        [4],
        [5, 6],
        [7],
        [8, 9],
      ],
    ]) {
      test('assembles short reads $pieces and reopens the source', () async {
        final file = _ReadFixtureFile(pieces.map(Uint8List.fromList).toList());
        await IOOverrides.runZoned(() async {
          final source = await wampFileSourceFromPath(file.path);
          for (var repetition = 0; repetition < 2; repetition++) {
            final chunks = await source.openReadChunks!(4).toList();
            final expected = pieces.expand((piece) => piece).toList();
            expect(chunks.expand((chunk) => chunk), expected);
            expect(
              chunks.every((chunk) => chunk.isNotEmpty && chunk.length <= 4),
              isTrue,
            );
            expect(
              chunks
                  .take(chunks.length - (chunks.isEmpty ? 0 : 1))
                  .every((chunk) => chunk.length == 4),
              isTrue,
            );
            expect(file.opened.last.closeCalls, 1);
          }
          expect(file.opened, hasLength(2));
        }, createFile: (_) => file);
      });
    }

    test(
      'cancelling after an owned chunk closes without reading ahead',
      () async {
        final file = _ReadFixtureFile([
          Uint8List.fromList([1, 2, 3, 4]),
          Uint8List.fromList([5, 6, 7, 8]),
        ]);
        await IOOverrides.runZoned(() async {
          final source = await wampFileSourceFromPath(file.path);
          final iterator = StreamIterator(source.openReadChunks!(4));
          expect(await iterator.moveNext(), isTrue);
          final chunk = iterator.current;
          await iterator.cancel();
          expect(chunk, [1, 2, 3, 4]);
          expect(file.opened.single.returned, hasLength(1));
          expect(file.opened.single.closeCalls, 1);
        }, createFile: (_) => file);
      },
    );

    test(
      'a partial-read failure closes the descriptor and stays observable',
      () async {
        final file = _ReadFixtureFile([
          Uint8List.fromList([1]),
        ], failAt: 1);
        await IOOverrides.runZoned(() async {
          final source = await wampFileSourceFromPath(file.path);
          await expectLater(
            source.openReadChunks!(4).toList(),
            throwsA(
              isA<FileSystemException>().having(
                (error) => error.message,
                'message',
                'fixture read failure',
              ),
            ),
          );
          expect(file.opened.single.closeCalls, 1);
        }, createFile: (_) => file);
      },
    );
  });
}

class _ReadFixtureFile implements File {
  _ReadFixtureFile(this.pieces, {this.failAt});
  final List<Uint8List> pieces;
  final int? failAt;
  final opened = <_ReadFixtureHandle>[];

  @override
  String get path => '/fixture/source.bin';
  @override
  Uri get uri => Uri.file(path);
  @override
  File get absolute => this;
  @override
  Future<int> length() async =>
      pieces.fold<int>(0, (sum, piece) => sum + piece.length);
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    final handle = _ReadFixtureHandle(
      pieces.map(Uint8List.fromList).toList(),
      failAt,
    );
    opened.add(handle);
    return handle;
  }

  @override
  dynamic noSuchMethod(invocation) => super.noSuchMethod(invocation);
}

class _ReadFixtureHandle implements RandomAccessFile {
  _ReadFixtureHandle(this.pending, this.failAt);
  final List<Uint8List> pending;
  final int? failAt;
  final returned = <Uint8List>[];
  int calls = 0;
  int closeCalls = 0;
  int copiedBytes = 0;

  @override
  Future<Uint8List> read(int bytes) async {
    if (calls++ == failAt) {
      throw const FileSystemException('fixture read failure');
    }
    if (pending.isEmpty) return Uint8List(0);
    final piece = pending.removeAt(0);
    final result = piece.length <= bytes
        ? piece
        : Uint8List.sublistView(piece, 0, bytes);
    if (piece.length > bytes) {
      pending.insert(0, Uint8List.sublistView(piece, bytes));
    }
    returned.add(result);
    return result;
  }

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async {
    final bytes = await read((end ?? buffer.length) - start);
    buffer.setRange(start, start + bytes.length, bytes);
    copiedBytes += bytes.length;
    return bytes.length;
  }

  @override
  Future<RandomAccessFile> close() async {
    closeCalls++;
    return this;
  }

  @override
  dynamic noSuchMethod(invocation) => super.noSuchMethod(invocation);
}
