import 'dart:core';

class UriPattern {
  static final Pattern REGULAR_PATTERN = RegExp(r'^([^\s\.#]+\.)*([^\s\.#]+)$');
  static final Pattern WILDCARD_PATTERN =
      RegExp(r'^(([^\s\.#]+\.)|\.)*([^\s\.#]+)?$');

  static bool match(String uri) {
    return REGULAR_PATTERN.allMatches(uri).isNotEmpty;
  }

  static bool matchWildcard(String uri) {
    return WILDCARD_PATTERN.allMatches(uri).isNotEmpty;
  }
}
