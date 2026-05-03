import 'dart:async';
import 'dart:convert';

import 'package:connectanum_client/connectanum.dart';

import '../protocol/json_rpc.dart';
import 'tool.dart';
import 'wamp_tool_delegate.dart';

typedef McpWampPublishInvoker =
    FutureOr<McpWampPublication?> Function(McpWampPublishRequest request);

typedef McpWampSubscribeInvoker =
    FutureOr<McpWampSubscription> Function(
      McpWampSubscribeRequest request,
      void Function(McpWampEvent event) onEvent,
    );

typedef McpWampUnsubscribeInvoker =
    FutureOr<void> Function(McpWampSubscription subscription);

class McpWampApi {
  McpWampApi({
    this.name,
    Iterable<McpWampProcedure> procedures = const [],
    Iterable<McpWampTopic> topics = const [],
    bool includeStandardMetaApi = false,
    bool includePublishedEventTopics = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : procedures = List<McpWampProcedure>.unmodifiable([
         ...procedures,
         if (includeStandardMetaApi) ...McpWampStandardMetaApi.procedures,
       ]),
       topics = _deduplicateTopics([
         ...topics,
         if (includePublishedEventTopics)
           for (final procedure in procedures)
             ..._publishedEventTopicsFor(procedure),
         if (includeStandardMetaApi) ...McpWampStandardMetaApi.topics,
       ]),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String? name;
  final List<McpWampProcedure> procedures;
  final List<McpWampTopic> topics;
  final Map<String, Object?> metadata;

  List<McpTool> toTools({
    McpWampCallInvoker? call,
    McpWampPublishInvoker? publish,
    McpWampSubscribeInvoker? subscribe,
    McpWampUnsubscribeInvoker? unsubscribe,
    bool includeApiMetaTools = true,
    bool includePubSubTools = true,
    Duration? timeout,
  }) {
    if (procedures.any((procedure) => procedure.allowCall) && call == null) {
      throw ArgumentError(
        'A WAMP call invoker is required when procedures are declared.',
      );
    }
    if (subscribe != null && unsubscribe == null) {
      throw ArgumentError(
        'A WAMP unsubscribe invoker is required when subscribe is provided.',
      );
    }

    final tools = <McpTool>[];
    for (final procedure in procedures) {
      if (!procedure.allowCall) {
        continue;
      }
      tools.add(
        McpWampToolDelegate(
          procedure: procedure.procedure,
          call: call!,
          argumentsBuilder:
              procedure.argumentsBuilder ??
              McpWampCallPayload.fromToolArguments,
          resultMapper:
              procedure.resultMapper ?? mcpWampLosslessJsonResultMapper,
          timeout: procedure.timeout ?? timeout,
        ).toTool(
          name: procedure.toolName,
          title: procedure.title,
          description: procedure.description,
          inputSchema: procedure.inputSchema,
          outputSchema: procedure.outputSchema,
          annotations: procedure.metadata.toToolAnnotations(
            title: procedure.title,
          ),
        ),
      );
    }
    if (includeApiMetaTools) {
      tools.addAll(_metaTools());
    }
    if (includePubSubTools) {
      tools.addAll(
        _pubSubTools(
          publish: publish,
          subscribe: subscribe,
          unsubscribe: unsubscribe,
        ),
      );
    }
    return tools;
  }

  List<McpTool> toSessionTools({
    required Session session,
    bool includeApiMetaTools = true,
    bool includePubSubTools = true,
    Duration? timeout,
  }) {
    return toTools(
      call: (call) => session.callSinglePayload(
        call.procedure,
        arguments: call.payload.arguments,
        argumentsKeywords: call.payload.argumentsKeywords,
        options: call.payload.options,
      ),
      publish: (request) async {
        final published = await session.publish(
          request.topic,
          arguments: request.arguments,
          argumentsKeywords: request.argumentsKeywords,
          options: request.options,
        );
        return McpWampPublication(
          publicationId: published?.publicationId,
          acknowledged: published != null,
        );
      },
      subscribe: (request, onEvent) async {
        final subscribed = await session.subscribePayloadHandler(
          request.topic,
          (event) => onEvent(McpWampEvent.fromPayload(event)),
          options: request.options,
        );
        return McpWampSubscription(
          topic: request.topic,
          subscriptionId: subscribed.subscriptionId,
        );
      },
      unsubscribe: (subscription) async {
        final subscriptionId = subscription.subscriptionId;
        if (subscriptionId != null) {
          await session.unsubscribe(subscriptionId);
        }
      },
      includeApiMetaTools: includeApiMetaTools,
      includePubSubTools: includePubSubTools,
      timeout: timeout,
    );
  }

  List<McpTool> _metaTools() {
    return [
      McpTool(
        name: 'connectanum.api.list',
        title: 'List WAMP API',
        description:
            'Lists the declared WAMP procedures and topics exposed through '
            'this MCP server.',
        annotations: const McpToolAnnotations(
          readOnlyHint: true,
          destructiveHint: false,
          idempotentHint: true,
          openWorldHint: false,
        ),
        inputSchema: const {
          'type': 'object',
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['procedure', 'topic'],
            },
            'tag': {'type': 'string'},
          },
          'additionalProperties': false,
        },
        handler: _handleApiList,
      ),
      McpTool(
        name: 'connectanum.api.describe',
        title: 'Describe WAMP API Entry',
        description:
            'Returns metadata and JSON schemas for one declared WAMP '
            'procedure or topic.',
        annotations: const McpToolAnnotations(
          readOnlyHint: true,
          destructiveHint: false,
          idempotentHint: true,
          openWorldHint: false,
        ),
        inputSchema: const {
          'type': 'object',
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['procedure', 'topic'],
            },
            'uri': {'type': 'string'},
          },
          'required': ['uri'],
          'additionalProperties': false,
        },
        handler: _handleApiDescribe,
      ),
    ];
  }

  List<McpTool> _pubSubTools({
    required McpWampPublishInvoker? publish,
    required McpWampSubscribeInvoker? subscribe,
    required McpWampUnsubscribeInvoker? unsubscribe,
  }) {
    final bridge = _McpWampPubSubTools(this, publish, subscribe, unsubscribe);
    return [
      McpTool(
        name: 'connectanum.pubsub.publish',
        title: 'Publish WAMP Event',
        description: 'Publishes an event to a declared WAMP topic.',
        annotations: const McpToolAnnotations(
          readOnlyHint: false,
          destructiveHint: false,
          idempotentHint: false,
          openWorldHint: false,
        ),
        inputSchema: const {
          'type': 'object',
          'properties': {
            'topic': {'type': 'string'},
            'arguments': {'type': 'array'},
            'argumentsKeywords': {
              'type': 'object',
              'additionalProperties': true,
            },
            'acknowledge': {'type': 'boolean'},
            'options': {'type': 'object', 'additionalProperties': true},
          },
          'required': ['topic'],
          'additionalProperties': false,
        },
        handler: bridge.publish,
      ),
      McpTool(
        name: 'connectanum.pubsub.subscribe',
        title: 'Subscribe WAMP Topic',
        description:
            'Subscribes to a declared WAMP topic and buffers events for '
            'polling through MCP.',
        annotations: const McpToolAnnotations(
          readOnlyHint: false,
          destructiveHint: false,
          idempotentHint: false,
          openWorldHint: false,
        ),
        inputSchema: const {
          'type': 'object',
          'properties': {
            'topic': {'type': 'string'},
            'queueLimit': {'type': 'integer', 'minimum': 1},
            'options': {'type': 'object', 'additionalProperties': true},
          },
          'required': ['topic'],
          'additionalProperties': false,
        },
        handler: bridge.subscribe,
      ),
      McpTool(
        name: 'connectanum.pubsub.poll',
        title: 'Poll WAMP Events',
        description: 'Returns buffered WAMP events for an MCP subscription.',
        annotations: const McpToolAnnotations(
          readOnlyHint: true,
          destructiveHint: false,
          idempotentHint: false,
          openWorldHint: false,
        ),
        inputSchema: const {
          'type': 'object',
          'properties': {
            'handle': {'type': 'string'},
            'limit': {'type': 'integer', 'minimum': 1},
          },
          'required': ['handle'],
          'additionalProperties': false,
        },
        handler: bridge.poll,
      ),
      McpTool(
        name: 'connectanum.pubsub.unsubscribe',
        title: 'Unsubscribe WAMP Topic',
        description: 'Unsubscribes an MCP-created WAMP topic subscription.',
        annotations: const McpToolAnnotations(
          readOnlyHint: false,
          destructiveHint: false,
          idempotentHint: true,
          openWorldHint: false,
        ),
        inputSchema: const {
          'type': 'object',
          'properties': {
            'handle': {'type': 'string'},
          },
          'required': ['handle'],
          'additionalProperties': false,
        },
        handler: bridge.unsubscribe,
      ),
    ];
  }

  Future<McpToolResult> _handleApiList(McpToolRequest request) async {
    final kind = _optionalString(request.arguments, 'kind');
    final tag = _optionalString(request.arguments, 'tag');
    final includeProcedures = kind == null || kind == 'procedure';
    final includeTopics = kind == null || kind == 'topic';
    final result = <String, Object?>{
      if (name != null) 'name': name,
      if (metadata.isNotEmpty) 'metadata': mcpWampJsonCompatible(metadata),
    };
    if (includeProcedures) {
      result['procedures'] = [
        for (final procedure in procedures)
          if (tag == null || procedure.metadata.tags.contains(tag))
            procedure.toJson(),
      ];
    }
    if (includeTopics) {
      result['topics'] = [
        for (final topic in topics)
          if (tag == null || topic.metadata.tags.contains(tag)) topic.toJson(),
      ];
    }
    return _jsonToolResult(result);
  }

  Future<McpToolResult> _handleApiDescribe(McpToolRequest request) async {
    final uri = _requiredString(request.arguments, 'uri');
    final kind = _optionalString(request.arguments, 'kind');
    if (kind == null || kind == 'procedure') {
      final procedure = _findProcedure(uri);
      if (procedure != null) {
        return _jsonToolResult(procedure.toJson());
      }
    }
    if (kind == null || kind == 'topic') {
      final topic = _findTopic(uri);
      if (topic != null) {
        return _jsonToolResult(topic.toJson());
      }
    }
    return McpToolResult.error('Unknown declared WAMP API entry: $uri');
  }

  McpWampProcedure? _findProcedure(String procedure) {
    for (final candidate in procedures) {
      if (candidate.procedure == procedure || candidate.toolName == procedure) {
        return candidate;
      }
    }
    return null;
  }

  McpWampTopic? _findTopic(String topic) {
    for (final candidate in topics) {
      if (candidate.topic == topic) {
        return candidate;
      }
    }
    return null;
  }
}

class McpWampProcedure {
  McpWampProcedure({
    required this.procedure,
    String? toolName,
    this.title,
    this.description,
    Map<String, Object?>? inputSchema,
    this.outputSchema,
    McpWampApiMetadata? metadata,
    this.argumentsBuilder,
    this.resultMapper,
    this.timeout,
    this.allowCall = true,
  }) : toolName = toolName ?? procedure,
       inputSchema = inputSchema ?? _defaultObjectSchema,
       metadata = metadata ?? const McpWampApiMetadata();

  final String procedure;
  final String toolName;
  final String? title;
  final String? description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?>? outputSchema;
  final McpWampApiMetadata metadata;
  final McpWampArgumentsBuilder? argumentsBuilder;
  final McpWampResultMapper? resultMapper;
  final Duration? timeout;
  final bool allowCall;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': 'procedure',
      'uri': procedure,
      'procedure': procedure,
      'toolName': toolName,
      'allowCall': allowCall,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      'inputSchema': mcpWampJsonCompatible(inputSchema),
      if (outputSchema != null)
        'outputSchema': mcpWampJsonCompatible(outputSchema),
      if (!metadata.isEmpty) 'metadata': metadata.toJson(),
    };
  }
}

class McpWampTopic {
  McpWampTopic({
    required this.topic,
    this.title,
    this.description,
    Map<String, Object?>? eventSchema,
    McpWampApiMetadata? metadata,
    this.allowPublish = true,
    this.allowSubscribe = true,
  }) : eventSchema = eventSchema ?? _defaultObjectSchema,
       metadata = metadata ?? const McpWampApiMetadata();

  final String topic;
  final String? title;
  final String? description;
  final Map<String, Object?> eventSchema;
  final McpWampApiMetadata metadata;
  final bool allowPublish;
  final bool allowSubscribe;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': 'topic',
      'uri': topic,
      'topic': topic,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      'eventSchema': mcpWampJsonCompatible(eventSchema),
      'allowPublish': allowPublish,
      'allowSubscribe': allowSubscribe,
      if (!metadata.isEmpty) 'metadata': metadata.toJson(),
    };
  }
}

class McpWampApiMetadata {
  const McpWampApiMetadata({
    this.shortDescription,
    this.description,
    this.domain,
    this.entity,
    this.verbs = const <String>[],
    this.tags = const <String>[],
    this.synonyms = const <String>[],
    this.publishesEvents = const <String>[],
    this.inputJsonSchema,
    this.outputJsonSchema,
    this.danger = false,
    this.readOnlyHint,
    this.destructiveHint,
    this.idempotentHint,
    this.openWorldHint,
  });

  final String? shortDescription;
  final String? description;
  final String? domain;
  final String? entity;
  final List<String> verbs;
  final List<String> tags;
  final List<String> synonyms;
  final List<String> publishesEvents;
  final Map<String, Object?>? inputJsonSchema;
  final Map<String, Object?>? outputJsonSchema;
  final bool danger;
  final bool? readOnlyHint;
  final bool? destructiveHint;
  final bool? idempotentHint;
  final bool? openWorldHint;

  bool get isEmpty =>
      shortDescription == null &&
      description == null &&
      domain == null &&
      entity == null &&
      verbs.isEmpty &&
      tags.isEmpty &&
      synonyms.isEmpty &&
      publishesEvents.isEmpty &&
      inputJsonSchema == null &&
      outputJsonSchema == null &&
      !danger &&
      readOnlyHint == null &&
      destructiveHint == null &&
      idempotentHint == null &&
      openWorldHint == null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (shortDescription != null) 'short_description': shortDescription,
      if (description != null) 'description': description,
      if (domain != null) 'domain': domain,
      if (entity != null) 'entity': entity,
      if (verbs.isNotEmpty) 'verbs': List<String>.unmodifiable(verbs),
      if (tags.isNotEmpty) 'tags': List<String>.unmodifiable(tags),
      if (synonyms.isNotEmpty) 'synonyms': List<String>.unmodifiable(synonyms),
      if (publishesEvents.isNotEmpty)
        'publishes_events': List<String>.unmodifiable(publishesEvents),
      if (inputJsonSchema != null)
        'input_json_schema': mcpWampJsonCompatible(inputJsonSchema),
      if (outputJsonSchema != null)
        'output_json_schema': mcpWampJsonCompatible(outputJsonSchema),
      if (danger) 'danger': true,
      if (readOnlyHint != null) 'read_only_hint': readOnlyHint,
      if (destructiveHint != null) 'destructive_hint': destructiveHint,
      if (idempotentHint != null) 'idempotent_hint': idempotentHint,
      if (openWorldHint != null) 'open_world_hint': openWorldHint,
    };
  }

  McpToolAnnotations? toToolAnnotations({String? title}) {
    final annotations = McpToolAnnotations(
      title: title,
      readOnlyHint: readOnlyHint ?? (danger ? false : null),
      destructiveHint: destructiveHint ?? (danger ? true : null),
      idempotentHint: idempotentHint,
      openWorldHint: openWorldHint,
    );
    return annotations.isEmpty ? null : annotations;
  }
}

class McpWampPublishRequest {
  const McpWampPublishRequest({
    required this.topic,
    this.arguments,
    this.argumentsKeywords,
    this.options,
  });

  final String topic;
  final List<dynamic>? arguments;
  final Map<String, dynamic>? argumentsKeywords;
  final PublishOptions? options;
}

class McpWampPublication {
  const McpWampPublication({this.publicationId, this.acknowledged = false});

  final int? publicationId;
  final bool acknowledged;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'acknowledged': acknowledged,
      if (publicationId != null) 'publicationId': publicationId,
    };
  }
}

class McpWampSubscribeRequest {
  const McpWampSubscribeRequest({
    required this.topic,
    required this.queueLimit,
    this.options,
  });

  final String topic;
  final int queueLimit;
  final SubscribeOptions? options;
}

class McpWampSubscription {
  const McpWampSubscription({required this.topic, this.subscriptionId});

  final String topic;
  final int? subscriptionId;
}

class McpWampEvent {
  const McpWampEvent({
    required this.subscriptionId,
    required this.publicationId,
    this.publisher,
    this.trustlevel,
    this.topic,
    this.pptScheme,
    this.pptSerializer,
    this.pptCipher,
    this.pptKeyId,
    this.customDetails,
    this.arguments,
    this.argumentsKeywords,
  });

  factory McpWampEvent.fromPayload(EventPayload event) {
    return McpWampEvent(
      subscriptionId: event.subscriptionId,
      publicationId: event.publicationId,
      publisher: event.publisher,
      trustlevel: event.trustlevel,
      topic: event.topic,
      pptScheme: event.pptScheme,
      pptSerializer: event.pptSerializer,
      pptCipher: event.pptCipher,
      pptKeyId: event.pptKeyId,
      customDetails: event.customDetails,
      arguments: event.arguments,
      argumentsKeywords: event.argumentsKeywords,
    );
  }

  final int subscriptionId;
  final int publicationId;
  final int? publisher;
  final int? trustlevel;
  final String? topic;
  final String? pptScheme;
  final String? pptSerializer;
  final String? pptCipher;
  final String? pptKeyId;
  final Map<String, dynamic>? customDetails;
  final List<dynamic>? arguments;
  final Map<String, dynamic>? argumentsKeywords;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'subscriptionId': subscriptionId,
      'publicationId': publicationId,
      if (publisher != null) 'publisher': publisher,
      if (trustlevel != null) 'trustlevel': trustlevel,
      if (topic != null) 'topic': topic,
      if (pptScheme != null) 'pptScheme': pptScheme,
      if (pptSerializer != null) 'pptSerializer': pptSerializer,
      if (pptCipher != null) 'pptCipher': pptCipher,
      if (pptKeyId != null) 'pptKeyId': pptKeyId,
      if (customDetails != null)
        'details': mcpWampJsonCompatible(customDetails),
      if (arguments != null) 'arguments': mcpWampJsonCompatible(arguments),
      if (argumentsKeywords != null)
        'argumentsKeywords': mcpWampJsonCompatible(argumentsKeywords),
    };
  }
}

class McpWampStandardMetaApi {
  static final List<McpWampProcedure> procedures =
      List<McpWampProcedure>.unmodifiable([
        _metaProcedure(
          'wamp.session.count',
          'Counts sessions visible to the caller.',
          tags: const ['wamp', 'meta', 'session'],
        ),
        _metaProcedure(
          'wamp.session.list',
          'Lists sessions visible to the caller.',
          tags: const ['wamp', 'meta', 'session'],
        ),
        _metaProcedure(
          'wamp.session.get',
          'Returns details for one session.',
          tags: const ['wamp', 'meta', 'session'],
        ),
        _metaProcedure(
          'wamp.registration.list',
          'Lists procedure registration ids grouped by match policy.',
          tags: const ['wamp', 'meta', 'registration'],
        ),
        _metaProcedure(
          'wamp.registration.lookup',
          'Looks up an exact procedure registration.',
          tags: const ['wamp', 'meta', 'registration'],
        ),
        _metaProcedure(
          'wamp.registration.match',
          'Matches a procedure URI against registered procedures.',
          tags: const ['wamp', 'meta', 'registration'],
        ),
        _metaProcedure(
          'wamp.registration.get',
          'Returns details for one registration.',
          tags: const ['wamp', 'meta', 'registration'],
        ),
        _metaProcedure(
          'wamp.registration.list_callees',
          'Lists sessions currently attached to a registration.',
          tags: const ['wamp', 'meta', 'registration'],
        ),
        _metaProcedure(
          'wamp.registration.count_callees',
          'Counts sessions currently attached to a registration.',
          tags: const ['wamp', 'meta', 'registration'],
        ),
        _metaProcedure(
          'wamp.subscription.list',
          'Lists subscription ids grouped by match policy.',
          tags: const ['wamp', 'meta', 'subscription'],
        ),
        _metaProcedure(
          'wamp.subscription.lookup',
          'Looks up an exact topic subscription.',
          tags: const ['wamp', 'meta', 'subscription'],
        ),
        _metaProcedure(
          'wamp.subscription.match',
          'Matches a topic URI against subscriptions.',
          tags: const ['wamp', 'meta', 'subscription'],
        ),
        _metaProcedure(
          'wamp.subscription.get',
          'Returns details for one subscription.',
          tags: const ['wamp', 'meta', 'subscription'],
        ),
        _metaProcedure(
          'wamp.subscription.list_subscribers',
          'Lists sessions currently attached to a subscription.',
          tags: const ['wamp', 'meta', 'subscription'],
        ),
        _metaProcedure(
          'wamp.subscription.count_subscribers',
          'Counts sessions currently attached to a subscription.',
          tags: const ['wamp', 'meta', 'subscription'],
        ),
      ]);

  static final List<McpWampTopic> topics = List<McpWampTopic>.unmodifiable([
    _metaTopic('wamp.session.on_join', 'Session join meta event.'),
    _metaTopic('wamp.session.on_leave', 'Session leave meta event.'),
    _metaTopic(
      'wamp.registration.on_create',
      'Procedure registration created meta event.',
    ),
    _metaTopic(
      'wamp.registration.on_register',
      'Callee attached to registration meta event.',
    ),
    _metaTopic(
      'wamp.registration.on_unregister',
      'Callee detached from registration meta event.',
    ),
    _metaTopic(
      'wamp.registration.on_delete',
      'Procedure registration deleted meta event.',
    ),
    _metaTopic(
      'wamp.subscription.on_create',
      'Topic subscription created meta event.',
    ),
    _metaTopic(
      'wamp.subscription.on_subscribe',
      'Subscriber attached to subscription meta event.',
    ),
    _metaTopic(
      'wamp.subscription.on_unsubscribe',
      'Subscriber detached from subscription meta event.',
    ),
    _metaTopic(
      'wamp.subscription.on_delete',
      'Topic subscription deleted meta event.',
    ),
  ]);
}

class _McpWampPubSubTools {
  _McpWampPubSubTools(
    this.api,
    this._publish,
    this._subscribe,
    this._unsubscribe,
  );

  final McpWampApi api;
  final McpWampPublishInvoker? _publish;
  final McpWampSubscribeInvoker? _subscribe;
  final McpWampUnsubscribeInvoker? _unsubscribe;
  final Map<String, _BufferedSubscription> _subscriptions =
      <String, _BufferedSubscription>{};
  int _nextHandle = 1;

  Future<McpToolResult> publish(McpToolRequest request) async {
    final publish = _publish;
    if (publish == null) {
      return McpToolResult.error('WAMP publish support is not configured.');
    }
    final topic = _declaredTopic(
      request.arguments,
      requirePublish: true,
      argumentName: 'topic',
    );
    final arguments = _optionalList(request.arguments, 'arguments');
    final argumentsKeywords = _optionalDynamicMap(
      request.arguments,
      'argumentsKeywords',
    );
    final acknowledge = _optionalBool(request.arguments, 'acknowledge');
    final customOptions = _optionalDynamicMap(request.arguments, 'options');
    final publication = await publish(
      McpWampPublishRequest(
        topic: topic.topic,
        arguments: arguments,
        argumentsKeywords: argumentsKeywords,
        options: PublishOptions(
          acknowledge: acknowledge,
          custom: customOptions,
        ),
      ),
    );
    return _jsonToolResult(<String, Object?>{
      'topic': topic.topic,
      ...?publication?.toJson(),
    });
  }

  Future<McpToolResult> subscribe(McpToolRequest request) async {
    final subscribe = _subscribe;
    final unsubscribe = _unsubscribe;
    if (subscribe == null || unsubscribe == null) {
      return McpToolResult.error('WAMP subscribe support is not configured.');
    }
    final topic = _declaredTopic(
      request.arguments,
      requireSubscribe: true,
      argumentName: 'topic',
    );
    final queueLimit =
        _optionalPositiveInt(request.arguments, 'queueLimit') ?? 100;
    final customOptions = _optionalDynamicMap(request.arguments, 'options');
    final handle = 'wamp-sub-${_nextHandle++}';
    final buffer = _BufferedSubscription(
      handle: handle,
      topic: topic.topic,
      queueLimit: queueLimit,
    );
    final subscription = await subscribe(
      McpWampSubscribeRequest(
        topic: topic.topic,
        queueLimit: queueLimit,
        options: customOptions == null
            ? null
            : SubscribeOptions(custom: customOptions),
      ),
      buffer.add,
    );
    buffer.attachSubscription(subscription);
    _subscriptions[handle] = buffer;
    return _jsonToolResult(<String, Object?>{
      'handle': handle,
      'topic': subscription.topic,
      if (subscription.subscriptionId != null)
        'subscriptionId': subscription.subscriptionId,
      'queueLimit': queueLimit,
    });
  }

  Future<McpToolResult> poll(McpToolRequest request) async {
    final handle = _requiredString(request.arguments, 'handle');
    final subscription = _subscriptions[handle];
    if (subscription == null) {
      return McpToolResult.error('Unknown WAMP subscription handle: $handle');
    }
    final limit = _optionalPositiveInt(request.arguments, 'limit');
    final events = subscription.drain(limit: limit);
    return _jsonToolResult(<String, Object?>{
      'handle': handle,
      'topic': subscription.topic,
      'events': [for (final event in events) event.toJson()],
      'dropped': subscription.dropped,
      'remaining': subscription.length,
    });
  }

  Future<McpToolResult> unsubscribe(McpToolRequest request) async {
    final unsubscribe = _unsubscribe;
    if (unsubscribe == null) {
      return McpToolResult.error('WAMP subscribe support is not configured.');
    }
    final handle = _requiredString(request.arguments, 'handle');
    final subscription = _subscriptions.remove(handle);
    if (subscription == null) {
      return McpToolResult.error('Unknown WAMP subscription handle: $handle');
    }
    await unsubscribe(subscription.subscription);
    return _jsonToolResult(<String, Object?>{
      'handle': handle,
      'topic': subscription.topic,
      'unsubscribed': true,
    });
  }

  McpWampTopic _declaredTopic(
    JsonMap arguments, {
    required String argumentName,
    bool requirePublish = false,
    bool requireSubscribe = false,
  }) {
    final topic = _requiredString(arguments, argumentName);
    final declared = api._findTopic(topic);
    if (declared == null) {
      throw ArgumentError('Unknown declared WAMP topic: $topic');
    }
    if (requirePublish && !declared.allowPublish) {
      throw ArgumentError('WAMP topic is not publishable through MCP: $topic');
    }
    if (requireSubscribe && !declared.allowSubscribe) {
      throw ArgumentError('WAMP topic is not subscribable through MCP: $topic');
    }
    return declared;
  }
}

class _BufferedSubscription {
  _BufferedSubscription({
    required this.handle,
    required this.topic,
    required this.queueLimit,
    McpWampSubscription? subscription,
  }) : _subscription = subscription ?? McpWampSubscription(topic: topic);

  final String handle;
  final String topic;
  final int queueLimit;
  McpWampSubscription _subscription;
  final List<McpWampEvent> _events = <McpWampEvent>[];
  int dropped = 0;

  int get length => _events.length;

  McpWampSubscription get subscription => _subscription;

  void attachSubscription(McpWampSubscription subscription) {
    _subscription = subscription;
  }

  void add(McpWampEvent event) {
    while (_events.length >= queueLimit) {
      _events.removeAt(0);
      dropped += 1;
    }
    _events.add(event);
  }

  List<McpWampEvent> drain({int? limit}) {
    final take = limit == null || limit > _events.length
        ? _events.length
        : limit;
    final drained = List<McpWampEvent>.unmodifiable(_events.take(take));
    _events.removeRange(0, take);
    return drained;
  }
}

const Map<String, Object?> _defaultObjectSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': true,
};

McpWampProcedure _metaProcedure(
  String procedure,
  String description, {
  required List<String> tags,
}) {
  return McpWampProcedure(
    procedure: procedure,
    title: procedure,
    description: description,
    inputSchema: const {
      'type': 'object',
      'properties': {
        'arguments': {'type': 'array'},
        'argumentsKeywords': {'type': 'object', 'additionalProperties': true},
      },
      'additionalProperties': true,
    },
    argumentsBuilder: _standardMetaArgumentsBuilder,
    metadata: McpWampApiMetadata(
      shortDescription: description,
      domain: 'wamp',
      entity: 'meta',
      verbs: const ['inspect'],
      tags: tags,
    ),
  );
}

McpWampCallPayload _standardMetaArgumentsBuilder(McpToolRequest request) {
  final positional = _optionalList(request.arguments, 'arguments');
  final explicitKeywords = _optionalDynamicMap(
    request.arguments,
    'argumentsKeywords',
  );
  final inlineKeywords = <String, dynamic>{
    for (final entry in request.arguments.entries)
      if (entry.key != 'arguments' && entry.key != 'argumentsKeywords')
        entry.key: entry.value,
  };
  return McpWampCallPayload(
    arguments: positional,
    argumentsKeywords: inlineKeywords.isNotEmpty
        ? <String, dynamic>{...?explicitKeywords, ...inlineKeywords}
        : explicitKeywords,
  );
}

McpWampTopic _metaTopic(String topic, String description) {
  return McpWampTopic(
    topic: topic,
    title: topic,
    description: description,
    allowPublish: false,
    metadata: McpWampApiMetadata(
      shortDescription: description,
      domain: 'wamp',
      entity: 'meta',
      verbs: const ['observe'],
      tags: const ['wamp', 'meta', 'event'],
    ),
  );
}

List<McpWampTopic> _deduplicateTopics(Iterable<McpWampTopic> topics) {
  final byTopic = <String, McpWampTopic>{};
  for (final topic in topics) {
    byTopic.putIfAbsent(topic.topic, () => topic);
  }
  return List<McpWampTopic>.unmodifiable(byTopic.values);
}

Iterable<McpWampTopic> _publishedEventTopicsFor(
  McpWampProcedure procedure,
) sync* {
  final metadata = procedure.metadata;
  for (final topic in metadata.publishesEvents) {
    final description = 'Event published by ${procedure.procedure}.';
    yield McpWampTopic(
      topic: topic,
      title: topic,
      description: description,
      metadata: McpWampApiMetadata(
        shortDescription: description,
        domain: metadata.domain,
        entity: metadata.entity,
        verbs: const ['observe'],
        tags: _deduplicateStrings([...metadata.tags, 'event']),
      ),
    );
  }
}

List<String> _deduplicateStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    if (seen.add(value)) {
      result.add(value);
    }
  }
  return List<String>.unmodifiable(result);
}

McpToolResult _jsonToolResult(Map<String, Object?> result) {
  return McpToolResult.text(jsonEncode(result), structuredContent: result);
}

String _requiredString(JsonMap arguments, String key) {
  final value = arguments[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw ArgumentError('arguments.$key must be a non-empty string');
}

String? _optionalString(JsonMap arguments, String key) {
  final value = arguments[key];
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw ArgumentError('arguments.$key must be a non-empty string');
}

bool? _optionalBool(JsonMap arguments, String key) {
  final value = arguments[key];
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw ArgumentError('arguments.$key must be a boolean');
}

int? _optionalPositiveInt(JsonMap arguments, String key) {
  final value = arguments[key];
  if (value == null) {
    return null;
  }
  if (value is int && value > 0) {
    return value;
  }
  throw ArgumentError('arguments.$key must be a positive integer');
}

List<dynamic>? _optionalList(JsonMap arguments, String key) {
  final value = arguments[key];
  if (value == null) {
    return null;
  }
  if (value is List) {
    return List<dynamic>.from(value);
  }
  throw ArgumentError('arguments.$key must be an array');
}

Map<String, dynamic>? _optionalDynamicMap(JsonMap arguments, String key) {
  final value = arguments[key];
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw ArgumentError('arguments.$key must be an object');
  }
  return <String, dynamic>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}
