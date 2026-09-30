// The explicit non-nullable constructor argument is clearer than the nullable
// initializing formal suggested by this lint.
// ignore_for_file: prefer_initializing_formals

import '../../core/json.dart';

enum V3ClothingDeltaKind { fixed, askPlayer }

final class V3ClothingDelta {
  const V3ClothingDelta.fixed(int value)
    : kind = V3ClothingDeltaKind.fixed,
      value = value;
  const V3ClothingDelta.askPlayer()
    : kind = V3ClothingDeltaKind.askPlayer,
      value = null;

  final V3ClothingDeltaKind kind;
  final int? value;

  factory V3ClothingDelta.fromJson(Object value) {
    if (value == 'ASK_PLAYER') return const V3ClothingDelta.askPlayer();
    if (value is int) return V3ClothingDelta.fixed(value);
    throw const FormatException('clothingDelta must be an int or ASK_PLAYER');
  }

  Object toJson() =>
      kind == V3ClothingDeltaKind.askPlayer ? 'ASK_PLAYER' : value!;
}

final class V3Requirements {
  const V3Requirements({
    this.distanceExcluded = false,
    this.requiresVideo = false,
    this.requiresRoleplay = false,
    this.requiresSurpriseParty = false,
    this.requiresSextoy = false,
    this.requiresVibratingToy = false,
    this.requiresRemoteControlToy = false,
    this.requiresConstraintAccessory = false,
    this.requiresOil = false,
    this.requiresLubricant = false,
    this.requiresProtection = false,
    this.requiresFood = false,
    this.requiresDrink = false,
    this.requiresAlcohol = false,
    this.minimumRemovableClothing = 0,
  }) : assert(minimumRemovableClothing >= 0);

  final bool distanceExcluded;
  final bool requiresVideo;
  final bool requiresRoleplay;
  final bool requiresSurpriseParty;
  final bool requiresSextoy;
  final bool requiresVibratingToy;
  final bool requiresRemoteControlToy;
  final bool requiresConstraintAccessory;
  final bool requiresOil;
  final bool requiresLubricant;
  final bool requiresProtection;
  final bool requiresFood;
  final bool requiresDrink;
  final bool requiresAlcohol;
  final int minimumRemovableClothing;

  bool get isDistanceCompatible => !distanceExcluded;

  factory V3Requirements.fromJson(Map<String, Object?> json) => V3Requirements(
    distanceExcluded: json['DISTANCE_EXCLUE'] as bool? ?? false,
    requiresVideo: json['requiresVideo'] as bool? ?? false,
    requiresRoleplay: json['requiresRoleplay'] as bool? ?? false,
    requiresSurpriseParty: json['requiresSurpriseParty'] as bool? ?? false,
    requiresSextoy: json['requiresSextoy'] as bool? ?? false,
    requiresVibratingToy: json['requiresVibratingToy'] as bool? ?? false,
    requiresRemoteControlToy:
        json['requiresRemoteControlToy'] as bool? ?? false,
    requiresConstraintAccessory:
        json['requiresConstraintAccessory'] as bool? ?? false,
    requiresOil: json['requiresOil'] as bool? ?? false,
    requiresLubricant: json['requiresLubricant'] as bool? ?? false,
    requiresProtection: json['requiresProtection'] as bool? ?? false,
    requiresFood: json['requiresFood'] as bool? ?? false,
    requiresDrink: json['requiresDrink'] as bool? ?? false,
    requiresAlcohol: json['requiresAlcohol'] as bool? ?? false,
    minimumRemovableClothing: json['minimumRemovableClothing'] as int? ?? 0,
  );

  Map<String, Object?> toJson() => {
    'DISTANCE_EXCLUE': distanceExcluded,
    'requiresVideo': requiresVideo,
    'requiresRoleplay': requiresRoleplay,
    'requiresSurpriseParty': requiresSurpriseParty,
    'requiresSextoy': requiresSextoy,
    'requiresVibratingToy': requiresVibratingToy,
    'requiresRemoteControlToy': requiresRemoteControlToy,
    'requiresConstraintAccessory': requiresConstraintAccessory,
    'requiresOil': requiresOil,
    'requiresLubricant': requiresLubricant,
    'requiresProtection': requiresProtection,
    'requiresFood': requiresFood,
    'requiresDrink': requiresDrink,
    'requiresAlcohol': requiresAlcohol,
    'minimumRemovableClothing': minimumRemovableClothing,
  };
}

final class V3SessionData {
  const V3SessionData({
    required this.removableClothingInitial,
    required this.removableClothingRemaining,
    required this.roleplayEnabled,
    this.roleplayScenario,
  }) : assert(removableClothingInitial >= 0),
       assert(removableClothingRemaining >= 0),
       assert(removableClothingRemaining <= removableClothingInitial),
       assert(roleplayEnabled || roleplayScenario == null);

  final int removableClothingInitial;
  final int removableClothingRemaining;
  final bool roleplayEnabled;
  final String? roleplayScenario;

  factory V3SessionData.fromJson(Map<String, Object?> json) => V3SessionData(
    removableClothingInitial: json['removableClothingInitial']! as int,
    removableClothingRemaining: json['removableClothingRemaining']! as int,
    roleplayEnabled: json['roleplayEnabled']! as bool,
    roleplayScenario: json['roleplayScenario'] as String?,
  );

  Map<String, Object?> toJson() => {
    'removableClothingInitial': removableClothingInitial,
    'removableClothingRemaining': removableClothingRemaining,
    'roleplayEnabled': roleplayEnabled,
    'roleplayScenario': roleplayScenario,
  };
}

final class V3CardMechanics {
  V3CardMechanics({
    required this.baseEngagementLevel,
    required this.clothingDelta,
    required this.requirements,
  }) {
    if (baseEngagementLevel < 1 || baseEngagementLevel > 5) {
      throw RangeError.range(baseEngagementLevel, 1, 5, 'baseEngagementLevel');
    }
  }

  final int baseEngagementLevel;
  final V3ClothingDelta clothingDelta;
  final V3Requirements requirements;

  int engagementLevelFor(int clothingModifier) => v3EffectiveEngagementLevel(
    baseEngagementLevel: baseEngagementLevel,
    clothingModifier: clothingModifier,
  );
}

/// Explicit, fully resolved V3 editorial data attached to a card or variant.
/// Legacy fields remain available during the staged catalogue migration.
final class V3EditorialData {
  V3EditorialData({
    required this.taxonomyVersion,
    required List<String> tags,
    required this.baseEngagementLevel,
    required this.requirements,
    this.clothingDelta,
    this.mergeCandidateWith,
    this.splitCandidate = false,
    List<String> ambiguities = const [],
  }) : tags = List.unmodifiable(tags),
       ambiguities = List.unmodifiable(ambiguities) {
    if (taxonomyVersion != 1) {
      throw const FormatException('Unsupported V3 taxonomy version');
    }
    if (tags.isEmpty || tags.toSet().length != tags.length) {
      throw const FormatException('V3 tags must be non-empty and unique');
    }
    if (tags.any((tag) => !tag.startsWith('v3.'))) {
      throw const FormatException('V3 tags must use v3 stable IDs');
    }
    if (baseEngagementLevel < 1 || baseEngagementLevel > 5) {
      throw RangeError.range(baseEngagementLevel, 1, 5, 'baseEngagementLevel');
    }
  }

  factory V3EditorialData.fromJson(JsonMap json) => V3EditorialData(
    taxonomyVersion: json['taxonomy_version']! as int,
    tags: (json['tags']! as List).cast<String>(),
    baseEngagementLevel: json['baseEngagementLevel']! as int,
    requirements: V3Requirements.fromJson(
      (json['requirements'] as JsonMap?) ?? const {},
    ),
    clothingDelta: json.containsKey('clothingDelta')
        ? V3ClothingDelta.fromJson(json['clothingDelta']!)
        : null,
    mergeCandidateWith: json['mergeCandidateWith'] as String?,
    splitCandidate: json['splitCandidate'] as bool? ?? false,
    ambiguities:
        (json['ambiguities'] as List?)?.cast<String>() ?? const <String>[],
  );

  final int taxonomyVersion;
  final List<String> tags;
  final int baseEngagementLevel;
  final V3Requirements requirements;
  final V3ClothingDelta? clothingDelta;
  final String? mergeCandidateWith;
  final bool splitCandidate;
  final List<String> ambiguities;
}

int v3EffectiveEngagementLevel({
  required int baseEngagementLevel,
  required int clothingModifier,
}) {
  if (baseEngagementLevel < 1 || baseEngagementLevel > 5) {
    throw RangeError.range(baseEngagementLevel, 1, 5, 'baseEngagementLevel');
  }
  if (baseEngagementLevel >= 4) return baseEngagementLevel;
  return (baseEngagementLevel + clothingModifier).clamp(1, 5);
}
