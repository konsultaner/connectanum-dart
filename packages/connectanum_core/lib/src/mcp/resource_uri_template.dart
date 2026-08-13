import 'dart:convert';

import 'text_validation.dart';

final RegExp _mcpResourceTemplateVariable = RegExp(
  r'^[A-Za-z0-9_][A-Za-z0-9_.]*$',
);

/// A bounded RFC 6570 Level 1 template for an MCP resource URI.
///
/// Only simple `{variable}` expressions are supported. Expansion accepts
/// decoded variable values and percent-encodes every byte outside the RFC 3986
/// unreserved set. Matching performs the inverse operation and returns decoded
/// values.
final class McpResourceUriTemplate {
  factory McpResourceUriTemplate(String template) {
    Never invalid(String reason) {
      throw ArgumentError.value(
        template,
        'template',
        'MCP resource URI templates support simple RFC 6570 Level 1 '
            'expressions only: $reason',
      );
    }

    if (template.isEmpty) {
      invalid('the template is empty.');
    }

    final literals = <String>[];
    final variables = <String>[];
    final seenVariables = <String>{};
    var cursor = 0;
    while (cursor < template.length) {
      final open = template.indexOf('{', cursor);
      final strayClose = template.indexOf('}', cursor);
      if (open == -1) {
        if (strayClose != -1) {
          invalid('the template contains an unmatched closing brace.');
        }
        literals.add(template.substring(cursor));
        cursor = template.length;
        break;
      }
      if (strayClose != -1 && strayClose < open) {
        invalid('the template contains an unmatched closing brace.');
      }

      literals.add(template.substring(cursor, open));
      final close = template.indexOf('}', open + 1);
      if (close == -1) {
        invalid('the template contains an unmatched opening brace.');
      }
      final variable = template.substring(open + 1, close);
      if (variable.contains('{') ||
          !_mcpResourceTemplateVariable.hasMatch(variable)) {
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
          _isMcpResourceTemplateExpansionByte(literal.codeUnitAt(0))) {
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
    final sample = sampleUri.toString();
    if (containsMcpWhitespaceOrControl(sample) ||
        Uri.tryParse(sample)?.hasScheme != true) {
      invalid('the expanded value must be an absolute URI with a scheme.');
    }

    return McpResourceUriTemplate._(
      template: template,
      literals: List<String>.unmodifiable(literals),
      variables: List<String>.unmodifiable(variables),
      literalLength: literals.fold<int>(
        0,
        (total, part) => total + part.length,
      ),
    );
  }

  const McpResourceUriTemplate._({
    required this.template,
    required List<String> literals,
    required this.variables,
    required this.literalLength,
  }) : _literals = literals;

  /// The original advertised URI-template string.
  final String template;

  /// Declared variables in template order.
  final List<String> variables;

  /// The total literal length used for deterministic match specificity.
  final int literalLength;

  final List<String> _literals;

  /// Expands decoded [values] into an absolute resource URI.
  ///
  /// Every declared variable must be present. Additional entries are ignored.
  String expand(Map<String, String> values) {
    final expanded = StringBuffer();
    for (var index = 0; index < variables.length; index += 1) {
      final variable = variables[index];
      if (!values.containsKey(variable)) {
        throw ArgumentError(
          'MCP resource URI template variable "$variable" is required.',
          'variables',
        );
      }
      expanded
        ..write(_literals[index])
        ..write(_encodeMcpResourceTemplateValue(values[variable]!));
    }
    expanded.write(_literals.last);
    return expanded.toString();
  }

  /// Matches a concrete [uri] and returns decoded variables, or `null`.
  Map<String, String>? match(String uri) {
    if (variables.isEmpty) {
      return uri == _literals.single ? const <String, String>{} : null;
    }

    final values = <String, String>{};
    var cursor = 0;
    for (var index = 0; index < variables.length; index += 1) {
      final literal = _literals[index];
      if (!uri.startsWith(literal, cursor)) {
        return null;
      }
      cursor += literal.length;

      final nextLiteral = _literals[index + 1];
      final end = nextLiteral.isEmpty
          ? uri.length
          : index == variables.length - 1
          ? uri.lastIndexOf(nextLiteral)
          : uri.indexOf(nextLiteral, cursor);
      if (end < cursor) {
        return null;
      }
      final encodedValue = uri.substring(cursor, end);
      if (!_isMcpResourceTemplateLevelOneExpansion(encodedValue)) {
        return null;
      }
      try {
        values[variables[index]] = Uri.decodeComponent(encodedValue);
      } on FormatException {
        return null;
      }
      cursor = end;
    }

    final trailingLiteral = _literals.last;
    if (!uri.startsWith(trailingLiteral, cursor) ||
        cursor + trailingLiteral.length != uri.length) {
      return null;
    }
    return Map<String, String>.unmodifiable(values);
  }

  @override
  String toString() => template;
}

String _encodeMcpResourceTemplateValue(String value) {
  final encoded = StringBuffer();
  for (final byte in utf8.encode(value)) {
    if (_isMcpResourceTemplateExpansionByte(byte)) {
      encoded.writeCharCode(byte);
    } else {
      encoded
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return encoded.toString();
}

bool _isMcpResourceTemplateLevelOneExpansion(String value) {
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (_isMcpResourceTemplateExpansionByte(codeUnit)) {
      continue;
    }
    if (codeUnit != 0x25 ||
        index + 2 >= value.length ||
        !_isMcpResourceTemplateHexByte(value.codeUnitAt(index + 1)) ||
        !_isMcpResourceTemplateHexByte(value.codeUnitAt(index + 2))) {
      return false;
    }
    index += 2;
  }
  return true;
}

bool _isMcpResourceTemplateExpansionByte(int byte) =>
    (byte >= 0x41 && byte <= 0x5a) ||
    (byte >= 0x61 && byte <= 0x7a) ||
    (byte >= 0x30 && byte <= 0x39) ||
    byte == 0x2d ||
    byte == 0x2e ||
    byte == 0x5f ||
    byte == 0x7e;

bool _isMcpResourceTemplateHexByte(int byte) =>
    (byte >= 0x30 && byte <= 0x39) ||
    (byte >= 0x41 && byte <= 0x46) ||
    (byte >= 0x61 && byte <= 0x66);
