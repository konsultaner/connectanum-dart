import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

List<Uint8List> retained = [];
Uint8List? transient;

Future<void> main() async {
  stdout.writeln('READY');
  await for (final command
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (command == 'stop') break;
    if (command != 'allocate') throw StateError('Unknown target command');
    retained = List.generate(16, (_) => Uint8List(1024 * 1024));
    for (var index = 0; index < 64; index++) {
      transient = Uint8List(1024 * 1024)..[0] = index;
    }
    transient = null;
    stdout.writeln('ALLOCATED');
  }
  if (retained.isNotEmpty && retained.length != 16) {
    throw StateError('Lost buffers');
  }
}
