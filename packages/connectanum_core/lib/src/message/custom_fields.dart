import 'dart:collection';

/// Lazily materializes string-keyed maps the first time their unresolved
/// contents are accessed.
class LazyStringKeyMap<T> extends MapBase<String, T> {
  LazyStringKeyMap({
    Map<String, T>? initialValues,
    Map<String, T> Function()? loader,
  }) : _values = initialValues == null
           ? <String, T>{}
           : Map<String, T>.from(initialValues),
       _loader = loader;

  final Map<String, T> _values;
  Map<String, T> Function()? _loader;

  bool get hasPendingLoader => _loader != null;

  void attachLoader(Map<String, T> Function() loader) {
    final previousLoader = _loader;
    if (previousLoader == null) {
      _loader = loader;
      return;
    }
    _loader = () {
      final merged = <String, T>{}
        ..addAll(previousLoader())
        ..addAll(loader());
      return merged;
    };
  }

  void _ensureLoaded() {
    final loader = _loader;
    if (loader == null) {
      return;
    }
    _loader = null;
    final loaded = loader();
    for (final entry in loaded.entries) {
      _values.putIfAbsent(entry.key, () => entry.value);
    }
  }

  @override
  T? operator [](Object? key) {
    if (_values.containsKey(key)) {
      return _values[key];
    }
    _ensureLoaded();
    return _values[key];
  }

  @override
  void operator []=(String key, T value) {
    _values[key] = value;
  }

  @override
  void clear() {
    _ensureLoaded();
    _values.clear();
  }

  @override
  Iterable<String> get keys {
    _ensureLoaded();
    return _values.keys;
  }

  @override
  T? remove(Object? key) {
    if (_values.containsKey(key)) {
      return _values.remove(key);
    }
    _ensureLoaded();
    return _values.remove(key);
  }
}

void attachLazyStringKeyMapLoader<T>(
  Map<String, T> map,
  Map<String, T> Function() loader,
) {
  if (map case LazyStringKeyMap<T> lazyMap) {
    lazyMap.attachLoader(loader);
    return;
  }
  map.addAll(loader());
}

Map<String, T> lazyStringKeyMap<T>({
  Map<String, T>? initialValues,
  Map<String, T> Function()? loader,
}) => LazyStringKeyMap<T>(initialValues: initialValues, loader: loader);

/// Provides storage for implementation-specific fields on WAMP option/detail
/// objects. Keys follow the WAMP convention of starting with an underscore,
/// but this container does not enforce validation so callers can remain
/// interoperable with peers that use legacy key formats.
mixin CustomFieldContainer {
  /// Arbitrary implementation-specific fields that should be forwarded over
  /// the wire when serializing WAMP options/details.
  final Map<String, dynamic> custom = LazyStringKeyMap<dynamic>();

  void setLazyCustomFieldsLoader(Map<String, dynamic> Function() loader) {
    attachLazyStringKeyMapLoader(custom, loader);
  }

  /// Assigns [value] to the custom field [key]. Existing values are replaced.
  void setCustomField(String key, dynamic value) {
    custom[key] = value;
  }

  /// Removes a previously assigned custom field.
  void removeCustomField(String key) {
    custom.remove(key);
  }
}
