const int _minRawSocketSizeExponent = 9;
const int _maxRawSocketSizeExponent = 30;

/// Validates and normalises a hostname.
String normalizeHostname(String host) {
  final trimmed = host.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(host, 'host', 'Host must not be empty');
  }
  final hostnamePattern = RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?)*$',
  );
  final ipv6Pattern = RegExp(r'^\[[0-9A-Fa-f:]+\]$');
  final ipv4Pattern = RegExp(
    r'^(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(?:\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3}$',
  );
  if (!(hostnamePattern.hasMatch(trimmed) ||
      ipv4Pattern.hasMatch(trimmed) ||
      ipv6Pattern.hasMatch(trimmed))) {
    throw ArgumentError.value(
      host,
      'host',
      'Host is not a valid hostname or IP',
    );
  }
  return trimmed;
}

/// Validates that [pem] looks like a PEM formatted blob.
String normalizePem(String pem, String fieldName) {
  final trimmed = pem.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(pem, fieldName, 'PEM value must not be empty');
  }
  final beginMatch = RegExp(
    r'^-----BEGIN ([A-Z0-9 ]+)-----',
    multiLine: true,
  ).firstMatch(trimmed);
  final endMatch = RegExp(
    r'-----END ([A-Z0-9 ]+)-----$',
    multiLine: true,
  ).firstMatch(trimmed);
  if (beginMatch == null || endMatch == null) {
    throw ArgumentError.value(
      pem,
      fieldName,
      'Value must contain PEM BEGIN/END markers',
    );
  }
  if (beginMatch.group(1) != endMatch.group(1)) {
    throw ArgumentError.value(
      pem,
      fieldName,
      'PEM BEGIN/END markers must match',
    );
  }
  return trimmed;
}

/// Ensures the TCP port is within the valid range.
int normalizePort(int port) {
  if (port < 0 || port > 65535) {
    throw ArgumentError.value(port, 'port', 'Port must be between 0 and 65535');
  }
  return port;
}

/// Validates raw socket size exponent boundaries (9..30, inclusive).
int normalizeRawSocketSizeExponent(int exponent) {
  if (exponent < _minRawSocketSizeExponent ||
      exponent > _maxRawSocketSizeExponent) {
    throw ArgumentError.value(
      exponent,
      'maxRawSocketSizeExponent',
      'maxRawSocketSizeExponent must be between '
          '$_minRawSocketSizeExponent and $_maxRawSocketSizeExponent',
    );
  }
  return exponent;
}

/// Validates the optional HTTP content length.
int? normalizeMaxHttpContentLength(int? value) {
  if (value == null) {
    return null;
  }
  if (value <= 0) {
    throw ArgumentError.value(
      value,
      'maxHttpContentLength',
      'maxHttpContentLength must be positive',
    );
  }
  return value;
}

/// Validates the optional idle timeout.
Duration? normalizeIdleTimeout(Duration? timeout) {
  if (timeout == null) {
    return null;
  }
  if (timeout.isNegative || timeout.inMilliseconds == 0) {
    throw ArgumentError.value(
      timeout,
      'idleTimeout',
      'idleTimeout must be positive',
    );
  }
  return timeout;
}

/// Validates the optional websocket path.
String? normalizeWebSocketPath(String? path) {
  if (path == null) {
    return null;
  }
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(path, 'webSocketPath', 'Path must not be empty');
  }
  if (!trimmed.startsWith('/')) {
    throw ArgumentError.value(
      path,
      'webSocketPath',
      'webSocketPath must start with "/"',
    );
  }
  return trimmed;
}
