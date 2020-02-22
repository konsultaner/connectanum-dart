import 'dart:core';

class UriPattern {
  static final Pattern REGULAR_PATTERN = RegExp(r"^([^\s\.#]+\.)*([^\s\.#]+)$");
  static final Pattern WILDCARD_PATTERN =
      RegExp(r"^(([^\s\.#]+\.)|\.)*([^\s\.#]+)?$");

  static match(String uri) {
    return REGULAR_PATTERN.allMatches(uri).length > 0;
  }

  static matchWildcard(String uri) {
    return WILDCARD_PATTERN.allMatches(uri).length > 0;
  }
}
