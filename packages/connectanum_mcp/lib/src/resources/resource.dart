import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../protocol/errors.dart';
import '../protocol/pagination.dart';

typedef McpResourceReader =
    FutureOr<List<McpResourceContent>> Function(McpResourceRequest);

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
  }) {
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
    this.title,
    this.description,
    this.mimeType,
    this.annotations,
  }) {
    if (uriTemplate.isEmpty) {
      throw ArgumentError.value(
        uriTemplate,
        'uriTemplate',
        'MCP resource template URI is required.',
      );
    }
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
  final String? title;
  final String? description;
  final String? mimeType;
  final McpResourceAnnotations? annotations;

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
    final annotations = this.annotations;
    if (annotations != null && !annotations.isEmpty) {
      json['annotations'] = annotations.toJson();
    }
    return json;
  }
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
    final resources = List<McpResource>.unmodifiable(_resources.values);
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
    final templates = List<McpResourceTemplate>.unmodifiable(_templates.values);
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
