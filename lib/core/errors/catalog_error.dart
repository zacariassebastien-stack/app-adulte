/// Machine-readable diagnostics never depend on localized display text.
final class CatalogIssue {
  const CatalogIssue({
    required this.code,
    required this.objectType,
    required this.stableId,
    required this.property,
    required this.message,
  });
  final String code;
  final String objectType;
  final String stableId;
  final String property;
  final String message;
  Map<String, Object?> toJson() => {
    'code': code,
    'object_type': objectType,
    'stable_id': stableId,
    'property': property,
    'message': message,
  };
  @override
  String toString() => '$code: $objectType [$stableId] $property: $message';
}

final class CatalogException implements Exception {
  CatalogException(Iterable<CatalogIssue> issues)
    : issues = List.unmodifiable(issues);
  final List<CatalogIssue> issues;
  @override
  String toString() => issues.join('\n');
}
