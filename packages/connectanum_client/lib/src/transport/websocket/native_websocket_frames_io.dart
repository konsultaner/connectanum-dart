import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../dart_transport_copy_metrics.dart';
import '../native/external_byte_buffer.dart';

class NativeWebSocketFrame {
  const NativeWebSocketFrame(this.headerLength, this.text);
  final int headerLength;
  final bool text;
}

final _nativeFrames = Expando<NativeWebSocketFrame>();

NativeWebSocketFrame? nativeWebSocketFrame(Uint8List bytes) =>
    _nativeFrames[bytes];

// Match the SDK's compile-time frame limit. This only disables coalescing;
// original frames always reach the SDK when a complete message would exceed it.
const _sdkFrameLimit = int.fromEnvironment(
  'dart.io.default.ws.max.payload.length',
  defaultValue: 8 * 1024 * 1024,
);

/// Supplies one privately owned native buffer for a complete, bounded message.
/// Controls, invalid headers, partial messages and oversized inputs retain their
/// original wire representation and the SDK's validation/error ordering.
Stream<Uint8List> coalesceNativeWebSocketFrames(
  Stream<Uint8List> source, {
  int maximumPayloadBytes = 8 * 1024 * 1024,
  int minimumPayloadBytes = 65536,
  void Function(Uint8List frame)? onNativeFrame,
}) {
  final parser = _Coalescer(
    math.min(maximumPayloadBytes, _sdkFrameLimit),
    minimumPayloadBytes,
    onNativeFrame,
  );
  return source.transform(
    StreamTransformer<Uint8List, Uint8List>.fromHandlers(
      handleData: parser.add,
      handleError: (error, stack, sink) {
        parser.flushPending(sink);
        sink.addError(error, stack);
      },
      handleDone: (sink) {
        parser.flushPending(sink);
        sink.close();
      },
    ),
  );
}

class _Coalescer {
  _Coalescer(this.maximumBytes, this.minimumBytes, this.onNativeFrame);

  final int maximumBytes;
  final int minimumBytes;
  final void Function(Uint8List frame)? onNativeFrame;
  final _header = <int>[];
  final _wire = <Uint8List>[];
  final _payload = <Uint8List>[];
  var _headerLength = 2;
  var _readingHeader = true;
  var _passthrough = false;
  var _fragmented = false;
  var _capture = true;
  var _captureFrame = false;
  var _opcode = 0;
  var _messageOpcode = 0;
  var _fin = false;
  var _remaining = 0;
  var _messageBytes = 0;
  var _headerBytes = 0;

  void add(Uint8List input, EventSink<Uint8List> sink) {
    var offset = 0;
    while (offset < input.length) {
      if (_passthrough) {
        sink.add(Uint8List.sublistView(input, offset));
        return;
      }
      if (_readingHeader) {
        _header.add(input[offset++]);
        if (_header.length == 1) {
          _opcode = _header[0] & 15;
          _fin = _header[0] & 128 != 0;
          if (_header[0] & 112 != 0 ||
              ![0, 1, 2, 8, 9, 10].contains(_opcode) ||
              _opcode >= 8 && !_fin ||
              _opcode == 0 && !_fragmented ||
              (_opcode == 1 || _opcode == 2) && _fragmented) {
            flushPending(sink);
            continue;
          }
        }
        if (_header.length == 2) {
          final indicator = _header[1] & 127;
          if (_header[1] & 128 != 0 || _opcode >= 8 && indicator > 125) {
            flushPending(sink);
            continue;
          }
          _headerLength = indicator == 126
              ? 4
              : indicator == 127
              ? 10
              : 2;
        }
        if (_header.length < _headerLength) continue;
        var length = _header[1] & 127;
        if (_headerLength > 2) {
          if (_headerLength == 10 && _header[2] & 128 != 0) {
            flushPending(sink);
            continue;
          }
          length = 0;
          for (final byte in _header.skip(2)) {
            length = (length << 8) | byte;
          }
          if (_headerLength == 4 && length < 126 ||
              _headerLength == 10 && length < 65536) {
            flushPending(sink);
            continue;
          }
        }
        _beginFrame(length, sink);
        if (_remaining == 0 && !_passthrough) _finishFrame(sink);
        continue;
      }

      final count = math.min(input.length - offset, _remaining);
      final end = offset + count;
      final part = Uint8List.sublistView(input, offset, end);
      if (_captureFrame && _wire.length >= 4096) {
        _flushWire(sink);
        _capture = _captureFrame = false;
      }
      if (_captureFrame) {
        _wire.add(part);
        _payload.add(part);
      } else {
        sink.add(part);
      }
      _remaining -= end - offset;
      offset = end;
      if (_remaining == 0) _finishFrame(sink);
    }
  }

  void _beginFrame(int length, EventSink<Uint8List> sink) {
    _readingHeader = false;
    _remaining = length;
    final header = Uint8List.fromList(_header);
    DartTransportCopyMetrics.recordWebSocketFragmentCoalesceCopy(header.length);
    if (_opcode >= 8) {
      // Keep controls in their exact original position. The remainder of an
      // interrupted data message also stays unmodified for SDK validation.
      _flushWire(sink);
      if (_fragmented) _capture = false;
      _captureFrame = false;
      sink.add(header);
      if (_opcode == 8) _passthrough = true;
      return;
    }
    if (_opcode == 1 || _opcode == 2) {
      _messageOpcode = _opcode;
      _messageBytes = _headerBytes = 0;
      _capture = true;
    }
    _headerBytes += header.length;
    if (length > maximumBytes || _messageBytes > maximumBytes - length) {
      _capture = false;
    } else {
      _messageBytes += length;
    }
    if (_headerBytes > 4096) _capture = false;
    if (!_capture) _flushWire(sink);
    _captureFrame = _capture;
    if (_captureFrame) {
      _wire.add(header);
    } else {
      sink.add(header);
    }
  }

  void _finishFrame(EventSink<Uint8List> sink) {
    if (_opcode < 8) {
      _fragmented = !_fin;
      if (_fin) {
        if (_capture &&
            _messageBytes >= minimumBytes &&
            (_messageOpcode == 1 || _payload.length > 1)) {
          final frame = _nativeFrame();
          _wire.clear();
          _payload.clear();
          onNativeFrame?.call(frame);
          sink.add(frame);
        } else {
          _flushWire(sink);
        }
        _capture = true;
      }
    }
    _header.clear();
    _headerLength = 2;
    _readingHeader = true;
  }

  Uint8List _nativeFrame() {
    final headerLength = _messageBytes < 126
        ? 2
        : _messageBytes < 65536
        ? 4
        : 10;
    final frame = allocateNativeExternalBytes(headerLength + _messageBytes);
    frame[0] = 128 | _messageOpcode;
    if (headerLength == 2) {
      frame[1] = _messageBytes;
    } else {
      frame[1] = headerLength == 4 ? 126 : 127;
      final view = ByteData.sublistView(frame);
      if (headerLength == 4) {
        view.setUint16(2, _messageBytes);
      } else {
        view.setUint64(2, _messageBytes);
      }
    }
    var offset = headerLength;
    for (final part in _payload) {
      frame.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    DartTransportCopyMetrics.recordWebSocketFragmentCoalesceCopy(_messageBytes);
    _nativeFrames[frame] = NativeWebSocketFrame(
      headerLength,
      _messageOpcode == 1,
    );
    return frame;
  }

  void _flushWire(EventSink<Uint8List> sink) {
    for (final part in _wire) {
      sink.add(part);
    }
    _wire.clear();
    _payload.clear();
  }

  void flushPending(EventSink<Uint8List> sink) {
    _flushWire(sink);
    if (_readingHeader && _header.isNotEmpty) {
      DartTransportCopyMetrics.recordWebSocketFragmentCoalesceCopy(
        _header.length,
      );
      sink.add(Uint8List.fromList(_header));
    }
    _header.clear();
    _passthrough = true;
  }
}
