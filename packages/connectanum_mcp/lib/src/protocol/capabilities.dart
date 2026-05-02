class McpServerInfo {
  const McpServerInfo({
    required this.name,
    required this.version,
    this.title,
    this.description,
  });

  final String name;
  final String version;
  final String? title;
  final String? description;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'name': name, 'version': version};
    final title = this.title;
    if (title != null) {
      json['title'] = title;
    }
    final description = this.description;
    if (description != null) {
      json['description'] = description;
    }
    return json;
  }
}

class McpServerCapabilities {
  const McpServerCapabilities({
    this.tools = const McpToolCapabilities(),
    this.prompts,
    this.resources,
  });

  final McpToolCapabilities? tools;
  final McpPromptCapabilities? prompts;
  final McpResourceCapabilities? resources;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    final tools = this.tools;
    if (tools != null) {
      json['tools'] = tools.toJson();
    }
    final prompts = this.prompts;
    if (prompts != null) {
      json['prompts'] = prompts.toJson();
    }
    final resources = this.resources;
    if (resources != null) {
      json['resources'] = resources.toJson();
    }
    return json;
  }
}

class McpToolCapabilities {
  const McpToolCapabilities({this.listChanged = false});

  final bool listChanged;

  Map<String, Object?> toJson() {
    if (!listChanged) {
      return <String, Object?>{};
    }
    return <String, Object?>{'listChanged': true};
  }
}

class McpPromptCapabilities {
  const McpPromptCapabilities({this.listChanged = false});

  final bool listChanged;

  Map<String, Object?> toJson() {
    if (!listChanged) {
      return <String, Object?>{};
    }
    return <String, Object?>{'listChanged': true};
  }
}

class McpResourceCapabilities {
  const McpResourceCapabilities({
    this.subscribe = false,
    this.listChanged = false,
  });

  final bool subscribe;
  final bool listChanged;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (subscribe) 'subscribe': true,
      if (listChanged) 'listChanged': true,
    };
  }
}
