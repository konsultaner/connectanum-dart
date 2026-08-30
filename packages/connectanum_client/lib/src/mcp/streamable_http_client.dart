import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart'
    show
        McpCompletionRequest,
        McpCompletionResult,
        containsMcpWhitespaceOrControl;

import 'authorization_discovery.dart';
import 'http_auth_client.dart';
import 'oauth_authorization.dart';
import 'oauth_dynamic_client_registration.dart';
import 'oauth_token_exchange.dart';

typedef McpJsonMap = Map<String, Object?>;
typedef McpHttpClientFactory = HttpClient Function();

const _acceptJson = 'application/json';
const _acceptSse = 'text/event-stream';
const _acceptStreamableHttp = 'application/json, text/event-stream';
const _headerLastEventId = 'Last-Event-ID';
const _headerProtocolVersion = 'MCP-Protocol-Version';
const _headerSessionId = 'MCP-Session-Id';
const _headerMethod = 'Mcp-Method';
const _headerName = 'Mcp-Name';
const _headerParameterPrefix = 'Mcp-Param-';
const _base64HeaderPrefix = '=?base64?';
const _base64HeaderSuffix = '?=';
final _mcpToolNamePattern = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');
const _mcpLatestSessionProtocolVersion = '2025-11-25';
const _mcpLatestProtocolVersion = '2026-07-28';
const _mcpSupportedProtocolVersions = <String>{
  '2025-03-26',
  '2025-06-18',
  _mcpLatestSessionProtocolVersion,
  _mcpLatestProtocolVersion,
};

bool _sameMcpOAuthResource(Uri expected, Uri candidate) {
  return expected.scheme.toLowerCase() == candidate.scheme.toLowerCase() &&
      expected.host.toLowerCase() == candidate.host.toLowerCase() &&
      expected.port == candidate.port &&
      expected.path == candidate.path &&
      expected.query == candidate.query &&
      candidate.userInfo.isEmpty &&
      !candidate.hasFragment;
}

bool _mcpOAuthScopeTokenValid(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit != 0x21 &&
        (codeUnit < 0x23 || codeUnit > 0x5b) &&
        (codeUnit < 0x5d || codeUnit > 0x7e)) {
      return false;
    }
  }
  return true;
}

bool _mcpOAuthMetadataUriValid(Uri? uri) {
  if (uri == null ||
      !uri.isAbsolute ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return false;
  }
  if (uri.scheme == 'https') {
    return true;
  }
  if (uri.scheme != 'http') {
    return false;
  }
  return uri.host.toLowerCase() == 'localhost' ||
      (InternetAddress.tryParse(uri.host)?.isLoopback ?? false);
}

String _validatedMcpToolName(String value, String name) {
  if (_mcpToolNamePattern.hasMatch(value)) {
    return value;
  }
  throw ArgumentError.value(
    value,
    name,
    'MCP tool names must be 1-128 ASCII letters, digits, underscores, '
    'hyphens, or dots.',
  );
}

String _validatedMcpResourceUri(String value, String name) {
  if (containsMcpWhitespaceOrControl(value)) {
    throw ArgumentError.value(
      value,
      name,
      'MCP resource URI must not contain whitespace or control characters.',
    );
  }

  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) {
    return value;
  }
  throw ArgumentError.value(
    value,
    name,
    'MCP resource URI must be an absolute URI with a scheme.',
  );
}

String _validatedMcpPromptName(String value, String name) {
  if (containsMcpWhitespaceOrControl(value)) {
    throw ArgumentError.value(
      value,
      name,
      'MCP prompt name must not contain whitespace or control characters.',
    );
  }

  if (value.isNotEmpty) {
    return value;
  }
  throw ArgumentError.value(value, name, 'MCP prompt name is required.');
}

String _validatedMcpCursor(String value, String name) {
  if (value.isNotEmpty && !containsMcpWhitespaceOrControl(value)) {
    return value;
  }
  throw ArgumentError.value(
    value,
    name,
    'MCP cursor must be a non-empty string without whitespace or control '
    'characters.',
  );
}

McpJsonMap? _cursorParams(String? cursor) {
  if (cursor == null) {
    return null;
  }
  return <String, Object?>{'cursor': _validatedMcpCursor(cursor, 'cursor')};
}

bool _mcpProtocolVersionSupported(String value) =>
    _mcpSupportedProtocolVersions.contains(value);

String _validatedMcpProtocolVersion(String value, String name) {
  if (_mcpProtocolVersionSupported(value)) {
    return value;
  }
  throw ArgumentError.value(value, name, 'Unsupported MCP protocol version.');
}

McpJsonMap? _validatedMcpClientInfo(McpJsonMap? value) {
  if (value == null) {
    return null;
  }
  final name = value['name'];
  final version = value['version'];
  if (name is! String ||
      name.isEmpty ||
      version is! String ||
      version.isEmpty) {
    throw ArgumentError.value(
      value,
      'clientInfo',
      'MCP client info must contain non-empty name and version strings.',
    );
  }
  return Map<String, Object?>.unmodifiable(value);
}

bool _mcpSessionIdHeaderValueValid(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x21 || codeUnit > 0x7e) {
      return false;
    }
  }
  return value.isNotEmpty;
}

bool _mcpLastEventIdHeaderValueValid(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit == 0x7f) {
      return false;
    }
  }
  return true;
}

void _validateJsonRpcVersion(McpJsonMap message, {required String label}) {
  if (message['jsonrpc'] != '2.0') {
    throw FormatException('JSON-RPC $label jsonrpc must be 2.0');
  }
}

Object? _validateJsonRpcRequestId(McpJsonMap message, {required String label}) {
  _validateJsonRpcVersion(message, label: label);
  final method = message['method'];
  if (method is! String || method.isEmpty) {
    throw FormatException('JSON-RPC $label method must be a non-empty string');
  }
  if (containsMcpWhitespaceOrControl(method)) {
    throw FormatException(
      'JSON-RPC $label method must not contain whitespace or control '
      'characters',
    );
  }
  if (message.containsKey('result') || message.containsKey('error')) {
    throw FormatException('JSON-RPC $label must not contain result or error');
  }
  if (message.containsKey('params')) {
    final params = message['params'];
    if (params is! Map) {
      throw FormatException('JSON-RPC $label params must be an object');
    }
    if (params.keys.any((key) => key is! String)) {
      throw FormatException(
        'JSON-RPC $label params must contain only string keys',
      );
    }
  }
  if (!message.containsKey('id')) {
    return null;
  }
  final id = message['id'];
  if (id is! String && id is! int) {
    throw FormatException(
      'JSON-RPC $label contained invalid request id ${id ?? 'null'}',
    );
  }
  return id;
}

Object? _validateJsonRpcResponseId(
  McpJsonMap response, {
  required String label,
}) {
  if (!response.containsKey('id')) {
    throw FormatException('$label must include an id');
  }
  final id = response['id'];
  if (id is! String && id is! int) {
    throw FormatException('$label id must be a string or integer');
  }
  return id;
}

void _validateJsonRpcBatchRequestIds(List<McpJsonMap> messages) {
  if (messages.isEmpty) {
    throw const FormatException('JSON-RPC batch must not be empty');
  }
  final seenIds = <Object?>[];
  for (final message in messages) {
    final id = _validateJsonRpcRequestId(message, label: 'batch request');
    if (id == null) {
      continue;
    }
    if (seenIds.any((seenId) => seenId == id)) {
      throw FormatException(
        'JSON-RPC batch request contained duplicate request id $id',
      );
    }
    seenIds.add(id);
  }
}

bool _jsonRpcMessageIsResponse(Object? value) {
  return value is Map &&
      (value.containsKey('result') || value.containsKey('error'));
}

void _validateJsonRpcSseMessageValue(Object? value) {
  if (value is List) {
    if (value.isEmpty) {
      throw const FormatException('JSON-RPC SSE event batch must not be empty');
    }
    for (final item in value) {
      _validateJsonRpcSseMessage(item, label: 'JSON-RPC SSE event batch item');
    }
    return;
  }
  if (value is! Map) {
    throw const FormatException(
      'JSON-RPC SSE event data must be an object or array',
    );
  }
  _validateJsonRpcSseMessage(value, label: 'JSON-RPC SSE event data');
}

void _validateJsonRpcSseMessage(Object? value, {required String label}) {
  final message = _jsonMapFrom(value, label: label);
  if (_jsonRpcMessageIsResponse(message)) {
    _validateJsonRpcResponseId(message, label: '$label response');
    _validateJsonRpcResponseObject(message, label: '$label response');
    return;
  }
  _validateJsonRpcRequestId(message, label: '$label request');
}

void _validateJsonRpcResponseObject(
  McpJsonMap response, {
  required String label,
}) {
  _validateJsonRpcVersion(response, label: label);
  final hasResult = response.containsKey('result');
  final hasError = response.containsKey('error');
  if (hasResult == hasError) {
    throw FormatException('$label must contain exactly one of result or error');
  }
  if (hasError) {
    final error = _jsonMapFrom(response['error'], label: '$label error');
    if (error['code'] is! int) {
      throw FormatException('$label error code must be an integer');
    }
    if (error['message'] is! String) {
      throw FormatException('$label error message must be a string');
    }
  }
}

/// Handles one MCP form-elicitation input request.
typedef McpFormElicitationHandler =
    FutureOr<McpFormElicitationResponse> Function(
      McpFormElicitationRequest request,
    );

/// The outcome selected by a consumer for an MCP form elicitation.
enum McpElicitationAction { accept, decline, cancel }

/// One validated form-mode `elicitation/create` input request.
final class McpFormElicitationRequest {
  factory McpFormElicitationRequest({
    required String inputRequestId,
    required String message,
    required McpJsonMap requestedSchema,
  }) {
    if (inputRequestId.isEmpty) {
      throw ArgumentError.value(
        inputRequestId,
        'inputRequestId',
        'MCP input request identifiers must not be empty.',
      );
    }
    if (message.isEmpty) {
      throw ArgumentError.value(
        message,
        'message',
        'MCP form elicitation messages must not be empty.',
      );
    }
    return McpFormElicitationRequest._(
      inputRequestId: inputRequestId,
      message: message,
      requestedSchema: _validatedMcpFormSchema(
        requestedSchema,
        label: 'requestedSchema',
      ),
    );
  }

  factory McpFormElicitationRequest.fromJson(
    String inputRequestId,
    Object? value,
  ) {
    final request = _jsonMapFrom(value, label: 'inputRequests.$inputRequestId');
    if (request['method'] != 'elicitation/create') {
      throw McpStreamableProtocolException(
        'Unsupported MCP input request method: ${request['method']}',
      );
    }
    final params = _jsonMapFrom(
      request['params'],
      label: 'inputRequests.$inputRequestId.params',
    );
    final mode = params['mode'];
    if (mode != null && mode != 'form') {
      throw McpStreamableProtocolException(
        'Unsupported MCP elicitation mode: $mode',
      );
    }
    final message = params['message'];
    if (message is! String || message.isEmpty) {
      throw FormatException(
        'inputRequests.$inputRequestId.params.message must be a non-empty '
        'string',
      );
    }
    return McpFormElicitationRequest(
      inputRequestId: inputRequestId,
      message: message,
      requestedSchema: _jsonMapFrom(
        params['requestedSchema'],
        label: 'inputRequests.$inputRequestId.params.requestedSchema',
      ),
    );
  }

  const McpFormElicitationRequest._({
    required this.inputRequestId,
    required this.message,
    required this.requestedSchema,
  });

  final String inputRequestId;
  final String message;
  final McpJsonMap requestedSchema;
}

/// A consumer's response to one MCP form elicitation request.
final class McpFormElicitationResponse {
  factory McpFormElicitationResponse.accept(McpJsonMap content) {
    return McpFormElicitationResponse._(
      McpElicitationAction.accept,
      Map<String, Object?>.unmodifiable(content),
    );
  }

  const McpFormElicitationResponse.decline()
    : this._(McpElicitationAction.decline, null);

  const McpFormElicitationResponse.cancel()
    : this._(McpElicitationAction.cancel, null);

  const McpFormElicitationResponse._(this.action, this.content);

  final McpElicitationAction action;
  final McpJsonMap? content;

  McpJsonMap toJsonFor(McpFormElicitationRequest request) {
    final content = this.content;
    if (action == McpElicitationAction.accept) {
      if (content == null) {
        throw const FormatException(
          'Accepted MCP form elicitation needs response content',
        );
      }
      _validateMcpFormContent(request.requestedSchema, content);
    } else if (content != null) {
      throw const FormatException(
        'Declined or cancelled MCP elicitation must not contain content',
      );
    }
    return <String, Object?>{'action': action.name, 'content': ?content};
  }
}

final class _McpInputRequiredRound {
  const _McpInputRequiredRound({
    required this.requests,
    required this.requestState,
  });

  final List<McpFormElicitationRequest> requests;
  final String? requestState;
}

_McpInputRequiredRound? _mcpInputRequiredRoundFrom(
  McpJsonMap result, {
  required String label,
}) {
  final resultType = result['resultType'];
  if (resultType == null || resultType == 'complete') {
    return null;
  }
  if (resultType != 'input_required') {
    throw FormatException(
      '$label.resultType must be complete or input_required',
    );
  }
  final metadata = result['_meta'];
  if (metadata != null) {
    _jsonMapFrom(metadata, label: '$label._meta');
  }
  final rawInputRequests = result['inputRequests'];
  final inputRequests = rawInputRequests == null
      ? const <String, Object?>{}
      : _jsonMapFrom(rawInputRequests, label: '$label.inputRequests');
  final requestState = result['requestState'];
  if (requestState != null && requestState is! String) {
    throw FormatException('$label.requestState must be a string');
  }
  if (inputRequests.isEmpty && requestState == null) {
    throw FormatException(
      '$label input_required needs inputRequests or requestState',
    );
  }
  return _McpInputRequiredRound(
    requests: List<McpFormElicitationRequest>.unmodifiable([
      for (final entry in inputRequests.entries)
        McpFormElicitationRequest.fromJson(entry.key, entry.value),
    ]),
    requestState: requestState as String?,
  );
}

McpJsonMap _validatedMcpFormSchema(Object? value, {required String label}) {
  final schema = _jsonMapFrom(value, label: label);
  if (schema['type'] != 'object') {
    throw FormatException('$label.type must be object');
  }
  final rawProperties = schema['properties'];
  if (rawProperties is! Map) {
    throw FormatException('$label.properties must be an object');
  }
  final properties = <String, Object?>{};
  for (final entry in rawProperties.entries) {
    if (entry.key is! String || (entry.key as String).isEmpty) {
      throw FormatException(
        '$label.properties must contain non-empty string keys',
      );
    }
    final propertyName = entry.key as String;
    properties[propertyName] = Map<String, Object?>.unmodifiable(
      _validatedMcpFormPropertySchema(
        entry.value,
        label: '$label.properties.$propertyName',
      ),
    );
  }
  final rawRequired = schema['required'];
  final required = <String>[];
  if (rawRequired != null) {
    if (rawRequired is! List ||
        rawRequired.any(
          (item) =>
              item is! String || item.isEmpty || !properties.containsKey(item),
        )) {
      throw FormatException(
        '$label.required must name declared string properties',
      );
    }
    required.addAll(rawRequired.cast<String>());
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    ...schema,
    'properties': Map<String, Object?>.unmodifiable(properties),
    if (rawRequired != null) 'required': List<String>.unmodifiable(required),
  });
}

McpJsonMap _validatedMcpFormPropertySchema(
  Object? value, {
  required String label,
}) {
  final schema = _jsonMapFrom(value, label: label);
  for (final textField in const ['title', 'description']) {
    final fieldValue = schema[textField];
    if (fieldValue != null && fieldValue is! String) {
      throw FormatException('$label.$textField must be a string');
    }
  }
  final type = schema['type'];
  switch (type) {
    case 'string':
      _validateOptionalNonNegativeInt(schema, 'minLength', label);
      _validateOptionalNonNegativeInt(schema, 'maxLength', label);
      final minLength = schema['minLength'];
      final maxLength = schema['maxLength'];
      if (minLength is int && maxLength is int && minLength > maxLength) {
        throw FormatException('$label.minLength must not exceed maxLength');
      }
      final format = schema['format'];
      if (format != null &&
          !const {'email', 'uri', 'date', 'date-time'}.contains(format)) {
        throw FormatException('$label.format is unsupported');
      }
      final defaultValue = schema['default'];
      if (defaultValue != null && defaultValue is! String) {
        throw FormatException('$label.default must be a string');
      }
      _validateMcpStringEnumSchema(schema, label);
    case 'number':
    case 'integer':
      _validateOptionalNumber(schema, 'minimum', label);
      _validateOptionalNumber(schema, 'maximum', label);
      _validateOptionalNumber(schema, 'default', label);
      final minimum = schema['minimum'];
      final maximum = schema['maximum'];
      if (minimum is num && maximum is num && minimum > maximum) {
        throw FormatException('$label.minimum must not exceed maximum');
      }
    case 'boolean':
      final defaultValue = schema['default'];
      if (defaultValue != null && defaultValue is! bool) {
        throw FormatException('$label.default must be a boolean');
      }
    case 'array':
      _validateOptionalNonNegativeInt(schema, 'minItems', label);
      _validateOptionalNonNegativeInt(schema, 'maxItems', label);
      final minItems = schema['minItems'];
      final maxItems = schema['maxItems'];
      if (minItems is int && maxItems is int && minItems > maxItems) {
        throw FormatException('$label.minItems must not exceed maxItems');
      }
      final items = _jsonMapFrom(schema['items'], label: '$label.items');
      final enumValues = items['enum'];
      final titledValues = items['anyOf'];
      if (items['type'] == 'string' && enumValues is List) {
        _validatedNonEmptyStringList(enumValues, '$label.items.enum');
      } else if (titledValues is List) {
        _validateMcpTitledChoices(titledValues, '$label.items.anyOf');
      } else {
        throw FormatException(
          '$label.items must define a string enum or titled choices',
        );
      }
      final defaultValue = schema['default'];
      if (defaultValue != null) {
        if (defaultValue is! List) {
          throw FormatException('$label.default must be a string array');
        }
        _validatedNonEmptyStringList(
          defaultValue,
          '$label.default',
          allowEmpty: true,
        );
      }
    default:
      throw FormatException(
        '$label.type must be string, number, integer, boolean, or array',
      );
  }
  return schema;
}

void _validateMcpStringEnumSchema(McpJsonMap schema, String label) {
  final enumValues = schema['enum'];
  final oneOf = schema['oneOf'];
  if (enumValues != null && oneOf != null) {
    throw FormatException('$label must not define both enum and oneOf');
  }
  if (enumValues != null) {
    if (enumValues is! List) {
      throw FormatException('$label.enum must be a string array');
    }
    final values = _validatedNonEmptyStringList(enumValues, '$label.enum');
    final enumNames = schema['enumNames'];
    if (enumNames != null) {
      if (enumNames is! List) {
        throw FormatException('$label.enumNames must be a string array');
      }
      final names = _validatedNonEmptyStringList(enumNames, '$label.enumNames');
      if (names.length != values.length) {
        throw FormatException('$label.enumNames must match enum length');
      }
    }
  }
  if (oneOf != null) {
    if (oneOf is! List) {
      throw FormatException('$label.oneOf must be an array');
    }
    _validateMcpTitledChoices(oneOf, '$label.oneOf');
  }
}

List<String> _validatedNonEmptyStringList(
  List<Object?> values,
  String label, {
  bool allowEmpty = false,
}) {
  if ((!allowEmpty && values.isEmpty) ||
      values.any((value) => value is! String)) {
    throw FormatException('$label must be a string array');
  }
  return values.cast<String>();
}

void _validateMcpTitledChoices(List<Object?> values, String label) {
  if (values.isEmpty) {
    throw FormatException('$label must not be empty');
  }
  for (var index = 0; index < values.length; index++) {
    final choice = _jsonMapFrom(values[index], label: '$label[$index]');
    if (choice['const'] is! String || choice['title'] is! String) {
      throw FormatException(
        '$label[$index] must contain string const and title fields',
      );
    }
  }
}

void _validateOptionalNonNegativeInt(
  McpJsonMap schema,
  String field,
  String label,
) {
  final value = schema[field];
  if (value != null && (value is! int || value < 0)) {
    throw FormatException('$label.$field must be a non-negative integer');
  }
}

void _validateOptionalNumber(McpJsonMap schema, String field, String label) {
  final value = schema[field];
  if (value != null && (value is! num || !value.isFinite)) {
    throw FormatException('$label.$field must be a finite number');
  }
}

void _validateMcpFormContent(McpJsonMap schema, McpJsonMap content) {
  final properties = _jsonMapFrom(
    schema['properties'],
    label: 'requestedSchema.properties',
  );
  final required = schema['required'];
  if (required is List) {
    for (final property in required.cast<String>()) {
      if (!content.containsKey(property)) {
        throw FormatException(
          'Accepted MCP form response is missing required field $property',
        );
      }
    }
  }
  for (final entry in content.entries) {
    final rawPropertySchema = properties[entry.key];
    if (rawPropertySchema == null) {
      throw FormatException(
        'Accepted MCP form response contains unknown field ${entry.key}',
      );
    }
    final propertySchema = _jsonMapFrom(
      rawPropertySchema,
      label: 'requestedSchema.properties.${entry.key}',
    );
    _validateMcpFormValue(
      entry.value,
      propertySchema,
      label: 'elicitation content.${entry.key}',
    );
  }
}

void _validateMcpFormValue(
  Object? value,
  McpJsonMap schema, {
  required String label,
}) {
  switch (schema['type']) {
    case 'string':
      if (value is! String) {
        throw FormatException('$label must be a string');
      }
      final minLength = schema['minLength'];
      final maxLength = schema['maxLength'];
      if (minLength is int && value.runes.length < minLength) {
        throw FormatException('$label is shorter than minLength');
      }
      if (maxLength is int && value.runes.length > maxLength) {
        throw FormatException('$label is longer than maxLength');
      }
      final format = schema['format'];
      if (format == 'email' &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
        throw FormatException('$label must be an email address');
      }
      if (format == 'uri') {
        final uri = Uri.tryParse(value);
        if (uri == null || !uri.hasScheme) {
          throw FormatException('$label must be an absolute URI');
        }
      }
      if (format == 'date' &&
          (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
              DateTime.tryParse(value) == null)) {
        throw FormatException('$label must be an ISO date');
      }
      if (format == 'date-time' && DateTime.tryParse(value) == null) {
        throw FormatException('$label must be an ISO date-time');
      }
      final allowed = _mcpStringChoices(schema);
      if (allowed != null && !allowed.contains(value)) {
        throw FormatException('$label is not an allowed enum value');
      }
    case 'number':
      if (value is! num || !value.isFinite) {
        throw FormatException('$label must be a finite number');
      }
      _validateMcpNumberRange(value, schema, label);
    case 'integer':
      if (value is! num || !value.isFinite || value % 1 != 0) {
        throw FormatException('$label must be an integer');
      }
      _validateMcpNumberRange(value, schema, label);
    case 'boolean':
      if (value is! bool) {
        throw FormatException('$label must be a boolean');
      }
    case 'array':
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('$label must be a string array');
      }
      final minItems = schema['minItems'];
      final maxItems = schema['maxItems'];
      if (minItems is int && value.length < minItems) {
        throw FormatException('$label has fewer than minItems values');
      }
      if (maxItems is int && value.length > maxItems) {
        throw FormatException('$label has more than maxItems values');
      }
      final items = _jsonMapFrom(schema['items'], label: '$label.items');
      final allowed = _mcpStringChoices(items)!;
      if (value.any((item) => !allowed.contains(item))) {
        throw FormatException('$label contains an unsupported enum value');
      }
  }
}

Set<String>? _mcpStringChoices(McpJsonMap schema) {
  final enumValues = schema['enum'];
  if (enumValues is List) {
    return enumValues.cast<String>().toSet();
  }
  final choices = schema['oneOf'] ?? schema['anyOf'];
  if (choices is List) {
    return {
      for (final choice in choices)
        (_jsonMapFrom(choice, label: 'enum choice')['const'] as String),
    };
  }
  return null;
}

void _validateMcpNumberRange(num value, McpJsonMap schema, String label) {
  final minimum = schema['minimum'];
  final maximum = schema['maximum'];
  if (minimum is num && value < minimum) {
    throw FormatException('$label is less than minimum');
  }
  if (maximum is num && value > maximum) {
    throw FormatException('$label is greater than maximum');
  }
}

/// Route-filtered server information returned by MCP `server/discover`.
final class McpStatelessDiscoveryResult {
  const McpStatelessDiscoveryResult({
    required this.supportedVersions,
    required this.capabilities,
    required this.serverInfo,
    this.instructions,
    this.ttlMs,
    this.cacheScope,
  });

  final List<String> supportedVersions;
  final McpJsonMap capabilities;
  final McpJsonMap? serverInfo;
  final String? instructions;
  final int? ttlMs;
  final String? cacheScope;
}

/// How an MCP 2026 request-scoped subscription stream ended.
enum McpSubscriptionCloseReason { local, graceful, remote }

/// Notification filter requested or acknowledged by `subscriptions/listen`.
class McpSubscriptionFilter {
  McpSubscriptionFilter({
    this.toolsListChanged = false,
    this.promptsListChanged = false,
    this.resourcesListChanged = false,
    Iterable<String> resourceSubscriptions = const <String>[],
  }) : resourceSubscriptions = List<String>.unmodifiable(resourceSubscriptions);

  final bool toolsListChanged;
  final bool promptsListChanged;
  final bool resourcesListChanged;
  final List<String> resourceSubscriptions;

  McpJsonMap toJson() => <String, Object?>{
    if (toolsListChanged) 'toolsListChanged': true,
    if (promptsListChanged) 'promptsListChanged': true,
    if (resourcesListChanged) 'resourcesListChanged': true,
    if (resourceSubscriptions.isNotEmpty)
      'resourceSubscriptions': <String>[...resourceSubscriptions],
  };
}

McpSubscriptionFilter _mcpSubscriptionFilterFromJson(
  Object? value, {
  required String label,
}) {
  final map = _jsonMapFrom(value, label: label);

  bool field(String name) {
    final value = map[name];
    if (value == null) {
      return false;
    }
    if (value is! bool) {
      throw FormatException('$label.$name must be a boolean');
    }
    return value;
  }

  final rawResourceSubscriptions = map['resourceSubscriptions'];
  final resourceSubscriptions = <String>[];
  if (rawResourceSubscriptions != null) {
    if (rawResourceSubscriptions is! List) {
      throw FormatException('$label.resourceSubscriptions must be a list');
    }
    final seen = <String>{};
    for (var index = 0; index < rawResourceSubscriptions.length; index++) {
      final value = rawResourceSubscriptions[index];
      if (value is! String) {
        throw FormatException(
          '$label.resourceSubscriptions[$index] must be a string',
        );
      }
      final String uri;
      try {
        uri = _validatedMcpResourceUri(
          value,
          '$label.resourceSubscriptions[$index]',
        );
      } on ArgumentError {
        throw FormatException(
          '$label.resourceSubscriptions[$index] must be an absolute MCP '
          'resource URI',
        );
      }
      if (!seen.add(uri)) {
        throw FormatException(
          '$label.resourceSubscriptions must not contain duplicates',
        );
      }
      resourceSubscriptions.add(uri);
    }
  }

  return McpSubscriptionFilter(
    toolsListChanged: field('toolsListChanged'),
    promptsListChanged: field('promptsListChanged'),
    resourcesListChanged: field('resourcesListChanged'),
    resourceSubscriptions: resourceSubscriptions,
  );
}

/// Splits SSE lines while bounding each complete event in raw bytes.
final class _McpBoundedSseLineTransformer
    extends StreamTransformerBase<List<int>, String> {
  const _McpBoundedSseLineTransformer(this.maxEventBytes);

  final int maxEventBytes;

  @override
  Stream<String> bind(Stream<List<int>> stream) async* {
    final lineBytes = BytesBuilder(copy: false);
    var eventBytes = 0;
    String? pendingCarriageReturnLine;

    void countByte() {
      eventBytes += 1;
      if (eventBytes > maxEventBytes) {
        throw McpStreamableProtocolException(
          'MCP SSE event exceeds $maxEventBytes bytes.',
        );
      }
    }

    String takeLine() => utf8.decode(lineBytes.takeBytes());

    await for (final chunk in stream) {
      for (final byte in chunk) {
        final pendingLine = pendingCarriageReturnLine;
        if (pendingLine != null) {
          if (byte == 0x0a) {
            countByte();
            yield pendingLine;
            if (pendingLine.isEmpty) {
              eventBytes = 0;
            }
            pendingCarriageReturnLine = null;
            continue;
          }
          yield pendingLine;
          if (pendingLine.isEmpty) {
            eventBytes = 0;
          }
          pendingCarriageReturnLine = null;
        }

        countByte();
        if (byte == 0x0d) {
          pendingCarriageReturnLine = takeLine();
          continue;
        }
        if (byte == 0x0a) {
          final line = takeLine();
          yield line;
          if (line.isEmpty) {
            eventBytes = 0;
          }
          continue;
        }
        lineBytes.addByte(byte);
      }
    }

    final pendingLine = pendingCarriageReturnLine;
    if (pendingLine != null) {
      yield pendingLine;
    }
    if (lineBytes.length != 0) {
      yield takeLine();
    }
  }
}

/// Active MCP 2026 request-scoped SSE subscription.
class McpStreamableSubscription {
  McpStreamableSubscription._({
    required this.id,
    required this.requestedNotifications,
    required HttpClient httpClient,
    required HttpClientRequest request,
    required HttpClientResponse response,
    required int maxEventBytes,
    required void Function() onClosed,
  }) : _httpClient = httpClient,
       _request = request,
       _response = response,
       _maxEventBytes = maxEventBytes,
       _onClosed = onClosed;

  final Object id;
  final McpSubscriptionFilter requestedNotifications;
  final HttpClient _httpClient;
  final HttpClientRequest _request;
  final HttpClientResponse _response;
  final int _maxEventBytes;
  final void Function() _onClosed;
  final StreamController<McpJsonMap> _notifications =
      StreamController<McpJsonMap>();
  final Completer<McpSubscriptionFilter> _acknowledged =
      Completer<McpSubscriptionFilter>();
  final Completer<McpSubscriptionCloseReason> _closed =
      Completer<McpSubscriptionCloseReason>();
  final List<String> _dataLines = <String>[];

  StreamSubscription<String>? _lineSubscription;
  McpSubscriptionFilter? _acknowledgedNotifications;
  bool _gracefulResultSeen = false;
  bool _finished = false;

  McpSubscriptionFilter get acknowledgedNotifications {
    final value = _acknowledgedNotifications;
    if (value == null) {
      throw StateError('MCP subscription has not been acknowledged');
    }
    return value;
  }

  Stream<McpJsonMap> get notifications => _notifications.stream;

  Future<McpSubscriptionCloseReason> get closed => _closed.future;

  Future<McpSubscriptionFilter> get _acknowledgment => _acknowledged.future;

  void _start() {
    _lineSubscription = _response
        .transform(_McpBoundedSseLineTransformer(_maxEventBytes))
        .listen(
          _handleLine,
          onError: _handleStreamError,
          onDone: _handleStreamDone,
          cancelOnError: false,
        );
  }

  Future<void> close() async {
    if (_finished) {
      return;
    }
    _finish(McpSubscriptionCloseReason.local);
    _request.abort();
    await _lineSubscription?.cancel();
  }

  void _handleLine(String line) {
    if (_finished) {
      return;
    }
    if (line.isEmpty) {
      _commitEvent();
      return;
    }
    if (line.startsWith(':')) {
      return;
    }
    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    if (field == 'data') {
      _dataLines.add(value);
    }
  }

  void _commitEvent() {
    if (_dataLines.isEmpty || _finished) {
      _dataLines.clear();
      return;
    }
    final data = _dataLines.join('\n');
    _dataLines.clear();
    try {
      final decoded = jsonDecode(data);
      final message = _jsonMapFrom(
        decoded,
        label: 'subscriptions/listen SSE message',
      );
      _handleMessage(message);
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _handleMessage(McpJsonMap message) {
    _validateJsonRpcVersion(message, label: 'subscription message');

    if (!_acknowledged.isCompleted) {
      if (message['error'] is Map) {
        final responseId = _validateJsonRpcResponseId(
          message,
          label: 'subscriptions/listen error response',
        );
        if (responseId != id) {
          throw const FormatException(
            'subscriptions/listen error response id does not match request',
          );
        }
        throw McpJsonRpcException(
          id: responseId,
          method: 'subscriptions/listen',
          error: _jsonMapFrom(
            message['error'],
            label: 'subscriptions/listen error',
          ),
        );
      }
      if (message.containsKey('id') ||
          message['method'] != 'notifications/subscriptions/acknowledged') {
        throw const FormatException(
          'The first subscriptions/listen SSE message must be the '
          'acknowledgment notification',
        );
      }
      final params = _subscriptionParams(
        message,
        label: 'subscriptions/listen acknowledgment',
      );
      final acknowledged = _mcpSubscriptionFilterFromJson(
        params['notifications'],
        label: 'subscriptions/listen acknowledgment notifications',
      );
      _validateAcknowledgedSubset(acknowledged);
      _acknowledgedNotifications = acknowledged;
      _acknowledged.complete(acknowledged);
      return;
    }

    if (message.containsKey('result') || message.containsKey('error')) {
      final responseId = _validateJsonRpcResponseId(
        message,
        label: 'subscriptions/listen completion response',
      );
      if (responseId != id) {
        throw const FormatException(
          'subscriptions/listen completion response id does not match request',
        );
      }
      if (message['error'] is Map) {
        throw McpJsonRpcException(
          id: responseId,
          method: 'subscriptions/listen',
          error: _jsonMapFrom(
            message['error'],
            label: 'subscriptions/listen completion error',
          ),
        );
      }
      final result = _jsonMapFrom(
        message['result'],
        label: 'subscriptions/listen completion result',
      );
      if (result['resultType'] != 'complete') {
        throw const FormatException(
          'subscriptions/listen completion resultType must be complete',
        );
      }
      _validateSubscriptionMetadata(
        result,
        label: 'subscriptions/listen completion result',
      );
      _gracefulResultSeen = true;
      return;
    }

    final method = message['method'];
    if (message.containsKey('id') || method is! String) {
      throw const FormatException(
        'subscriptions/listen streams may deliver only notifications',
      );
    }
    final params = _subscriptionParams(
      message,
      label: 'subscriptions/listen notification',
    );
    final acknowledged = acknowledgedNotifications;
    switch (method) {
      case 'notifications/tools/list_changed':
        if (!acknowledged.toolsListChanged) {
          throw const FormatException(
            'Received an unacknowledged tools list-change notification',
          );
        }
        break;
      case 'notifications/prompts/list_changed':
        if (!acknowledged.promptsListChanged) {
          throw const FormatException(
            'Received an unacknowledged prompts list-change notification',
          );
        }
        break;
      case 'notifications/resources/list_changed':
        if (!acknowledged.resourcesListChanged) {
          throw const FormatException(
            'Received an unacknowledged resources list-change notification',
          );
        }
        break;
      case 'notifications/resources/updated':
        if (acknowledged.resourceSubscriptions.isEmpty) {
          throw const FormatException(
            'Received an unacknowledged resource-update notification',
          );
        }
        final uri = params['uri'];
        if (uri is! String) {
          throw const FormatException(
            'Resource-update notifications must include a URI',
          );
        }
        try {
          _validatedMcpResourceUri(
            uri,
            'subscriptions/listen resource update URI',
          );
        } on ArgumentError {
          throw const FormatException(
            'Resource-update notification URI must be absolute',
          );
        }
        if (!acknowledged.resourceSubscriptions.contains(uri)) {
          throw const FormatException(
            'Received a resource update outside the acknowledged filter',
          );
        }
        break;
      default:
        throw FormatException(
          'Unsupported subscriptions/listen notification: $method',
        );
    }
    _notifications.add(Map<String, Object?>.unmodifiable(message));
  }

  McpJsonMap _subscriptionParams(McpJsonMap message, {required String label}) {
    final params = _jsonMapFrom(message['params'], label: '$label params');
    _validateSubscriptionMetadata(params, label: '$label params');
    return params;
  }

  void _validateSubscriptionMetadata(
    McpJsonMap container, {
    required String label,
  }) {
    final metadata = _jsonMapFrom(container['_meta'], label: '$label metadata');
    if (metadata['io.modelcontextprotocol/subscriptionId'] != id) {
      throw FormatException('$label has the wrong subscription ID');
    }
  }

  void _validateAcknowledgedSubset(McpSubscriptionFilter acknowledged) {
    if (acknowledged.toolsListChanged &&
        !requestedNotifications.toolsListChanged) {
      throw const FormatException(
        'Server acknowledged an unrequested tools list subscription',
      );
    }
    if (acknowledged.promptsListChanged &&
        !requestedNotifications.promptsListChanged) {
      throw const FormatException(
        'Server acknowledged an unrequested prompts list subscription',
      );
    }
    if (acknowledged.resourcesListChanged &&
        !requestedNotifications.resourcesListChanged) {
      throw const FormatException(
        'Server acknowledged an unrequested resources list subscription',
      );
    }
    final requestedResources = requestedNotifications.resourceSubscriptions
        .toSet();
    if (acknowledged.resourceSubscriptions.any(
      (uri) => !requestedResources.contains(uri),
    )) {
      throw const FormatException(
        'Server acknowledged an unrequested resource subscription',
      );
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _fail(error, stackTrace);
  }

  void _handleStreamDone() {
    if (_finished) {
      return;
    }
    _commitEvent();
    if (_finished) {
      return;
    }
    if (!_acknowledged.isCompleted) {
      _fail(
        const McpStreamableProtocolException(
          'subscriptions/listen closed before acknowledgment',
        ),
        StackTrace.current,
      );
      return;
    }
    _finish(
      _gracefulResultSeen
          ? McpSubscriptionCloseReason.graceful
          : McpSubscriptionCloseReason.remote,
    );
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_finished) {
      return;
    }
    if (!_acknowledged.isCompleted) {
      _acknowledged.completeError(error, stackTrace);
    } else {
      _notifications.addError(error, stackTrace);
    }
    _request.abort(error, stackTrace);
    final lineSubscription = _lineSubscription;
    if (lineSubscription != null) {
      unawaited(lineSubscription.cancel());
    }
    _finish(McpSubscriptionCloseReason.remote);
  }

  void _finish(McpSubscriptionCloseReason reason) {
    if (_finished) {
      return;
    }
    _finished = true;
    _dataLines.clear();
    _httpClient.close(force: true);
    if (!_acknowledged.isCompleted) {
      _acknowledged.completeError(
        const McpStreamableProtocolException(
          'subscriptions/listen ended before acknowledgment',
        ),
      );
    }
    unawaited(_notifications.close());
    _closed.complete(reason);
    _onClosed();
  }
}

final class _McpSessionStateSnapshot {
  const _McpSessionStateSnapshot(this.token, this.sessionId);

  final Object token;
  final String? sessionId;
}

final class _McpAuthorizationStateSnapshot {
  const _McpAuthorizationStateSnapshot(
    this.token,
    this.headerValue,
    this.expiresAt,
  );

  final Object token;
  final String? headerValue;
  final DateTime? expiresAt;
}

final class _McpResumeStateSnapshot {
  const _McpResumeStateSnapshot(this.token, this.lastEventId);

  final Object token;
  final String? lastEventId;
}

int _validatedMcpMaxRequestBytes(int value) {
  if (value <= 0) {
    throw ArgumentError.value(
      value,
      'maxRequestBytes',
      'maxRequestBytes must be positive',
    );
  }
  return value;
}

List<int> _encodeBoundedMcpHttpRequest(Object? message, int maxRequestBytes) {
  final requestBody = utf8.encode(jsonEncode(message));
  if (requestBody.length > maxRequestBytes) {
    throw McpStreamableProtocolException(
      'MCP HTTP request exceeds $maxRequestBytes bytes.',
    );
  }
  return requestBody;
}

int _validatedMcpMaxResponseBytes(int value) {
  if (value <= 0) {
    throw ArgumentError.value(
      value,
      'maxResponseBytes',
      'maxResponseBytes must be positive',
    );
  }
  return value;
}

Duration _validatedMcpRequestTimeout(Duration value) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(
      value,
      'requestTimeout',
      'requestTimeout must be positive',
    );
  }
  return value;
}

abstract interface class _McpPendingHttpOperation {
  void reject(Object error, StackTrace stackTrace);
}

final class _McpPendingHttpOperationHandle<T>
    implements _McpPendingHttpOperation {
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  void complete(T value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }

  @override
  void reject(Object error, StackTrace stackTrace) {
    completeError(error, stackTrace);
  }
}

final class _McpHttpOperationContext {
  _McpHttpOperationContext({this.onAbort});

  final void Function()? onAbort;
  final Set<HttpClientRequest> requests = <HttpClientRequest>{};
  final Set<_McpPendingHttpResponseBody> responseBodies =
      <_McpPendingHttpResponseBody>{};
  Object? terminalError;
}

final class _McpPendingHttpResponseBody {
  _McpPendingHttpResponseBody(
    HttpClientResponse response,
    this._maxResponseBytes,
  ) {
    final subscription = response.listen(
      _add,
      onError: _fail,
      onDone: _finish,
      cancelOnError: true,
    );
    _subscription = subscription;
    if (_cancelRequested) {
      unawaited(_cancel(subscription));
    }
  }

  final int _maxResponseBytes;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final Completer<String> _result = Completer<String>();
  StreamSubscription<List<int>>? _subscription;
  int _length = 0;
  bool _cancelRequested = false;
  bool _finished = false;

  Future<String> get future => _result.future;

  void abort(Object error) {
    if (_finished) {
      return;
    }
    _finished = true;
    _result.completeError(error, StackTrace.current);
    _requestCancel();
  }

  void _add(List<int> chunk) {
    if (_finished) {
      return;
    }
    _length += chunk.length;
    if (_length > _maxResponseBytes) {
      _finished = true;
      _result.completeError(
        McpStreamableProtocolException(
          'MCP HTTP response exceeds $_maxResponseBytes bytes.',
        ),
        StackTrace.current,
      );
      _requestCancel();
      return;
    }
    _buffer.add(chunk);
  }

  void _finish() {
    if (_finished) {
      return;
    }
    _finished = true;
    try {
      _result.complete(utf8.decode(_buffer.takeBytes()));
    } catch (error, stackTrace) {
      _result.completeError(error, stackTrace);
    }
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_finished) {
      return;
    }
    _finished = true;
    _result.completeError(error, stackTrace);
  }

  void _requestCancel() {
    final subscription = _subscription;
    if (subscription == null) {
      _cancelRequested = true;
      return;
    }
    unawaited(_cancel(subscription));
  }

  Future<void> _cancel(StreamSubscription<List<int>> subscription) async {
    try {
      await subscription.cancel();
    } catch (_) {
      // The deterministic close or response-limit error already completed the
      // body future.
    }
  }
}

final class _McpPendingOAuthHttpOperation {
  final Completer<void> _canceled = Completer<void>();
  Object? _error;

  Future<T> cancellation<T>() async {
    await _canceled.future;
    throw _error!;
  }

  void abort(Object error) {
    if (_canceled.isCompleted) {
      return;
    }
    _error = error;
    _canceled.complete();
  }
}

/// HTTP client for session-based MCP revisions and stateless MCP 2026.
///
/// For session-based revisions, the client keeps the negotiated MCP session
/// headers and SSE cursor so consumer applications do not need to reimplement
/// the transport details.
final class McpStreamableHttpClient {
  /// Default total deadline for one MCP HTTP exchange.
  static const Duration defaultRequestTimeout = Duration(seconds: 30);

  /// Default maximum raw byte length for encoded JSON request bodies.
  static const int defaultMaxRequestBytes = 16 * 1024 * 1024;

  /// Default maximum raw byte length for buffered responses and SSE events.
  static const int defaultMaxResponseBytes = 16 * 1024 * 1024;

  /// Latest supported stateless MCP protocol revision.
  static const latestProtocolVersion = _mcpLatestProtocolVersion;

  /// Latest supported session-based MCP protocol revision.
  static const latestSessionProtocolVersion = _mcpLatestSessionProtocolVersion;

  /// Discovers a same-origin HTTP auth bridge advertised by a protected MCP
  /// endpoint.
  ///
  /// The probe uses a fresh transport, is sessionless, and never sends caller
  /// credentials. Discovery succeeds only when the endpoint returns HTTP 401
  /// with a Bearer challenge for [realm] that includes a safe `auth_path`
  /// parameter.
  ///
  /// Default [headers] are applied only to the returned auth client. They are
  /// never sent by the discovery probe.
  ///
  /// When [httpClient] is omitted, the returned auth client owns the internally
  /// created transport. A supplied client remains caller-owned unless
  /// [closeHttpClient] is true.
  static Future<ConnectanumHttpAuthClient> discoverHttpAuthClient(
    Uri endpoint, {
    required String realm,
    HttpClient? httpClient,
    Map<String, String> headers = const <String, String>{},
    Duration requestTimeout = defaultRequestTimeout,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) async {
    final scheme = endpoint.scheme.toLowerCase();
    if (!endpoint.isAbsolute ||
        (scheme != 'http' && scheme != 'https') ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasFragment) {
      throw const ConnectanumHttpAuthProtocolException(
        'MCP endpoint must be an absolute credential-free HTTP(S) URI',
      );
    }
    if (realm.isEmpty || containsMcpWhitespaceOrControl(realm)) {
      throw ArgumentError.value(
        realm,
        'realm',
        'realm must be non-empty and contain no whitespace or control characters.',
      );
    }

    final probe = McpStreamableHttpClient.stateless(
      endpoint,
      clientInfo: const <String, Object?>{
        'name': 'connectanum-http-auth-discovery',
        'version': '3.0.0-beta.5',
      },
      requestTimeout: requestTimeout,
      maxResponseBytes: maxResponseBytes,
    );
    var succeeded = false;
    try {
      try {
        await probe.pingDirect(id: 'http-auth-discovery');
      } on McpStreamableHttpException catch (error) {
        if (error.statusCode != HttpStatus.unauthorized) {
          throw ConnectanumHttpAuthProtocolException(
            'HTTP auth discovery returned HTTP ${error.statusCode}; '
            'expected ${HttpStatus.unauthorized}.',
          );
        }
        for (final challenge in error.bearerChallenges) {
          if (challenge.realm == realm && challenge.authPath != null) {
            final client = ConnectanumHttpAuthClient.fromMcpBearerChallenge(
              endpoint,
              challenge,
              httpClient: httpClient,
              headers: headers,
              requestTimeout: requestTimeout,
              maxResponseBytes: maxResponseBytes,
              closeHttpClient: closeHttpClient,
            );
            succeeded = true;
            return client;
          }
        }
        throw const ConnectanumHttpAuthProtocolException(
          'HTTP auth discovery did not receive a compatible Bearer challenge '
          'with auth_path for the requested realm.',
        );
      }
      throw const ConnectanumHttpAuthProtocolException(
        'HTTP auth discovery expected the MCP endpoint to require Bearer '
        'authentication.',
      );
    } finally {
      probe.close(force: true);
      if (!succeeded && httpClient != null && closeHttpClient) {
        httpClient.close(force: true);
      }
    }
  }

  /// Creates a session-based Streamable HTTP MCP client for [endpoint].
  McpStreamableHttpClient(
    this.endpoint, {
    HttpClient? httpClient,
    McpHttpClientFactory? subscriptionHttpClientFactory,
    this.headers = const <String, String>{},
    McpJsonMap? clientInfo,
    this.clientCapabilities = const <String, Object?>{},
    String defaultProtocolVersion = latestSessionProtocolVersion,
    Duration requestTimeout = defaultRequestTimeout,
    int maxRequestBytes = defaultMaxRequestBytes,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) : clientInfo = _validatedMcpClientInfo(clientInfo),
       defaultProtocolVersion = _validatedMcpProtocolVersion(
         defaultProtocolVersion,
         'defaultProtocolVersion',
       ),
       requestTimeout = _validatedMcpRequestTimeout(requestTimeout),
       maxRequestBytes = _validatedMcpMaxRequestBytes(maxRequestBytes),
       maxResponseBytes = _validatedMcpMaxResponseBytes(maxResponseBytes),
       _httpClient = httpClient ?? HttpClient(),
       _subscriptionHttpClientFactory =
           subscriptionHttpClientFactory ?? HttpClient.new,
       _ownsHttpClient = httpClient == null || closeHttpClient,
       _authorizationHeader = _authorizationHeaderFrom(headers),
       _protocolVersion = _validatedMcpProtocolVersion(
         defaultProtocolVersion,
         'defaultProtocolVersion',
       );

  /// Creates a client for bearer-protected MCP HTTP endpoints.
  McpStreamableHttpClient.withBearerToken(
    Uri endpoint,
    String bearerToken, {
    HttpClient? httpClient,
    McpHttpClientFactory? subscriptionHttpClientFactory,
    Map<String, String> headers = const <String, String>{},
    McpJsonMap? clientInfo,
    McpJsonMap clientCapabilities = const <String, Object?>{},
    String defaultProtocolVersion = latestSessionProtocolVersion,
    Duration requestTimeout = defaultRequestTimeout,
    int maxRequestBytes = defaultMaxRequestBytes,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) : this(
         endpoint,
         httpClient: httpClient,
         subscriptionHttpClientFactory: subscriptionHttpClientFactory,
         headers: _headersWithBearerToken(headers, bearerToken),
         clientInfo: clientInfo,
         clientCapabilities: clientCapabilities,
         defaultProtocolVersion: defaultProtocolVersion,
         requestTimeout: requestTimeout,
         maxRequestBytes: maxRequestBytes,
         maxResponseBytes: maxResponseBytes,
         closeHttpClient: closeHttpClient,
       );

  /// Creates a sessionless client for MCP protocol revision `2026-07-28`.
  McpStreamableHttpClient.stateless(
    Uri endpoint, {
    required McpJsonMap clientInfo,
    McpJsonMap clientCapabilities = const <String, Object?>{},
    HttpClient? httpClient,
    McpHttpClientFactory? subscriptionHttpClientFactory,
    Map<String, String> headers = const <String, String>{},
    Duration requestTimeout = defaultRequestTimeout,
    int maxRequestBytes = defaultMaxRequestBytes,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) : this(
         endpoint,
         httpClient: httpClient,
         subscriptionHttpClientFactory: subscriptionHttpClientFactory,
         headers: headers,
         clientInfo: clientInfo,
         clientCapabilities: clientCapabilities,
         defaultProtocolVersion: latestProtocolVersion,
         requestTimeout: requestTimeout,
         maxRequestBytes: maxRequestBytes,
         maxResponseBytes: maxResponseBytes,
         closeHttpClient: closeHttpClient,
       );

  /// Creates a bearer-authenticated sessionless MCP 2026 client.
  McpStreamableHttpClient.statelessWithBearerToken(
    Uri endpoint,
    String bearerToken, {
    required McpJsonMap clientInfo,
    McpJsonMap clientCapabilities = const <String, Object?>{},
    HttpClient? httpClient,
    McpHttpClientFactory? subscriptionHttpClientFactory,
    Map<String, String> headers = const <String, String>{},
    Duration requestTimeout = defaultRequestTimeout,
    int maxRequestBytes = defaultMaxRequestBytes,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) : this.withBearerToken(
         endpoint,
         bearerToken,
         httpClient: httpClient,
         subscriptionHttpClientFactory: subscriptionHttpClientFactory,
         headers: headers,
         clientInfo: clientInfo,
         clientCapabilities: clientCapabilities,
         defaultProtocolVersion: latestProtocolVersion,
         requestTimeout: requestTimeout,
         maxRequestBytes: maxRequestBytes,
         maxResponseBytes: maxResponseBytes,
         closeHttpClient: closeHttpClient,
       );

  /// Creates a sessionless MCP 2026 client using an HTTP auth bridge grant.
  ///
  /// The grant's issuing auth endpoint must share [endpoint]'s HTTP origin.
  factory McpStreamableHttpClient.statelessWithAuthGrant(
    Uri endpoint,
    ConnectanumHttpAuthGrant grant, {
    required McpJsonMap clientInfo,
    McpJsonMap clientCapabilities = const <String, Object?>{},
    HttpClient? httpClient,
    McpHttpClientFactory? subscriptionHttpClientFactory,
    Map<String, String> headers = const <String, String>{},
    Duration requestTimeout = defaultRequestTimeout,
    int maxRequestBytes = defaultMaxRequestBytes,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) {
    return McpStreamableHttpClient.withAuthGrant(
      endpoint,
      grant,
      httpClient: httpClient,
      subscriptionHttpClientFactory: subscriptionHttpClientFactory,
      headers: headers,
      clientInfo: clientInfo,
      clientCapabilities: clientCapabilities,
      defaultProtocolVersion: latestProtocolVersion,
      requestTimeout: requestTimeout,
      maxRequestBytes: maxRequestBytes,
      maxResponseBytes: maxResponseBytes,
      closeHttpClient: closeHttpClient,
    );
  }

  /// Creates a client authorized by a validated OAuth token [grant].
  factory McpStreamableHttpClient.withOAuthToken(
    Uri endpoint,
    McpOAuthTokenGrant grant, {
    HttpClient? httpClient,
    McpHttpClientFactory? subscriptionHttpClientFactory,
    Map<String, String> headers = const <String, String>{},
    McpJsonMap? clientInfo,
    McpJsonMap clientCapabilities = const <String, Object?>{},
    String defaultProtocolVersion = latestSessionProtocolVersion,
    Duration requestTimeout = defaultRequestTimeout,
    int maxRequestBytes = defaultMaxRequestBytes,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) {
    _validateOAuthTokenGrant(endpoint, grant);
    final client = McpStreamableHttpClient.withBearerToken(
      endpoint,
      grant.accessToken,
      httpClient: httpClient,
      subscriptionHttpClientFactory: subscriptionHttpClientFactory,
      headers: headers,
      clientInfo: clientInfo,
      clientCapabilities: clientCapabilities,
      defaultProtocolVersion: defaultProtocolVersion,
      requestTimeout: requestTimeout,
      maxRequestBytes: maxRequestBytes,
      maxResponseBytes: maxResponseBytes,
      closeHttpClient: closeHttpClient,
    );
    client._authorizationExpiresAt = grant.expiresAt?.toUtc();
    return client;
  }

  /// Creates a client for MCP HTTP endpoints using an HTTP auth bridge grant.
  ///
  /// The grant's issuing auth endpoint must share [endpoint]'s HTTP origin.
  factory McpStreamableHttpClient.withAuthGrant(
    Uri endpoint,
    ConnectanumHttpAuthGrant grant, {
    HttpClient? httpClient,
    McpHttpClientFactory? subscriptionHttpClientFactory,
    Map<String, String> headers = const <String, String>{},
    McpJsonMap? clientInfo,
    McpJsonMap clientCapabilities = const <String, Object?>{},
    String defaultProtocolVersion = latestSessionProtocolVersion,
    Duration requestTimeout = defaultRequestTimeout,
    int maxRequestBytes = defaultMaxRequestBytes,
    int maxResponseBytes = defaultMaxResponseBytes,
    bool closeHttpClient = false,
  }) {
    final client = McpStreamableHttpClient(
      endpoint,
      httpClient: httpClient,
      subscriptionHttpClientFactory: subscriptionHttpClientFactory,
      headers: _headersWithAuthGrant(endpoint, headers, grant),
      clientInfo: clientInfo,
      clientCapabilities: clientCapabilities,
      defaultProtocolVersion: defaultProtocolVersion,
      requestTimeout: requestTimeout,
      maxRequestBytes: maxRequestBytes,
      maxResponseBytes: maxResponseBytes,
      closeHttpClient: closeHttpClient,
    );
    client._authorizationExpiresAt = grant.accessTokenExpiresAt?.toUtc();
    return client;
  }

  /// Maximum raw byte length for each encoded JSON request body.
  final int maxRequestBytes;

  /// Maximum raw byte length for each buffered HTTP response or SSE event.
  ///
  /// Request-scoped listener streams remain incremental: this limit applies to
  /// each complete SSE event, not to the total lifetime response.
  final int maxResponseBytes;

  /// Total deadline for one POST, GET, DELETE, or listener-setup exchange.
  ///
  /// Established `subscriptions/listen` streams are not lifetime-limited by
  /// this value after their acknowledgment arrives.
  final Duration requestTimeout;

  /// Absolute Streamable HTTP endpoint used by this client.
  final Uri endpoint;

  /// Default HTTP headers applied to outgoing MCP requests.
  final Map<String, String> headers;

  /// Client identity sent during MCP initialization, when configured.
  final McpJsonMap? clientInfo;

  /// Client capabilities sent during MCP initialization.
  final McpJsonMap clientCapabilities;

  /// Protocol revision used before a server negotiates another revision.
  final String defaultProtocolVersion;
  final HttpClient _httpClient;
  final McpHttpClientFactory _subscriptionHttpClientFactory;
  final bool _ownsHttpClient;
  bool _closed = false;
  final Set<HttpClientRequest> _pendingHttpRequests = <HttpClientRequest>{};
  final Set<_McpPendingHttpOperation> _pendingHttpOperations =
      <_McpPendingHttpOperation>{};
  final Set<_McpPendingOAuthHttpOperation> _pendingOAuthHttpOperations =
      <_McpPendingOAuthHttpOperation>{};
  final Set<_McpPendingHttpResponseBody> _pendingHttpResponseBodies =
      <_McpPendingHttpResponseBody>{};
  Object _httpRequestStateToken = Object();
  String? _authorizationHeader;
  DateTime? _authorizationExpiresAt;
  Object _authorizationStateToken = Object();
  final Set<McpStreamableSubscription> _subscriptions =
      <McpStreamableSubscription>{};
  final Set<HttpClient> _pendingSubscriptionHttpClients = <HttpClient>{};
  Object _subscriptionStateToken = Object();
  final _toolHeaderParametersByName = <String, List<_McpToolHeaderParameter>>{};
  final _toolHeaderParameterGenerationByName = <String, int>{};

  int _nextRequestId = 1;
  int _toolCatalogRequestGeneration = 0;

  String _protocolVersion;
  String? _sessionId;
  Object _sessionStateToken = Object();
  String? _lastEventId;
  Object _resumeStateToken = Object();

  /// MCP protocol revision currently used for requests.
  String get protocolVersion => _protocolVersion;

  /// Active MCP session identifier, or `null` for a stateless client.
  String? get sessionId => _sessionId;

  set sessionId(String? value) {
    _sessionId = value;
    _sessionStateToken = Object();
  }

  _McpSessionStateSnapshot get _sessionStateSnapshot =>
      _McpSessionStateSnapshot(_sessionStateToken, _sessionId);

  /// Last accepted SSE event identifier used when resuming a stream.
  String? get lastEventId => _lastEventId;

  set lastEventId(String? value) {
    _lastEventId = value;
    _resumeStateToken = Object();
  }

  _McpResumeStateSnapshot get _resumeStateSnapshot =>
      _McpResumeStateSnapshot(_resumeStateToken, _lastEventId);

  _McpAuthorizationStateSnapshot get _authorizationStateSnapshot =>
      _McpAuthorizationStateSnapshot(
        _authorizationStateToken,
        _authorizationHeader,
        _authorizationExpiresAt,
      );

  set protocolVersion(String value) {
    final validated = _validatedMcpProtocolVersion(value, 'protocolVersion');
    if (validated == latestProtocolVersion) {
      _clearSessionState();
    }
    _protocolVersion = validated;
  }

  static Map<String, String> _headersWithBearerToken(
    Map<String, String> headers,
    String bearerToken,
  ) {
    final token = bearerToken.trim();
    if (token.isEmpty || containsMcpWhitespaceOrControl(token)) {
      throw ArgumentError.value(
        bearerToken,
        'bearerToken',
        token.isEmpty
            ? 'Bearer token must not be empty.'
            : 'Bearer token must not contain whitespace or control characters.',
      );
    }
    return <String, String>{
      for (final entry in headers.entries)
        if (entry.key.toLowerCase() != HttpHeaders.authorizationHeader)
          entry.key: entry.value,
      HttpHeaders.authorizationHeader: 'Bearer $token',
    };
  }

  static String? _authorizationHeaderFrom(Map<String, String> headers) {
    String? value;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == HttpHeaders.authorizationHeader) {
        value = entry.value;
      }
    }
    return value;
  }

  static Map<String, String> _headersWithAuthGrant(
    Uri endpoint,
    Map<String, String> headers,
    ConnectanumHttpAuthGrant grant,
  ) {
    if (!grant.isForMcpEndpoint(endpoint)) {
      throw ArgumentError(
        'grant.authEndpoint must share the MCP endpoint HTTP origin.',
      );
    }
    if (grant.isAccessTokenExpired()) {
      throw ArgumentError(
        'grant.accessToken is expired and cannot authorize an MCP client.',
      );
    }
    final tokenType = grant.tokenType.trim();
    if (tokenType.toLowerCase() != 'bearer') {
      throw ArgumentError.value(
        grant.tokenType,
        'grant.tokenType',
        'Only Bearer HTTP auth grants can authorize MCP HTTP clients.',
      );
    }
    return _headersWithBearerToken(headers, grant.accessToken);
  }

  static void _validateOAuthTokenGrant(Uri endpoint, McpOAuthTokenGrant grant) {
    if (!grant.isForResource(endpoint)) {
      throw McpOAuthTokenException(
        'OAuth token grant is not valid for this MCP resource.',
        endpoint: endpoint,
      );
    }
    if (grant.isAccessTokenExpired()) {
      throw McpOAuthTokenException(
        'OAuth token grant access token has expired.',
        endpoint: endpoint,
      );
    }
  }

  /// Discovers OAuth Protected Resource Metadata without using session state.
  ///
  /// [timeout] is one total deadline across the probe and metadata fallbacks.
  Future<McpProtectedResourceDiscovery> discoverProtectedResourceMetadata({
    Map<String, String> headers = const <String, String>{},
    int maxMetadataBytes = 1024 * 1024,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _runTrackedOAuthHttpOperation(
      (onRequestOpened) => discoverMcpProtectedResourceMetadata(
        endpoint,
        httpClient: _httpClient,
        headers: headers,
        maxMetadataBytes: maxMetadataBytes,
        timeout: timeout,
        onRequestOpened: onRequestOpened,
      ),
    );
  }

  /// Discovers validated OAuth metadata for an advertised authorization server.
  ///
  /// [timeout] is one total deadline across every well-known fallback.
  Future<McpAuthorizationServerDiscovery> discoverAuthorizationServerMetadata(
    Uri issuer, {
    Map<String, String> headers = const <String, String>{},
    int maxMetadataBytes = 1024 * 1024,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _runTrackedOAuthHttpOperation(
      (onRequestOpened) => discoverMcpAuthorizationServerMetadata(
        issuer,
        httpClient: _httpClient,
        headers: headers,
        maxMetadataBytes: maxMetadataBytes,
        timeout: timeout,
        onRequestOpened: onRequestOpened,
      ),
    );
  }

  /// Creates an OAuth authorization-code request for this MCP endpoint.
  McpAuthorizationRequest createAuthorizationRequest({
    required McpAuthorizationServerMetadata authorizationServer,
    required String clientId,
    required Uri redirectUri,
    Iterable<String> scopes = const <String>[],
    McpPkcePair? pkce,
  }) {
    return createMcpAuthorizationRequest(
      authorizationServer: authorizationServer,
      resource: endpoint,
      clientId: clientId,
      redirectUri: redirectUri,
      scopes: scopes,
      pkce: pkce,
    );
  }

  /// Creates an initial OAuth request bound to validated MCP discovery.
  ///
  /// The protected resource must match [endpoint], and the selected
  /// authorization server must be one of its advertised issuers. This method
  /// does not mutate credentials, protocol, session, or resume state.
  McpAuthorizationRequest createDiscoveredAuthorizationRequest({
    required McpProtectedResourceDiscovery protectedResource,
    required McpAuthorizationServerDiscovery authorizationServer,
    required String clientId,
    required Uri redirectUri,
    Iterable<String> additionalScopes = const <String>[],
    McpPkcePair? pkce,
  }) {
    return createMcpDiscoveredAuthorizationRequest(
      protectedResource: protectedResource,
      authorizationServer: authorizationServer,
      resource: endpoint,
      clientId: clientId,
      redirectUri: redirectUri,
      additionalScopes: additionalScopes,
      pkce: pkce,
    );
  }

  /// Builds a resource-bound OAuth request for an MCP scope challenge.
  ///
  /// This validates one HTTP 403 Bearer `insufficient_scope` challenge,
  /// preserves the current and previously requested scopes, and adds the
  /// authoritative challenge scopes. It does not mutate this client's grant,
  /// session, resume cursor, or negotiated protocol.
  ///
  /// Throws [McpOAuthStepUpException] when the response context is ambiguous,
  /// malformed, missing protected-resource metadata, or bound to another MCP
  /// resource. Browser interaction, token exchange, grant replacement, and
  /// retry limits remain caller-owned.
  McpAuthorizationRequest createStepUpAuthorizationRequest({
    required McpOAuthTokenGrant currentGrant,
    required McpStreamableHttpException authorizationFailure,
    required Uri redirectUri,
    Iterable<String> previouslyRequestedScopes = const <String>[],
    McpPkcePair? pkce,
  }) {
    if (!currentGrant.isForResource(endpoint)) {
      throw const McpOAuthStepUpException(
        'OAuth grant belongs to a different MCP resource.',
      );
    }
    if (authorizationFailure.statusCode != HttpStatus.forbidden) {
      throw const McpOAuthStepUpException(
        'OAuth step-up requires an HTTP 403 response.',
      );
    }

    final challenges = authorizationFailure.bearerChallenges;
    if (challenges.length != 1) {
      throw const McpOAuthStepUpException(
        'OAuth step-up requires one unambiguous Bearer challenge.',
      );
    }
    final challenge = challenges.single;
    if (challenge.error != 'insufficient_scope') {
      throw const McpOAuthStepUpException(
        'Bearer challenge does not request OAuth scope step-up.',
      );
    }
    if (!_mcpOAuthMetadataUriValid(challenge.resourceMetadata)) {
      throw const McpOAuthStepUpException(
        'Bearer challenge has invalid protected-resource metadata.',
      );
    }
    final challengeScopes = challenge.scopes;
    if (challengeScopes.isEmpty ||
        challengeScopes.any((scope) => !_mcpOAuthScopeTokenValid(scope))) {
      throw const McpOAuthStepUpException(
        'Bearer challenge has invalid OAuth scopes.',
      );
    }

    final scopes = <String>[];
    final seenScopes = <String>{};
    void addScopes(Iterable<String> candidates) {
      for (final scope in candidates) {
        if (!_mcpOAuthScopeTokenValid(scope)) {
          throw const McpOAuthStepUpException(
            'OAuth step-up context has invalid scopes.',
          );
        }
        if (seenScopes.add(scope)) {
          scopes.add(scope);
        }
      }
    }

    addScopes(currentGrant.scopes);
    addScopes(previouslyRequestedScopes);
    addScopes(challengeScopes);
    return createMcpAuthorizationRequest(
      authorizationServer: currentGrant.authorizationServer,
      resource: endpoint,
      clientId: currentGrant.clientId,
      redirectUri: redirectUri,
      scopes: scopes,
      pkce: pkce,
    );
  }

  /// Registers an OAuth client with the discovered authorization server.
  Future<McpOAuthDynamicClientRegistration> registerOAuthClient(
    McpAuthorizationServerMetadata authorizationServer, {
    required McpOAuthDynamicClientRegistrationRequest registration,
    String? initialAccessToken,
    Map<String, String> headers = const <String, String>{},
    Duration timeout = const Duration(seconds: 30),
    int maxResponseBytes = 64 * 1024,
  }) {
    return _runTrackedOAuthHttpOperation(
      (onRequestOpened) => registerMcpOAuthClient(
        authorizationServer: authorizationServer,
        registration: registration,
        initialAccessToken: initialAccessToken,
        httpClient: _httpClient,
        headers: headers,
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
        onRequestOpened: onRequestOpened,
      ),
    );
  }

  /// Exchanges an OAuth authorization code for an access-token grant.
  Future<McpOAuthTokenGrant> exchangeAuthorizationCode(
    McpAuthorizationCode authorizationCode, {
    required McpOAuthClientAuthentication clientAuthentication,
    Map<String, String> headers = const <String, String>{},
    Duration timeout = const Duration(seconds: 30),
    int maxResponseBytes = 64 * 1024,
  }) {
    _throwIfClosed();
    if (!_sameMcpOAuthResource(authorizationCode.request.resource, endpoint)) {
      throw McpOAuthTokenException(
        'Authorization code is not valid for this MCP resource.',
        endpoint: endpoint,
      );
    }
    return _runTrackedOAuthHttpOperation(
      (onRequestOpened) => exchangeMcpAuthorizationCode(
        authorizationCode,
        clientAuthentication: clientAuthentication,
        httpClient: _httpClient,
        headers: headers,
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
        onRequestOpened: onRequestOpened,
      ),
    );
  }

  /// Refreshes a resource-bound OAuth grant without changing MCP session state.
  Future<McpOAuthTokenGrant> refreshOAuthToken(
    McpOAuthTokenGrant grant, {
    required McpOAuthClientAuthentication clientAuthentication,
    Iterable<String>? scopes,
    Map<String, String> headers = const <String, String>{},
    Duration timeout = const Duration(seconds: 30),
    int maxResponseBytes = 64 * 1024,
  }) {
    _throwIfClosed();
    if (!grant.isForResource(endpoint)) {
      throw McpOAuthTokenException(
        'OAuth token grant is not valid for this MCP resource.',
        endpoint: endpoint,
      );
    }
    return _runTrackedOAuthHttpOperation(
      (onRequestOpened) => refreshMcpOAuthToken(
        grant,
        clientAuthentication: clientAuthentication,
        scopes: scopes,
        httpClient: _httpClient,
        headers: headers,
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
        onRequestOpened: onRequestOpened,
      ),
    );
  }

  /// Revokes one OAuth grant credential without changing MCP session state.
  Future<void> revokeOAuthToken(
    McpOAuthTokenGrant grant, {
    required McpOAuthClientAuthentication clientAuthentication,
    McpOAuthTokenKind tokenKind = McpOAuthTokenKind.refreshToken,
    Map<String, String> headers = const <String, String>{},
    Duration timeout = const Duration(seconds: 30),
    int maxResponseBytes = 64 * 1024,
  }) {
    _throwIfClosed();
    if (!grant.isForResource(endpoint)) {
      throw McpOAuthTokenException(
        'OAuth token grant is not valid for this MCP resource.',
        endpoint: endpoint,
      );
    }
    return _runTrackedOAuthHttpOperation(
      (onRequestOpened) => revokeMcpOAuthToken(
        grant,
        clientAuthentication: clientAuthentication,
        tokenKind: tokenKind,
        httpClient: _httpClient,
        headers: headers,
        timeout: timeout,
        maxResponseBytes: maxResponseBytes,
        onRequestOpened: onRequestOpened,
      ),
    );
  }

  /// Replaces the router HTTP-auth grant used for subsequent MCP requests.
  ///
  /// The [grant] must contain a valid Bearer access token issued by an auth
  /// endpoint that shares this client's HTTP origin. Streamable HTTP session,
  /// resume, protocol, request, and connection state remain unchanged.
  /// Requests already in flight keep their captured credential, and a delayed
  /// 401 or failed initialize for that credential cannot clear the replacement
  /// authorization state's active session. Refresh timing and request retries
  /// stay caller-controlled.
  void replaceAuthGrant(ConnectanumHttpAuthGrant grant) {
    final authorizationHeader = _authorizationHeaderFrom(
      _headersWithAuthGrant(
        endpoint,
        const <String, String>{},
        grant,
      ),
    );
    final authorizationExpiresAt = grant.accessTokenExpiresAt?.toUtc();
    _authorizationHeader = authorizationHeader;
    _authorizationExpiresAt = authorizationExpiresAt;
    _authorizationStateToken = Object();
  }

  /// Replaces the OAuth access token used for subsequent MCP HTTP requests.
  ///
  /// The [grant] must be unexpired and bound to this client's MCP endpoint.
  /// Streamable HTTP session, resume, protocol, request, and connection state
  /// remain unchanged. Requests already in flight keep their captured
  /// credential, and a delayed 401 or failed initialize for that credential
  /// cannot clear the replacement authorization state's active session.
  /// Authorization flows and request retries stay caller-controlled.
  void replaceOAuthToken(McpOAuthTokenGrant grant) {
    _validateOAuthTokenGrant(endpoint, grant);
    final authorizationHeader = _authorizationHeaderFrom(
      _headersWithBearerToken(const <String, String>{}, grant.accessToken),
    );
    final authorizationExpiresAt = grant.expiresAt?.toUtc();
    _authorizationHeader = authorizationHeader;
    _authorizationExpiresAt = authorizationExpiresAt;
    _authorizationStateToken = Object();
  }

  /// Initializes a session-based MCP connection and captures its session ID.
  Future<McpJsonMap> initialize({
    Object? id = 'initialize',
    McpJsonMap capabilities = const <String, Object?>{},
    McpJsonMap clientInfo = const <String, Object?>{
      'name': 'connectanum_client',
      'version': '3.0.0-beta.5',
    },
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final requestedProtocolVersion = protocolVersion ?? this.protocolVersion;
    final response = await post(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': requestedProtocolVersion,
          'capabilities': capabilities,
          'clientInfo': clientInfo,
        },
      },
      includeSession: false,
      protocolVersion: requestedProtocolVersion,
      headers: headers,
    );
    if (response == null) {
      throw const FormatException('initialize did not return a JSON-RPC body');
    }
    return response;
  }

  /// Discovers an MCP 2026 server without creating a protocol session.
  Future<McpStatelessDiscoveryResult> discover({
    Object? id,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'server/discover',
      id: id,
      protocolVersion: latestProtocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: 'server/discover');
    final rawVersions = result['supportedVersions'];
    if (rawVersions is! List ||
        rawVersions.isEmpty ||
        rawVersions.any((version) => version is! String || version.isEmpty)) {
      throw const FormatException(
        'server/discover supportedVersions must be a non-empty string array',
      );
    }
    final capabilities = _jsonMapFrom(
      result['capabilities'],
      label: 'server/discover capabilities',
    );
    final metadata = result['_meta'];
    final serverInfoValue = metadata is Map
        ? _jsonMapFrom(
            metadata,
            label: 'server/discover result metadata',
          )['io.modelcontextprotocol/serverInfo']
        : null;
    final serverInfo = serverInfoValue == null
        ? null
        : _jsonMapFrom(serverInfoValue, label: 'server/discover server info');
    final instructions = result['instructions'];
    if (instructions != null && instructions is! String) {
      throw const FormatException(
        'server/discover instructions must be a string',
      );
    }
    final ttlMs = result['ttlMs'];
    if (ttlMs != null && (ttlMs is! int || ttlMs < 0)) {
      throw const FormatException(
        'server/discover ttlMs must be a non-negative integer',
      );
    }
    final cacheScope = result['cacheScope'];
    if (cacheScope != null && cacheScope is! String) {
      throw const FormatException(
        'server/discover cacheScope must be a string',
      );
    }
    return McpStatelessDiscoveryResult(
      supportedVersions: List<String>.unmodifiable(rawVersions.cast<String>()),
      capabilities: capabilities,
      serverInfo: serverInfo,
      instructions: instructions as String?,
      ttlMs: ttlMs as int?,
      cacheScope: cacheScope as String?,
    );
  }

  /// Opens a resumable Streamable HTTP listener for server notifications.
  Future<McpStreamableSubscription> listen({
    Object? id,
    bool toolsListChanged = false,
    bool promptsListChanged = false,
    bool resourcesListChanged = false,
    Iterable<String> resourceSubscriptions = const <String>[],
    Map<String, String> headers = const <String, String>{},
  }) async {
    _throwIfClosed();
    if (protocolVersion != latestProtocolVersion) {
      throw const McpStreamableProtocolException(
        'subscriptions/listen requires the MCP 2026 stateless protocol',
      );
    }

    final validatedResources = <String>[];
    final seenResources = <String>{};
    for (final resourceUri in resourceSubscriptions) {
      final uri = _validatedMcpResourceUri(
        resourceUri,
        'resourceSubscriptions',
      );
      if (!seenResources.add(uri)) {
        throw ArgumentError.value(
          resourceSubscriptions,
          'resourceSubscriptions',
          'MCP resource subscriptions must not contain duplicates.',
        );
      }
      validatedResources.add(uri);
    }
    final requestedNotifications = McpSubscriptionFilter(
      toolsListChanged: toolsListChanged,
      promptsListChanged: promptsListChanged,
      resourcesListChanged: resourcesListChanged,
      resourceSubscriptions: validatedResources,
    );
    final requestId = id ?? _nextRequestId++;
    final message = <String, Object?>{
      'jsonrpc': '2.0',
      'id': requestId,
      'method': 'subscriptions/listen',
      'params': <String, Object?>{
        'notifications': requestedNotifications.toJson(),
      },
    };
    _validateJsonRpcRequestId(message, label: 'subscriptions/listen request');
    final preparedMessage = _prepareMessageForProtocol(
      message,
      latestProtocolVersion,
    );
    final requestBody = _encodeBoundedMcpHttpRequest(
      preparedMessage,
      maxRequestBytes,
    );

    HttpClient? pendingSubscriptionHttpClient;
    void abortSubscriptionSetup() {
      final client = pendingSubscriptionHttpClient;
      if (client == null) {
        return;
      }
      pendingSubscriptionHttpClient = null;
      _pendingSubscriptionHttpClients.remove(client);
      client.close(force: true);
    }

    return _runTrackedHttpOperation<McpStreamableSubscription>(
      (operation) async {
        final requestAuthorizationState = _authorizationStateSnapshot;
        final subscriptionStateToken = _subscriptionStateToken;
        final subscriptionHttpClient = _subscriptionHttpClientFactory();
        pendingSubscriptionHttpClient = subscriptionHttpClient;
        _pendingSubscriptionHttpClients.add(subscriptionHttpClient);
        void closeSubscriptionHttpClient() {
          if (identical(
            pendingSubscriptionHttpClient,
            subscriptionHttpClient,
          )) {
            pendingSubscriptionHttpClient = null;
          }
          _pendingSubscriptionHttpClients.remove(subscriptionHttpClient);
          subscriptionHttpClient.close(force: true);
        }

        final HttpClientRequest request;
        try {
          request = await _openTrackedHttpRequest(
            () => subscriptionHttpClient.postUrl(endpoint),
            operation,
            requestAuthorizationState,
            enforceClientState: false,
          );
        } catch (_) {
          closeSubscriptionHttpClient();
          rethrow;
        }
        final HttpClientResponse response;
        try {
          _applyHeaders(
            request,
            accept: _acceptStreamableHttp,
            includeSession: false,
            protocolVersion: latestProtocolVersion,
            authorizationState: requestAuthorizationState,
            extraHeaders: headers,
          );
          _applyStandardRequestHeaders(request, preparedMessage);
          request.headers.contentType = ContentType.json;
          request.persistentConnection = false;
          request.contentLength = requestBody.length;
          request.add(requestBody);
          response = await _sendTrackedHttpRequest(request, operation);
        } catch (_) {
          closeSubscriptionHttpClient();
          rethrow;
        }
        try {
          if (response.statusCode < HttpStatus.ok ||
              response.statusCode >= HttpStatus.multipleChoices) {
            final body = await _readTrackedHttpResponseBody(
              request,
              response,
              operation,
            );
            _throwIfHttpError(response, body);
          }
          if (!_isSse(response)) {
            final body = await _readTrackedHttpResponseBody(
              request,
              response,
              operation,
            );
            if (_isJson(response) && body.isNotEmpty) {
              final jsonResponse = _jsonMapFromBody(
                body,
                'subscriptions/listen JSON response',
              );
              _jsonRpcResultFrom(jsonResponse, method: 'subscriptions/listen');
            }
            throw FormatException(
              'Expected $_acceptSse response, got '
              '${response.headers.contentType?.mimeType ?? 'unknown'}',
            );
          }
          _captureSessionHeaders(
            response,
            captureSessionState: false,
            forbidSessionId: true,
            expectedProtocolVersion: latestProtocolVersion,
          );
        } catch (_) {
          closeSubscriptionHttpClient();
          rethrow;
        }

        if (!identical(subscriptionStateToken, _subscriptionStateToken)) {
          closeSubscriptionHttpClient();
          throw StateError(
            'MCP client closed while subscriptions/listen was pending.',
          );
        }

        late final McpStreamableSubscription subscription;
        subscription = McpStreamableSubscription._(
          id: requestId,
          requestedNotifications: requestedNotifications,
          httpClient: subscriptionHttpClient,
          request: request,
          response: response,
          maxEventBytes: maxResponseBytes,
          onClosed: () => _subscriptions.remove(subscription),
        );
        _pendingSubscriptionHttpClients.remove(subscriptionHttpClient);
        _subscriptions.add(subscription);
        subscription._start();
        try {
          await subscription._acknowledgment;
          pendingSubscriptionHttpClient = null;
          return subscription;
        } catch (_) {
          pendingSubscriptionHttpClient = null;
          await subscription.close();
          rethrow;
        }
      },
      onAbort: abortSubscriptionSetup,
      trackForClose: false,
    );
  }

  /// Sends the MCP `notifications/initialized` lifecycle notification.
  Future<void> notifyInitialized({
    Map<String, String> headers = const <String, String>{},
  }) async {
    await notification('notifications/initialized', headers: headers);
  }

  /// Sends a stateful JSON-RPC request using the active MCP session.
  Future<McpJsonMap> request(
    String method, {
    Object? id,
    McpJsonMap? params,
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await post(
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': id ?? _nextRequestId++,
        'method': method,
        'params': ?params,
      },
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    if (response == null) {
      throw FormatException('$method did not return a JSON-RPC body');
    }
    return response;
  }

  /// Sends a direct JSON API request without MCP session headers.
  Future<McpJsonMap> requestDirect(
    String method, {
    Object? id,
    McpJsonMap? params,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return request(
      method,
      id: id,
      params: params,
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Pings the active MCP session.
  Future<McpJsonMap> ping({
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'ping',
      id: id,
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return _jsonRpcResultFrom(response, method: 'ping');
  }

  /// Pings the endpoint through the direct JSON API.
  Future<McpJsonMap> pingDirect({
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await requestDirect(
      'ping',
      id: id,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return _jsonRpcResultFrom(response, method: 'ping');
  }

  /// Lists one page of tools through the active MCP session.
  Future<McpStreamableToolListPage> listTools({
    Object? id,
    String? cursor,
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    const method = 'tools/list';
    final requestGeneration = _claimToolCatalogRequestGeneration();
    final response = await request(
      method,
      id: id,
      params: _cursorParams(cursor),
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: method);
    final catalogTools = _validatedToolCatalogEntries(
      _jsonMapListFrom(
        result,
        key: 'tools',
        method: method,
        label: '$method result tool',
      ),
      label: '$method result tool',
    );
    final nextCursor = _nextCursorFrom(result, method: method);
    final tools = _rememberToolHeaderParameters(
      catalogTools,
      requestGeneration: requestGeneration,
    );
    return McpStreamableToolListPage(tools: tools, nextCursor: nextCursor);
  }

  /// Lists one page of tools through the direct JSON API.
  Future<McpStreamableToolListPage> listToolsDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    const method = 'tools/list';
    final requestGeneration = _claimToolCatalogRequestGeneration();
    final response = await requestDirect(
      method,
      id: id,
      params: _cursorParams(cursor),
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: method);
    final catalogTools = _validatedToolCatalogEntries(
      _jsonMapListFrom(
        result,
        key: 'tools',
        method: method,
        label: '$method result tool',
      ),
      label: '$method result tool',
    );
    final nextCursor = _nextCursorFrom(result, method: method);
    final tools = _rememberToolHeaderParameters(
      catalogTools,
      requestGeneration: requestGeneration,
    );
    return McpStreamableToolListPage(tools: tools, nextCursor: nextCursor);
  }

  /// Calls an MCP tool through the active session.
  Future<McpJsonMap> callTool(
    String name, {
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final toolName = _validatedMcpToolName(name, 'name');
    final response = await request(
      'tools/call',
      id: id,
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
    return _validatedToolCallResult(
      _jsonRpcResultFrom(response, method: 'tools/call'),
      label: 'tools/call result',
    );
  }

  /// Calls a modern stateless tool and completes bounded form input rounds
  /// through [onElicitation].
  Future<McpJsonMap> callToolWithFormElicitation(
    String name, {
    required McpFormElicitationHandler onElicitation,
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
    int maxInputRequiredRounds = 8,
  }) {
    return _callToolWithFormElicitation(
      name,
      onElicitation: onElicitation,
      id: id,
      arguments: arguments,
      streamable: streamable,
      direct: false,
      protocolVersion: protocolVersion,
      headers: headers,
      maxInputRequiredRounds: maxInputRequiredRounds,
    );
  }

  /// Calls a modern stateless tool directly and completes bounded form input
  /// rounds through [onElicitation].
  Future<McpJsonMap> callToolDirectWithFormElicitation(
    String name, {
    required McpFormElicitationHandler onElicitation,
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
    int maxInputRequiredRounds = 8,
  }) {
    return _callToolWithFormElicitation(
      name,
      onElicitation: onElicitation,
      id: id,
      arguments: arguments,
      streamable: false,
      direct: true,
      protocolVersion: protocolVersion,
      headers: headers,
      maxInputRequiredRounds: maxInputRequiredRounds,
    );
  }

  Future<McpJsonMap> _callToolWithFormElicitation(
    String name, {
    required McpFormElicitationHandler onElicitation,
    required Object? id,
    required McpJsonMap arguments,
    required bool streamable,
    required bool direct,
    required String? protocolVersion,
    required Map<String, String> headers,
    required int maxInputRequiredRounds,
  }) async {
    final effectiveProtocolVersion = _validatedMcpProtocolVersion(
      protocolVersion ?? this.protocolVersion,
      'protocolVersion',
    );
    if (effectiveProtocolVersion != latestProtocolVersion) {
      throw McpStreamableProtocolException(
        'MCP form elicitation requires protocol $latestProtocolVersion',
      );
    }
    if (maxInputRequiredRounds < 1) {
      throw ArgumentError.value(
        maxInputRequiredRounds,
        'maxInputRequiredRounds',
        'MCP form elicitation needs at least one permitted input round.',
      );
    }

    final toolName = _validatedMcpToolName(name, 'name');
    final requestHeaders = _headersWithToolParameterHeaders(
      toolName,
      arguments,
      headers,
    );
    final usedRequestIds = <Object>{};
    Object nextGeneratedRequestId() {
      Object candidate;
      do {
        candidate = _nextRequestId++;
      } while (usedRequestIds.contains(candidate));
      usedRequestIds.add(candidate);
      return candidate;
    }

    var requestId = id ?? nextGeneratedRequestId();
    usedRequestIds.add(requestId);
    var inputRequiredRounds = 0;
    var params = <String, Object?>{
      'name': toolName,
      'arguments': arguments,
      '_meta': const <String, Object?>{
        'io.modelcontextprotocol/clientCapabilities': <String, Object?>{
          'elicitation': <String, Object?>{'form': <String, Object?>{}},
        },
      },
    };

    while (true) {
      final response = direct
          ? await requestDirect(
              'tools/call',
              id: requestId,
              params: params,
              protocolVersion: effectiveProtocolVersion,
              headers: requestHeaders,
            )
          : await request(
              'tools/call',
              id: requestId,
              params: params,
              streamable: streamable,
              protocolVersion: effectiveProtocolVersion,
              headers: requestHeaders,
            );
      final result = _jsonRpcResultFrom(response, method: 'tools/call');
      final inputRound = _mcpInputRequiredRoundFrom(
        result,
        label: 'tools/call result',
      );
      if (inputRound == null) {
        return _validatedToolCallResult(result, label: 'tools/call result');
      }
      inputRequiredRounds += 1;
      if (inputRequiredRounds > maxInputRequiredRounds) {
        throw McpStreamableProtocolException(
          'MCP tools/call exceeded $maxInputRequiredRounds '
          'input-required rounds',
        );
      }

      final inputResponses = <String, Object?>{};
      for (final inputRequest in inputRound.requests) {
        final response = await onElicitation(inputRequest);
        inputResponses[inputRequest.inputRequestId] = response.toJsonFor(
          inputRequest,
        );
      }
      params = <String, Object?>{
        'name': toolName,
        'arguments': arguments,
        if (inputResponses.isNotEmpty) 'inputResponses': inputResponses,
        'requestState': ?inputRound.requestState,
        '_meta': const <String, Object?>{
          'io.modelcontextprotocol/clientCapabilities': <String, Object?>{
            'elicitation': <String, Object?>{'form': <String, Object?>{}},
          },
        },
      };
      requestId = nextGeneratedRequestId();
    }
  }

  /// Invokes an MCP tool as a notification through the active session.
  Future<void> notifyTool(
    String name, {
    McpJsonMap arguments = const <String, Object?>{},
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final toolName = _validatedMcpToolName(name, 'name');
    return notification(
      'tools/call',
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
  }

  /// Calls an MCP tool through the direct JSON API.
  Future<McpJsonMap> callToolDirect(
    String name, {
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final toolName = _validatedMcpToolName(name, 'name');
    final response = await requestDirect(
      'tools/call',
      id: id,
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
    return _validatedToolCallResult(
      _jsonRpcResultFrom(response, method: 'tools/call'),
      label: 'tools/call result',
    );
  }

  /// Invokes an MCP tool notification through the direct JSON API.
  Future<void> notifyToolDirect(
    String name, {
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final toolName = _validatedMcpToolName(name, 'name');
    return notificationDirect(
      'tools/call',
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
  }

  /// Lists Connectanum JSON tools from the direct API catalog.
  Future<McpStreamableToolListPage> listConnectanumToolsDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    const method = 'connectanum.tools.list';
    final requestGeneration = _claimToolCatalogRequestGeneration();
    final response = await request(
      method,
      id: id,
      params: _cursorParams(cursor),
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: method);
    final catalogTools = _validatedToolCatalogEntries(
      _jsonMapListFrom(
        result,
        key: 'tools',
        method: method,
        label: '$method result tool',
      ),
      label: '$method result tool',
    );
    final nextCursor = _nextCursorFrom(result, method: method);
    final tools = _rememberToolHeaderParameters(
      catalogTools,
      requestGeneration: requestGeneration,
    );
    return McpStreamableToolListPage(tools: tools, nextCursor: nextCursor);
  }

  /// Calls a Connectanum JSON tool through the direct API.
  Future<McpJsonMap> callConnectanumToolDirect(
    String name, {
    Object? id,
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    const method = 'connectanum.tool.call';
    final toolName = _validatedMcpToolName(name, 'name');
    final response = await request(
      method,
      id: id,
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
    return _validatedToolCallResult(
      _jsonRpcResultFrom(response, method: method),
      label: '$method result',
    );
  }

  /// Calls a Connectanum JSON method through the active MCP session.
  Future<McpJsonMap> callConnectanumMethod(
    String method, {
    Object? id,
    McpJsonMap params = const <String, Object?>{},
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      method,
      id: id,
      params: params,
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: protocolVersion,
      headers: _headersWithConnectanumMethodParameterHeaders(
        method,
        params,
        headers,
      ),
    );
    return _jsonRpcResultFrom(response, method: method);
  }

  /// Calls a Connectanum JSON method through the direct API.
  Future<McpJsonMap> callConnectanumMethodDirect(
    String method, {
    Object? id,
    McpJsonMap params = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await requestDirect(
      method,
      id: id,
      params: params,
      protocolVersion: protocolVersion,
      headers: _headersWithConnectanumMethodParameterHeaders(
        method,
        params,
        headers,
      ),
    );
    return _jsonRpcResultFrom(response, method: method);
  }

  /// Sends a Connectanum JSON tool notification through the direct API.
  Future<void> notifyConnectanumToolDirect(
    String name, {
    McpJsonMap arguments = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    final toolName = _validatedMcpToolName(name, 'name');
    return notificationDirect(
      'connectanum.tool.call',
      params: <String, Object?>{'name': toolName, 'arguments': arguments},
      protocolVersion: protocolVersion,
      headers: _headersWithToolParameterHeaders(toolName, arguments, headers),
    );
  }

  /// Sends a Connectanum JSON method notification through the MCP session.
  Future<void> notifyConnectanumMethod(
    String method, {
    McpJsonMap params = const <String, Object?>{},
    bool streamable = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return notification(
      method,
      params: params,
      streamable: streamable,
      protocolVersion: protocolVersion,
      headers: _headersWithConnectanumMethodParameterHeaders(
        method,
        params,
        headers,
      ),
    );
  }

  /// Sends a Connectanum JSON method notification through the direct API.
  Future<void> notifyConnectanumMethodDirect(
    String method, {
    McpJsonMap params = const <String, Object?>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return notificationDirect(
      method,
      params: params,
      protocolVersion: protocolVersion,
      headers: _headersWithConnectanumMethodParameterHeaders(
        method,
        params,
        headers,
      ),
    );
  }

  /// Lists one page of resources through the active MCP session.
  Future<McpStreamableResourceListPage> listResources({
    Object? id,
    String? cursor,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'resources/list',
      id: id,
      params: _cursorParams(cursor),
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: 'resources/list');
    return McpStreamableResourceListPage(
      resources: _validatedResourceCatalogEntries(
        _jsonMapListFrom(
          result,
          key: 'resources',
          method: 'resources/list',
          label: 'resources/list result resource',
        ),
        label: 'resources/list result resource',
      ),
      nextCursor: _nextCursorFrom(result, method: 'resources/list'),
    );
  }

  /// Reads a resource through the active MCP session.
  Future<List<McpJsonMap>> readResource(
    String uri, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final resourceUri = _validatedMcpResourceUri(uri, 'uri');
    final response = await request(
      'resources/read',
      id: id,
      params: <String, Object?>{'uri': resourceUri},
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: 'resources/read');
    return _validatedResourceReadContents(
      _jsonMapListFrom(
        result,
        key: 'contents',
        method: 'resources/read',
        label: 'resources/read result content',
      ),
      label: 'resources/read result content',
    );
  }

  /// Subscribes the active MCP session to resource updates.
  Future<void> subscribeResource(
    String uri, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final resourceUri = _validatedMcpResourceUri(uri, 'uri');
    final response = await request(
      'resources/subscribe',
      id: id,
      params: <String, Object?>{'uri': resourceUri},
      protocolVersion: protocolVersion,
      headers: headers,
    );
    _jsonRpcResultFrom(response, method: 'resources/subscribe');
  }

  /// Unsubscribes the active MCP session from resource updates.
  Future<void> unsubscribeResource(
    String uri, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final resourceUri = _validatedMcpResourceUri(uri, 'uri');
    final response = await request(
      'resources/unsubscribe',
      id: id,
      params: <String, Object?>{'uri': resourceUri},
      protocolVersion: protocolVersion,
      headers: headers,
    );
    _jsonRpcResultFrom(response, method: 'resources/unsubscribe');
  }

  /// Lists one page of resource templates through the MCP session.
  Future<McpStreamableResourceTemplateListPage> listResourceTemplates({
    Object? id,
    String? cursor,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'resources/templates/list',
      id: id,
      params: _cursorParams(cursor),
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(
      response,
      method: 'resources/templates/list',
    );
    return McpStreamableResourceTemplateListPage(
      resourceTemplates: _validatedResourceTemplateCatalogEntries(
        _jsonMapListFrom(
          result,
          key: 'resourceTemplates',
          method: 'resources/templates/list',
          label: 'resources/templates/list result resource template',
        ),
        label: 'resources/templates/list result resource template',
      ),
      nextCursor: _nextCursorFrom(result, method: 'resources/templates/list'),
    );
  }

  /// Lists one page of prompts through the active MCP session.
  Future<McpStreamablePromptListPage> listPrompts({
    Object? id,
    String? cursor,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'prompts/list',
      id: id,
      params: _cursorParams(cursor),
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    final result = _jsonRpcResultFrom(response, method: 'prompts/list');
    return McpStreamablePromptListPage(
      prompts: _validatedPromptCatalogEntries(
        _jsonMapListFrom(
          result,
          key: 'prompts',
          method: 'prompts/list',
          label: 'prompts/list result prompt',
        ),
        label: 'prompts/list result prompt',
      ),
      nextCursor: _nextCursorFrom(result, method: 'prompts/list'),
    );
  }

  /// Resolves a prompt through the active MCP session.
  Future<McpJsonMap> getPrompt(
    String name, {
    Object? id,
    Map<String, String> arguments = const <String, String>{},
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final promptName = _validatedMcpPromptName(name, 'name');
    final response = await request(
      'prompts/get',
      id: id,
      params: <String, Object?>{'name': promptName, 'arguments': arguments},
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return _validatedPromptGetResult(
      _jsonRpcResultFrom(response, method: 'prompts/get'),
      label: 'prompts/get result',
    );
  }

  /// Lists one page of resources through the direct JSON API.
  Future<McpStreamableResourceListPage> listResourcesDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listResources(
      id: id,
      cursor: cursor,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Reads a resource through the direct JSON API.
  Future<List<McpJsonMap>> readResourceDirect(
    String uri, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return readResource(
      uri,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Lists one page of resource templates through the direct JSON API.
  Future<McpStreamableResourceTemplateListPage> listResourceTemplatesDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listResourceTemplates(
      id: id,
      cursor: cursor,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Lists one page of prompts through the direct JSON API.
  Future<McpStreamablePromptListPage> listPromptsDirect({
    Object? id,
    String? cursor,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return listPrompts(
      id: id,
      cursor: cursor,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Resolves a prompt through the direct JSON API.
  Future<McpJsonMap> getPromptDirect(
    String name, {
    Object? id,
    Map<String, String> arguments = const <String, String>{},
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return getPrompt(
      name,
      id: id,
      arguments: arguments,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Requests typed suggestions for a prompt or resource-template argument.
  Future<McpCompletionResult> complete(
    McpCompletionRequest completionRequest, {
    Object? id,
    bool streamable = true,
    bool directJson = false,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await request(
      'completion/complete',
      id: id,
      params: completionRequest.toJson(),
      streamable: directJson ? false : streamable,
      includeSession: !directJson,
      protocolVersion: protocolVersion,
      headers: headers,
    );
    return McpCompletionResult.fromJson(
      _jsonRpcResultFrom(response, method: 'completion/complete'),
    );
  }

  /// Requests completion without reading or mutating Streamable session state.
  Future<McpCompletionResult> completeDirect(
    McpCompletionRequest completionRequest, {
    Object? id,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return complete(
      completionRequest,
      id: id,
      directJson: true,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Sends an arbitrary JSON-RPC notification through the MCP session.
  Future<void> notification(
    String method, {
    McpJsonMap? params,
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    await post(
      <String, Object?>{'jsonrpc': '2.0', 'method': method, 'params': ?params},
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Sends an arbitrary JSON-RPC notification through the direct API.
  Future<void> notificationDirect(
    String method, {
    McpJsonMap? params,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return notification(
      method,
      params: params,
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Posts one JSON-RPC message through the active MCP session.
  Future<McpJsonMap?> post(
    McpJsonMap message, {
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    _validateJsonRpcRequestId(message, label: 'request');
    final effectiveProtocolVersion = _validatedMcpProtocolVersion(
      protocolVersion ?? this.protocolVersion,
      'protocolVersion',
    );
    final preparedMessage = _prepareMessageForProtocol(
      message,
      effectiveProtocolVersion,
    );
    final response = await _postPayload(
      preparedMessage,
      streamable: streamable,
      includeSession:
          includeSession && effectiveProtocolVersion != latestProtocolVersion,
      protocolVersion: effectiveProtocolVersion,
      extraHeaders: headers,
    );
    if (response == null) {
      return null;
    }
    return _jsonMapFrom(response, label: 'JSON-RPC response');
  }

  /// Posts one JSON-RPC message through the direct JSON API.
  Future<McpJsonMap?> postDirect(
    McpJsonMap message, {
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return post(
      message,
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  /// Posts a JSON-RPC batch through the active MCP session.
  Future<List<McpJsonMap>?> postBatch(
    List<McpJsonMap> messages, {
    bool streamable = true,
    bool includeSession = true,
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) async {
    _validateJsonRpcBatchRequestIds(messages);
    final effectiveProtocolVersion = _validatedMcpProtocolVersion(
      protocolVersion ?? this.protocolVersion,
      'protocolVersion',
    );
    if (effectiveProtocolVersion == latestProtocolVersion) {
      throw const McpStreamableProtocolException(
        'MCP 2026 HTTP does not support JSON-RPC batches',
      );
    }
    final response = await _postPayload(
      messages,
      streamable: streamable,
      includeSession: includeSession,
      protocolVersion: effectiveProtocolVersion,
      extraHeaders: headers,
    );
    if (response == null) {
      return null;
    }
    if (response is! List) {
      throw FormatException('JSON-RPC batch response must be an array');
    }
    return [
      for (final item in response)
        _jsonMapFrom(item, label: 'JSON-RPC batch response item'),
    ];
  }

  /// Posts a JSON-RPC batch through the direct JSON API.
  Future<List<McpJsonMap>?> postBatchDirect(
    List<McpJsonMap> messages, {
    String? protocolVersion,
    Map<String, String> headers = const <String, String>{},
  }) {
    return postBatch(
      messages,
      streamable: false,
      includeSession: false,
      protocolVersion: protocolVersion,
      headers: headers,
    );
  }

  McpJsonMap _prepareMessageForProtocol(
    McpJsonMap message,
    String protocolVersion,
  ) {
    if (protocolVersion != latestProtocolVersion) {
      return message;
    }
    if (message['method'] == 'initialize') {
      throw const McpStreamableProtocolException(
        'MCP 2026 uses server/discover instead of initialize',
      );
    }
    final rawParams = message['params'];
    final params = rawParams == null
        ? <String, Object?>{}
        : _jsonMapFrom(rawParams, label: 'MCP 2026 request params');
    final rawMetadata = params['_meta'];
    final metadata = rawMetadata == null
        ? <String, Object?>{}
        : _jsonMapFrom(rawMetadata, label: 'MCP 2026 request metadata');
    final rawRequestCapabilities =
        metadata['io.modelcontextprotocol/clientCapabilities'];
    final requestCapabilities = rawRequestCapabilities == null
        ? null
        : _jsonMapFrom(
            rawRequestCapabilities,
            label: 'MCP 2026 request client capabilities',
          );
    final info = clientInfo;
    return <String, Object?>{
      ...message,
      'params': <String, Object?>{
        ...params,
        '_meta': <String, Object?>{
          ...metadata,
          'io.modelcontextprotocol/protocolVersion': protocolVersion,
          if (info != null)
            'io.modelcontextprotocol/clientInfo': <String, Object?>{...info},
          'io.modelcontextprotocol/clientCapabilities': <String, Object?>{
            ...clientCapabilities,
            ...?requestCapabilities,
          },
        },
      },
    };
  }

  Future<Object?> _postPayload(
    Object? message, {
    bool streamable = true,
    bool includeSession = true,
    required String protocolVersion,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    return _runTrackedHttpOperation<Object?>((operation) async {
      final requestBody = _encodeBoundedMcpHttpRequest(
        message,
        maxRequestBytes,
      );
      final requestSessionState = _sessionStateSnapshot;
      final requestAuthorizationState = _authorizationStateSnapshot;
      final requestResumeState = _resumeStateSnapshot;
      final request = await _openTrackedHttpRequest(
        () => _httpClient.postUrl(endpoint),
        operation,
        requestAuthorizationState,
      );
      final acceptsSse = streamable || protocolVersion == latestProtocolVersion;
      _applyHeaders(
        request,
        accept: acceptsSse ? _acceptStreamableHttp : _acceptJson,
        includeSession: includeSession,
        protocolVersion: protocolVersion,
        sessionState: requestSessionState,
        authorizationState: requestAuthorizationState,
        extraHeaders: extraHeaders,
      );
      _applyStandardRequestHeaders(request, message);
      request.headers.contentType = ContentType.json;
      request.contentLength = requestBody.length;
      request.add(requestBody);

      final requestMethod = _requestMethodForStandardHeaders(message);
      final validatesResponseHeaders = streamable || includeSession;
      final affectsSessionState =
          includeSession || (streamable && requestMethod == 'initialize');
      final clearsSessionOnMissing = requestMethod == 'initialize';
      final resetsLastEventId = requestMethod == 'initialize';
      final response = await _sendTrackedHttpRequest(request, operation);
      final body = await _readTrackedHttpResponseBody(
        request,
        response,
        operation,
      );
      if (affectsSessionState) {
        _throwIfHttpErrorForSession(
          response,
          body,
          expectedSessionToken: requestSessionState.token,
          expectedAuthorizationToken: requestAuthorizationState.token,
        );
      } else {
        _throwIfHttpError(response, body);
      }

      if (response.statusCode == HttpStatus.accepted ||
          response.statusCode == HttpStatus.noContent ||
          body.isEmpty) {
        _validatePostResponseShape(
          message,
          null,
          protocolVersion: protocolVersion,
        );
        if (validatesResponseHeaders) {
          _capturePostResponseSessionState(
            response,
            requestMethod: requestMethod,
            responseValue: null,
            requestProtocolVersion: protocolVersion,
            requestIncludesSession: includeSession,
            requestSessionState: requestSessionState,
            requestAuthorizationState: requestAuthorizationState,
            clearSessionOnMissing: clearsSessionOnMissing,
            resetLastEventId: resetsLastEventId,
          );
        }
        return null;
      }

      if (_isSse(response)) {
        final events = parseMcpSseEvents(body);
        final value = _jsonRpcResponseValueFromSseEvents(message, events);
        _validatePostResponseShape(
          message,
          value,
          responseBodyReturned: body.isNotEmpty,
          protocolVersion: protocolVersion,
        );
        _validateMcpSseEventIds(events);
        if (validatesResponseHeaders) {
          final capturedSessionState = _capturePostResponseSessionState(
            response,
            requestMethod: requestMethod,
            responseValue: value,
            requestProtocolVersion: protocolVersion,
            requestIncludesSession: includeSession,
            requestSessionState: requestSessionState,
            requestAuthorizationState: requestAuthorizationState,
            clearSessionOnMissing: clearsSessionOnMissing,
            resetLastEventId: resetsLastEventId,
          );
          if (capturedSessionState) {
            _captureLastEventId(
              events,
              expectedResumeToken: requestResumeState.token,
            );
          }
        }
        return value;
      }

      if (!_isJson(response)) {
        throw FormatException(
          'Expected $_acceptJson response, got ${response.headers.contentType?.mimeType ?? 'unknown'}',
        );
      }

      final value = _jsonValueFromBody(body);
      _validatePostResponseShape(
        message,
        value,
        responseBodyReturned: true,
        protocolVersion: protocolVersion,
      );
      if (validatesResponseHeaders) {
        _capturePostResponseSessionState(
          response,
          requestMethod: requestMethod,
          responseValue: value,
          requestProtocolVersion: protocolVersion,
          requestIncludesSession: includeSession,
          requestSessionState: requestSessionState,
          requestAuthorizationState: requestAuthorizationState,
          clearSessionOnMissing: clearsSessionOnMissing,
          resetLastEventId: resetsLastEventId,
        );
      }
      return value;
    });
  }

  void _validateResultTypeForProtocol(
    McpJsonMap response,
    String? protocolVersion,
  ) {
    if (protocolVersion != latestProtocolVersion || response['error'] != null) {
      return;
    }
    final result = response['result'];
    final resultType = result is Map ? result['resultType'] : null;
    if (resultType != null &&
        resultType != 'complete' &&
        resultType != 'input_required') {
      throw FormatException(
        'MCP 2026 resultType must be complete or input_required, got '
        '$resultType',
      );
    }
  }

  void _validatePostResponseShape(
    Object? requestPayload,
    Object? responseValue, {
    bool responseBodyReturned = false,
    String? protocolVersion,
  }) {
    if (requestPayload is Map && requestPayload.containsKey('id')) {
      if (responseValue == null) {
        throw const FormatException('JSON-RPC response was not returned');
      }
      final response = _jsonMapFrom(responseValue, label: 'JSON-RPC response');
      final expectedResponseId = requestPayload['id'];
      final responseId = _validateJsonRpcResponseId(
        response,
        label: 'JSON-RPC response',
      );
      if (responseId != expectedResponseId) {
        throw FormatException(
          'JSON-RPC response contained unexpected response id $responseId',
        );
      }
      _validateJsonRpcResponseObject(response, label: 'JSON-RPC response');
      _validateResultTypeForProtocol(response, protocolVersion);
      return;
    }

    if (requestPayload is Map) {
      if (responseBodyReturned) {
        throw const FormatException(
          'JSON-RPC notification response must not include a body',
        );
      }
      return;
    }

    if (requestPayload is List) {
      final expectedResponseIds = <Object?>[];
      for (final item in requestPayload) {
        if (item is Map && item.containsKey('id')) {
          expectedResponseIds.add(item['id']);
        }
      }
      if (expectedResponseIds.isEmpty) {
        if (responseBodyReturned) {
          throw const FormatException(
            'JSON-RPC notification-only batch response must not include a body',
          );
        }
        return;
      }
      if (responseValue == null) {
        throw const FormatException('JSON-RPC batch response was not returned');
      }
      if (responseValue is! List) {
        throw const FormatException('JSON-RPC batch response must be an array');
      }
      final responseIds = <Object?>[];
      for (final item in responseValue) {
        final response = _jsonMapFrom(
          item,
          label: 'JSON-RPC batch response item',
        );
        final responseId = _validateJsonRpcResponseId(
          response,
          label: 'JSON-RPC batch response item',
        );
        if (!expectedResponseIds.contains(responseId)) {
          throw FormatException(
            'JSON-RPC batch response contained unexpected response id '
            '$responseId',
          );
        }
        if (responseIds.contains(responseId)) {
          throw FormatException(
            'JSON-RPC batch response contained duplicate response for id '
            '$responseId',
          );
        }
        _validateJsonRpcResponseObject(
          response,
          label: 'JSON-RPC batch response item',
        );
        _validateResultTypeForProtocol(response, protocolVersion);
        responseIds.add(responseId);
      }
      for (final id in expectedResponseIds) {
        if (!responseIds.contains(id)) {
          throw FormatException(
            'JSON-RPC batch response missing response for id $id',
          );
        }
      }
    }
  }

  /// Polls pending Streamable HTTP events for the active session.
  Future<List<McpSseEvent>> poll({
    String? lastEventId,
    Map<String, String> headers = const <String, String>{},
  }) async {
    if (protocolVersion == latestProtocolVersion) {
      throw const McpStreamableProtocolException(
        'MCP 2026 HTTP does not support GET polling',
      );
    }
    return _runTrackedHttpOperation<List<McpSseEvent>>((operation) async {
      final requestSessionState = _sessionStateSnapshot;
      final requestAuthorizationState = _authorizationStateSnapshot;
      final requestResumeState = _resumeStateSnapshot;
      final requestProtocolVersion = protocolVersion;
      final requestLastEventId = lastEventId ?? requestResumeState.lastEventId;
      final request = await _openTrackedHttpRequest(
        () => _httpClient.getUrl(endpoint),
        operation,
        requestAuthorizationState,
      );
      _applyHeaders(
        request,
        accept: _acceptSse,
        lastEventId: requestLastEventId,
        protocolVersion: requestProtocolVersion,
        sessionState: requestSessionState,
        authorizationState: requestAuthorizationState,
        extraHeaders: headers,
      );

      final response = await _sendTrackedHttpRequest(request, operation);
      final body = await _readTrackedHttpResponseBody(
        request,
        response,
        operation,
      );
      _throwIfHttpErrorForSession(
        response,
        body,
        expectedSessionToken: requestSessionState.token,
        expectedAuthorizationToken: requestAuthorizationState.token,
      );

      if (!_isSse(response)) {
        throw FormatException(
          'Expected $_acceptSse response, got ${response.headers.contentType?.mimeType ?? 'unknown'}',
        );
      }

      final events = parseMcpSseEvents(body);
      for (final event in events) {
        final value = event.jsonValue;
        if (value != null) {
          _validateJsonRpcSseMessageValue(value);
        }
      }
      _validateMcpSseEventIds(events);
      final ownsSessionState = identical(
        _sessionStateToken,
        requestSessionState.token,
      );
      _captureSessionHeaders(
        response,
        captureSessionState: ownsSessionState,
        expectedSessionState: requestSessionState,
        expectedProtocolVersion: requestProtocolVersion,
      );
      if (ownsSessionState) {
        _captureLastEventId(
          events,
          expectedResumeToken: requestResumeState.token,
        );
      }
      return events;
    });
  }

  /// Terminates the active server-side MCP session and clears local state.
  Future<void> deleteSession({
    Map<String, String> headers = const <String, String>{},
  }) async {
    if (protocolVersion == latestProtocolVersion) {
      throw const McpStreamableProtocolException(
        'MCP 2026 HTTP does not support DELETE session requests',
      );
    }
    final requestSessionState = _sessionStateSnapshot;
    final requestAuthorizationState = _authorizationStateSnapshot;
    final activeSessionId = requestSessionState.sessionId;
    if (activeSessionId == null) {
      _clearSessionState();
      return;
    }
    return _runTrackedHttpOperation<void>((operation) async {
      final activeProtocolVersion = protocolVersion;
      final request = await _openTrackedHttpRequest(
        () => _httpClient.deleteUrl(endpoint),
        operation,
        requestAuthorizationState,
      );
      _applyHeaders(
        request,
        accept: _acceptJson,
        protocolVersion: activeProtocolVersion,
        sessionState: requestSessionState,
        authorizationState: requestAuthorizationState,
        extraHeaders: headers,
      );

      final response = await _sendTrackedHttpRequest(request, operation);
      final body = await _readTrackedHttpResponseBody(
        request,
        response,
        operation,
      );
      _throwIfHttpErrorForSession(
        response,
        body,
        expectedSessionToken: requestSessionState.token,
        expectedAuthorizationToken: requestAuthorizationState.token,
      );
      _captureSessionHeaders(
        response,
        captureSessionState: false,
        expectedSessionState: requestSessionState,
        expectedProtocolVersion: activeProtocolVersion,
      );
      if (identical(_sessionStateToken, requestSessionState.token)) {
        _clearSessionState();
      }
    });
  }

  Future<T> _runTrackedOAuthHttpOperation<T>(
    Future<T> Function(void Function(HttpClientRequest request) onRequestOpened)
    operation,
  ) {
    _throwIfClosed();
    final requestStateToken = _httpRequestStateToken;
    final pendingOperation = _McpPendingOAuthHttpOperation();
    final operationRequests = <HttpClientRequest>{};
    _pendingOAuthHttpOperations.add(pendingOperation);

    void onRequestOpened(HttpClientRequest request) {
      if (!identical(_httpRequestStateToken, requestStateToken)) {
        request.abort(
          StateError('MCP client closed while opening an OAuth HTTP request'),
        );
        return;
      }
      operationRequests.add(request);
      _pendingHttpRequests.add(request);
    }

    final operationFuture = Future<T>.sync(() => operation(onRequestOpened));

    void removeOperationRequests() {
      for (final request in operationRequests) {
        _pendingHttpRequests.remove(request);
      }
    }

    unawaited(
      operationFuture.then<void>(
        (_) => removeOperationRequests(),
        onError: (Object _, StackTrace _) => removeOperationRequests(),
      ),
    );

    return Future.any<T>(<Future<T>>[
      operationFuture,
      pendingOperation.cancellation<T>(),
    ]).whenComplete(() {
      _pendingOAuthHttpOperations.remove(pendingOperation);
    });
  }

  Future<T> _runTrackedHttpOperation<T>(
    Future<T> Function(_McpHttpOperationContext operation) work, {
    void Function()? onAbort,
    bool trackForClose = true,
  }) {
    _throwIfClosed();
    final pending = _McpPendingHttpOperationHandle<T>();
    final operation = _McpHttpOperationContext(onAbort: onAbort);
    final timeoutError = TimeoutException(
      'MCP HTTP operation exceeded ${requestTimeout.inMilliseconds} ms.',
      requestTimeout,
    );
    if (trackForClose) {
      _pendingHttpOperations.add(pending);
    }

    late final Timer timer;
    void finishPending() {
      timer.cancel();
      _pendingHttpOperations.remove(pending);
    }

    timer = Timer(requestTimeout, () {
      operation.terminalError = timeoutError;
      final stackTrace = StackTrace.current;
      pending.reject(timeoutError, stackTrace);
      try {
        operation.onAbort?.call();
      } catch (_) {
        // Timeout remains authoritative even if local transport cleanup fails.
      }
      for (final body in operation.responseBodies.toList(growable: false)) {
        _pendingHttpResponseBodies.remove(body);
        body.abort(timeoutError);
      }
      for (final request in operation.requests.toList(growable: false)) {
        _pendingHttpRequests.remove(request);
        request.abort(timeoutError, stackTrace);
      }
    });

    unawaited(
      pending.future.then<void>(
        (_) => finishPending(),
        onError: (Object _, StackTrace _) => finishPending(),
      ),
    );
    unawaited(
      Future<T>.sync(() => work(operation))
          .then<void>(
            pending.complete,
            onError: (Object error, StackTrace stackTrace) {
              pending.completeError(error, stackTrace);
            },
          )
          .whenComplete(() {
            for (final body in operation.responseBodies) {
              _pendingHttpResponseBodies.remove(body);
            }
            for (final request in operation.requests) {
              _pendingHttpRequests.remove(request);
            }
          }),
    );
    return pending.future;
  }

  void _throwIfAuthorizationExpired(
    _McpAuthorizationStateSnapshot authorizationState,
  ) {
    final expiresAt = authorizationState.expiresAt;
    if (expiresAt == null || DateTime.now().toUtc().isBefore(expiresAt)) {
      return;
    }
    throw McpAuthorizationExpiredException(expiresAt);
  }

  Future<HttpClientRequest> _openTrackedHttpRequest(
    Future<HttpClientRequest> Function() open,
    _McpHttpOperationContext operation,
    _McpAuthorizationStateSnapshot authorizationState, {
    bool enforceClientState = true,
  }) async {
    _throwIfClosed();
    final terminalError = operation.terminalError;
    if (terminalError != null) {
      throw terminalError;
    }
    _throwIfAuthorizationExpired(authorizationState);
    final requestStateToken = _httpRequestStateToken;
    final request = await open();
    final lateTerminalError = operation.terminalError;
    if ((enforceClientState &&
            !identical(_httpRequestStateToken, requestStateToken)) ||
        lateTerminalError != null) {
      final error =
          lateTerminalError ??
          StateError('MCP client closed while opening an HTTP request');
      request.abort(error, StackTrace.current);
      throw error;
    }
    try {
      request.followRedirects = false;
    } catch (error, stackTrace) {
      request.abort(error, stackTrace);
      rethrow;
    }
    operation.requests.add(request);
    _pendingHttpRequests.add(request);
    return request;
  }

  Future<HttpClientResponse> _sendTrackedHttpRequest(
    HttpClientRequest request,
    _McpHttpOperationContext operation,
  ) async {
    try {
      return await request.close();
    } catch (_) {
      operation.requests.remove(request);
      _pendingHttpRequests.remove(request);
      rethrow;
    }
  }

  Future<String> _readTrackedHttpResponseBody(
    HttpClientRequest request,
    HttpClientResponse response,
    _McpHttpOperationContext operation,
  ) async {
    late final _McpPendingHttpResponseBody pendingBody;
    try {
      pendingBody = _McpPendingHttpResponseBody(response, maxResponseBytes);
    } catch (_) {
      operation.requests.remove(request);
      _pendingHttpRequests.remove(request);
      rethrow;
    }
    operation.responseBodies.add(pendingBody);
    _pendingHttpResponseBodies.add(pendingBody);
    final terminalError = operation.terminalError;
    if (terminalError != null) {
      pendingBody.abort(terminalError);
    } else if (!_pendingHttpRequests.contains(request)) {
      pendingBody.abort(
        StateError(
          'MCP client closed before an HTTP response body could be read',
        ),
      );
    }
    try {
      return await pendingBody.future;
    } finally {
      operation.responseBodies.remove(pendingBody);
      operation.requests.remove(request);
      _pendingHttpResponseBodies.remove(pendingBody);
      _pendingHttpRequests.remove(request);
    }
  }

  void _throwIfClosed() {
    if (_closed) {
      throw StateError('MCP client is closed.');
    }
  }

  /// Permanently closes this MCP client and rejects subsequent network work.
  ///
  /// A caller-owned HTTP transport is left open so a replacement MCP client
  /// can reuse it.
  void close({bool force = false}) {
    _closed = true;
    _clearSessionState();
    _httpRequestStateToken = Object();
    final pendingHttpOperations = _pendingHttpOperations.toList(
      growable: false,
    );
    _pendingHttpOperations.clear();
    final pendingHttpRequests = _pendingHttpRequests.toList(growable: false);
    _pendingHttpRequests.clear();
    final pendingOAuthHttpOperations = _pendingOAuthHttpOperations.toList(
      growable: false,
    );
    _pendingOAuthHttpOperations.clear();
    final pendingHttpResponseBodies = _pendingHttpResponseBodies.toList(
      growable: false,
    );
    _pendingHttpResponseBodies.clear();
    final closeError = StateError(
      'MCP client closed while an HTTP request was pending',
    );
    final oauthCloseError = StateError(
      'MCP client closed while an OAuth HTTP request was pending',
    );
    final closeStackTrace = StackTrace.current;
    for (final pendingOperation in pendingHttpOperations) {
      pendingOperation.reject(closeError, closeStackTrace);
    }
    for (final pendingOperation in pendingOAuthHttpOperations) {
      pendingOperation.abort(oauthCloseError);
    }
    for (final responseBody in pendingHttpResponseBodies) {
      responseBody.abort(closeError);
    }
    for (final request in pendingHttpRequests) {
      request.abort(closeError);
    }

    _subscriptionStateToken = Object();
    final pendingSubscriptionHttpClients = _pendingSubscriptionHttpClients
        .toList(growable: false);
    _pendingSubscriptionHttpClients.clear();
    for (final httpClient in pendingSubscriptionHttpClients) {
      httpClient.close(force: true);
    }
    for (final subscription in _subscriptions.toList(growable: false)) {
      unawaited(subscription.close());
    }
    if (_ownsHttpClient) {
      _httpClient.close(force: force);
    }
  }

  void _applyStandardRequestHeaders(
    HttpClientRequest request,
    Object? message,
  ) {
    final method = _requestMethodForStandardHeaders(message);
    if (method == null) {
      return;
    }
    request.headers.set(_headerMethod, method);
    final name = _requestNameForStandardHeaders(message, method);
    if (name != null) {
      request.headers.set(_headerName, name);
    }
  }

  void _applyHeaders(
    HttpClientRequest request, {
    required String accept,
    String? lastEventId,
    bool includeSession = true,
    String? protocolVersion,
    _McpSessionStateSnapshot? sessionState,
    _McpAuthorizationStateSnapshot? authorizationState,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    final effectiveProtocolVersion = _validatedMcpProtocolVersion(
      protocolVersion ?? this.protocolVersion,
      'protocolVersion',
    );
    request.headers.set(HttpHeaders.acceptHeader, accept);
    request.headers.set(_headerProtocolVersion, effectiveProtocolVersion);
    void applyConsumerHeaders(Map<String, String> source) {
      for (final entry in source.entries) {
        if (_isControlledMcpRequestHeader(entry.key)) {
          continue;
        }
        request.headers.set(entry.key, entry.value);
      }
    }

    applyConsumerHeaders(headers);
    applyConsumerHeaders(extraHeaders);
    final authorizationHeader = authorizationState == null
        ? _authorizationHeader
        : authorizationState.headerValue;
    if (authorizationHeader != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorizationHeader);
    }
    final session = includeSession
        ? sessionState == null
              ? sessionId
              : sessionState.sessionId
        : null;
    if (session != null) {
      if (!_mcpSessionIdHeaderValueValid(session)) {
        throw const FormatException(
          'MCP-Session-Id header value contains invalid characters',
        );
      }
      request.headers.set(_headerSessionId, session);
    }
    if (lastEventId != null) {
      if (!_mcpLastEventIdHeaderValueValid(lastEventId)) {
        throw const FormatException(
          'Last-Event-ID header value contains invalid characters',
        );
      }
      request.headers.set(_headerLastEventId, lastEventId);
    }
  }

  String _validatedInitializeProtocolVersion(Object? responseValue) {
    if (responseValue is! Map || responseValue['result'] is! Map) {
      throw const FormatException('initialize result must be a JSON object');
    }
    final result = responseValue['result'] as Map;
    final negotiatedProtocolVersion = result['protocolVersion'];
    if (negotiatedProtocolVersion is! String ||
        negotiatedProtocolVersion.isEmpty) {
      throw const FormatException(
        'initialize result protocolVersion must be a non-empty string',
      );
    }
    if (!_mcpProtocolVersionSupported(negotiatedProtocolVersion)) {
      throw McpStreamableProtocolException(
        'Unsupported initialize protocolVersion: $negotiatedProtocolVersion',
      );
    }
    return negotiatedProtocolVersion;
  }

  void _captureSessionHeaders(
    HttpClientResponse response, {
    bool allowSessionAssignment = false,
    bool captureSessionState = true,
    bool forbidSessionId = false,
    _McpSessionStateSnapshot? expectedSessionState,
    String? expectedProtocolVersion,
    String protocolVersionExpectation = 'active protocol version',
    bool clearSessionOnMissing = false,
    bool resetLastEventId = false,
  }) {
    final negotiatedSessionId = response.headers.value(_headerSessionId);
    if (negotiatedSessionId != null &&
        !_mcpSessionIdHeaderValueValid(negotiatedSessionId)) {
      throw const McpStreamableProtocolException(
        'Invalid MCP-Session-Id response header',
      );
    }

    final responseProtocolVersion = response.headers.value(
      _headerProtocolVersion,
    );
    if (responseProtocolVersion != null &&
        !_mcpProtocolVersionSupported(responseProtocolVersion)) {
      throw McpStreamableProtocolException(
        'Unsupported MCP-Protocol-Version response header: '
        '$responseProtocolVersion',
      );
    }
    if (responseProtocolVersion != null &&
        expectedProtocolVersion != null &&
        responseProtocolVersion != expectedProtocolVersion) {
      throw McpStreamableProtocolException(
        'MCP-Protocol-Version response header did not match the '
        '$protocolVersionExpectation '
        '(expected $expectedProtocolVersion, got $responseProtocolVersion)',
      );
    }
    if (forbidSessionId && negotiatedSessionId != null) {
      throw const McpStreamableProtocolException(
        'MCP stateless response must not create a session',
      );
    }
    if (negotiatedSessionId != null && !allowSessionAssignment) {
      final expectedSessionId = expectedSessionState == null
          ? sessionId
          : expectedSessionState.sessionId;
      if (negotiatedSessionId != expectedSessionId) {
        throw const McpStreamableProtocolException(
          'MCP-Session-Id response header did not match the active session',
        );
      }
    }

    if (!captureSessionState) {
      return;
    }
    if (negotiatedSessionId != null) {
      if (allowSessionAssignment) {
        if (resetLastEventId || sessionId != negotiatedSessionId) {
          lastEventId = null;
        }
        _sessionId = negotiatedSessionId;
      }
    } else if (clearSessionOnMissing) {
      _clearSessionState();
    }
  }

  bool _capturePostResponseSessionState(
    HttpClientResponse response, {
    required String? requestMethod,
    required Object? responseValue,
    required String requestProtocolVersion,
    required bool requestIncludesSession,
    required _McpSessionStateSnapshot requestSessionState,
    required _McpAuthorizationStateSnapshot requestAuthorizationState,
    bool clearSessionOnMissing = false,
    bool resetLastEventId = false,
  }) {
    final ownsRequestSessionState = identical(
      _sessionStateToken,
      requestSessionState.token,
    );
    final ownsRequestAuthorizationState = identical(
      _authorizationStateToken,
      requestAuthorizationState.token,
    );
    final rejectedInitialize =
        requestMethod == 'initialize' &&
        responseValue is Map &&
        responseValue['error'] is Map;
    if (rejectedInitialize) {
      // The JSON-RPC envelope was validated before this helper. Validate its
      // response headers too, but a rejected initialize cannot negotiate any
      // reusable session, protocol-version, or resume state.
      _captureSessionHeaders(
        response,
        allowSessionAssignment: true,
        captureSessionState: false,
      );
      if (ownsRequestSessionState && ownsRequestAuthorizationState) {
        _clearSessionState();
      }
      return false;
    }

    if (requestMethod == 'initialize') {
      final previousProtocolVersion = protocolVersion;
      try {
        final negotiatedProtocolVersion = _validatedInitializeProtocolVersion(
          responseValue,
        );
        if (!ownsRequestSessionState) {
          // An initialize response establishes a new session; stale responses
          // validate their own header shape but never compare with active state.
          _captureSessionHeaders(
            response,
            allowSessionAssignment: true,
            captureSessionState: false,
            expectedProtocolVersion: negotiatedProtocolVersion,
            protocolVersionExpectation: 'initialize result',
          );
          return false;
        }

        _captureSessionHeaders(
          response,
          allowSessionAssignment: true,
          expectedProtocolVersion: negotiatedProtocolVersion,
          protocolVersionExpectation: 'initialize result',
          clearSessionOnMissing: clearSessionOnMissing,
          resetLastEventId: resetLastEventId,
        );
        protocolVersion = negotiatedProtocolVersion;
        _sessionStateToken = Object();
        return true;
      } catch (_) {
        if (ownsRequestSessionState && ownsRequestAuthorizationState) {
          // The previous value was already validated before this request.
          _protocolVersion = previousProtocolVersion;
          _clearSessionState();
        }
        rethrow;
      }
    }

    final statelessRequest =
        !requestIncludesSession ||
        requestProtocolVersion == latestProtocolVersion;
    _captureSessionHeaders(
      response,
      captureSessionState: !statelessRequest && ownsRequestSessionState,
      forbidSessionId: statelessRequest,
      expectedSessionState: requestSessionState,
      expectedProtocolVersion: requestProtocolVersion,
      protocolVersionExpectation: requestProtocolVersion == protocolVersion
          ? 'active protocol version'
          : 'request protocol version override',
      clearSessionOnMissing: clearSessionOnMissing,
      resetLastEventId: resetLastEventId,
    );
    return !statelessRequest && ownsRequestSessionState;
  }

  void _throwIfHttpErrorForSession(
    HttpClientResponse response,
    String body, {
    Object? expectedSessionToken,
    Object? expectedAuthorizationToken,
  }) {
    try {
      _throwIfHttpError(response, body);
    } on McpStreamableHttpException catch (error) {
      // A 403, including insufficient_scope, does not terminate the session.
      final ownsSessionState =
          expectedSessionToken == null ||
          identical(expectedSessionToken, _sessionStateToken);
      final ownsAuthorizationState =
          expectedAuthorizationToken == null ||
          identical(expectedAuthorizationToken, _authorizationStateToken);
      final terminatesCurrentSession =
          error.statusCode == HttpStatus.notFound ||
          (error.statusCode == HttpStatus.unauthorized &&
              ownsAuthorizationState);
      if (terminatesCurrentSession && ownsSessionState) {
        _clearSessionState();
      }
      rethrow;
    }
  }

  void _clearSessionState() {
    _sessionId = null;
    lastEventId = null;
    _sessionStateToken = Object();
  }

  Object? _jsonRpcResponseValueFromSseEvents(
    Object? requestPayload,
    List<McpSseEvent> events,
  ) {
    final values = <Object?>[];
    for (final event in events) {
      final value = event.jsonValue;
      if (value != null) {
        _validateJsonRpcSseMessageValue(value);
        values.add(value);
      }
    }

    if (requestPayload is Map) {
      if (!requestPayload.containsKey('id')) {
        return null;
      }
      final requestId = requestPayload['id'];
      Object? matchingResponse;
      for (final responseValue in _jsonRpcResponseValues(values)) {
        if (!_jsonRpcMessageIsResponse(responseValue)) {
          continue;
        }
        final response = _jsonMapFrom(
          responseValue,
          label: 'JSON-RPC response',
        );
        if (!response.containsKey('id')) {
          throw const FormatException('JSON-RPC response must include an id');
        }
        if (!_jsonRpcResponseIdMatches(response, requestId)) {
          throw FormatException(
            'JSON-RPC response contained unexpected response id '
            '${response['id']}',
          );
        }
        if (matchingResponse != null) {
          throw FormatException(
            'JSON-RPC response contained duplicate response for id $requestId',
          );
        }
        _validateJsonRpcResponseObject(response, label: 'JSON-RPC response');
        matchingResponse = response;
      }
      return matchingResponse;
    }

    if (requestPayload is List) {
      final requestIds = <Object?>[];
      for (final item in requestPayload) {
        if (item is Map && item.containsKey('id')) {
          requestIds.add(item['id']);
        }
      }
      if (requestIds.isEmpty) {
        return null;
      }
      final responses = <Object?>[];
      for (final response in _jsonRpcResponseValues(values)) {
        if (_jsonRpcMessageIsResponse(response)) {
          responses.add(response);
        }
      }
      return responses.isEmpty ? null : responses;
    }

    for (final value in values) {
      return value;
    }
    return null;
  }

  Iterable<Object?> _jsonRpcResponseValues(List<Object?> values) sync* {
    for (final value in values) {
      if (value is List) {
        yield* value;
      } else {
        yield value;
      }
    }
  }

  bool _jsonRpcResponseIdMatches(McpJsonMap response, Object? requestId) {
    final responseId = _validateJsonRpcResponseId(
      response,
      label: 'JSON-RPC response',
    );
    return responseId == requestId;
  }

  void _validateMcpSseEventIds(List<McpSseEvent> events) {
    for (final event in events) {
      final id = event.id;
      if (id != null && !_mcpLastEventIdHeaderValueValid(id)) {
        throw const FormatException(
          'SSE event id cannot be used as Last-Event-ID',
        );
      }
    }
  }

  void _captureLastEventId(
    List<McpSseEvent> events, {
    required Object expectedResumeToken,
  }) {
    if (!identical(_resumeStateToken, expectedResumeToken)) {
      return;
    }
    String? capturedLastEventId;
    var captured = false;
    for (final event in events) {
      final id = event.id;
      if (id != null) {
        capturedLastEventId = id.isEmpty ? null : id;
        captured = true;
      }
    }
    if (captured) {
      _lastEventId = capturedLastEventId;
      _resumeStateToken = Object();
    }
  }

  int _claimToolCatalogRequestGeneration() => ++_toolCatalogRequestGeneration;

  List<McpJsonMap> _rememberToolHeaderParameters(
    List<McpJsonMap> tools, {
    required int requestGeneration,
  }) {
    final visibleTools = <McpJsonMap>[];
    for (final tool in tools) {
      final name = tool['name'];
      if (name is! String) {
        visibleTools.add(tool);
        continue;
      }
      final headerParameters = _mcpToolHeaderParametersFromTool(tool);
      final lastGeneration = _toolHeaderParameterGenerationByName[name];
      final ownsCacheUpdate =
          lastGeneration == null || requestGeneration >= lastGeneration;
      if (ownsCacheUpdate) {
        _toolHeaderParameterGenerationByName[name] = requestGeneration;
        if (headerParameters == null || headerParameters.isEmpty) {
          _toolHeaderParametersByName.remove(name);
        } else {
          _toolHeaderParametersByName[name] = headerParameters;
        }
      }
      if (headerParameters != null) {
        visibleTools.add(tool);
      }
    }
    return List<McpJsonMap>.unmodifiable(visibleTools);
  }

  Map<String, String> _mcpToolParameterHeaders(
    String toolName,
    McpJsonMap arguments,
  ) {
    final parameters = _toolHeaderParametersByName[toolName];
    if (parameters == null || parameters.isEmpty) {
      return const <String, String>{};
    }
    final headers = <String, String>{};
    for (final parameter in parameters) {
      if (!arguments.containsKey(parameter.argumentName)) {
        continue;
      }
      final value = arguments[parameter.argumentName];
      if (value == null) {
        continue;
      }
      headers['$_headerParameterPrefix${parameter.headerName}'] =
          _encodeMcpParameterHeaderValue(
            value,
            argumentName: parameter.argumentName,
          );
    }
    return headers;
  }

  Map<String, String> _headersWithToolParameterHeaders(
    String toolName,
    McpJsonMap arguments,
    Map<String, String> headers,
  ) {
    final parameterHeaders = _mcpToolParameterHeaders(toolName, arguments);
    final filteredHeaders = <String, String>{};
    final parameterPrefix = _headerParameterPrefix.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase().startsWith(parameterPrefix)) {
        continue;
      }
      filteredHeaders[entry.key] = entry.value;
    }
    if (parameterHeaders.isEmpty) {
      return filteredHeaders.length == headers.length
          ? headers
          : filteredHeaders;
    }
    return <String, String>{...filteredHeaders, ...parameterHeaders};
  }

  Map<String, String> _headersWithConnectanumMethodParameterHeaders(
    String method,
    McpJsonMap params,
    Map<String, String> headers,
  ) {
    Object? toolName;
    McpJsonMap? arguments;
    if (method == 'tools/call' ||
        method == 'connectanum.tool.call' ||
        method == 'connectanum.tools.call') {
      toolName = params['name'];
      final rawArguments = params['arguments'];
      arguments = rawArguments == null
          ? const <String, Object?>{}
          : _jsonMapFrom(rawArguments, label: 'direct tool arguments');
    } else if (method.contains('.')) {
      toolName = method;
      arguments = params;
    }
    return toolName is String && arguments != null
        ? _headersWithToolParameterHeaders(toolName, arguments, headers)
        : headers;
  }
}

bool _isControlledMcpRequestHeader(String name) {
  final normalized = name.toLowerCase();
  return normalized == HttpHeaders.acceptHeader ||
      normalized == _headerProtocolVersion.toLowerCase() ||
      normalized == _headerSessionId.toLowerCase() ||
      normalized == _headerLastEventId.toLowerCase() ||
      normalized == _headerMethod.toLowerCase() ||
      normalized == _headerName.toLowerCase();
}

final class _McpToolHeaderParameter {
  const _McpToolHeaderParameter({
    required this.argumentName,
    required this.headerName,
  });

  final String argumentName;
  final String headerName;
}

List<_McpToolHeaderParameter>? _mcpToolHeaderParametersFromTool(
  McpJsonMap tool,
) {
  final inputSchema = tool['inputSchema'];
  if (inputSchema is! Map) {
    return const <_McpToolHeaderParameter>[];
  }
  final properties = inputSchema['properties'];
  if (properties is! Map) {
    return const <_McpToolHeaderParameter>[];
  }
  final headerNames = <String>{};
  final parameters = <_McpToolHeaderParameter>[];
  for (final entry in properties.entries) {
    final argumentName = entry.key;
    final property = entry.value;
    if (argumentName is! String || property is! Map) {
      continue;
    }
    final headerName = property['x-mcp-header'];
    if (headerName == null) {
      continue;
    }
    if (headerName is! String ||
        !_isValidMcpHeaderNameSegment(headerName) ||
        !headerNames.add(headerName.toLowerCase()) ||
        !_mcpHeaderParameterSchemaIsPrimitive(property)) {
      return null;
    }
    parameters.add(
      _McpToolHeaderParameter(
        argumentName: argumentName,
        headerName: headerName,
      ),
    );
  }
  return List<_McpToolHeaderParameter>.unmodifiable(parameters);
}

bool _isValidMcpHeaderNameSegment(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x21 || codeUnit > 0x7E || codeUnit == 0x3A) {
      return false;
    }
  }
  return true;
}

bool _mcpHeaderParameterSchemaIsPrimitive(Map property) {
  final type = property['type'];
  if (type is String) {
    return _isMcpHeaderPrimitiveType(type);
  }
  if (type is Iterable) {
    var sawType = false;
    for (final value in type) {
      if (value is! String) {
        return false;
      }
      if (value == 'null') {
        continue;
      }
      sawType = true;
      if (!_isMcpHeaderPrimitiveType(value)) {
        return false;
      }
    }
    return sawType;
  }
  return false;
}

bool _isMcpHeaderPrimitiveType(String type) {
  return type == 'string' ||
      type == 'number' ||
      type == 'integer' ||
      type == 'boolean';
}

String _encodeMcpParameterHeaderValue(
  Object? value, {
  required String argumentName,
}) {
  final stringValue = switch (value) {
    final String value => value,
    final num value => value.toString(),
    final bool value => value ? 'true' : 'false',
    _ => throw ArgumentError.value(
      value,
      argumentName,
      'MCP header parameters must be strings, numbers, or booleans.',
    ),
  };
  if (!_mcpParameterHeaderValueNeedsBase64(stringValue)) {
    return stringValue;
  }
  return '$_base64HeaderPrefix${base64Encode(utf8.encode(stringValue))}'
      '$_base64HeaderSuffix';
}

bool _mcpParameterHeaderValueNeedsBase64(String value) {
  if (value.startsWith(_base64HeaderPrefix) &&
      value.endsWith(_base64HeaderSuffix)) {
    return true;
  }
  if (value.startsWith(' ') ||
      value.startsWith('\t') ||
      value.endsWith(' ') ||
      value.endsWith('\t')) {
    return true;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit > 0x7E || codeUnit == 0x7F) {
      return true;
    }
  }
  return false;
}

String? _requestMethodForStandardHeaders(Object? message) {
  if (message is! Map) {
    return null;
  }
  final method = message['method'];
  return method is String && method.isNotEmpty ? method : null;
}

String? _requestNameForStandardHeaders(Object? message, String method) {
  if (message is! Map) {
    return null;
  }
  final params = message['params'];
  if (params is! Map) {
    return null;
  }
  final field = switch (method) {
    'tools/call' ||
    'connectanum.tool.call' ||
    'connectanum.tools.call' ||
    'prompts/get' => 'name',
    'resources/read' ||
    'resources/subscribe' ||
    'resources/unsubscribe' => 'uri',
    _ => null,
  };
  if (field == null) {
    return null;
  }
  final value = params[field];
  return value is String && value.isNotEmpty ? value : null;
}

final class McpStreamableToolListPage {
  const McpStreamableToolListPage({required this.tools, this.nextCursor});

  final List<McpJsonMap> tools;
  final String? nextCursor;
}

final class McpStreamableResourceListPage {
  const McpStreamableResourceListPage({
    required this.resources,
    this.nextCursor,
  });

  final List<McpJsonMap> resources;
  final String? nextCursor;
}

final class McpStreamableResourceTemplateListPage {
  const McpStreamableResourceTemplateListPage({
    required this.resourceTemplates,
    this.nextCursor,
  });

  final List<McpJsonMap> resourceTemplates;
  final String? nextCursor;
}

final class McpStreamablePromptListPage {
  const McpStreamablePromptListPage({required this.prompts, this.nextCursor});

  final List<McpJsonMap> prompts;
  final String? nextCursor;
}

final class McpJsonRpcException implements Exception {
  const McpJsonRpcException({
    required this.id,
    required this.method,
    required this.error,
  });

  final Object? id;
  final String method;
  final McpJsonMap error;

  @override
  String toString() {
    final message = error['message'];
    return 'McpJsonRpcException($method, id: $id): $message';
  }
}

final class McpSseEvent {
  const McpSseEvent({this.id, this.event, required this.data, this.retryMs});

  final String? id;
  final String? event;
  final String data;
  final int? retryMs;

  Object? get jsonValue {
    if (data.trim().isEmpty) {
      return null;
    }
    return _jsonValueFromBody(data);
  }

  McpJsonMap? get jsonData {
    final value = jsonValue;
    if (value == null) {
      return null;
    }
    return _jsonMapFrom(value, label: 'SSE event data');
  }
}

final class McpStreamableHttpException implements Exception {
  const McpStreamableHttpException({
    required this.statusCode,
    required this.reasonPhrase,
    required this.body,
    this.error,
    this.responseHeaders = const <String, List<String>>{},
    this.bearerChallenges = const <McpBearerChallenge>[],
  });

  final int statusCode;
  final String reasonPhrase;
  final String body;
  final McpJsonMap? error;
  final Map<String, List<String>> responseHeaders;
  final List<McpBearerChallenge> bearerChallenges;

  @override
  String toString() {
    final detail = error ?? (body.isEmpty ? reasonPhrase : body);
    return 'McpStreamableHttpException($statusCode): $detail';
  }
}

/// Thrown before a new HTTP request uses a locally known-expired grant.
///
/// Refresh the grant and replace it on the client to keep any active
/// Streamable HTTP session and resume cursor. Existing listener streams are not
/// closed merely because the grant used to establish them expires.
final class McpAuthorizationExpiredException implements Exception {
  const McpAuthorizationExpiredException(this.expiresAt);

  final DateTime expiresAt;

  @override
  String toString() =>
      'McpAuthorizationExpiredException: MCP authorization expired at '
      '${expiresAt.toUtc().toIso8601String()}.';
}

/// A redacted failure to derive an OAuth step-up authorization request.
final class McpOAuthStepUpException implements Exception {
  const McpOAuthStepUpException(this.message);

  final String message;

  @override
  String toString() => 'McpOAuthStepUpException: $message';
}

final class McpStreamableProtocolException implements Exception {
  const McpStreamableProtocolException(this.message);

  final String message;

  @override
  String toString() => 'McpStreamableProtocolException: $message';
}

List<McpSseEvent> parseMcpSseEvents(String body) {
  final events = <McpSseEvent>[];
  final dataLines = <String>[];
  String? id;
  String? event;
  int? retryMs;

  void commit() {
    if (id != null ||
        event != null ||
        retryMs != null ||
        dataLines.isNotEmpty) {
      events.add(
        McpSseEvent(
          id: id,
          event: event,
          data: dataLines.join('\n'),
          retryMs: retryMs,
        ),
      );
    }
    id = null;
    event = null;
    retryMs = null;
    dataLines.clear();
  }

  for (final rawLine in const LineSplitter().convert(body)) {
    if (rawLine.isEmpty) {
      commit();
      continue;
    }
    if (rawLine.startsWith(':')) {
      continue;
    }

    final colonIndex = rawLine.indexOf(':');
    final field = colonIndex == -1 ? rawLine : rawLine.substring(0, colonIndex);
    var value = colonIndex == -1 ? '' : rawLine.substring(colonIndex + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }

    switch (field) {
      case 'data':
        dataLines.add(value);
        break;
      case 'id':
        id = value;
        break;
      case 'event':
        event = value;
        break;
      case 'retry':
        retryMs = int.tryParse(value);
        break;
    }
  }
  commit();
  return events;
}

bool _isSse(HttpClientResponse response) {
  return response.headers.contentType?.mimeType == _acceptSse;
}

bool _isJson(HttpClientResponse response) {
  return response.headers.contentType?.mimeType == _acceptJson;
}

McpJsonMap _jsonMapFromBody(String body, String label) {
  return _jsonMapFrom(_jsonValueFromBody(body), label: label);
}

Object? _jsonValueFromBody(String body) {
  return jsonDecode(body);
}

void _throwIfHttpError(HttpClientResponse response, String body) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return;
  }

  McpJsonMap? error;
  if (body.isNotEmpty) {
    try {
      error = _jsonMapFromBody(body, 'HTTP error response');
    } on Object {
      error = null;
    }
  }
  final responseHeaders = <String, List<String>>{};
  response.headers.forEach((name, values) {
    responseHeaders[name.toLowerCase()] = List<String>.unmodifiable(values);
  });
  final immutableHeaders = Map<String, List<String>>.unmodifiable(
    responseHeaders,
  );
  throw McpStreamableHttpException(
    statusCode: response.statusCode,
    reasonPhrase: response.reasonPhrase,
    body: body,
    error: error,
    responseHeaders: immutableHeaders,
    bearerChallenges: parseMcpBearerChallenges(
      immutableHeaders[HttpHeaders.wwwAuthenticateHeader] ?? const <String>[],
    ),
  );
}

McpJsonMap _jsonRpcResultFrom(McpJsonMap response, {required String method}) {
  final error = response['error'];
  if (error != null) {
    throw McpJsonRpcException(
      id: response['id'],
      method: method,
      error: _jsonMapFrom(error, label: '$method error'),
    );
  }
  return _jsonMapFrom(response['result'], label: '$method result');
}

List<McpJsonMap> _jsonMapListFrom(
  McpJsonMap result, {
  required String key,
  required String method,
  required String label,
}) {
  final value = result[key];
  if (value is! List) {
    throw FormatException('$method result.$key must be an array');
  }
  return [for (final item in value) _jsonMapFrom(item, label: label)];
}

List<McpJsonMap> _validatedToolCatalogEntries(
  List<McpJsonMap> entries, {
  required String label,
}) {
  for (final entry in entries) {
    final name = entry['name'];
    if (name is! String || !_mcpToolNamePattern.hasMatch(name)) {
      throw FormatException('$label.name must be a valid MCP tool name');
    }
  }
  return List<McpJsonMap>.unmodifiable(entries);
}

List<McpJsonMap> _validatedResourceCatalogEntries(
  List<McpJsonMap> entries, {
  required String label,
}) {
  for (final entry in entries) {
    final uri = entry['uri'];
    if (uri is! String ||
        containsMcpWhitespaceOrControl(uri) ||
        Uri.tryParse(uri)?.hasScheme != true) {
      throw FormatException('$label.uri must be an absolute URI with a scheme');
    }
  }
  return List<McpJsonMap>.unmodifiable(entries);
}

List<McpJsonMap> _validatedResourceTemplateCatalogEntries(
  List<McpJsonMap> entries, {
  required String label,
}) {
  for (final entry in entries) {
    _requireCatalogText(entry, 'uriTemplate', label: label);
  }
  return List<McpJsonMap>.unmodifiable(entries);
}

List<McpJsonMap> _validatedPromptCatalogEntries(
  List<McpJsonMap> entries, {
  required String label,
}) {
  for (final entry in entries) {
    _requireCatalogText(entry, 'name', label: label);
  }
  return List<McpJsonMap>.unmodifiable(entries);
}

List<McpJsonMap> _validatedResourceReadContents(
  List<McpJsonMap> entries, {
  required String label,
}) {
  for (final entry in entries) {
    _validateResourceContent(entry, label: label);
  }
  return entries;
}

McpJsonMap _validatedToolCallResult(
  McpJsonMap result, {
  required String label,
}) {
  final contentValue = result['content'];
  if (contentValue is! List) {
    throw FormatException('$label.content must be an array');
  }
  for (final item in contentValue) {
    final block = _jsonMapFrom(item, label: '$label.content');
    _validateContentBlock(block, label: '$label.content');
  }

  final isError = result['isError'];
  if (isError != null && isError is! bool) {
    throw FormatException('$label.isError must be a boolean');
  }

  final metadata = result['_meta'];
  if (metadata != null) {
    _jsonMapFrom(metadata, label: '$label._meta');
  }

  return result;
}

McpJsonMap _validatedPromptGetResult(
  McpJsonMap result, {
  required String label,
}) {
  final description = result['description'];
  if (description != null && description is! String) {
    throw FormatException('$label.description must be a string');
  }

  final messagesValue = result['messages'];
  if (messagesValue is! List) {
    throw FormatException('$label.messages must be an array');
  }
  for (final item in messagesValue) {
    final message = _jsonMapFrom(item, label: '$label message');
    _validatePromptMessage(message, label: '$label message');
  }
  return result;
}

void _validatePromptMessage(McpJsonMap message, {required String label}) {
  final role = message['role'];
  if (role != 'user' && role != 'assistant') {
    throw FormatException('$label.role must be user or assistant');
  }
  final content = _jsonMapFrom(message['content'], label: '$label.content');
  _validateContentBlock(content, label: '$label.content');
}

void _validateContentBlock(McpJsonMap content, {required String label}) {
  final type = content['type'];
  if (type is! String || type.isEmpty) {
    throw FormatException('$label.type must be a non-empty string');
  }

  switch (type) {
    case 'text':
      _requireStringField(content, 'text', label: label);
      break;
    case 'image':
    case 'audio':
      _requireStringField(content, 'data', label: label);
      _requireStringField(content, 'mimeType', label: label);
      _validateBase64Field(content, 'data', label: label);
      break;
    case 'resource':
      final resource = _jsonMapFrom(
        content['resource'],
        label: '$label.resource',
      );
      _validateResourceContent(resource, label: '$label.resource');
      break;
    case 'resource_link':
      final uri = content['uri'];
      if (uri is! String ||
          containsMcpWhitespaceOrControl(uri) ||
          Uri.tryParse(uri)?.hasScheme != true) {
        throw FormatException(
          '$label.uri must be an absolute URI with a scheme',
        );
      }
      _requireNonEmptyStringField(content, 'name', label: label);
      break;
    default:
      throw FormatException(
        '$label.type must be a supported content block type',
      );
  }
}

void _validateResourceContent(McpJsonMap content, {required String label}) {
  final uri = content['uri'];
  if (uri is! String ||
      containsMcpWhitespaceOrControl(uri) ||
      Uri.tryParse(uri)?.hasScheme != true) {
    throw FormatException('$label.uri must be an absolute URI with a scheme');
  }

  final mimeType = content['mimeType'];
  if (mimeType != null && mimeType is! String) {
    throw FormatException('$label.mimeType must be a string');
  }

  final hasText = content.containsKey('text');
  final hasBlob = content.containsKey('blob');
  if (hasText == hasBlob) {
    throw FormatException('$label must contain exactly one of text or blob');
  }
  if (hasText) {
    _requireStringField(content, 'text', label: label);
  } else {
    _requireStringField(content, 'blob', label: label);
    _validateBase64Field(content, 'blob', label: label);
  }
}

void _requireCatalogText(
  McpJsonMap entry,
  String key, {
  required String label,
}) {
  final value = entry[key];
  if (value is! String ||
      value.isEmpty ||
      containsMcpWhitespaceOrControl(value)) {
    throw FormatException(
      '$label.$key must be a non-empty string without whitespace or '
      'control characters',
    );
  }
}

void _requireStringField(
  McpJsonMap entry,
  String key, {
  required String label,
}) {
  if (entry[key] is! String) {
    throw FormatException('$label.$key must be a string');
  }
}

void _requireNonEmptyStringField(
  McpJsonMap entry,
  String key, {
  required String label,
}) {
  final value = entry[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$label.$key must be a non-empty string');
  }
}

void _validateBase64Field(
  McpJsonMap entry,
  String key, {
  required String label,
}) {
  final value = entry[key] as String;
  try {
    base64Decode(value);
  } on FormatException {
    throw FormatException('$label.$key must be base64 encoded');
  }
}

String? _nextCursorFrom(McpJsonMap result, {required String method}) {
  final nextCursor = result['nextCursor'];
  if (nextCursor == null) {
    return null;
  }
  if (nextCursor is! String) {
    throw FormatException('$method result.nextCursor must be a string');
  }
  if (nextCursor.isEmpty || containsMcpWhitespaceOrControl(nextCursor)) {
    throw FormatException(
      '$method result.nextCursor must be a non-empty string without '
      'whitespace or control characters',
    );
  }
  return nextCursor;
}

McpJsonMap _jsonMapFrom(Object? value, {required String label}) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$label must contain only string keys');
    }
    result[key] = entry.value;
  }
  return result;
}
