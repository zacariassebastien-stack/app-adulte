// Validated compatibility contract. No inventory or inferred tags are supplied.
// ignore_for_file: constant_identifier_names
enum AccessoryCompatibilityTag {
  ANAL,
  VAGINAL,
  BUCCAL,
  PHALLUS,
  EXTERNE,
  VIBRANT,
}

final class TaggedSessionAccessory {
  TaggedSessionAccessory({
    required this.id,
    required this.label,
    required this.ownerPlayerId,
    required Set<AccessoryCompatibilityTag> tags,
  }) : tags = Set.unmodifiable(tags);
  final String id, label, ownerPlayerId;
  final Set<AccessoryCompatibilityTag> tags;

  /// All tags must be satisfied by this same accessory. Ownership is irrelevant.
  bool supports(Set<AccessoryCompatibilityTag> requiredTags) =>
      tags.containsAll(requiredTags);

  /// Accessory preferences identify the exact set, not a subset or a name.
  String get preferenceTagSet =>
      (tags.map((t) => t.name).toList()..sort()).join('+');
}

Set<AccessoryCompatibilityTag> requiredAccessoryTags(
  String conceptId,
  String actionId,
) {
  if (!{'049', '050', '051', '052'}.contains(conceptId) ||
      !actionId.startsWith('$conceptId.')) {
    throw ArgumentError('Not a sextoy action');
  }
  final usage = actionId.substring(conceptId.length + 1);
  final tag = switch (usage) {
    'external' => AccessoryCompatibilityTag.EXTERNE,
    'phallus' => AccessoryCompatibilityTag.PHALLUS,
    'vaginal_insertion' => AccessoryCompatibilityTag.VAGINAL,
    'anal_insertion' => AccessoryCompatibilityTag.ANAL,
    _ => throw ArgumentError('Unknown sextoy usage'),
  };
  return Set.unmodifiable({
    tag,
    if (conceptId == '052') AccessoryCompatibilityTag.VIBRANT,
  });
}
