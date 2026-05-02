part of '../router_instance.dart';

Future<void> _handleMcpHttpRequestForBinding(
  RouterBinding binding, {
  required RouterHttpRequest request,
  required NativeHttpHandshake? handshake,
  required ListenerSettings? listenerSettings,
  required HttpRouteSettings route,
  required SessionProfileSettings? sessionProfile,
}) async {
  if (request.method.trim().toUpperCase() != 'POST') {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.methodNotAllowed,
        headers: const {HttpHeaders.allowHeader: 'POST'},
        body: NativeHttpResponseJson(const <String, Object?>{
          'status': 'error',
          'reason': 'method_not_allowed',
          'message': 'MCP HTTP endpoint only supports POST',
        }),
      ),
    );
    return;
  }

  final profileRealm = sessionProfile?.realm?.trim();
  final resolvedRealmUri = profileRealm != null && profileRealm.isNotEmpty
      ? profileRealm
      : (request.realm ?? route.action.realm ?? '');
  if (resolvedRealmUri.isEmpty) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.internalServerError,
        body: NativeHttpResponseJson(const <String, Object?>{
          'jsonrpc': '2.0',
          'id': null,
          'error': {
            'code': mcp.McpErrorCodes.internalError,
            'message': 'MCP route has no resolved WAMP realm',
          },
        }),
      ),
    );
    return;
  }

  final Object? rawMessage;
  try {
    rawMessage = jsonDecode(utf8.decode(request.body));
  } on FormatException {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.badRequest,
        body: NativeHttpResponseJson(
          mcp.JsonRpcResponse.error(
            null,
            mcp.McpException(
              mcp.McpErrorCodes.parseError,
              'Invalid JSON-RPC message',
            ),
          ).toJson(),
        ),
      ),
    );
    return;
  }

  final RouterSession session;
  try {
    final bearer = binding._extractBearerToken(request.headers);
    if (bearer != null) {
      session = await binding._authenticatedHttpSessionForToken(
        token: bearer,
        request: request,
        realmUri: resolvedRealmUri,
        sessionProfile: sessionProfile,
      );
    } else {
      final allowsAnonymous = httpSessionProfileAllowsAnonymous(sessionProfile);
      final requiresBridgeAuth =
          sessionProfile != null &&
          sessionProfile.auth.methods.isNotEmpty &&
          !allowsAnonymous;
      if (requiresBridgeAuth) {
        await binding._sendImmediateHttpResponse(
          request: request,
          handshake: handshake,
          response: NativeHttpResponse(
            status: HttpStatus.unauthorized,
            headers: binding._httpUnauthorizedHeaders(
              realm: resolvedRealmUri,
              authPath: binding._httpAuthPathFor(listenerSettings?.http),
            ),
            body: NativeHttpResponseJson(<String, Object?>{
              'status': 'error',
              'reason': 'unauthorized',
              'message': 'Bearer token required',
            }),
          ),
        );
        return;
      }
      session = await binding._ensureInternalSession(
        realmUri: resolvedRealmUri,
        sessionProfile: sessionProfile?.name,
        authId: sessionProfile?.auth.authId ?? 'anonymous',
        authMethod: 'anonymous',
        authProvider: 'router-http',
        cacheKey: _mcpAnonymousRouteSessionCacheKey(
          request: request,
          route: route,
          realmUri: resolvedRealmUri,
          sessionProfile: sessionProfile,
        ),
      );
    }
  } on _HttpUnauthorized catch (error) {
    await binding._sendImmediateHttpResponse(
      request: request,
      handshake: handshake,
      response: NativeHttpResponse(
        status: HttpStatus.unauthorized,
        headers: binding._httpUnauthorizedHeaders(
          realm: resolvedRealmUri,
          authPath: binding._httpAuthPathFor(listenerSettings?.http),
        ),
        body: NativeHttpResponseJson(<String, Object?>{
          'status': 'error',
          'reason': error.reason,
          if (error.message != null) 'message': error.message,
        }),
      ),
    );
    return;
  }

  final endpoint = binding._mcpEndpointForRoute(
    request: request,
    route: route,
    session: session,
  );
  final response = await endpoint.handleMessage(rawMessage);
  await binding._sendImmediateHttpResponse(
    request: request,
    handshake: handshake,
    response: response == null
        ? NativeHttpResponse(
            status: HttpStatus.accepted,
            body: NativeHttpResponseText(''),
          )
        : NativeHttpResponse(
            status: HttpStatus.ok,
            body: NativeHttpResponseJson(response),
          ),
  );
}

extension _RouterBindingMcp on RouterBinding {
  _RouterMcpEndpoint _mcpEndpointForRoute({
    required RouterHttpRequest request,
    required HttpRouteSettings route,
    required RouterSession session,
  }) {
    final routeKey = route.match.path ?? route.match.prefix ?? request.path;
    final key = [
      request.listenerId,
      routeKey,
      session.cacheKey ?? session.realmUri,
      session.sessionId,
    ].join(':');
    return _mcpEndpoints.putIfAbsent(
      key,
      () => _RouterMcpEndpoint(binding: this, route: route, session: session),
    );
  }
}

class _RouterMcpEndpoint {
  _RouterMcpEndpoint({
    required this.binding,
    required this.route,
    required this.session,
  }) : server = mcp.McpServer(
         serverInfo: const mcp.McpServerInfo(
           name: 'connectanum-router',
           version: '0.1.0',
         ),
         instructions:
             'This MCP endpoint is hosted by the Connectanum router and uses '
             'the route-authenticated WAMP principal for calls and pub/sub.',
         toolListPageSize: _intOption(
           route.action.options,
           'tool_list_page_size',
         ),
       );

  final RouterBinding binding;
  final HttpRouteSettings route;
  final RouterSession session;
  final mcp.McpServer server;
  String? _toolSignature;

  bool ownsSession(RouterSession candidate) => identical(candidate, session);

  void dispose() {
    server.shutdown();
  }

  Future<mcp.JsonMap?> handleMessage(Object? rawMessage) async {
    await _refreshTools();
    return server.handleMessage(rawMessage);
  }

  Future<void> _refreshTools() async {
    final api = await _buildApi();
    final tools = api.toTools(
      call: _call,
      publish: _publish,
      subscribe: _subscribe,
      unsubscribe: _unsubscribe,
      includePubSubTools: _boolOption(
        route.action.options,
        'include_pubsub_tools',
        defaultValue: true,
      ),
    );
    final signature = jsonEncode([for (final tool in tools) tool.toJson()]);
    if (signature == _toolSignature) {
      return;
    }
    server.tools.replaceAll(tools);
    _toolSignature = signature;
  }

  Future<mcp.McpWampApi> _buildApi() async {
    final options = route.action.options;
    final procedures = <String, mcp.McpWampProcedure>{
      for (final procedure in _configuredProcedures(options))
        procedure.procedure: procedure,
    };
    final topics = <String, mcp.McpWampTopic>{
      for (final topic in _configuredTopics(options)) topic.topic: topic,
    };
    final includeRegistered = _boolOption(
      options,
      'include_registered_procedures',
      defaultValue: true,
    );
    final includeSubscriptions = _boolOption(
      options,
      'include_subscribed_topics',
      defaultValue: true,
    );
    if (includeRegistered || includeSubscriptions) {
      final snapshot = await _snapshot();
      if (includeRegistered) {
        for (final registration in snapshot.registrations) {
          if (registration.matchPolicy != ProcedureMatchPolicy.exact) {
            continue;
          }
          final details = registration.callees.isEmpty
              ? const <String, Object?>{}
              : registration.callees.first.details;
          final metadata = _metadataFromDetails(details);
          procedures.putIfAbsent(
            registration.procedure,
            () => mcp.McpWampProcedure(
              procedure: registration.procedure,
              title: _stringFrom(details['title']),
              description:
                  _stringFrom(details['description']) ??
                  metadata?.description ??
                  metadata?.shortDescription,
              inputSchema:
                  _schemaFromDetails(details, 'input') ??
                  metadata?.inputJsonSchema,
              outputSchema:
                  _schemaFromDetails(details, 'output') ??
                  metadata?.outputJsonSchema,
              metadata: metadata,
              allowCall: _allowCallFrom(details),
            ),
          );
        }
      }
      if (includeSubscriptions) {
        for (final subscription in snapshot.subscriptions) {
          final details = subscription.options;
          final metadata = _metadataFromDetails(details);
          topics.putIfAbsent(
            subscription.topic,
            () => mcp.McpWampTopic(
              topic: subscription.topic,
              title: _stringFrom(details['title']),
              description:
                  _stringFrom(details['description']) ??
                  metadata?.description ??
                  metadata?.shortDescription,
              eventSchema:
                  _schemaFromDetails(details, 'event') ??
                  metadata?.outputJsonSchema,
              metadata: metadata,
            ),
          );
        }
      }
    }
    return mcp.McpWampApi(
      name: _stringFrom(options['name']) ?? 'connectanum-router',
      procedures: procedures.values,
      topics: topics.values,
      includeStandardMetaApi: _boolOption(
        options,
        'include_standard_meta_api',
        defaultValue: true,
      ),
      metadata: <String, Object?>{
        'realm': session.realmUri,
        'routerHosted': true,
        if (session.authId != null) 'authid': session.authId,
        if (session.authRole != null) 'authrole': session.authRole,
        if (session.authMethod != null) 'authmethod': session.authMethod,
      },
    );
  }

  Future<ResultPayload> _call(mcp.McpWampToolCall call) async {
    final metaResult = await _handleMetaCall(call);
    if (metaResult != null) {
      return metaResult;
    }
    final result = await session
        .call(
          call.procedure,
          arguments: call.payload.arguments,
          argumentsKeywords: call.payload.argumentsKeywords,
          options: call.payload.options,
        )
        .firstWhere((result) => !result.isProgressive());
    return result.toPayload();
  }

  Future<mcp.McpWampPublication?> _publish(
    mcp.McpWampPublishRequest request,
  ) async {
    final published = await session.publish(
      request.topic,
      arguments: request.arguments,
      argumentsKeywords: request.argumentsKeywords,
      options: request.options,
    );
    return mcp.McpWampPublication(
      publicationId: published?.publicationId,
      acknowledged: published != null,
    );
  }

  Future<mcp.McpWampSubscription> _subscribe(
    mcp.McpWampSubscribeRequest request,
    void Function(mcp.McpWampEvent event) onEvent,
  ) async {
    final subscribed = await session.subscribe(
      request.topic,
      options: request.options,
    );
    subscribed.onEventPayload(
      (event) => onEvent(mcp.McpWampEvent.fromPayload(event)),
    );
    return mcp.McpWampSubscription(
      topic: request.topic,
      subscriptionId: subscribed.subscriptionId,
    );
  }

  Future<void> _unsubscribe(mcp.McpWampSubscription subscription) async {
    final subscriptionId = subscription.subscriptionId;
    if (subscriptionId != null) {
      await session.unsubscribe(subscriptionId);
    }
  }

  Future<RealmSnapshot> _snapshot() {
    final boss = binding._boss;
    if (boss == null) {
      throw StateError('Router MCP endpoint requires a running boss');
    }
    return boss.fetchRealmSnapshot(session.realmUri);
  }

  Future<ResultPayload?> _handleMetaCall(mcp.McpWampToolCall call) async {
    if (!call.procedure.startsWith('wamp.')) {
      return null;
    }
    final snapshot = await _snapshot();
    switch (call.procedure) {
      case 'wamp.session.count':
        return _resultPayload(
          argumentsKeywords: {'count': snapshot.sessions.length},
        );
      case 'wamp.session.list':
        return _resultPayload(
          argumentsKeywords: {
            'session_ids': [
              for (final session in snapshot.sessions) session.id,
            ],
          },
        );
      case 'wamp.session.get':
        final id = _firstIntArgument(call);
        final sessionInfo = snapshot.sessions
            .where((session) => session.id == id)
            .firstOrNull;
        if (sessionInfo == null) {
          return _resultPayload(
            arguments: const ['wamp.error.no_such_session'],
          );
        }
        return _resultPayload(
          argumentsKeywords: {'details': _sessionDetails(sessionInfo)},
        );
      case 'wamp.registration.list':
        return _resultPayload(
          argumentsKeywords: _idsByProcedureMatchPolicy(snapshot),
        );
      case 'wamp.registration.lookup':
        final procedure = _firstStringArgument(call);
        final match = _matchOption(call);
        return _resultPayload(
          arguments: [
            for (final registration in snapshot.registrations)
              if (registration.procedure == procedure &&
                  (match == null ||
                      _procedureMatchPolicyName(registration.matchPolicy) ==
                          match))
                registration.registrationId,
          ],
        );
      case 'wamp.registration.match':
        final procedure = _firstStringArgument(call);
        final match = snapshot.registrations.where((registration) {
          return procedure != null &&
              _registrationMatches(registration, procedure);
        }).firstOrNull;
        return _resultPayload(
          arguments: [if (match != null) match.registrationId],
        );
      case 'wamp.registration.get':
        final id = _firstIntArgument(call);
        final registration = _registrationById(snapshot, id);
        if (registration == null) {
          return _resultPayload(
            arguments: const ['wamp.error.no_such_procedure'],
          );
        }
        return _resultPayload(
          argumentsKeywords: _registrationDetails(registration),
        );
      case 'wamp.registration.list_callees':
        final registration = _registrationById(
          snapshot,
          _firstIntArgument(call),
        );
        return _resultPayload(
          arguments: [
            for (final callee
                in registration?.callees ?? const <RegistrationRecord>[])
              callee.sessionId,
          ],
        );
      case 'wamp.registration.count_callees':
        final registration = _registrationById(
          snapshot,
          _firstIntArgument(call),
        );
        return _resultPayload(arguments: [registration?.callees.length ?? 0]);
      case 'wamp.subscription.list':
        return _resultPayload(
          argumentsKeywords: _idsBySubscriptionMatchPolicy(snapshot),
        );
      case 'wamp.subscription.lookup':
        final topic = _firstStringArgument(call);
        final match = _matchOption(call);
        return _resultPayload(
          arguments: [
            for (final subscription in snapshot.subscriptions)
              if (subscription.topic == topic &&
                  (match == null ||
                      _topicMatchPolicyName(subscription.matchPolicy) == match))
                subscription.id,
          ],
        );
      case 'wamp.subscription.match':
        final topic = _firstStringArgument(call);
        return _resultPayload(
          arguments: [
            for (final subscription in snapshot.subscriptions)
              if (topic != null && _subscriptionMatches(subscription, topic))
                subscription.id,
          ],
        );
      case 'wamp.subscription.get':
        final subscription = _subscriptionById(
          snapshot,
          _firstIntArgument(call),
        );
        if (subscription == null) {
          return _resultPayload(
            arguments: const ['wamp.error.no_such_subscription'],
          );
        }
        return _resultPayload(
          argumentsKeywords: _subscriptionDetails(subscription),
        );
      case 'wamp.subscription.list_subscribers':
        final subscription = _subscriptionById(
          snapshot,
          _firstIntArgument(call),
        );
        return _resultPayload(
          arguments: [
            for (final subscriber
                in subscription?.subscribers ?? const <SubscriberRecord>[])
              subscriber.sessionId,
          ],
        );
      case 'wamp.subscription.count_subscribers':
        final subscription = _subscriptionById(
          snapshot,
          _firstIntArgument(call),
        );
        return _resultPayload(
          arguments: [subscription?.subscribers.length ?? 0],
        );
      default:
        return null;
    }
  }
}

String _mcpAnonymousRouteSessionCacheKey({
  required RouterHttpRequest request,
  required HttpRouteSettings route,
  required String realmUri,
  required SessionProfileSettings? sessionProfile,
}) {
  final routeKey = route.match.path ?? route.match.prefix ?? request.path;
  final profileKey = sessionProfile?.name ?? 'anonymous';
  return [
    'http-mcp-anonymous',
    request.listenerId,
    routeKey,
    realmUri,
    profileKey,
  ].join(':');
}

ResultPayload _resultPayload({
  List<dynamic>? arguments,
  Map<String, dynamic>? argumentsKeywords,
}) {
  return (
    callRequestId: 0,
    progress: false,
    pptScheme: null,
    pptSerializer: null,
    pptCipher: null,
    pptKeyId: null,
    customDetails: null,
    arguments: arguments,
    argumentsKeywords: argumentsKeywords,
  );
}

List<mcp.McpWampProcedure> _configuredProcedures(Map<String, Object?> options) {
  final entries = options['procedures'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map) _procedureFromConfig(entry.cast<String, Object?>()),
  ];
}

List<mcp.McpWampTopic> _configuredTopics(Map<String, Object?> options) {
  final entries = options['topics'];
  if (entries is! List) {
    return const [];
  }
  return [
    for (final entry in entries)
      if (entry is Map) _topicFromConfig(entry.cast<String, Object?>()),
  ];
}

mcp.McpWampProcedure _procedureFromConfig(Map<String, Object?> config) {
  final procedure =
      _stringFrom(config['procedure']) ??
      _stringFrom(config['uri']) ??
      (throw FormatException('MCP procedure config requires procedure or uri'));
  final metadata = _metadataFromDetails(config);
  return mcp.McpWampProcedure(
    procedure: procedure,
    toolName: _stringFrom(config['tool_name']) ?? _stringFrom(config['name']),
    title: _stringFrom(config['title']),
    description:
        _stringFrom(config['description']) ?? metadata?.shortDescription,
    inputSchema:
        _schemaFromDetails(config, 'input') ?? metadata?.inputJsonSchema,
    outputSchema:
        _schemaFromDetails(config, 'output') ?? metadata?.outputJsonSchema,
    metadata: metadata,
    allowCall: _allowCallFrom(config),
  );
}

mcp.McpWampTopic _topicFromConfig(Map<String, Object?> config) {
  final topic =
      _stringFrom(config['topic']) ??
      _stringFrom(config['uri']) ??
      (throw FormatException('MCP topic config requires topic or uri'));
  final metadata = _metadataFromDetails(config);
  return mcp.McpWampTopic(
    topic: topic,
    title: _stringFrom(config['title']),
    description:
        _stringFrom(config['description']) ?? metadata?.shortDescription,
    eventSchema:
        _schemaFromDetails(config, 'event') ?? metadata?.outputJsonSchema,
    allowPublish: _boolOption(config, 'allow_publish', defaultValue: true),
    allowSubscribe: _boolOption(config, 'allow_subscribe', defaultValue: true),
    metadata: metadata,
  );
}

mcp.McpWampApiMetadata? _metadataFromDetails(Map<String, Object?> details) {
  final raw =
      details['_ai_meta_data'] ??
      details['ai_meta_data'] ??
      details['aiMetaData'] ??
      details['metadata'];
  if (raw is! Map) {
    return null;
  }
  final map = raw.cast<String, Object?>();
  return mcp.McpWampApiMetadata(
    shortDescription:
        _stringFrom(map['short_description']) ??
        _stringFrom(map['shortDescription']),
    description: _stringFrom(map['description']),
    domain: _stringFrom(map['domain']),
    entity: _stringFrom(map['entity']),
    verbs: _stringListFrom(map['verbs']),
    tags: _stringListFrom(map['tags']),
    synonyms: _stringListFrom(map['synonyms']),
    publishesEvents: _stringListFrom(
      map['publishes_events'] ?? map['publishesEvents'],
    ),
    inputJsonSchema:
        _jsonMapFrom(map['input_json_schema']) ??
        _jsonMapFrom(map['inputJsonSchema']),
    outputJsonSchema:
        _jsonMapFrom(map['output_json_schema']) ??
        _jsonMapFrom(map['outputJsonSchema']),
    danger: _dangerFrom(map['danger']),
    readOnlyHint: _annotationBool(map, 'read_only_hint', 'readOnlyHint'),
    destructiveHint: _annotationBool(
      map,
      'destructive_hint',
      'destructiveHint',
    ),
    idempotentHint: _annotationBool(map, 'idempotent_hint', 'idempotentHint'),
    openWorldHint: _annotationBool(map, 'open_world_hint', 'openWorldHint'),
  );
}

bool _allowCallFrom(Map<String, Object?> config) {
  final allowCall = config['allow_call'] ?? config['allowCall'];
  if (allowCall is bool) {
    return allowCall;
  }
  final callable = config['callable'];
  if (callable is bool) {
    return callable;
  }
  return true;
}

bool _dangerFrom(Object? value) {
  if (value == null || value == false) {
    return false;
  }
  if (value == true) {
    return true;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'false') {
      return false;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded == null || decoded == false) {
        return false;
      }
    } on FormatException {
      // Non-empty danger strings are treated as a safety warning.
    }
    return true;
  }
  if (value is Map) {
    return value.isNotEmpty;
  }
  return false;
}

bool? _annotationBool(
  Map<String, Object?> map,
  String snakeKey,
  String camelKey,
) {
  final direct = map[snakeKey] ?? map[camelKey];
  if (direct is bool) {
    return direct;
  }
  final annotations = map['annotations'];
  if (annotations is Map) {
    final value = annotations[camelKey] ?? annotations[snakeKey];
    if (value is bool) {
      return value;
    }
  }
  return null;
}

Map<String, Object?>? _schemaFromDetails(
  Map<String, Object?> details,
  String prefix,
) {
  return _jsonMapFrom(details['${prefix}_schema']) ??
      _jsonMapFrom(details['${prefix}Schema']) ??
      _jsonMapFrom(details['${prefix}_json_schema']) ??
      _jsonMapFrom(details['${prefix}JsonSchema']);
}

Map<String, dynamic> _idsByProcedureMatchPolicy(RealmSnapshot snapshot) {
  return <String, dynamic>{
    'exact': [
      for (final registration in snapshot.registrations)
        if (registration.matchPolicy == ProcedureMatchPolicy.exact)
          registration.registrationId,
    ],
    'prefix': [
      for (final registration in snapshot.registrations)
        if (registration.matchPolicy == ProcedureMatchPolicy.prefix)
          registration.registrationId,
    ],
    'wildcard': [
      for (final registration in snapshot.registrations)
        if (registration.matchPolicy == ProcedureMatchPolicy.wildcard)
          registration.registrationId,
    ],
  };
}

Map<String, dynamic> _idsBySubscriptionMatchPolicy(RealmSnapshot snapshot) {
  return <String, dynamic>{
    'exact': [
      for (final subscription in snapshot.subscriptions)
        if (subscription.matchPolicy == TopicMatchPolicy.exact) subscription.id,
    ],
    'prefix': [
      for (final subscription in snapshot.subscriptions)
        if (subscription.matchPolicy == TopicMatchPolicy.prefix)
          subscription.id,
    ],
    'wildcard': [
      for (final subscription in snapshot.subscriptions)
        if (subscription.matchPolicy == TopicMatchPolicy.wildcard)
          subscription.id,
    ],
  };
}

Map<String, dynamic> _sessionDetails(SessionInfo session) {
  return <String, dynamic>{
    'id': session.id,
    if (session.authId != null) 'authid': session.authId,
    if (session.authRole != null) 'authrole': session.authRole,
    if (session.authMethod != null) 'authmethod': session.authMethod,
    if (session.authProvider != null) 'authprovider': session.authProvider,
    'roles': session.roles,
    'worker_id': session.workerId,
    'connection_id': session.connectionId,
    'last_activity': session.lastActivity.toIso8601String(),
    if (session.protocol != null)
      'protocol': listenerProtocolToString(session.protocol!),
  };
}

Map<String, dynamic> _registrationDetails(RegistrationSnapshot registration) {
  final details = registration.callees.isEmpty
      ? const <String, Object?>{}
      : registration.callees.first.details;
  return <String, dynamic>{
    'id': registration.registrationId,
    'uri': registration.procedure,
    'match': _procedureMatchPolicyName(registration.matchPolicy),
    'invoke': registration.policy.name,
    if (details['_ai_meta_data'] != null)
      '_ai_meta_data': details['_ai_meta_data'],
  };
}

Map<String, dynamic> _subscriptionDetails(SubscriptionSnapshot subscription) {
  return <String, dynamic>{
    'id': subscription.id,
    'uri': subscription.topic,
    'match': _topicMatchPolicyName(subscription.matchPolicy),
    if (subscription.options['_ai_meta_data'] != null)
      '_ai_meta_data': subscription.options['_ai_meta_data'],
  };
}

RegistrationSnapshot? _registrationById(RealmSnapshot snapshot, int? id) {
  if (id == null) {
    return null;
  }
  for (final registration in snapshot.registrations) {
    if (registration.registrationId == id) {
      return registration;
    }
  }
  return null;
}

SubscriptionSnapshot? _subscriptionById(RealmSnapshot snapshot, int? id) {
  if (id == null) {
    return null;
  }
  for (final subscription in snapshot.subscriptions) {
    if (subscription.id == id) {
      return subscription;
    }
  }
  return null;
}

bool _registrationMatches(RegistrationSnapshot registration, String procedure) {
  switch (registration.matchPolicy) {
    case ProcedureMatchPolicy.exact:
      return registration.procedure == procedure;
    case ProcedureMatchPolicy.prefix:
      return procedure == registration.procedure ||
          procedure.startsWith('${registration.procedure}.') ||
          (registration.procedure.endsWith('.') &&
              procedure.startsWith(registration.procedure));
    case ProcedureMatchPolicy.wildcard:
      final pattern = registration.procedure.split('.');
      final candidate = procedure.split('.');
      if (pattern.length != candidate.length) {
        return false;
      }
      for (var i = 0; i < pattern.length; i += 1) {
        if (pattern[i].isNotEmpty && pattern[i] != candidate[i]) {
          return false;
        }
      }
      return true;
  }
}

bool _subscriptionMatches(SubscriptionSnapshot subscription, String topic) {
  switch (subscription.matchPolicy) {
    case TopicMatchPolicy.exact:
      return subscription.topic == topic;
    case TopicMatchPolicy.prefix:
      return topic.startsWith(subscription.topic);
    case TopicMatchPolicy.wildcard:
      final pattern = subscription.topic.split('.');
      final candidate = topic.split('.');
      if (pattern.length != candidate.length) {
        return false;
      }
      for (var i = 0; i < pattern.length; i += 1) {
        if (pattern[i].isNotEmpty && pattern[i] != candidate[i]) {
          return false;
        }
      }
      return true;
  }
}

String _procedureMatchPolicyName(ProcedureMatchPolicy policy) =>
    switch (policy) {
      ProcedureMatchPolicy.exact => 'exact',
      ProcedureMatchPolicy.prefix => 'prefix',
      ProcedureMatchPolicy.wildcard => 'wildcard',
    };

String _topicMatchPolicyName(TopicMatchPolicy policy) => switch (policy) {
  TopicMatchPolicy.exact => 'exact',
  TopicMatchPolicy.prefix => 'prefix',
  TopicMatchPolicy.wildcard => 'wildcard',
};

String? _firstStringArgument(mcp.McpWampToolCall call) {
  final first = call.payload.arguments?.firstOrNull;
  if (first is String) {
    return first;
  }
  final kwargs = call.payload.argumentsKeywords;
  return _stringFrom(kwargs?['uri']) ??
      _stringFrom(kwargs?['procedure']) ??
      _stringFrom(kwargs?['topic']);
}

int? _firstIntArgument(mcp.McpWampToolCall call) {
  final first = call.payload.arguments?.firstOrNull;
  if (first is int) {
    return first;
  }
  final kwargs = call.payload.argumentsKeywords;
  final candidate =
      kwargs?['id'] ?? kwargs?['registration'] ?? kwargs?['subscription'];
  if (candidate is int) {
    return candidate;
  }
  return null;
}

String? _matchOption(mcp.McpWampToolCall call) {
  final second =
      call.payload.arguments != null && call.payload.arguments!.length > 1
      ? call.payload.arguments![1]
      : null;
  if (second is Map) {
    return _stringFrom(second['match']);
  }
  return _stringFrom(call.payload.argumentsKeywords?['match']);
}

String? _stringFrom(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

List<String> _stringListFrom(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final entry in value)
      if (entry is String) entry,
  ];
}

Map<String, Object?>? _jsonMapFrom(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

bool _boolOption(
  Map<String, Object?> options,
  String key, {
  required bool defaultValue,
}) {
  final value = options[key];
  return value is bool ? value : defaultValue;
}

int? _intOption(Map<String, Object?> options, String key) {
  final value = options[key];
  return value is int ? value : null;
}
