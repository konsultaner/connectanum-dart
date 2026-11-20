import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import '../dart_transport_copy_metrics.dart';

// Keep HTTP, TLS, control handling and framing in dart:io. Only complete JSON
// payload messages use its binary accumulator, with the same strict UTF-8
// decoder feeding any non-ASCII suffix before a final fragment can be emitted.
Stream<Uint8List> canonicalJsonByteFrames(
  Stream<Uint8List> source, {
  void Function(bool text)? onMessage,
}) async* {
  final reader = _Reader(source);
  var fragmented = false;
  _TextCheck? check;
  final staged = <({Uint8List header, Uint8List payload})>[];
  var stagedSize = 0;
  var text = false;
  var header = <int>[];
  Uint8List? prefix;
  var copied = 0;
  try {
    while (true) {
      header = [];
      prefix = null;
      copied = 0;
      final first = await reader.take(1);
      if (first == null) break;
      header.add(first.single);
      final opcode = header[0] & 15, fin = header[0] & 128 != 0;
      final invalidFirst =
          header[0] & 112 != 0 ||
          ![0, 1, 2, 8, 9, 10].contains(opcode) ||
          opcode >= 8 && !fin ||
          opcode == 0 && !fragmented ||
          (opcode == 1 || opcode == 2) && fragmented;
      if (invalidFirst) {
        if (staged.isNotEmpty) {
          yield* _stagedBytes(staged);
          staged.clear();
          stagedSize = 0;
        }
        yield Uint8List.fromList(header);
        header = [];
        yield* reader.rest();
        return;
      }
      final second = await reader.take(1);
      if (second == null) break;
      header.add(second.single);
      final indicator = header[1] & 127;
      if (header[1] & 128 != 0 || opcode >= 8 && indicator > 125) {
        if (staged.isNotEmpty) {
          yield* _stagedBytes(staged);
          staged.clear();
          stagedSize = 0;
        }
        yield Uint8List.fromList(header);
        header = [];
        yield* reader.rest();
        return;
      }
      final extra = indicator == 126
          ? 2
          : indicator == 127
          ? 8
          : 0;
      while (header.length < 2 + extra) {
        final part = await reader.take(2 + extra - header.length);
        if (part == null) break;
        header.addAll(part);
      }
      if (header.length < 2 + extra) break;
      var length = indicator;
      var invalidLength = false;
      if (extra != 0) {
        invalidLength = extra == 8 && header[2] & 128 != 0;
        length = 0;
        if (!invalidLength) {
          for (final byte in header.skip(2)) {
            length = (length << 8) | byte;
          }
        }
        invalidLength =
            invalidLength ||
            extra == 2 && length < 126 ||
            extra == 8 && length < 65536;
      }
      if (invalidLength) {
        if (staged.isNotEmpty) {
          yield* _stagedBytes(staged);
          staged.clear();
          stagedSize = 0;
        }
        yield Uint8List.fromList(header);
        header = [];
        yield* reader.rest();
        return;
      }
      if (opcode == 1 || opcode == 2) text = opcode == 1;
      if (staged.isNotEmpty &&
          opcode == 0 &&
          !fin &&
          length <= 4096 &&
          stagedSize + header.length + length <= 4096) {
        prefix = Uint8List(length);
        while (copied < length) {
          final part = await reader.take(length - copied);
          if (part == null) break;
          prefix.setRange(copied, copied + part.length, part);
          DartTransportCopyMetrics.recordWebSocketFragmentCoalesceCopy(
            part.length,
          );
          copied += part.length;
        }
        if (copied == length && _ascii(prefix, 0, copied)) {
          staged.add((header: Uint8List.fromList(header), payload: prefix));
          stagedSize += header.length + copied;
          header = [];
          prefix = null;
          copied = 0;
          continue;
        }
      }
      if (staged.isNotEmpty && opcode == 0) {
        final optimize = length >= 65536 && length <= 8 * 1024 * 1024;
        if (optimize) {
          staged.first.header[0] = (staged.first.header[0] & 240) | 2;
          check = _TextCheck();
          for (final fragment in staged) {
            check.add(fragment.payload, false);
          }
        }
        yield* _stagedBytes(staged);
        staged.clear();
        stagedSize = 0;
      }
      if (opcode == 1 &&
          !fragmented &&
          check == null &&
          length > 0 &&
          (!fin && length <= 4096 ||
              length >= 65536 && length <= 8 * 1024 * 1024)) {
        prefix = Uint8List(math.min(length, 4096));
        while (copied < prefix.length) {
          final part = await reader.take(prefix.length - copied);
          if (part == null) break;
          prefix.setRange(copied, copied + part.length, part);
          DartTransportCopyMetrics.recordWebSocketFragmentCoalesceCopy(
            part.length,
          );
          copied += part.length;
        }
        final completePrefix = copied == prefix.length;
        final canonical =
            completePrefix &&
            _ascii(prefix, 0, copied) &&
            (length <= 4096
                ? _payloadMessagePrefix(prefix)
                : _canonicalPrefix(prefix));
        if (canonical && !fin && length <= 4096) {
          staged.add((header: Uint8List.fromList(header), payload: prefix));
          stagedSize = header.length + copied;
          header = [];
          prefix = null;
          copied = 0;
          fragmented = true;
          continue;
        }
        if (canonical && length >= 65536) {
          header[0] = (header[0] & 240) | 2;
          check = _TextCheck();
        }
      }
      final isMessageData = opcode < 8;
      // A final empty continuation can complete a pending UTF-8 sequence.
      if (isMessageData && fin && length == 0) {
        check?.add(Uint8List(0), true);
        onMessage?.call(text);
      }
      yield Uint8List.fromList(header);
      header = [];
      if (copied != 0) {
        final part = Uint8List.sublistView(prefix!, 0, copied);
        check?.add(part, fin && copied == length);
        if (isMessageData && fin && copied == length) onMessage?.call(text);
        yield part;
      }
      var left = length - copied;
      prefix = null;
      copied = 0;
      while (left != 0) {
        final part = await reader.take(left);
        if (part == null) break;
        left -= part.length;
        if (isMessageData) check?.add(part, fin && left == 0);
        if (isMessageData && fin && left == 0) onMessage?.call(text);
        yield part;
      }
      if (left != 0) break;
      if (opcode == 1 || opcode == 2) fragmented = !fin;
      if (opcode == 0 && fin) fragmented = false;
      if (isMessageData && fin) check = null;
      if (opcode == 8) {
        staged.clear();
        stagedSize = 0;
      }
    }
    if (staged.isNotEmpty) {
      yield* _stagedBytes(staged);
    }
    if (header.isNotEmpty) yield Uint8List.fromList(header);
    if (prefix != null && copied != 0) {
      yield Uint8List.sublistView(prefix, 0, copied);
    }
  } catch (error, stack) {
    // Socket failures preserve the exact pending prefix. UTF-8 failure must
    // arrive before its final bytes: dart:io then sends the original 1007 close.
    if (error is! FormatException) {
      if (staged.isNotEmpty) {
        yield* _stagedBytes(staged);
      }
      if (header.isNotEmpty) yield Uint8List.fromList(header);
      if (prefix != null && copied != 0) {
        yield Uint8List.sublistView(prefix, 0, copied);
      }
    }
    Error.throwWithStackTrace(error, stack);
  } finally {
    await reader.cancel();
  }
}

Stream<Uint8List> _stagedBytes(
  List<({Uint8List header, Uint8List payload})> fragments,
) async* {
  for (final fragment in fragments) {
    yield fragment.header;
    yield fragment.payload;
  }
}

bool _payloadMessagePrefix(Uint8List bytes) {
  for (final code in [16, 36, 48, 50, 68, 70]) {
    final prefix = '[$code,'.codeUnits;
    if (bytes.length >= prefix.length &&
        List.generate(
          prefix.length,
          (i) => bytes[i] == prefix[i],
        ).every((same) => same)) {
      return true;
    }
  }
  return false;
}

bool _canonicalPrefix(Uint8List bytes) {
  if (bytes.isEmpty || bytes[0] != 91) return false;
  const marker = [91, 34, 92, 117, 48, 48, 48, 48];
  for (var i = 1; i <= bytes.length - marker.length; i++) {
    var j = 0;
    while (j != marker.length && bytes[i + j] == marker[j]) {
      j++;
    }
    if (j == marker.length) return true;
  }
  return false;
}

bool _ascii(Uint8List bytes, int start, int end) {
  while (start < end && (bytes.offsetInBytes + start) % 8 != 0) {
    if (bytes[start++] > 127) return false;
  }
  if (start == end) return true;
  final words = Uint64List.view(
    bytes.buffer,
    bytes.offsetInBytes + start,
    (end - start) ~/ 8,
  );
  for (final word in words) {
    if (word & 0x8080808080808080 != 0) return false;
  }
  start += words.length * 8;
  while (start < end) {
    if (bytes[start++] > 127) return false;
  }
  return true;
}

class _TextCheck {
  ByteConversionSink? sink;
  void add(Uint8List bytes, bool last) {
    if (sink == null && !_ascii(bytes, 0, bytes.length)) {
      sink = utf8.decoder.startChunkedConversion(
        StringConversionSink.fromStringSink(_DiscardStrings()),
      );
    }
    sink?.add(bytes);
    if (last) sink?.close();
  }
}

class _DiscardStrings implements StringSink {
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
}

class _Reader {
  _Reader(Stream<Uint8List> source) : input = StreamIterator(source);
  final StreamIterator<Uint8List> input;
  Uint8List chunk = Uint8List(0);
  int offset = 0;
  Future<Uint8List?> take(int maximum) async {
    while (offset == chunk.length) {
      if (!await input.moveNext()) return null;
      chunk = input.current;
      offset = 0;
    }
    final end = math.min(chunk.length, offset + maximum);
    final result = Uint8List.sublistView(chunk, offset, end);
    offset = end;
    return result;
  }

  Stream<Uint8List> rest() async* {
    if (offset != chunk.length) yield Uint8List.sublistView(chunk, offset);
    offset = chunk.length;
    while (await input.moveNext()) {
      yield input.current;
    }
  }

  Future<void> cancel() => input.cancel();
}
