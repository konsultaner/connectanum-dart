class McpIcon {
  const McpIcon({
    required this.src,
    this.mimeType,
    this.sizes = const <String>[],
    this.theme,
  });

  final String src;
  final String? mimeType;
  final List<String> sizes;
  final McpIconTheme? theme;

  Map<String, Object?> toJson() {
    _validateIconSource(src);
    final mimeType = this.mimeType;
    if (mimeType != null && mimeType.isEmpty) {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'MCP icon MIME type must be non-empty when provided.',
      );
    }
    for (final size in sizes) {
      if (size.isEmpty) {
        throw ArgumentError.value(
          size,
          'sizes',
          'MCP icon sizes must be non-empty strings.',
        );
      }
    }
    final theme = this.theme;
    return <String, Object?>{
      'src': src,
      'mimeType': ?mimeType,
      if (sizes.isNotEmpty) 'sizes': sizes,
      'theme': ?theme?.name,
    };
  }
}

enum McpIconTheme { light, dark }

void addMcpIconsToJson(Map<String, Object?> json, Iterable<McpIcon> icons) {
  final values = icons.toList(growable: false);
  if (values.isNotEmpty) {
    json['icons'] = [for (final icon in values) icon.toJson()];
  }
}

void _validateIconSource(String source) {
  final parsed = Uri.tryParse(source);
  if (source.isEmpty || parsed == null || !parsed.hasScheme) {
    throw ArgumentError.value(
      source,
      'src',
      'MCP icon source must be an absolute URI.',
    );
  }
  switch (parsed.scheme) {
    case 'data':
    case 'http':
    case 'https':
      return;
    default:
      throw ArgumentError.value(
        source,
        'src',
        'MCP icon source must use http, https, or data URI schemes.',
      );
  }
}
