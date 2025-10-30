/// Provides storage for implementation-specific fields on WAMP option/detail
/// objects. Keys follow the WAMP convention of starting with an underscore,
/// but this container does not enforce validation so callers can remain
/// interoperable with peers that use legacy key formats.
mixin CustomFieldContainer {
  /// Arbitrary implementation-specific fields that should be forwarded over
  /// the wire when serializing WAMP options/details.
  final Map<String, dynamic> custom = <String, dynamic>{};

  /// Assigns [value] to the custom field [key]. Existing values are replaced.
  void setCustomField(String key, dynamic value) {
    custom[key] = value;
  }

  /// Removes a previously assigned custom field.
  void removeCustomField(String key) {
    custom.remove(key);
  }
}
