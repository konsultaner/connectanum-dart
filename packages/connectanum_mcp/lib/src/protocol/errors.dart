abstract final class McpErrorCodes {
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  static const int serverClosed = -32000;
  static const int serverNotInitialized = -32002;
  static const int resourceNotFound = -32002;
}

class McpException implements Exception {
  McpException(this.code, this.message, {this.data});

  final int code;
  final String message;
  final Object? data;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'code': code, 'message': message};
    final data = this.data;
    if (data != null) {
      json['data'] = data;
    }
    return json;
  }

  @override
  String toString() => 'McpException($code, $message)';
}
