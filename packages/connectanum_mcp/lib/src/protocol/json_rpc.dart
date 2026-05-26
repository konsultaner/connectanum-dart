import 'errors.dart';

typedef JsonMap = Map<String, Object?>;

class JsonRpcResponse {
  JsonRpcResponse.result(this.id, this.result) : error = null;

  JsonRpcResponse.error(this.id, McpException error)
    : result = null,
      error = error.toJson();

  final Object? id;
  final Object? result;
  final JsonMap? error;

  JsonMap toJson() {
    final json = <String, Object?>{'jsonrpc': '2.0', 'id': id};
    final error = this.error;
    if (error != null) {
      json['error'] = error;
    } else {
      json['result'] = result;
    }
    return json;
  }
}

bool isJsonRpcId(Object? value) => value == null || isJsonRpcRequestId(value);

bool isJsonRpcRequestId(Object? value) => value is String || value is int;

JsonMap jsonMapFrom(Object? value, {String label = 'params'}) {
  if (value == null) {
    return <String, Object?>{};
  }
  if (value is! Map) {
    throw McpException(McpErrorCodes.invalidParams, '$label must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw McpException(
        McpErrorCodes.invalidParams,
        '$label must contain only string keys',
      );
    }
    result[key] = entry.value;
  }
  return result;
}
