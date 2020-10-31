import 'dart:collection';

import 'abstract_message.dart';
import 'message_types.dart';

/// Used to subscribe to a topic
class Subscribe extends AbstractMessage {
  int requestId;
  SubscribeOptions options;
  String topic;

  /// The [requestId] will identify the subscription server response. The [topic]
  /// is the actual topic to subscribe to or a prefix or wildcard topic as
  /// defined in the [options].
  Subscribe(this.requestId, this.topic, {this.options}) {
    id = MessageTypes.CODE_SUBSCRIBE;
  }
}

/// Used to either define advanced router options such a prefix or wildcard
/// matching or subsciption retention. One may also add custom options, Those
/// custom options need to be added with a custom serializer because flutter
/// disables reflections.
class SubscribeOptions {
  static final String MATCH_PLAIN = null;
  static final String MATCH_PREFIX = 'prefix';
  static final String MATCH_WILDCARD = 'wildcard';

  static final String CUSTOM_SERIALIZER_JSON = 'json';
  static final String CUSTOM_SERIALIZER_MSGPACK = 'msgpack';

  String match;
  String meta_topic;
  bool get_retained;

  final HashMap<String, dynamic Function(String)> _customSerializedOptions =
      HashMap<String, dynamic Function(String)>();

  /// the constructor
  SubscribeOptions({this.match, this.meta_topic, this.get_retained});

  /// add a custom [valueSerializer] to a given option [key]. The [valueSerializer]
  /// is passed a serializerr type. According to that type the serializer should
  /// respond with a correct serialized value.
  /// Example:
  /// ```dart
  /// options.addCustomValue(
  ///  'key1', (serializerType) {
  ///    if (serializerType == SubscribeOptions.CUSTOM_SERIALIZER_JSON) {
  ///      return '12';
  ///    } else if (serializerType == SubscribeOptions.CUSTOM_SERIALIZER_MSGPACK) {
  ///      return 12;
  ///    } else throw Exception('Unknown serializer');
  ///  }
  /// )
  /// options.addCustomValue(
  ///  'key2', (serializerType) {
  ///    if (serializerType == SubscribeOptions.CUSTOM_SERIALIZER_JSON) {
  ///      return '{"complexObjectKey":"complexObjectValue"}';
  ///    } else if (serializerType == SubscribeOptions.CUSTOM_SERIALIZER_MSGPACK) {
  ///      return {"complexObjectKey":"complexObjectValue"};
  ///    } else throw Exception('Unknown serializer');
  ///  }
  /// )
  /// ```
  void addCustomValue(String key, dynamic Function(String) valueSerializer) {
    _customSerializedOptions[key] = valueSerializer;
  }

  /// Some server need custom values to be added to the options. Since flutter
  /// disables reflection in favor of tree shaking, the custom values need a
  /// custom serialization process that has to be defined for each value
  /// separately. The current [serializerType] is passed to the custom
  /// serializer.
  HashMap<String, T> getCustomValues<T>(String serializerType) {
    var resultMap = HashMap<String, T>();
    _customSerializedOptions.forEach((key, value) {
      resultMap[key] = value(serializerType);
    });
    return resultMap;
  }
}
