import 'dart:core';

class UriPattern {
  static final Pattern REGULAR_PATTERN = RegExp(r'^([^\s\.#]+\.)*([^\s\.#]+)$');
  static final Pattern WILDCARD_PATTERN =
      RegExp(r'^(([^\s\.#]+\.)|\.)*([^\s\.#]+)?$');

  /// Test if a given [uri] matches a regular uri pattern
  static bool match(String uri) {
    return REGULAR_PATTERN.allMatches(uri).isNotEmpty;
  }

  /// Test if a given [uri] matches a regular wildcard uri
  static bool matchWildcard(String uri) {
    return WILDCARD_PATTERN.allMatches(uri).isNotEmpty;
  }
}
