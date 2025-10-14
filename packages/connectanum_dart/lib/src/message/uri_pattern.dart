import 'dart:core';

class UriPattern {
  static final Pattern regularPattern = RegExp(r'^([^\s.#]+\.)*([^\s.#]+)$');
  static final Pattern wildcardPattern =
      RegExp(r'^(([^\s.#]+\.)|\.)*([^\s.#]+)?$');

  /// Test if a given [uri] matches a regular uri pattern
  static bool match(String uri) {
    return regularPattern.allMatches(uri).isNotEmpty;
  }

  /// Test if a given [uri] matches a regular wildcard uri
  static bool matchWildcard(String uri) {
    return wildcardPattern.allMatches(uri).isNotEmpty;
  }
}
