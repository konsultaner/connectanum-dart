import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
    this.title,
    this.description,
    this.mimeType,
    this.annotations,
    Iterable<McpIcon> icons = const [],
  }) : icons = List<McpIcon>.unmodifiable(icons),
       _pattern = _McpResourceTemplatePattern.parse(uriTemplate) {
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
  final String? title;
  final String? description;
  final String? mimeType;
  final McpResourceAnnotations? annotations;
  final List<McpIcon> icons;
  final _McpResourceTemplatePattern _pattern;

  Map<String, String>? _matchUri(String uri) => _pattern.match(uri);

  int get _literalLength => _pattern.literalLength;

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

class _McpResourceTemplatePattern {
  const _McpResourceTemplatePattern({
    required this.literals,
    required this.variables,
    required this.literalLength,
  });

  factory _McpResourceTemplatePattern.parse(String uriTemplate) {
    Never invalid(String reason) {
      throw ArgumentError.value(
        uriTemplate,
        'uriTemplate',
        'MCP resource templates support simple RFC 6570 Level 1 '
            'expressions only: $reason',
      );
    }

    if (uriTemplate.isEmpty) {
      invalid('the template is empty.');
    }

    final literals = <String>[];
    final variables = <String>[];
    final seenVariables = <String>{};
    var cursor = 0;
    while (cursor < uriTemplate.length) {
      final open = uriTemplate.indexOf('{', cursor);
      final strayClose = uriTemplate.indexOf('}', cursor);
      if (open == -1) {
        if (strayClose != -1) {
          invalid('the template contains an unmatched closing brace.');
        }
        literals.add(uriTemplate.substring(cursor));
        cursor = uriTemplate.length;
        break;
      }
      if (strayClose != -1 && strayClose < open) {
        invalid('the template contains an unmatched closing brace.');
      }

      literals.add(uriTemplate.substring(cursor, open));
      final close = uriTemplate.indexOf('}', open + 1);
      if (close == -1) {
        invalid('the template contains an unmatched opening brace.');
      }
      final variable = uriTemplate.substring(open + 1, close);
      if (variable.contains('{') ||
          !_resourceTemplateVariable.hasMatch(variable)) {
        invalid('"$variable" is not a supported simple variable name.');
      }
      if (!seenVariables.add(variable)) {
        invalid('the variable "$variable" is repeated.');
      }
      variables.add(variable);
      cursor = close + 1;
    }
    if (literals.length == variables.length) {
      literals.add('');
    }

    for (var index = 1; index < literals.length - 1; index += 1) {
      if (literals[index].isEmpty) {
        invalid('adjacent variable expressions are ambiguous.');
      }
    }
    for (var index = 1; index < literals.length - 1; index += 1) {
      final literal = literals[index];
      if (literal.isNotEmpty &&
          _isResourceTemplateExpansionCodeUnit(literal.codeUnitAt(0))) {
        invalid(
          'a literal following a variable must begin with a reserved '
          'delimiter.',
        );
      }
    }

    final sampleUri = StringBuffer();
    for (var index = 0; index < variables.length; index += 1) {
      sampleUri
        ..write(literals[index])
        ..write('x');
    }
    sampleUri.write(literals.last);
    _validateResourceUri(sampleUri.toString(), 'uriTemplate');

    return _McpResourceTemplatePattern(
      literals: List<String>.unmodifiable(literals),
      variables: List<String>.unmodifiable(variables),
      literalLength: literals.fold<int>(
        0,
        (total, part) => total + part.length,
      ),
    );
  }

  final List<String> literals;
  final List<String> variables;
  final int literalLength;

  Map<String, String>? match(String uri) {
    if (variables.isEmpty) {
      return uri == literals.single ? const <String, String>{} : null;
    }

    final values = <String, String>{};
    var cursor = 0;
    for (var index = 0; index < variables.length; index += 1) {
      final literal = literals[index];
      if (!uri.startsWith(literal, cursor)) {
        return null;
      }
      cursor += literal.length;

      final nextLiteral = literals[index + 1];
      final end = nextLiteral.isEmpty
          ? uri.length
          : index == variables.length - 1
          ? uri.lastIndexOf(nextLiteral)
          : uri.indexOf(nextLiteral, cursor);
      if (end < cursor) {
        return null;
      }
      final encodedValue = uri.substring(cursor, end);
      if (!_isResourceTemplateLevelOneExpansion(encodedValue)) {
        return null;
      }
      try {
        values[variables[index]] = Uri.decodeComponent(encodedValue);
      } on FormatException {
        return null;
      }
      cursor = end;
    }

    final trailingLiteral = literals.last;
    if (!uri.startsWith(trailingLiteral, cursor) ||
        cursor + trailingLiteral.length != uri.length) {
      return null;
    }
    return Map<String, String>.unmodifiable(values);
  }
}

final RegExp _resourceTemplateVariable = RegExp(
  r'^[A-Za-z0-9_][A-Za-z0-9_.]*$',
);

bool _isResourceTemplateLevelOneExpansion(String value) {
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (_isResourceTemplateExpansionCodeUnit(codeUnit)) {
      continue;
    }
    if (codeUnit != 0x25 ||
        index + 2 >= value.length ||
        !_isHexCodeUnit(value.codeUnitAt(index + 1)) ||
        !_isHexCodeUnit(value.codeUnitAt(index + 2))) {
      return false;
    }
    index += 2;
  }
  return true;
}

bool _isResourceTemplateExpansionCodeUnit(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    codeUnit == 0x2d ||
    codeUnit == 0x2e ||
    codeUnit == 0x5f ||
    codeUnit == 0x7e;

bool _isHexCodeUnit(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x41 && codeUnit <= 0x46) ||
    (codeUnit >= 0x61 && codeUnit <= 0x66);

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

  Future<List<McpResourceContent>> read(McpResourceRequest request) async {
    final resource = _resources[request.uri];
    if (resource != null) {
      return resource.read(request);
    }

    McpResourceTemplate? selectedTemplate;
    Map<String, String>? selectedVariables;
    for (final template in _templates.values) {
      if (template.read == null) {
        continue;
      }
      final variables = template._matchUri(request.uri);
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

    final template = selectedTemplate;
    final reader = template?.read;
    if (template == null || reader == null || selectedVariables == null) {
      throw McpException(
        McpErrorCodes.resourceNotFound,
        'Resource not found',
        data: <String, Object?>{'uri': request.uri},
      );
    }
    return reader(request, selectedVariables);
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
