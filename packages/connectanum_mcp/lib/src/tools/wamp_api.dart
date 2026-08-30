import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectanum_client/connectanum.dart';

import '../protocol/errors.dart';
import '../protocol/json_rpc.dart';
import '../protocol/pagination.dart';
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

/// Retains WAMP pub/sub handles across regenerated MCP tool catalogs.
///
/// Reuse one state object only for successive [McpWampApi.toTools] or
/// [McpWampApi.toSessionTools] calls that belong to the same logical endpoint,
/// session, and authorization principal.
final class McpWampPubSubState {
  _McpWampPubSubTools? _bridge;

  /// Releases retained handles whose topics are no longer subscribable.
  ///
  /// [release] overrides the latest unsubscriber bound by [McpWampApi.toTools]
  /// or [McpWampApi.toSessionTools]. Hosts can use it for mandatory cleanup
  /// that must not depend on user-facing unsubscribe authorization. A handle
  /// remains available for retry when releasing its subscription fails.
  Future<void> reconcileSubscribedTopics(
    Iterable<String> subscribableTopics, {
    McpWampUnsubscribeInvoker? release,
  }) async {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }
    await bridge._reconcileSubscribedTopics(
      Set<String>.of(subscribableTopics),
      release: release,
    );
  }

  _McpWampPubSubTools _bind({
    required McpWampApi api,
    required McpWampPublishInvoker? publish,
    required McpWampSubscribeInvoker? subscribe,
    required McpWampUnsubscribeInvoker? unsubscribe,
    required int? maxBufferedEventBytes,
  }) {
    final bridge = _bridge;
    if (bridge == null) {
      return _bridge = _McpWampPubSubTools(
        api,
        publish,
        subscribe,
        unsubscribe,
        maxBufferedEventBytes,
      );
    }
    bridge._rebind(
      api: api,
      publish: publish,
      subscribe: subscribe,
      unsubscribe: unsubscribe,
      maxBufferedEventBytes: maxBufferedEventBytes,
    );
    return bridge;
  }
}

const String _wampApiCursorPrefix = 'wampApi:';
var _nextWampApiCursorRevision = 0;

int? _validatedWampApiListPageSize(int? value) {
  if (value != null && value <= 0) {
    throw ArgumentError.value(
      value,
      'listPageSize',
      'must be a positive integer',
    );
  }
  return value;
}

class McpWampApi {
  McpWampApi({
    this.name,
    Iterable<McpWampProcedure> procedures = const [],
    Iterable<McpWampTopic> topics = const [],
    bool includeStandardMetaApi = false,
    bool includePublishedEventTopics = true,
    int? listPageSize,
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
       listPageSize = _validatedWampApiListPageSize(listPageSize),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String? name;
  final List<McpWampProcedure> procedures;
  final List<McpWampTopic> topics;
  final int? listPageSize;
  final Map<String, Object?> metadata;
  final int _cursorRevision = _nextWampApiCursorRevision++;

  List<McpTool> toTools({
    McpWampCallInvoker? call,
    McpWampPublishInvoker? publish,
    McpWampSubscribeInvoker? subscribe,
    McpWampUnsubscribeInvoker? unsubscribe,
    bool includeApiMetaTools = true,
    bool includePubSubTools = true,
    Duration? timeout,
    int? maxBufferedEventBytes,
    McpWampPubSubState? pubSubState,
  }) {
    if (maxBufferedEventBytes != null && maxBufferedEventBytes <= 0) {
      throw ArgumentError.value(
        maxBufferedEventBytes,
        'maxBufferedEventBytes',
        'must be a positive integer',
      );
    }
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
          maxBufferedEventBytes: maxBufferedEventBytes,
          pubSubState: pubSubState,
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
    int? maxBufferedEventBytes,
    McpWampPubSubState? pubSubState,
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
          sessionSubscription: subscribed,
        );
      },
      unsubscribe: (subscription) async {
        final sessionSubscription = subscription.sessionSubscription;
        if (sessionSubscription != null) {
          await session.releaseSubscription(sessionSubscription);
          return;
        }
        final subscriptionId = subscription.subscriptionId;
        if (subscriptionId != null) {
          await session.unsubscribe(subscriptionId);
        }
      },
      includeApiMetaTools: includeApiMetaTools,
      includePubSubTools: includePubSubTools,
      timeout: timeout,
      maxBufferedEventBytes: maxBufferedEventBytes,
      pubSubState: pubSubState,
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
            'cursor': {'type': 'string'},
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
    required int? maxBufferedEventBytes,
    required McpWampPubSubState? pubSubState,
  }) {
    final bridge =
        pubSubState?._bind(
          api: this,
          publish: publish,
          subscribe: subscribe,
          unsubscribe: unsubscribe,
          maxBufferedEventBytes: maxBufferedEventBytes,
        ) ??
        _McpWampPubSubTools(
          this,
          publish,
          subscribe,
          unsubscribe,
          maxBufferedEventBytes,
        );
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
    final cursor = _optionalString(request.arguments, 'cursor');
    final includeProcedures = kind == null || kind == 'procedure';
    final includeTopics = kind == null || kind == 'topic';
    final visibleProcedures = <McpWampProcedure>[
      if (includeProcedures)
        for (final procedure in procedures)
          if (tag == null || procedure.metadata.tags.contains(tag)) procedure,
    ]..sort((left, right) => left.procedure.compareTo(right.procedure));
    final visibleTopics = <McpWampTopic>[
      if (includeTopics)
        for (final topic in topics)
          if (tag == null || topic.metadata.tags.contains(tag)) topic,
    ]..sort((left, right) => left.topic.compareTo(right.topic));

    final entries = <({String kind, Map<String, Object?> value})>[
      for (final procedure in visibleProcedures)
        (kind: 'procedure', value: procedure.toJson()),
      for (final topic in visibleTopics) (kind: 'topic', value: topic.toJson()),
    ];
    final pageSize = listPageSize;
    if (pageSize == null && cursor != null) {
      throw McpException(
        McpErrorCodes.invalidParams,
        'connectanum.api.list.arguments.cursor is invalid or stale',
      );
    }

    final start = pageSize == null
        ? 0
        : decodeMcpCursor(
            cursor,
            prefix: _wampApiCursorPrefix,
            expectedRevision: Object.hash(_cursorRevision, kind, tag),
            maxOffset: entries.length,
            errorMessage:
                'connectanum.api.list.arguments.cursor is invalid or stale',
          );
    final end = pageSize == null
        ? entries.length
        : math.min(start + pageSize, entries.length);
    final page = entries.sublist(start, end);
    final result = <String, Object?>{
      if (name != null) 'name': name,
      if (metadata.isNotEmpty) 'metadata': mcpWampJsonCompatible(metadata),
      if (includeProcedures)
        'procedures': [
          for (final entry in page)
            if (entry.kind == 'procedure') entry.value,
        ],
      if (includeTopics)
        'topics': [
          for (final entry in page)
            if (entry.kind == 'topic') entry.value,
        ],
      if (pageSize != null && end < entries.length)
        'nextCursor': encodeMcpCursor(
          prefix: _wampApiCursorPrefix,
          revision: Object.hash(_cursorRevision, kind, tag),
          offset: end,
        ),
    };
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

/// Search, schema, and safety metadata for a WAMP procedure or topic.
class McpWampApiMetadata {
  /// Creates metadata advertised by the generated MCP catalog tools.
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

  /// Compact summary suitable for catalogs and search results.
  final String? shortDescription;

  /// Full human-readable description of the WAMP operation.
  final String? description;

  /// Application domain associated with the operation.
  final String? domain;

  /// Entity type read or changed by the operation.
  final String? entity;

  /// Action verbs that help agents discover the operation.
  final List<String> verbs;

  /// Free-form catalog tags associated with the operation.
  final List<String> tags;

  /// Alternative terms that should match this operation in search.
  final List<String> synonyms;

  /// Event topics that the operation may cause the router to publish.
  final List<String> publishesEvents;

  /// JSON Schema for the operation's logical input.
  final Map<String, Object?>? inputJsonSchema;

  /// JSON Schema for the operation's logical output.
  final Map<String, Object?>? outputJsonSchema;

  /// Whether invoking the operation can carry elevated application risk.
  final bool danger;

  /// MCP hint indicating that the operation does not modify state.
  final bool? readOnlyHint;

  /// MCP hint indicating that the operation may destroy existing state.
  final bool? destructiveHint;

  /// MCP hint indicating that repeated identical calls are safe.
  final bool? idempotentHint;

  /// MCP hint indicating that the operation can interact outside its domain.
  final bool? openWorldHint;

  /// Whether no catalog, schema, or safety metadata is present.
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

  /// Converts the metadata to the direct JSON catalog representation.
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

  /// Maps safety hints to MCP tool annotations, or returns `null` when empty.
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
  const McpWampSubscription({
    required this.topic,
    this.subscriptionId,
    this.sessionSubscription,
  });

  final String topic;
  final int? subscriptionId;
  final Subscribed? sessionSubscription;
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
          namedArgument: 'sessionId',
        ),
        _metaProcedure(
          'wamp.registration.list',
          'Lists procedure registration ids grouped by match policy.',
          tags: const ['wamp', 'meta', 'registration'],
        ),
        _metaProcedure(
          'wamp.registration.lookup',
          'Looks up a procedure registration by URI and match policy.',
          tags: const ['wamp', 'meta', 'registration'],
          namedArgument: 'procedure',
          allowMatch: true,
        ),
        _metaProcedure(
          'wamp.registration.match',
          'Matches a procedure URI against registered procedures.',
          tags: const ['wamp', 'meta', 'registration'],
          namedArgument: 'procedure',
        ),
        _metaProcedure(
          'wamp.registration.get',
          'Returns details for one registration.',
          tags: const ['wamp', 'meta', 'registration'],
          namedArgument: 'registrationId',
        ),
        _metaProcedure(
          'wamp.registration.list_callees',
          'Lists sessions currently attached to a registration.',
          tags: const ['wamp', 'meta', 'registration'],
          namedArgument: 'registrationId',
        ),
        _metaProcedure(
          'wamp.registration.count_callees',
          'Counts sessions currently attached to a registration.',
          tags: const ['wamp', 'meta', 'registration'],
          namedArgument: 'registrationId',
        ),
        _metaProcedure(
          'wamp.subscription.list',
          'Lists subscription ids grouped by match policy.',
          tags: const ['wamp', 'meta', 'subscription'],
        ),
        _metaProcedure(
          'wamp.subscription.lookup',
          'Looks up a topic subscription by URI and match policy.',
          tags: const ['wamp', 'meta', 'subscription'],
          namedArgument: 'topic',
          allowMatch: true,
        ),
        _metaProcedure(
          'wamp.subscription.match',
          'Matches a topic URI against subscriptions.',
          tags: const ['wamp', 'meta', 'subscription'],
          namedArgument: 'topic',
        ),
        _metaProcedure(
          'wamp.subscription.get',
          'Returns details for one subscription.',
          tags: const ['wamp', 'meta', 'subscription'],
          namedArgument: 'subscriptionId',
        ),
        _metaProcedure(
          'wamp.subscription.list_subscribers',
          'Lists sessions currently attached to a subscription.',
          tags: const ['wamp', 'meta', 'subscription'],
          namedArgument: 'subscriptionId',
        ),
        _metaProcedure(
          'wamp.subscription.count_subscribers',
          'Counts sessions currently attached to a subscription.',
          tags: const ['wamp', 'meta', 'subscription'],
          namedArgument: 'subscriptionId',
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
    this.maxBufferedEventBytes,
  );

  void _rebind({
    required McpWampApi api,
    required McpWampPublishInvoker? publish,
    required McpWampSubscribeInvoker? subscribe,
    required McpWampUnsubscribeInvoker? unsubscribe,
    required int? maxBufferedEventBytes,
  }) {
    this.api = api;
    _publish = publish;
    _subscribe = subscribe;
    _unsubscribe = unsubscribe;
    this.maxBufferedEventBytes = maxBufferedEventBytes;
  }

  McpWampApi api;
  McpWampPublishInvoker? _publish;
  McpWampSubscribeInvoker? _subscribe;
  McpWampUnsubscribeInvoker? _unsubscribe;
  int? maxBufferedEventBytes;
  final Map<String, _BufferedSubscription> _subscriptions =
      <String, _BufferedSubscription>{};
  final Map<String, _PendingBufferedSubscription> _pendingSubscriptions =
      <String, _PendingBufferedSubscription>{};
  int _nextHandle = 1;

  Future<void> _reconcileSubscribedTopics(
    Set<String> subscribableTopics, {
    McpWampUnsubscribeInvoker? release,
  }) async {
    final revokedPending = <MapEntry<String, _PendingBufferedSubscription>>[
      for (final entry in _pendingSubscriptions.entries)
        if (entry.value.revoked ||
            !subscribableTopics.contains(entry.value.buffer.topic))
          entry,
    ];
    final revokedHandles = <String>[
      for (final entry in _subscriptions.entries)
        if (!subscribableTopics.contains(entry.value.topic)) entry.key,
    ];
    if (revokedPending.isEmpty && revokedHandles.isEmpty) {
      return;
    }
    final releaseSubscription = release ?? _unsubscribe;
    if (releaseSubscription == null) {
      throw StateError('WAMP unsubscribe support is not configured.');
    }

    for (final entry in revokedPending) {
      entry.value.revoke(releaseSubscription);
    }
    for (final entry in revokedPending) {
      if (await entry.value.releaseIfReady()) {
        _pendingSubscriptions.remove(entry.key);
      }
    }
    for (final handle in revokedHandles) {
      final subscription = _subscriptions.remove(handle);
      if (subscription == null) {
        continue;
      }
      try {
        await releaseSubscription(subscription.subscription);
      } catch (_) {
        _subscriptions.putIfAbsent(handle, () => subscription);
        rethrow;
      }
    }
  }

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
        options: _publishOptionsFrom(
          acknowledge: acknowledge,
          options: customOptions,
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
      maxBufferedEventBytes: maxBufferedEventBytes,
    );
    final pending = _PendingBufferedSubscription(buffer);
    _pendingSubscriptions[handle] = pending;
    try {
      final subscription = await subscribe(
        McpWampSubscribeRequest(
          topic: topic.topic,
          queueLimit: queueLimit,
          options: _subscribeOptionsFrom(customOptions),
        ),
        pending.add,
      );
      pending.attachSubscription(subscription);
      if (pending.revoked) {
        await pending.releaseIfReady();
        _pendingSubscriptions.remove(handle);
        return McpToolResult.error(
          'WAMP topic is no longer subscribable while its subscription was '
          'pending: ${topic.topic}',
        );
      }
      _pendingSubscriptions.remove(handle);
      _subscriptions[handle] = buffer;
      return _jsonToolResult(<String, Object?>{
        'handle': handle,
        'topic': subscription.topic,
        if (subscription.subscriptionId != null)
          'subscriptionId': subscription.subscriptionId,
        'queueLimit': queueLimit,
        if (maxBufferedEventBytes != null)
          'queueByteLimit': maxBufferedEventBytes,
      });
    } catch (_) {
      if (!pending.hasSubscription || pending.released) {
        _pendingSubscriptions.remove(handle);
      }
      rethrow;
    }
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
      'remainingBytes': subscription.bufferedEventBytes,
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
    try {
      await unsubscribe(subscription.subscription);
    } catch (_) {
      _subscriptions.putIfAbsent(handle, () => subscription);
      rethrow;
    }
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

class _PendingBufferedSubscription {
  _PendingBufferedSubscription(this.buffer);

  final _BufferedSubscription buffer;
  bool revoked = false;
  bool hasSubscription = false;
  bool released = false;
  McpWampUnsubscribeInvoker? _release;
  Future<void>? _releaseFuture;

  void add(McpWampEvent event) {
    if (!revoked) {
      buffer.add(event);
    }
  }

  void attachSubscription(McpWampSubscription subscription) {
    buffer.attachSubscription(subscription);
    hasSubscription = true;
  }

  void revoke(McpWampUnsubscribeInvoker release) {
    revoked = true;
    _release = release;
    buffer.drain();
  }

  Future<bool> releaseIfReady() async {
    if (!revoked || !hasSubscription) {
      return false;
    }
    if (released) {
      return true;
    }
    final release = _release;
    if (release == null) {
      throw StateError('WAMP unsubscribe support is not configured.');
    }
    final operation = _releaseFuture ??= Future<void>.sync(
      () => release(buffer.subscription),
    );
    try {
      await operation;
      released = true;
      return true;
    } catch (_) {
      if (identical(_releaseFuture, operation)) {
        _releaseFuture = null;
      }
      rethrow;
    }
  }
}

class _BufferedSubscription {
  _BufferedSubscription({
    required this.handle,
    required this.topic,
    required this.queueLimit,
    required this.maxBufferedEventBytes,
    McpWampSubscription? subscription,
  }) : _subscription = subscription ?? McpWampSubscription(topic: topic);

  final String handle;
  final String topic;
  final int queueLimit;
  final int? maxBufferedEventBytes;
  McpWampSubscription _subscription;
  final List<({McpWampEvent event, int encodedByteLength})> _events =
      <({McpWampEvent event, int encodedByteLength})>[];
  int _bufferedEventBytes = 0;
  int dropped = 0;

  int get length => _events.length;

  int get bufferedEventBytes => _bufferedEventBytes;

  McpWampSubscription get subscription => _subscription;

  void attachSubscription(McpWampSubscription subscription) {
    _subscription = subscription;
  }

  void add(McpWampEvent event) {
    final encodedByteLength = utf8.encode(jsonEncode(event.toJson())).length;
    final byteLimit = maxBufferedEventBytes;
    if (byteLimit != null && encodedByteLength > byteLimit) {
      dropped += 1;
      return;
    }
    while (_events.length >= queueLimit ||
        (byteLimit != null &&
            _bufferedEventBytes + encodedByteLength > byteLimit)) {
      _dropOldest();
    }
    _events.add((event: event, encodedByteLength: encodedByteLength));
    _bufferedEventBytes += encodedByteLength;
  }

  List<McpWampEvent> drain({int? limit}) {
    final take = limit == null || limit > _events.length
        ? _events.length
        : limit;
    final drained = List<McpWampEvent>.unmodifiable(
      _events.take(take).map((buffered) => buffered.event),
    );
    for (var index = 0; index < take; index++) {
      _bufferedEventBytes -= _events[index].encodedByteLength;
    }
    _events.removeRange(0, take);
    return drained;
  }

  void _dropOldest() {
    final removed = _events.removeAt(0);
    _bufferedEventBytes -= removed.encodedByteLength;
    dropped += 1;
  }
}

const Map<String, Object?> _defaultObjectSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': true,
};

const Map<String, Object?> _standardMetaOutputSchema = {
  'type': 'object',
  'properties': {
    'arguments': {'type': 'array'},
    'argumentsKeywords': {
      'type': 'object',
      'additionalProperties': true,
    },
    'details': {
      'type': 'object',
      'additionalProperties': true,
    },
  },
  'additionalProperties': false,
};

List<String> _standardMetaLegacyAliases(String namedArgument) {
  return switch (namedArgument) {
    'sessionId' => const ['id', 'session'],
    'registrationId' => const ['id', 'registration'],
    'subscriptionId' => const ['id', 'subscription'],
    'procedure' || 'topic' => const ['uri'],
    _ => throw StateError(
      'Unknown standard WAMP Meta argument: $namedArgument',
    ),
  };
}

Map<String, Object?> _standardMetaInputSchema(
  String? namedArgument, {
  required bool allowMatch,
}) {
  final legacyAliases = namedArgument == null
      ? const <String>[]
      : _standardMetaLegacyAliases(namedArgument);
  final properties = <String, Object?>{
    ?namedArgument: _standardMetaNamedArgumentSchema(namedArgument),
    for (final alias in legacyAliases)
      alias: <String, Object?>{
        ..._standardMetaNamedArgumentSchema(namedArgument!),
        'description': 'Legacy direct JSON alias; prefer $namedArgument.',
      },
    if (allowMatch)
      'match': const {
        'type': 'string',
        'enum': ['exact', 'prefix', 'wildcard'],
        'description':
            'Optional WAMP registration or subscription match policy.',
      },
    'arguments': const {
      'type': 'array',
      'description': 'Raw positional WAMP arguments compatibility form.',
    },
    'argumentsKeywords': const {
      'type': 'object',
      'additionalProperties': true,
      'description': 'Raw keyword WAMP arguments compatibility form.',
    },
  };
  return <String, Object?>{
    'type': 'object',
    'properties': properties,
    if (namedArgument != null)
      'anyOf': [
        {
          'required': [namedArgument],
        },
        for (final alias in legacyAliases)
          {
            'required': [alias],
          },
        const {
          'required': ['arguments'],
        },
        const {
          'required': ['argumentsKeywords'],
        },
      ],
    'additionalProperties': false,
  };
}

Map<String, Object?> _standardMetaNamedArgumentSchema(String argument) {
  return switch (argument) {
    'sessionId' || 'registrationId' || 'subscriptionId' => <String, Object?>{
      'type': 'integer',
      'minimum': 1,
    },
    'procedure' || 'topic' => <String, Object?>{
      'type': 'string',
      'minLength': 1,
    },
    _ => throw StateError('Unknown standard WAMP Meta argument: $argument'),
  };
}

McpWampProcedure _metaProcedure(
  String procedure,
  String description, {
  required List<String> tags,
  String? namedArgument,
  bool allowMatch = false,
}) {
  return McpWampProcedure(
    procedure: procedure,
    title: procedure,
    description: description,
    inputSchema: _standardMetaInputSchema(
      namedArgument,
      allowMatch: allowMatch,
    ),
    outputSchema: _standardMetaOutputSchema,
    argumentsBuilder: (request) => _standardMetaArgumentsBuilder(
      request,
      namedArgument: namedArgument,
      allowMatch: allowMatch,
    ),
    metadata: McpWampApiMetadata(
      shortDescription: description,
      domain: 'wamp',
      entity: 'meta',
      verbs: const ['inspect'],
      tags: tags,
    ),
  );
}

McpWampCallPayload _standardMetaArgumentsBuilder(
  McpToolRequest request, {
  required String? namedArgument,
  required bool allowMatch,
}) {
  final arguments = request.arguments;
  final legacyAliases = namedArgument == null
      ? const <String>[]
      : _standardMetaLegacyAliases(namedArgument);
  final suppliedNamedKeys = <String>[
    if (namedArgument != null && arguments.containsKey(namedArgument))
      namedArgument,
    for (final alias in legacyAliases)
      if (arguments.containsKey(alias)) alias,
  ];
  if (suppliedNamedKeys.length > 1) {
    throw ArgumentError(
      'arguments cannot combine standard WAMP Meta parameter aliases',
    );
  }

  final hasRawArguments = arguments.containsKey('arguments');
  final hasRawKeywords = arguments.containsKey('argumentsKeywords');
  if (suppliedNamedKeys.isNotEmpty && (hasRawArguments || hasRawKeywords)) {
    throw ArgumentError(
      'arguments cannot combine named and raw WAMP arguments',
    );
  }

  final supportedKeys = <String>{
    ?namedArgument,
    ...legacyAliases,
    if (allowMatch) 'match',
    'arguments',
    'argumentsKeywords',
  };
  final unknownKeys = arguments.keys
      .where((key) => !supportedKeys.contains(key))
      .toList(growable: false);
  if (unknownKeys.isNotEmpty) {
    throw ArgumentError(
      'arguments contains unsupported standard WAMP Meta fields: '
      '${unknownKeys.join(', ')}',
    );
  }

  final match = allowMatch ? _optionalStandardMetaMatch(arguments) : null;
  if (hasRawArguments || hasRawKeywords) {
    final positional = _optionalList(arguments, 'arguments');
    final explicitKeywords = _optionalDynamicMap(
      arguments,
      'argumentsKeywords',
    );
    return McpWampCallPayload(
      arguments: positional,
      argumentsKeywords: match == null
          ? explicitKeywords
          : <String, dynamic>{...?explicitKeywords, 'match': match},
    );
  }

  if (namedArgument == null) {
    return const McpWampCallPayload();
  }
  final inputKey = suppliedNamedKeys.isEmpty
      ? namedArgument
      : suppliedNamedKeys.single;
  final positional = switch (namedArgument) {
    'sessionId' || 'registrationId' || 'subscriptionId' => [
      _requiredPositiveInt(arguments, inputKey),
    ],
    'procedure' || 'topic' => [_requiredString(arguments, inputKey)],
    _ => throw StateError(
      'Unknown standard WAMP Meta argument: $namedArgument',
    ),
  };
  return McpWampCallPayload(
    arguments: positional,
    argumentsKeywords: match == null ? null : <String, dynamic>{'match': match},
  );
}

int _requiredPositiveInt(JsonMap arguments, String key) {
  final value = _optionalPositiveInt(arguments, key);
  if (value != null) {
    return value;
  }
  throw ArgumentError('arguments.$key must be a positive integer');
}

String? _optionalStandardMetaMatch(JsonMap arguments) {
  final match = _optionalString(arguments, 'match');
  if (match == null) {
    return null;
  }
  const policies = {'exact', 'prefix', 'wildcard'};
  if (!policies.contains(match)) {
    throw ArgumentError(
      'arguments.match must be exact, prefix, or wildcard',
    );
  }
  return match;
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

PublishOptions _publishOptionsFrom({
  required bool? acknowledge,
  required Map<String, dynamic>? options,
}) {
  final custom = <String, dynamic>{...?options};
  final optionAcknowledge = _takeBoolOption(custom, ['acknowledge']);
  return PublishOptions(
    acknowledge: acknowledge ?? optionAcknowledge,
    exclude: _takeIntListOption(custom, ['exclude']),
    excludeAuthId: _takeStringListOption(custom, [
      'exclude_authid',
      'exclude_auth_id',
      'excludeAuthId',
    ]),
    excludeAuthRole: _takeStringListOption(custom, [
      'exclude_authrole',
      'exclude_auth_role',
      'excludeAuthRole',
    ]),
    eligible: _takeIntListOption(custom, ['eligible']),
    eligibleAuthId: _takeStringListOption(custom, [
      'eligible_authid',
      'eligible_auth_id',
      'eligibleAuthId',
    ]),
    eligibleAuthRole: _takeStringListOption(custom, [
      'eligible_authrole',
      'eligible_auth_role',
      'eligibleAuthRole',
    ]),
    excludeMe: _takeBoolOption(custom, ['exclude_me', 'excludeMe']),
    discloseMe: _takeBoolOption(custom, ['disclose_me', 'discloseMe']),
    retain: _takeBoolOption(custom, ['retain']),
    pptScheme: _takeStringOption(custom, ['ppt_scheme', 'pptScheme']),
    pptSerializer: _takeStringOption(custom, [
      'ppt_serializer',
      'pptSerializer',
    ]),
    pptCipher: _takeStringOption(custom, ['ppt_cipher', 'pptCipher']),
    pptKeyId: _takeStringOption(custom, [
      'ppt_keyid',
      'ppt_key_id',
      'pptKeyId',
    ]),
    custom: custom.isEmpty ? null : custom,
  );
}

SubscribeOptions? _subscribeOptionsFrom(Map<String, dynamic>? options) {
  if (options == null) {
    return null;
  }
  final custom = <String, dynamic>{...options};
  return SubscribeOptions(
    match: _takeStringOption(custom, ['match']),
    metaTopic: _takeStringOption(custom, ['meta_topic', 'metaTopic']),
    getRetained: _takeBoolOption(custom, ['get_retained', 'getRetained']),
    custom: custom.isEmpty ? null : custom,
  );
}

Object? _takeOption(Map<String, dynamic> options, List<String> keys) {
  var found = false;
  Object? value;
  for (final key in keys) {
    if (options.containsKey(key)) {
      if (!found) {
        value = options[key];
        found = true;
      }
      options.remove(key);
    }
  }
  return found ? value : null;
}

bool? _takeBoolOption(Map<String, dynamic> options, List<String> keys) {
  final value = _takeOption(options, keys);
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw ArgumentError('arguments.options.${keys.first} must be a boolean');
}

String? _takeStringOption(Map<String, dynamic> options, List<String> keys) {
  final value = _takeOption(options, keys);
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw ArgumentError(
    'arguments.options.${keys.first} must be a non-empty string',
  );
}

List<int>? _takeIntListOption(Map<String, dynamic> options, List<String> keys) {
  final value = _takeOption(options, keys);
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw ArgumentError('arguments.options.${keys.first} must be an array');
  }
  final values = <int>[];
  for (final item in value) {
    if (item is! int) {
      throw ArgumentError(
        'arguments.options.${keys.first} must contain only integers',
      );
    }
    values.add(item);
  }
  return values;
}

List<String>? _takeStringListOption(
  Map<String, dynamic> options,
  List<String> keys,
) {
  final value = _takeOption(options, keys);
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw ArgumentError('arguments.options.${keys.first} must be an array');
  }
  final values = <String>[];
  for (final item in value) {
    if (item is! String) {
      throw ArgumentError(
        'arguments.options.${keys.first} must contain only strings',
      );
    }
    values.add(item);
  }
  return values;
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
