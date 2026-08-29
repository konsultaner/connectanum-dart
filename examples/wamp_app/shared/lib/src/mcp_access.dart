import 'server_endpoint.dart';

abstract final class WampAppMcpAccessContract {
  static const version = 1;
  static const keywordNames = <String>{
    'version',
    'mcp_path',
    'auth_path',
    'streamable_http',
    'direct_json',
    'tools',
    'resources',
    'prompts',
    'profile_fields',
  };
  static const profileFields = <String>[
    'username',
    'display_name',
    'status',
    'profile_revision',
    'profile_updated_at',
    'consent_revision',
  ];
}

final class WampAppMcpAccessConfiguration {
  WampAppMcpAccessConfiguration({
    required this.mcpPath,
    required this.authPath,
    required this.streamableHttp,
    required this.directJson,
    required this.tools,
    required this.resources,
    required this.prompts,
    required Iterable<String> profileFields,
  }) : profileFields = List.unmodifiable(profileFields) {
    _validateRoutePath(mcpPath, 'mcp_path');
    _validateRoutePath(authPath, 'auth_path');
    if (mcpPath == authPath) {
      throw const FormatException('MCP and authentication paths must differ.');
    }
    if (!streamableHttp || !directJson || !tools || !resources || !prompts) {
      throw const FormatException(
        'The MCP access configuration is missing a required capability.',
      );
    }
    final uniqueFields = profileFields.toSet();
    if (uniqueFields.length != profileFields.length ||
        uniqueFields.length != WampAppMcpAccessContract.profileFields.length ||
        !WampAppMcpAccessContract.profileFields.every(uniqueFields.contains)) {
      throw const FormatException(
        'The MCP public-profile field boundary is invalid.',
      );
    }
  }

  factory WampAppMcpAccessConfiguration.standard({
    required String mcpPath,
    required String authPath,
  }) => WampAppMcpAccessConfiguration(
    mcpPath: mcpPath,
    authPath: authPath,
    streamableHttp: true,
    directJson: true,
    tools: true,
    resources: true,
    prompts: true,
    profileFields: WampAppMcpAccessContract.profileFields,
  );

  final String mcpPath;
  final String authPath;
  final bool streamableHttp;
  final bool directJson;
  final bool tools;
  final bool resources;
  final bool prompts;
  final List<String> profileFields;

  Uri mcpUriFor(ServerEndpoint endpoint) => _httpUri(endpoint, mcpPath);

  Uri authUriFor(ServerEndpoint endpoint) => _httpUri(endpoint, authPath);

  Map<String, dynamic> toWampKeywords() => {
    'version': WampAppMcpAccessContract.version,
    'mcp_path': mcpPath,
    'auth_path': authPath,
    'streamable_http': streamableHttp,
    'direct_json': directJson,
    'tools': tools,
    'resources': resources,
    'prompts': prompts,
    'profile_fields': profileFields,
  };

  factory WampAppMcpAccessConfiguration.fromWampKeywords(
    Map<String, dynamic>? value,
  ) {
    if (value == null ||
        value.keys.toSet().length !=
            WampAppMcpAccessContract.keywordNames.length ||
        !WampAppMcpAccessContract.keywordNames.every(value.containsKey) ||
        value['version'] != WampAppMcpAccessContract.version ||
        value['mcp_path'] is! String ||
        value['auth_path'] is! String ||
        value['streamable_http'] is! bool ||
        value['direct_json'] is! bool ||
        value['tools'] is! bool ||
        value['resources'] is! bool ||
        value['prompts'] is! bool ||
        value['profile_fields'] is! List) {
      throw const FormatException('MCP access configuration is malformed.');
    }
    final fields = (value['profile_fields'] as List);
    if (fields.any((field) => field is! String)) {
      throw const FormatException('MCP profile fields are malformed.');
    }
    return WampAppMcpAccessConfiguration(
      mcpPath: value['mcp_path'] as String,
      authPath: value['auth_path'] as String,
      streamableHttp: value['streamable_http'] as bool,
      directJson: value['direct_json'] as bool,
      tools: value['tools'] as bool,
      resources: value['resources'] as bool,
      prompts: value['prompts'] as bool,
      profileFields: fields.cast<String>(),
    );
  }
}

Uri _httpUri(ServerEndpoint endpoint, String path) =>
    endpoint.websocketUri.replace(
      scheme: endpoint.isSecure ? 'https' : 'http',
      path: path,
      query: null,
      fragment: null,
    );

void _validateRoutePath(String value, String name) {
  final parsed = Uri.tryParse(value);
  if (value.isEmpty ||
      !value.startsWith('/') ||
      parsed == null ||
      parsed.scheme.isNotEmpty ||
      parsed.host.isNotEmpty ||
      parsed.userInfo.isNotEmpty ||
      parsed.hasQuery ||
      parsed.fragment.isNotEmpty ||
      parsed.path != value) {
    throw FormatException('$name must be an absolute route path.');
  }
}
