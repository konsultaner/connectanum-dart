class ServerEndpoint {
  ServerEndpoint._(this.websocketUri);

  factory ServerEndpoint.parse(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      throw const FormatException('Enter a server address.');
    }
    if (!value.contains('://')) {
      value = 'wss://$value';
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
      throw const FormatException('Enter a valid server address.');
    }
    final scheme = switch (parsed.scheme.toLowerCase()) {
      'http' => 'ws',
      'https' => 'wss',
      'ws' => 'ws',
      'wss' => 'wss',
      _ => throw const FormatException(
        'Server addresses must use ws, wss, http, or https.',
      ),
    };
    if (parsed.hasQuery || parsed.fragment.isNotEmpty) {
      throw const FormatException(
        'Server addresses cannot contain a query or fragment.',
      );
    }
    final path = parsed.path.isEmpty || parsed.path == '/'
        ? '/ws'
        : parsed.path;
    return ServerEndpoint._(
      parsed.replace(scheme: scheme, path: path, query: null, fragment: null),
    );
  }

  final Uri websocketUri;

  bool get isSecure => websocketUri.scheme == 'wss';

  bool get isLoopback =>
      websocketUri.host == 'localhost' ||
      websocketUri.host == '127.0.0.1' ||
      websocketUri.host == '::1';

  void requireSecureRegistration() {
    if (!isSecure && !isLoopback) {
      throw const FormatException(
        'Account registration requires wss:// outside the local machine.',
      );
    }
  }

  @override
  String toString() => websocketUri.toString();
}
