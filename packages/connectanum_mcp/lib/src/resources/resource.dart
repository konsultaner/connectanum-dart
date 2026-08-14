import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart'
    show McpCompletionHandler, McpResourceUriTemplate;

import '../protocol/errors.dart';
import '../protocol/icons.dart';
import '../protocol/pagination.dart';

typedef McpResourceReader =
    FutureOr<List<McpResourceContent>> Function(McpResourceRequest);

typedef McpResourceTemplateReader =
    FutureOr<List<McpResourceContent>> Function(
      McpResourceRequest request,
      Map<String, String> variables,
    );

class McpResource {
  McpResource({
    required this.uri,
    required this.name,
    required this.read,
    this.title,
    this.description,
    this.mimeType,
    this.size,
    this.annotations,
    Iterable<McpIcon> icons = const [],
  }) : icons = List<McpIcon>.unmodifiable(icons) {
    _validateResourceUri(uri, 'uri');
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'MCP resource name is required.');
    }
    final size = this.size;
    if (size != null && size < 0) {
      throw ArgumentError.value(
        size,
        'size',
        'MCP resource size must be non-negative.',
      );
    }
  }

  final String uri;
  final String name;
  final String? title;
  final String? description;
  final String? mimeType;
  final int? size;
  final McpResourceAnnotations? annotations;
  final List<McpIcon> icons;
  final McpResourceReader read;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'uri': uri, 'name': name};
    final title = this.title;
    if (title != null) {
      json['title'] = title;
    }
    final description = this.description;
    if (description != null) {
      json['description'] = description;
    }
    final mimeType = this.mimeType;
    if (mimeType != null) {
      json['mimeType'] = mimeType;
    }
    addMcpIconsToJson(json, icons);
    final size = this.size;
    if (size != null) {
      json['size'] = size;
    }
    final annotations = this.annotations;
    if (annotations != null && !annotations.isEmpty) {
      json['annotations'] = annotations.toJson();
    }
    return json;
  }
}

class McpResourceTemplate {
  McpResourceTemplate({
    required this.uriTemplate,
    required this.name,
    this.read,
    this.complete,
    this.title,
    this.description,
    this.mimeType,
    this.annotations,
    Iterable<McpIcon> icons = const [],
  }) : icons = List<McpIcon>.unmodifiable(icons),
       _uriTemplate = McpResourceUriTemplate(uriTemplate) {
    if (name.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'MCP resource template name is required.',
      );
    }
  }

  final String uriTemplate;
  final String name;
  final McpResourceTemplateReader? read;
  final McpCompletionHandler? complete;
  final String? title;
  final String? description;
  final String? mimeType;
  final McpResourceAnnotations? annotations;
  final List<McpIcon> icons;
  final McpResourceUriTemplate _uriTemplate;

  /// Declared URI-template variables in protocol order.
  List<String> get variables => _uriTemplate.variables;

  /// Expands decoded values into a concrete URI for this template.
  String expandUri(Map<String, String> variables) =>
      _uriTemplate.expand(variables);

  Map<String, String>? _matchUri(String uri) => _uriTemplate.match(uri);

  int get _literalLength => _uriTemplate.literalLength;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'uriTemplate': uriTemplate, 'name': name};
    final title = this.title;
    if (title != null) {
      json['title'] = title;
    }
    final description = this.description;
    if (description != null) {
      json['description'] = description;
    }
    final mimeType = this.mimeType;
    if (mimeType != null) {
      json['mimeType'] = mimeType;
    }
    addMcpIconsToJson(json, icons);
    final annotations = this.annotations;
    if (annotations != null && !annotations.isEmpty) {
      json['annotations'] = annotations.toJson();
    }
    return json;
  }
}

/// A readable resource-template match for a concrete resource URI.
class McpResourceTemplateMatch {
  McpResourceTemplateMatch({
    required this.template,
    required Map<String, String> variables,
  }) : variables = Map<String, String>.unmodifiable(variables);

  final McpResourceTemplate template;
  final Map<String, String> variables;
}

class McpResourceAnnotations {
  const McpResourceAnnotations({
    this.audience = const [],
    this.priority,
    this.lastModified,
  });

  final List<String> audience;
  final double? priority;
  final DateTime? lastModified;

  bool get isEmpty =>
      audience.isEmpty && priority == null && lastModified == null;

  Map<String, Object?> toJson() {
    final priority = this.priority;
    final lastModified = this.lastModified;
    if (priority != null && (priority < 0 || priority > 1)) {
      throw ArgumentError.value(
        priority,
        'priority',
        'MCP resource annotation priority must be between 0.0 and 1.0.',
      );
    }
    return <String, Object?>{
      if (audience.isNotEmpty) 'audience': audience,
      'priority': ?priority,
      'lastModified': ?lastModified?.toUtc().toIso8601String(),
    };
  }
}

class McpResourceRequest {
  const McpResourceRequest({required this.uri});

  final String uri;
}

sealed class McpResourceContent {
  const McpResourceContent({required this.uri, this.mimeType});

  final String uri;
  final String? mimeType;

  Map<String, Object?> toJson();
}

class McpTextResourceContent extends McpResourceContent {
  const McpTextResourceContent({
    required super.uri,
    required this.text,
    super.mimeType,
  });

  final String text;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'uri': uri,
    if (mimeType != null) 'mimeType': mimeType,
    'text': text,
  };
}

class McpBlobResourceContent extends McpResourceContent {
  McpBlobResourceContent({
    required super.uri,
    required this.blob,
    super.mimeType,
  });

  McpBlobResourceContent.bytes({
    required String uri,
    required Uint8List bytes,
    String? mimeType,
  }) : this(uri: uri, blob: base64Encode(bytes), mimeType: mimeType);

  final String blob;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'uri': uri,
    if (mimeType != null) 'mimeType': mimeType,
    'blob': blob,
  };
}

class McpResourceRegistry {
  McpResourceRegistry({
    Iterable<McpResource> resources = const [],
    Iterable<McpResourceTemplate> templates = const [],
    this.pageSize,
    this.templatePageSize,
  }) {
    _validatePageSize(pageSize, 'pageSize');
    _validatePageSize(templatePageSize, 'templatePageSize');
    registerAll(resources);
    registerTemplates(templates);
  }

  final int? pageSize;
  final int? templatePageSize;
  final Map<String, McpResource> _resources = <String, McpResource>{};
  final Map<String, McpResourceTemplate> _templates =
      <String, McpResourceTemplate>{};
  int _revision = 0;

  bool get isNotEmpty => _resources.isNotEmpty || _templates.isNotEmpty;
  bool get hasCompletions =>
      _templates.values.any((template) => template.complete != null);

  void register(McpResource resource) {
    if (_resources.containsKey(resource.uri)) {
      throw ArgumentError.value(
        resource.uri,
        'resource.uri',
        'Duplicate MCP resource',
      );
    }
    _resources[resource.uri] = resource;
    _revision += 1;
  }

  void registerAll(Iterable<McpResource> resources) {
    for (final resource in resources) {
      register(resource);
    }
  }

  void replaceAll(Iterable<McpResource> resources) {
    _resources.clear();
    _revision += 1;
    registerAll(resources);
  }

  void registerTemplate(McpResourceTemplate template) {
    if (_templates.containsKey(template.uriTemplate)) {
      throw ArgumentError.value(
        template.uriTemplate,
        'template.uriTemplate',
        'Duplicate MCP resource template',
      );
    }
    _templates[template.uriTemplate] = template;
    _revision += 1;
  }

  void registerTemplates(Iterable<McpResourceTemplate> templates) {
    for (final template in templates) {
      registerTemplate(template);
    }
  }

  void replaceTemplates(Iterable<McpResourceTemplate> templates) {
    _templates.clear();
    _revision += 1;
    registerTemplates(templates);
  }

  McpResourceListPage listPage({String? cursor}) {
    final resources = List<McpResource>.unmodifiable(
      _resources.values.toList(growable: false)
        ..sort((left, right) => left.uri.compareTo(right.uri)),
    );
    final pageSize = this.pageSize;
    if (pageSize == null) {
      if (cursor != null) {
        throw McpException(
          McpErrorCodes.invalidParams,
          'resources/list.params.cursor is invalid or stale',
        );
      }
      return McpResourceListPage(resources: resources);
    }

    final start = decodeMcpCursor(
      cursor,
      prefix: _resourceCursorPrefix,
      expectedRevision: _revision,
      maxOffset: resources.length,
      errorMessage: 'resources/list.params.cursor is invalid or stale',
    );
    final end = math.min(start + pageSize, resources.length);
    return McpResourceListPage(
      resources: List<McpResource>.unmodifiable(resources.sublist(start, end)),
      nextCursor: end < resources.length
          ? encodeMcpCursor(
              prefix: _resourceCursorPrefix,
              revision: _revision,
              offset: end,
            )
          : null,
    );
  }

  McpResourceTemplateListPage listTemplatePage({String? cursor}) {
    final templates = List<McpResourceTemplate>.unmodifiable(
      _templates.values.toList(growable: false)
        ..sort((left, right) => left.uriTemplate.compareTo(right.uriTemplate)),
    );
    final pageSize = templatePageSize;
    if (pageSize == null) {
      if (cursor != null) {
        throw McpException(
          McpErrorCodes.invalidParams,
          'resources/templates/list.params.cursor is invalid or stale',
        );
      }
      return McpResourceTemplateListPage(templates: templates);
    }

    final start = decodeMcpCursor(
      cursor,
      prefix: _resourceTemplateCursorPrefix,
      expectedRevision: _revision,
      maxOffset: templates.length,
      errorMessage:
          'resources/templates/list.params.cursor is invalid or stale',
    );
    final end = math.min(start + pageSize, templates.length);
    return McpResourceTemplateListPage(
      templates: List<McpResourceTemplate>.unmodifiable(
        templates.sublist(start, end),
      ),
      nextCursor: end < templates.length
          ? encodeMcpCursor(
              prefix: _resourceTemplateCursorPrefix,
              revision: _revision,
              offset: end,
            )
          : null,
    );
  }

  /// Matches [uri] against registered templates that can be read.
  ///
  /// When multiple templates match, the template with the most literal
  /// characters wins. Lexical template order breaks ties, matching
  /// [read]'s deterministic resolution.
  McpResourceTemplateMatch? matchReadableTemplate(String uri) {
    McpResourceTemplate? selectedTemplate;
    Map<String, String>? selectedVariables;
    for (final template in _templates.values) {
      if (template.read == null) {
        continue;
      }
      final variables = template._matchUri(uri);
      if (variables == null) {
        continue;
      }

      final selected = selectedTemplate;
      if (selected == null ||
          template._literalLength > selected._literalLength ||
          (template._literalLength == selected._literalLength &&
              template.uriTemplate.compareTo(selected.uriTemplate) < 0)) {
        selectedTemplate = template;
        selectedVariables = variables;
      }
    }

    if (selectedTemplate == null || selectedVariables == null) {
      return null;
    }
    return McpResourceTemplateMatch(
      template: selectedTemplate,
      variables: selectedVariables,
    );
  }

  Future<List<McpResourceContent>> read(McpResourceRequest request) async {
    final resource = _resources[request.uri];
    if (resource != null) {
      return resource.read(request);
    }

    final match = matchReadableTemplate(request.uri);
    final reader = match?.template.read;
    if (match == null || reader == null) {
      throw McpException(
        McpErrorCodes.resourceNotFound,
        'Resource not found',
        data: <String, Object?>{'uri': request.uri},
      );
    }
    return reader(request, match.variables);
  }

  /// Returns the template advertised with the exact [uriTemplate].
  McpResourceTemplate? template(String uriTemplate) => _templates[uriTemplate];

  McpResource? operator [](String uri) => _resources[uri];
}

class McpResourceListPage {
  const McpResourceListPage({required this.resources, this.nextCursor});

  final List<McpResource> resources;
  final String? nextCursor;
}

class McpResourceTemplateListPage {
  const McpResourceTemplateListPage({required this.templates, this.nextCursor});

  final List<McpResourceTemplate> templates;
  final String? nextCursor;
}

const String _resourceCursorPrefix = 'resources:';
const String _resourceTemplateCursorPrefix = 'resourceTemplates:';

void _validatePageSize(int? pageSize, String name) {
  if (pageSize != null && pageSize <= 0) {
    throw ArgumentError.value(
      pageSize,
      name,
      'MCP resource list page size must be greater than zero.',
    );
  }
}

void _validateResourceUri(String uri, String name) {
  final parsed = Uri.tryParse(uri);
  if (uri.isEmpty || parsed == null || !parsed.hasScheme) {
    throw ArgumentError.value(
      uri,
      name,
      'MCP resource URI must be an absolute URI with a scheme.',
    );
  }
}
