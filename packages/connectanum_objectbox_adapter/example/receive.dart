import 'package:connectanum_client/connectanum.dart' as client;
import 'package:connectanum_objectbox_adapter/connectanum_objectbox_adapter.dart';

/// The application opens its normal ObjectBox Store using the shared model,
/// constructs an adapter for its entity type, then installs this handler.
Future<void> receiveEntities<T>(
  client.Session session,
  ObjectBoxFlatBufferAdapter<T> adapter, {
  String topic = 'com.example.entity',
}) async {
  await session.subscribeLazyPayloadHandler(topic, (event) {
    adapter.putEvent(event);
  });
}
