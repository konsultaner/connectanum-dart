@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library wamp_multisession_conformance_test;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/message/publish.dart' as publish_msg;
import 'package:connectanum_core/src/message/subscribe.dart' as subscribe_msg;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:connectanum_router/src/router/models/endpoint.dart';
import 'package:connectanum_router/src/router/models/tls_mode.dart';
import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:connectanum_router/src/router/state/commands.dart';
import 'package:connectanum_router/src/router/state/session.dart';
import 'package:connectanum_router/src/router/state/store.dart';
import 'package:test/test.dart';

const _routerAssignedIdFields = {
  'session_id',
  'subscription_id',
  'publication_id',
  'registration_id',
  'invocation_id',
};

void main() {
  final vectorsRoot = _resolveVectorsRoot();
  final vectors = _loadMultisessionVectors(vectorsRoot);

  late RouterSettings routerSettings;
  late RouterStateStore stateStore;

  setUp(() {
    routerSettings = _buildRouterSettings();
    stateStore = RouterStateStore(settings: routerSettings)..start();
  });

  tearDown(() {
    stateStore.dispose();
  });

  group('pinned WAMP multisession conformance', () {
    test('vendors the upstream multisession vector snapshot', () {
      expect(
        File(
          '${vectorsRoot.path}/multisession/advanced/publisher_exclusion_disabled.json',
        ).existsSync(),
        isTrue,
      );
    });

    for (final vector in vectors) {
      test(vector.label, () async {
        await _runVector(
          vector,
          stateStore: stateStore,
          routerSettings: routerSettings,
        );
      });
    }
  });
}

Future<void> _runVector(
  _MultisessionVector vector, {
  required RouterStateStore stateStore,
  required RouterSettings routerSettings,
}) async {
  final bossMessages = <Map<String, Object?>>[];
  final bossPort = ReceivePort()
    ..listen((dynamic message) {
      if (message is Map<String, Object?>) {
        bossMessages.add(message);
      }
    });
  addTearDown(bossPort.close);

  final listener = _buildListener();
  final realmContexts = RealmContextCache(statePort: stateStore.commandPort);
  addTearDown(realmContexts.dispose);

  final workerStates = <String, WorkerConnectionState>{};
  final sessionLabelsByConnectionId = <int, String>{};
  final connectionIdsBySessionLabel = <String, int>{};

  var nextSessionId = 800;
  var nextConnectionId = 900;

  for (final session in vector.sessions) {
    final realm = routerSettings.realms.singleWhere(
      (candidate) => candidate.name == session.realm,
    );
    final connectionId = nextConnectionId++;
    final sessionId = nextSessionId++;
    final workerState =
        createWorkerStateForTest(
              listener: listener,
              listenerSettings: routerSettings.listeners.first,
            )
            as WorkerConnectionState;
    workerState
      ..serializer = NativeMessageSerializer.json
      ..phase = HandshakePhase.open
      ..realmUri = session.realm
      ..realmSettings = realm
      ..sessionId = sessionId;

    _openSession(
      stateStore,
      sessionId: sessionId,
      realmUri: session.realm,
      listener: listener,
      connectionId: connectionId,
      authId: session.sessionLabel,
    );
    workerStates[session.sessionLabel] = workerState;
    sessionLabelsByConnectionId[connectionId] = session.sessionLabel;
    connectionIdsBySessionLabel[session.sessionLabel] = connectionId;
  }
  await Future<void>.delayed(Duration.zero);

  final pendingRouterMessages = Queue<_ObservedRouterMessage>();
  final observedRouterMessages = <_ObservedRouterMessage>[];
  final placeholderBindings = <String, int>{};
  var seenBossMessages = 0;

  for (final step in vector.sequence) {
    if (step.from == 'router') {
      expect(
        pendingRouterMessages,
        isNotEmpty,
        reason:
            'Missing router message for step ${step.step}: ${step.description}',
      );
      final actual = pendingRouterMessages.removeFirst();
      expect(
        actual.to,
        equals(step.to),
        reason:
            'Router step ${step.step} targeted ${actual.to}, expected ${step.to}',
      );
      _expectSubset(
        step.message,
        actual.message,
        placeholderBindings: placeholderBindings,
        path: 'step_${step.step}',
      );
      continue;
    }

    final workerState = workerStates[step.from];
    expect(
      workerState,
      isNotNull,
      reason: 'Missing worker state for session ${step.from}',
    );
    final connectionId = connectionIdsBySessionLabel[step.from];
    expect(
      connectionId,
      isNotNull,
      reason: 'Missing connection id for session ${step.from}',
    );

    await handleSessionMessageForTest(
      bossPort: bossPort.sendPort,
      statePort: stateStore.commandPort,
      realmContexts: realmContexts,
      state: workerState!,
      message: _buildClientMessage(step.message),
      connectionId: connectionId!,
    );
    await Future<void>.delayed(Duration.zero);

    final newMessages = bossMessages.sublist(seenBossMessages);
    seenBossMessages = bossMessages.length;
    final observed = _extractObservedRouterMessages(
      newMessages,
      sessionLabelsByConnectionId: sessionLabelsByConnectionId,
    );
    pendingRouterMessages.addAll(observed);
    observedRouterMessages.addAll(observed);
  }

  expect(
    pendingRouterMessages,
    isEmpty,
    reason:
        'Unconsumed router messages remained after executing ${vector.label}',
  );

  final expectedOutcome = vector.expectedOutcome;
  if (expectedOutcome case {'session_1_receives_event': final bool receives}) {
    final actualReceives = observedRouterMessages.any(
      (message) =>
          message.to == 'session_1' && message.message['type'] == 'EVENT',
    );
    expect(actualReceives, equals(receives));
  }
  if (expectedOutcome case {'event_count': final int eventCount}) {
    final actualEventCount = observedRouterMessages
        .where((message) => message.message['type'] == 'EVENT')
        .length;
    expect(actualEventCount, equals(eventCount));
  }
  if (expectedOutcome case {
    'event_recipients': final List<dynamic> recipients,
  }) {
    final actualRecipients = observedRouterMessages
        .where((message) => message.message['type'] == 'EVENT')
        .map((message) => message.to)
        .toList(growable: false);
    expect(actualRecipients, equals(recipients.cast<String>()));
  }
}

AbstractMessage _buildClientMessage(Map<String, Object?> message) {
  final type = message['type'];
  switch (type) {
    case 'SUBSCRIBE':
      return subscribe_msg.Subscribe(
        message['request_id']! as int,
        message['topic']! as String,
        options: _buildSubscribeOptions(message['options']),
      );
    case 'PUBLISH':
      return publish_msg.Publish(
        message['request_id']! as int,
        message['topic']! as String,
        options: _buildPublishOptions(message['options']),
        arguments: _toDynamicList(message['args']),
        argumentsKeywords: _toDynamicMap(message['kwargs']),
      );
  }
  throw UnsupportedError('Unsupported client conformance message type: $type');
}

subscribe_msg.SubscribeOptions? _buildSubscribeOptions(Object? optionsSpec) {
  final options = _toDynamicMap(optionsSpec);
  if (options == null || options.isEmpty) {
    return null;
  }
  return subscribe_msg.SubscribeOptions(
    match: options['match'] as String?,
    metaTopic: options['meta_topic'] as String?,
    getRetained: options['get_retained'] as bool?,
    custom: Map<String, dynamic>.from(options)
      ..remove('match')
      ..remove('meta_topic')
      ..remove('get_retained'),
  );
}

publish_msg.PublishOptions? _buildPublishOptions(Object? optionsSpec) {
  final options = _toDynamicMap(optionsSpec);
  if (options == null || options.isEmpty) {
    return null;
  }
  return publish_msg.PublishOptions(
    acknowledge: options['acknowledge'] as bool?,
    excludeMe: options['exclude_me'] as bool?,
    discloseMe: options['disclose_me'] as bool?,
    retain: options['retain'] as bool?,
    custom: Map<String, dynamic>.from(options)
      ..remove('acknowledge')
      ..remove('exclude_me')
      ..remove('disclose_me')
      ..remove('retain'),
  );
}

Iterable<_ObservedRouterMessage> _extractObservedRouterMessages(
  List<Map<String, Object?>> bossMessages, {
  required Map<int, String> sessionLabelsByConnectionId,
}) sync* {
  for (final bossMessage in bossMessages) {
    final type = bossMessage['type'];
    if (type == 'worker_send') {
      final connectionId = bossMessage['connectionId'] as int;
      final payload = bossMessage['payload'] as Uint8List;
      yield _ObservedRouterMessage(
        to: sessionLabelsByConnectionId[connectionId]!,
        message: _normalizeJsonFrame(
          jsonDecode(utf8.decode(payload)) as List<dynamic>,
        ),
      );
    } else if (type == 'worker_forward_message') {
      final connectionId = bossMessage['connectionId'] as int;
      final message = bossMessage['message'] as AbstractMessage;
      yield _ObservedRouterMessage(
        to: sessionLabelsByConnectionId[connectionId]!,
        message: _normalizeMessageObject(message),
      );
    }
  }
}

Map<String, Object?> _normalizeJsonFrame(List<dynamic> frame) {
  final code = frame.first;
  if (code == MessageTypes.codeSubscribed) {
    return {
      'type': 'SUBSCRIBED',
      'request_id': frame[1] as int,
      'subscription_id': frame[2] as int,
    };
  }
  if (code == MessageTypes.codeEvent) {
    final result = <String, Object?>{
      'type': 'EVENT',
      'subscription_id': frame[1] as int,
      'publication_id': frame[2] as int,
      'details': _normalizeValue(frame[3]) as Map<String, Object?>,
    };
    if (frame.length > 4) {
      result['args'] = _normalizeValue(frame[4]);
    }
    if (frame.length > 5) {
      result['kwargs'] = _normalizeValue(frame[5]);
    }
    return result;
  }
  throw UnsupportedError('Unsupported router JSON frame code: $code');
}

Map<String, Object?> _normalizeMessageObject(AbstractMessage message) {
  switch (message) {
    case Subscribed():
      return {
        'type': 'SUBSCRIBED',
        'request_id': message.subscribeRequestId,
        'subscription_id': message.subscriptionId,
      };
    case Event():
      final result = <String, Object?>{
        'type': 'EVENT',
        'subscription_id': message.subscriptionId,
        'publication_id': message.publicationId,
        'details': _normalizeEventDetails(message.details),
      };
      if (message.arguments != null) {
        result['args'] = _normalizeValue(message.arguments);
      }
      if (message.argumentsKeywords != null) {
        result['kwargs'] = _normalizeValue(message.argumentsKeywords);
      }
      return result;
  }
  throw UnsupportedError(
    'Unsupported routed message type: ${message.runtimeType}',
  );
}

Map<String, Object?> _normalizeEventDetails(EventDetails details) {
  final normalized = <String, Object?>{};
  if (details.publisher != null) {
    normalized['publisher'] = details.publisher;
  }
  if (details.trustlevel != null) {
    normalized['trustlevel'] = details.trustlevel;
  }
  if (details.topic != null) {
    normalized['topic'] = details.topic;
  }
  if (details.pptScheme != null) {
    normalized['ppt_scheme'] = details.pptScheme;
  }
  if (details.pptSerializer != null) {
    normalized['ppt_serializer'] = details.pptSerializer;
  }
  if (details.pptCipher != null) {
    normalized['ppt_cipher'] = details.pptCipher;
  }
  if (details.pptKeyId != null) {
    normalized['ppt_keyid'] = details.pptKeyId;
  }
  normalized.addAll(_normalizeValue(details.custom) as Map<String, Object?>);
  return normalized;
}

Object? _normalizeValue(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entryValue) =>
          MapEntry(key.toString(), _normalizeValue(entryValue)),
    );
  }
  if (value is List) {
    return value.map(_normalizeValue).toList(growable: false);
  }
  return value;
}

void _expectSubset(
  Object? expected,
  Object? actual, {
  required Map<String, int> placeholderBindings,
  required String path,
  String? currentKey,
}) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: '$path should be a map');
    final actualMap = (actual as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    for (final entry in expected.entries) {
      expect(
        actualMap.containsKey(entry.key),
        isTrue,
        reason: '$path is missing key ${entry.key}',
      );
      _expectSubset(
        entry.value,
        actualMap[entry.key],
        placeholderBindings: placeholderBindings,
        path: '$path.${entry.key}',
        currentKey: entry.key,
      );
    }
    return;
  }

  if (expected is List) {
    expect(actual, isA<List>(), reason: '$path should be a list');
    final actualList = actual as List;
    expect(actualList, hasLength(expected.length), reason: path);
    for (var index = 0; index < expected.length; index += 1) {
      _expectSubset(
        expected[index],
        actualList[index],
        placeholderBindings: placeholderBindings,
        path: '$path[$index]',
      );
    }
    return;
  }

  if (currentKey != null &&
      expected is int &&
      _routerAssignedIdFields.contains(currentKey)) {
    final actualValue = actual as int?;
    expect(actualValue, isNotNull, reason: '$path should be an int');
    final bindingKey = '$currentKey:$expected';
    final boundValue = placeholderBindings[bindingKey];
    if (boundValue == null) {
      expect(actualValue, greaterThan(0), reason: '$path should be positive');
      placeholderBindings[bindingKey] = actualValue!;
    } else {
      expect(actualValue, equals(boundValue), reason: path);
    }
    return;
  }

  expect(actual, equals(expected), reason: path);
}

Directory _resolveVectorsRoot() {
  final candidates = [
    Directory('../connectanum_core/testdata/wamp_conformance'),
    Directory('packages/connectanum_core/testdata/wamp_conformance'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate;
    }
  }
  throw StateError('Could not locate vendored WAMP conformance vectors');
}

List<_MultisessionVector> _loadMultisessionVectors(Directory root) {
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where((file) => file.path.contains('/multisession/'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  return files.map(_loadMultisessionVector).toList(growable: false);
}

_MultisessionVector _loadMultisessionVector(File file) {
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final relativePath = file.path.replaceAll('\\', '/');
  return _MultisessionVector(
    label: '$relativePath :: ${raw['description']}',
    feature: raw['feature']! as String,
    sessions: (raw['sessions'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(_VectorSession.fromJson)
        .toList(growable: false),
    sequence:
        (raw['sequence'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(_VectorStep.fromJson)
            .toList(growable: false)
          ..sort((left, right) => left.step.compareTo(right.step)),
    expectedOutcome: (raw['expected_outcome'] as Map<String, dynamic>? ?? {})
        .map((key, value) => MapEntry(key, value)),
  );
}

List<dynamic>? _toDynamicList(Object? value) {
  if (value == null) {
    return null;
  }
  return List<dynamic>.from(value as List<dynamic>);
}

Map<String, dynamic>? _toDynamicMap(Object? value) {
  if (value == null) {
    return null;
  }
  return Map<String, dynamic>.from(value as Map);
}

void _openSession(
  RouterStateStore store, {
  required int sessionId,
  required String realmUri,
  required RouterListener listener,
  required int connectionId,
  String? authRole = 'member',
  String? authId = 'tester',
}) {
  final session = SessionRecord(
    id: sessionId,
    authId: authId,
    authRole: authRole,
    roles: const {},
    workerId: 1,
    connectionId: connectionId,
    lastActivity: DateTime.now(),
    listener: listener,
  );
  store.commandPort.send(
    SessionOpenCommand(realmUri: realmUri, session: session),
  );
}

RouterSettings _buildRouterSettings() {
  final realm = RealmSettings(
    name: 'realm1',
    autoCreate: false,
    auth: const RealmAuthSettings(methods: [], methodOptions: {}),
    roles: const [],
    limits: const RealmLimitSettings(),
  );

  final listener = ListenerSettings(
    type: 'rawsocket',
    endpoint: '127.0.0.1:8000',
    authmethods: const [],
    options: const {},
  );

  return RouterSettings(
    realms: [realm],
    listeners: [listener],
    metrics: null,
    authenticators: const <String, AuthenticatorDefinition>{},
  );
}

RouterListener _buildListener() => RouterListener(
  listenerId: 1,
  endpoint: Endpoint(
    host: '127.0.0.1',
    port: 8000,
    tlsMode: TlsMode.disabled,
    maxRawSocketSizeExponent: 16,
  ),
  port: 8000,
  http3Port: 0,
);

class _ObservedRouterMessage {
  const _ObservedRouterMessage({required this.to, required this.message});

  final String to;
  final Map<String, Object?> message;
}

class _MultisessionVector {
  const _MultisessionVector({
    required this.label,
    required this.feature,
    required this.sessions,
    required this.sequence,
    required this.expectedOutcome,
  });

  final String label;
  final String feature;
  final List<_VectorSession> sessions;
  final List<_VectorStep> sequence;
  final Map<String, Object?> expectedOutcome;
}

class _VectorSession {
  const _VectorSession({
    required this.sessionLabel,
    required this.roles,
    required this.realm,
  });

  factory _VectorSession.fromJson(Map<String, dynamic> json) {
    return _VectorSession(
      sessionLabel: json['session_id']! as String,
      roles: (json['roles'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toList(growable: false),
      realm: json['realm'] as String? ?? 'realm1',
    );
  }

  final String sessionLabel;
  final List<String> roles;
  final String realm;
}

class _VectorStep {
  const _VectorStep({
    required this.step,
    required this.description,
    required this.from,
    required this.to,
    required this.message,
  });

  factory _VectorStep.fromJson(Map<String, dynamic> json) {
    return _VectorStep(
      step: json['step']! as int,
      description: json['description']! as String,
      from: json['from']! as String,
      to: json['to']! as String,
      message: Map<String, Object?>.from(json['message']! as Map),
    );
  }

  final int step;
  final String description;
  final String from;
  final String to;
  final Map<String, Object?> message;
}
