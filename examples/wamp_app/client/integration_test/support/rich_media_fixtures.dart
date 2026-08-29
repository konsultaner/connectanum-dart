import 'dart:math' as math;
import 'dart:typed_data';

const nativeVoiceNoteDurationMilliseconds = 2000;

Uint8List nativeAnimatedGifBytes() => Uint8List.fromList([
  0x47,
  0x49,
  0x46,
  0x38,
  0x39,
  0x61,
  0x01,
  0x00,
  0x01,
  0x00,
  0x80,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0xff,
  0xff,
  0xff,
  0x21,
  0xff,
  0x0b,
  0x4e,
  0x45,
  0x54,
  0x53,
  0x43,
  0x41,
  0x50,
  0x45,
  0x32,
  0x2e,
  0x30,
  0x03,
  0x01,
  0x00,
  0x00,
  0x00,
  0x21,
  0xf9,
  0x04,
  0x00,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x2c,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x02,
  0x02,
  0x44,
  0x01,
  0x00,
  0x21,
  0xf9,
  0x04,
  0x00,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x2c,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x02,
  0x02,
  0x4c,
  0x01,
  0x00,
  0x3b,
]);

Uint8List nativeVoiceNoteBytes() {
  const sampleRate = 16000;
  const channelCount = 1;
  const bitsPerSample = 16;
  const bytesPerSample = bitsPerSample ~/ 8;
  const sampleCount = sampleRate * nativeVoiceNoteDurationMilliseconds ~/ 1000;
  const payloadBytes = sampleCount * bytesPerSample;
  final bytes = Uint8List(44 + payloadBytes);
  final data = ByteData.view(bytes.buffer);

  void writeAscii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + payloadBytes, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channelCount, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channelCount * bytesPerSample, Endian.little);
  data.setUint16(32, channelCount * bytesPerSample, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, payloadBytes, Endian.little);
  for (var sample = 0; sample < sampleCount; sample += 1) {
    final value = (math.sin(2 * math.pi * 440 * sample / sampleRate) * 10000)
        .round();
    data.setInt16(44 + (sample * bytesPerSample), value, Endian.little);
  }
  return bytes;
}
