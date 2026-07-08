# connectanum

`connectanum` is the compatibility package for the Connectanum Dart WAMP
client. New modular applications can depend on `connectanum_client` directly;
existing applications that import `package:connectanum/...` can use this facade
while migrating at their own pace.

## Install

```bash
dart pub add connectanum
```

## Quick Start

```dart
import 'package:connectanum/connectanum.dart';
import 'package:connectanum/json.dart';

Future<void> main() async {
  final client = Client(
    realm: 'demo.realm',
    transport: WebSocketTransport(
      'ws://127.0.0.1:8080/ws',
      Serializer(),
      WebSocketSerialization.serializationJson,
    ),
  );

  final session = await client.connect().first;
  await session.close();
  await client.disconnect();
}
```

This package intentionally stays thin. Its public libraries forward to
`connectanum_client`; router, MCP server, auth-server, and benchmark features
remain in their dedicated modular packages.
