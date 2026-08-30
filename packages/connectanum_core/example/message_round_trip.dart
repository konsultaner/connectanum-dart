import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' as json;

void main() {
  final serializer = json.Serializer();
  final call = Call(
    1,
    'com.example.greet',
    arguments: const <Object?>['Connectanum'],
  );

  final encoded = serializer.serialize(call);
  final decoded =
      serializer.deserialize(
            Uint8List.fromList(utf8.encode(encoded)),
          )!
          as Call;

  print('${decoded.procedure}: ${decoded.arguments!.single}');
}
