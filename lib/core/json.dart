import 'errors/catalog_error.dart';

typedef JsonMap = Map<String, Object?>;

Object? freezeJson(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map((k, v) => MapEntry(k, freezeJson(v))),
    );
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(freezeJson));
  }
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw ArgumentError('Not a JSON value');
}

/// Reader used by every model so malformed input never leaks a CastError.
final class JsonReader {
  JsonReader(JsonMap json, this.objectType, {String? ownerId, this.path = ''})
    : json = freezeJson(json)! as JsonMap,
      stableId = json['stable_id'] is String
          ? json['stable_id']! as String
          : ownerId ?? '<missing>';
  final JsonMap json;
  final String objectType;
  final String stableId;
  final String path;
  Never fail(String key, String message, {String code = 'invalid_value'}) =>
      throw CatalogException([
        CatalogIssue(
          code: code,
          objectType: objectType,
          stableId: stableId,
          property: path.isEmpty ? key : '$path.$key',
          message: message,
        ),
      ]);
  String string(String key, {bool optional = false}) {
    final value = json[key];
    if (optional && value == null) return '';
    if (value is! String || value.trim().isEmpty) {
      fail(key, 'Expected non-empty string');
    }
    return value;
  }

  String? optionalString(String key) => json[key] == null ? null : string(key);
  int integer(String key, {int? fallback, int? min, int? max}) {
    final value = json.containsKey(key) ? json[key] : fallback;
    if (value is! int ||
        (min != null && value < min) ||
        (max != null && value > max)) {
      fail(
        key,
        'Expected integer${min == null ? '' : ' >= $min'}${max == null ? '' : ' <= $max'}',
      );
    }
    return value;
  }

  int? optionalInteger(String key, {int? min, int? max}) =>
      json[key] == null ? null : integer(key, min: min, max: max);
  bool boolean(String key, {bool? fallback}) {
    final value = json.containsKey(key) ? json[key] : fallback;
    if (value is! bool) fail(key, 'Expected boolean');
    return value;
  }

  T enumeration<T extends Enum>(String key, List<T> values, {T? fallback}) {
    if (!json.containsKey(key) && fallback != null) return fallback;
    final value = json[key];
    for (final item in values) {
      if (item.name == value) return item;
    }
    fail(key, 'Unknown enum: $value', code: 'unknown_enum');
  }

  List<Object?> list(String key, {bool optional = false}) {
    if (optional && !json.containsKey(key)) return const [];
    final value = json[key];
    if (value is! List<Object?>) fail(key, 'Expected list');
    return value;
  }

  List<String> strings(String key, {bool optional = false}) {
    final values = list(key, optional: optional);
    for (var i = 0; i < values.length; i++) {
      if (values[i] is! String || (values[i]! as String).trim().isEmpty) {
        fail('$key[$i]', 'Expected non-empty string');
      }
    }
    return List.unmodifiable(values.cast<String>());
  }

  List<T> objects<T>(
    String key,
    T Function(JsonReader) parse,
    String type, {
    bool optional = false,
  }) {
    final values = list(key, optional: optional);
    return List.unmodifiable([
      for (var i = 0; i < values.length; i++)
        parse(child(values[i], '$key[$i]', type)),
    ]);
  }

  JsonReader child(Object? value, String key, String type) {
    if (value is! JsonMap) fail(key, 'Expected object');
    return JsonReader(
      value,
      type,
      ownerId: stableId,
      path: path.isEmpty ? key : '$path.$key',
    );
  }

  DateTime dateTime(String key) {
    final raw = string(key);
    final date = DateTime.tryParse(raw);
    if (date == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
      fail(key, 'Expected ISO-8601 timestamp with timezone');
    }
    return date;
  }

  void only(Set<String> allowed) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        fail(key, 'Unsupported property', code: 'unknown_property');
      }
    }
  }
}

/// Immutable JSON backing preserves optional fields, extension metadata and IDs
/// exactly on round-trip. Subclasses expose typed, validated domain properties.
abstract base class JsonModel {
  JsonModel(this.reader);
  final JsonReader reader;
  JsonMap toJson() => reader.json;
}
