import 'dart:convert';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';

// Shared CLI contract checks. HTTP parsing and CLI verification have distinct
// responsibilities; exercise malformed parsed values directly as well as over IO.

List<String> expectBatchResponses(
  List<McpJsonMap>? responses,
  List<String> expectedIds, {
  required String label,
}) {
  final responseIds = expectBatchResponseIds(
    responses,
    expectedIds,
    label: label,
  );
  for (final response in responses!) {
    final id = response['id'];
    if (response.containsKey('error')) {
      throw StateError(
        '$label batch response $id errored: ${response['error']}',
      );
    }
  }
  return responseIds;
}

List<String> expectBatchResponseIds(
  List<McpJsonMap>? responses,
  List<String> expectedIds, {
  required String label,
}) {
  if (responses == null) {
    throw StateError('$label batch returned no responses.');
  }
  if (responses.length != expectedIds.length) {
    throw StateError(
      '$label batch returned ${responses.length} responses for '
      '${expectedIds.length} requests.',
    );
  }

  final responseIds = <String>[];
  for (final response in responses) {
    final id = response['id'];
    if (id is! String) {
      throw StateError('$label batch response had a non-string id.');
    }
    responseIds.add(id);
  }

  final missingIds = [
    for (final expectedId in expectedIds)
      if (!responseIds.contains(expectedId)) expectedId,
  ];
  if (missingIds.isNotEmpty) {
    throw StateError('$label batch missed responses for $missingIds.');
  }
  return responseIds;
}

McpJsonMap batchResult(
  List<McpJsonMap>? responses,
  String id, {
  required String label,
}) {
  if (responses == null) {
    throw StateError('$label batch returned no responses.');
  }
  for (final response in responses) {
    if (response['id'] != id) {
      continue;
    }
    final result = response['result'];
    if (result is Map) {
      return result.cast<String, Object?>();
    }
    throw StateError('$label batch response $id had a non-object result.');
  }
  throw StateError('$label batch missed response $id.');
}

McpJsonMap batchError(
  List<McpJsonMap>? responses,
  String id, {
  required String label,
}) {
  if (responses == null) {
    throw StateError('$label batch returned no responses.');
  }
  for (final response in responses) {
    if (response['id'] != id) {
      continue;
    }
    final error = response['error'];
    if (error is Map) {
      return error.cast<String, Object?>();
    }
    if (response.containsKey('result')) {
      throw StateError('$label batch response $id succeeded unexpectedly.');
    }
    throw StateError('$label batch response $id had a non-object error.');
  }
  throw StateError('$label batch missed response $id.');
}

McpJsonMap responseResult(
  McpJsonMap? response,
  String id, {
  required String label,
}) {
  if (response == null) {
    throw StateError('$label returned no response.');
  }
  if (response['id'] != id) {
    throw StateError(
      '$label returned response id ${response['id']} instead of $id.',
    );
  }
  final result = response['result'];
  if (result is Map) {
    return result.cast<String, Object?>();
  }
  if (response.containsKey('error')) {
    throw StateError('$label returned error ${jsonEncode(response['error'])}.');
  }
  throw StateError('$label response had a non-object result.');
}

void expectWampMetaProcedure(
  McpStreamableWampMetaCallResult result,
  String expectedProcedure, {
  required String label,
}) {
  if (result.procedure != expectedProcedure) {
    throw StateError(
      '$label returned ${result.procedure}, expected $expectedProcedure.',
    );
  }
}

void expectWampCatalogContains({
  required Object? catalog,
  required String uri,
  required String label,
}) {
  if (!wampCatalogContainsUri(catalog, uri)) {
    throw StateError('$label catalog did not include $uri.');
  }
}

bool wampCatalogContainsUri(Object? catalog, String uri) {
  return catalogContainsValue(catalog: catalog, field: 'uri', value: uri);
}

void expectWampSubscription(
  McpStreamableWampSubscriptionResult subscription, {
  required String topic,
  required int queueLimit,
  required String label,
}) {
  if (subscription.topic != topic) {
    throw StateError(
      '$label returned subscription for ${subscription.topic}, expected $topic.',
    );
  }
  if (subscription.handle.isEmpty) {
    throw StateError('$label returned an empty subscription handle.');
  }
  if (subscription.queueLimit != queueLimit) {
    throw StateError(
      '$label returned queue limit ${subscription.queueLimit}, '
      'expected $queueLimit.',
    );
  }
}

bool catalogContainsValue({
  required Object? catalog,
  required String field,
  required String value,
}) {
  if (catalog is! Iterable<Object?>) {
    return false;
  }
  for (final entry in catalog) {
    if (entry is Map && entry[field] == value) {
      return true;
    }
  }
  return false;
}

void expectStreamableStateUnchanged(
  McpStreamableHttpClient client, {
  required String? sessionId,
  required String? lastEventId,
  required String label,
  String? diagnostic,
}) {
  if (client.sessionId != sessionId || client.lastEventId != lastEventId) {
    throw StateError(diagnostic ?? '$label changed Streamable state.');
  }
}

void expectSessionIdUnchanged(
  McpStreamableHttpClient client, {
  required String? sessionId,
  required String diagnostic,
}) {
  if (client.sessionId != sessionId) {
    throw StateError(diagnostic);
  }
}
