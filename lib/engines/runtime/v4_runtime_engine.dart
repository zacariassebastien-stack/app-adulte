import 'dart:math';

import '../../domain/catalog/v4_catalog.dart';
import '../../domain/game/game_models.dart';
import '../deck/session_deck_builder.dart';

enum V4SessionMode { presentiel, distance, hybrid }

enum V4TurnPhase {
  boundary,
  selection,
  commit,
  negotiation,
  resolution,
  actionInProgress,
  ended,
}

enum V4CycleAvailability { continueCurrent, switchHybridContext, endCommon }

final class V4CycleGuard {
  const V4CycleGuard();

  V4CycleAvailability evaluate({
    required V4SessionMode mode,
    required Map<String, int> activeOccurrencesByPlayer,
    Map<String, int> alternateContextOccurrencesByPlayer = const {},
  }) {
    final firstEmpty = activeOccurrencesByPlayer.entries
        .where((entry) => entry.value <= 0)
        .firstOrNull;
    if (firstEmpty == null) return V4CycleAvailability.continueCurrent;
    if (mode == V4SessionMode.hybrid &&
        (alternateContextOccurrencesByPlayer[firstEmpty.key] ?? 0) > 0) {
      return V4CycleAvailability.switchHybridContext;
    }
    return V4CycleAvailability.endCommon;
  }
}

final class V4ActionCompletionGate {
  V4ActionCompletionGate({this.completed = false});

  bool completed;

  /// Returns true only for the first completion message, independently of
  /// which player sent it.
  bool complete() {
    if (completed) return false;
    completed = true;
    return true;
  }
}

final class V4ContinuationState {
  V4ContinuationState({
    required Map<String, int> clothingCounts,
    required this.accessoryPool,
    required this.presence,
    required List<V4PersistentEffect> effects,
    required this.unlockedSpice,
    required Set<String> consumedOccurrenceIds,
    this.cycle = 1,
  }) : clothingCounts = Map.unmodifiable(clothingCounts),
       effects = List.unmodifiable(effects),
       consumedOccurrenceIds = Set.unmodifiable(consumedOccurrenceIds);

  final Map<String, int> clothingCounts;
  final V4SessionAccessoryPool accessoryPool;
  final V4SessionPresence presence;
  final List<V4PersistentEffect> effects;
  final int unlockedSpice;
  final Set<String> consumedOccurrenceIds;
  final int cycle;

  V4ContinuationState nextCycle() => V4ContinuationState(
    clothingCounts: clothingCounts,
    accessoryPool: accessoryPool,
    presence: presence,
    effects: effects,
    unlockedSpice: unlockedSpice,
    consumedOccurrenceIds: const {},
    cycle: cycle + 1,
  );

  static V4ContinuationState newCustomizedGame({
    V4SessionPresence presence = V4SessionPresence.presentiel,
  }) => V4ContinuationState(
    clothingCounts: const {},
    accessoryPool: V4SessionAccessoryPool(profileAccessories: const []),
    presence: presence,
    effects: const [],
    unlockedSpice: 1,
    consumedOccurrenceIds: const {},
  );
}

final class V4TurnContext {
  const V4TurnContext({
    required this.mode,
    required this.presence,
    this.phase = V4TurnPhase.boundary,
  });

  final V4SessionMode mode;
  final V4SessionPresence presence;
  final V4TurnPhase phase;

  bool get canChangePresence =>
      mode == V4SessionMode.hybrid && phase == V4TurnPhase.boundary;

  V4TurnContext startTurn() => V4TurnContext(
    mode: mode,
    presence: _fixedPresence(mode, presence),
    phase: V4TurnPhase.selection,
  );

  V4TurnContext enter(V4TurnPhase value) =>
      V4TurnContext(mode: mode, presence: presence, phase: value);

  V4TurnContext changePresence(V4SessionPresence value) {
    if (!canChangePresence) {
      throw StateError('Presence can only change at a HYBRID round boundary');
    }
    return V4TurnContext(mode: mode, presence: value, phase: phase);
  }

  static V4SessionPresence _fixedPresence(
    V4SessionMode mode,
    V4SessionPresence requested,
  ) => switch (mode) {
    V4SessionMode.presentiel => V4SessionPresence.presentiel,
    V4SessionMode.distance => V4SessionPresence.distance,
    V4SessionMode.hybrid => requested,
  };
}

enum V4OccurrenceStatus { pool, hand, reserved, consumed }

final class V4OccurrenceLedger {
  V4OccurrenceLedger([Map<String, V4OccurrenceStatus> values = const {}])
    : _values = Map.of(values);

  final Map<String, V4OccurrenceStatus> _values;

  Map<String, V4OccurrenceStatus> get values => Map.unmodifiable(_values);

  V4OccurrenceStatus statusOf(String occurrenceId) =>
      _values[occurrenceId] ?? V4OccurrenceStatus.pool;

  bool moveToHand(String occurrenceId) => _transition(
    occurrenceId,
    V4OccurrenceStatus.pool,
    V4OccurrenceStatus.hand,
  );

  bool reserve(String occurrenceId) {
    final status = statusOf(occurrenceId);
    if (status == V4OccurrenceStatus.reserved) return true;
    return _transition(
      occurrenceId,
      V4OccurrenceStatus.hand,
      V4OccurrenceStatus.reserved,
    );
  }

  bool cancelReservation(String occurrenceId) {
    final status = statusOf(occurrenceId);
    if (status == V4OccurrenceStatus.hand) return true;
    return _transition(
      occurrenceId,
      V4OccurrenceStatus.reserved,
      V4OccurrenceStatus.hand,
    );
  }

  bool consume(String occurrenceId) {
    final status = statusOf(occurrenceId);
    if (status == V4OccurrenceStatus.consumed) return false;
    return _transition(
      occurrenceId,
      V4OccurrenceStatus.reserved,
      V4OccurrenceStatus.consumed,
    );
  }

  bool _transition(
    String id,
    V4OccurrenceStatus expected,
    V4OccurrenceStatus next,
  ) {
    if (statusOf(id) != expected) return false;
    _values[id] = next;
    return true;
  }
}

final class V4ResolvedParameters {
  const V4ResolvedParameters({
    this.zoneSelectionSource = V4ZoneSelectionSource.none,
    this.sexualOrIntimateZone = false,
    this.zoneId,
    this.accessoryId,
  });

  final V4ZoneSelectionSource zoneSelectionSource;
  final bool sexualOrIntimateZone;
  final String? zoneId;
  final String? accessoryId;

  int effectiveSpice(int baseSpice) => v4EffectiveChiliLevel(
    baseChiliLevel: baseSpice,
    zoneSelectionSource: zoneSelectionSource,
    sexualOrIntimateZone: sexualOrIntimateZone,
  );

  Map<String, Object?> toJson() => {
    'zone_selection_source': zoneSelectionSource.name,
    'sexual_or_intimate_zone': sexualOrIntimateZone,
    'zone_id': zoneId,
    'accessory_id': accessoryId,
  };

  factory V4ResolvedParameters.fromJson(Map<String, Object?> json) =>
      V4ResolvedParameters(
        zoneSelectionSource: V4ZoneSelectionSource.values.byName(
          (json['zone_selection_source'] as String?) ?? 'none',
        ),
        sexualOrIntimateZone:
            (json['sexual_or_intimate_zone'] as bool?) ?? false,
        zoneId: json['zone_id'] as String?,
        accessoryId: json['accessory_id'] as String?,
      );
}

final class V4CatalogParameterResolver {
  const V4CatalogParameterResolver();

  V4ResolvedParameters resolve({
    required V4ScoringCatalog catalog,
    required String cardId,
    required String variantId,
    required V4ResolvedParameters current,
  }) {
    final card = catalog.cards
        .where((item) => item.cardId == cardId)
        .firstOrNull;
    final variant = card?.variants
        .where((item) => item.variantId == variantId)
        .firstOrNull;
    if (variant?.scope.trim().toLowerCase() !=
        'chaque zone intime compatible') {
      return current;
    }
    return V4ResolvedParameters(
      zoneSelectionSource: V4ZoneSelectionSource.game,
      sexualOrIntimateZone: true,
      zoneId: current.zoneId ?? 'zone.intime',
      accessoryId: current.accessoryId,
    );
  }
}

final class V4PlayableOccurrence {
  const V4PlayableOccurrence({
    required this.candidate,
    required this.parameters,
    required this.playable,
    this.locked = false,
  });

  final DeckCandidateV3 candidate;
  final V4ResolvedParameters parameters;
  final bool playable;
  final bool locked;
}

/// Replaces one locked hand entry only when this is required to avoid a
/// soft-lock. Selection is uniform and never reads a PA value.
final class V4PlayableHandGuard {
  const V4PlayableHandGuard();

  List<V4PlayableOccurrence> ensurePlayable({
    required List<V4PlayableOccurrence> hand,
    required List<V4PlayableOccurrence> availablePool,
    required Random random,
  }) {
    if (hand.any((item) => item.playable)) return List.unmodifiable(hand);
    final candidates = availablePool.where((item) => item.playable).toList();
    if (candidates.isEmpty) return List.unmodifiable(hand);
    final replacement = candidates[random.nextInt(candidates.length)];
    if (hand.isEmpty) return [replacement];
    var replaceIndex = hand.indexWhere((item) => item.locked && !item.playable);
    if (replaceIndex < 0) {
      replaceIndex = hand.indexWhere((item) => !item.playable);
    }
    if (replaceIndex < 0) return List.unmodifiable(hand);
    return List.unmodifiable([
      for (final (index, item) in hand.indexed)
        if (index == replaceIndex) replacement else item,
    ]);
  }
}

final class V4ClothingCounter {
  V4ClothingCounter(Map<String, int> counts)
    : _counts = {
        for (final entry in counts.entries) entry.key: max(0, entry.value),
      };

  final Map<String, int> _counts;

  Map<String, int> get counts => Map.unmodifiable(_counts);
  int countFor(String playerId) => _counts[playerId] ?? 0;

  int remove(String playerId, int amount) {
    if (amount < 0) throw ArgumentError.value(amount, 'amount');
    final next = max(0, countFor(playerId) - amount);
    _counts[playerId] = next;
    return next;
  }

  void resynchronize(String playerId, int actualCount) {
    if (actualCount < 0) {
      throw ArgumentError.value(actualCount, 'actualCount');
    }
    _counts[playerId] = actualCount;
  }
}

final class V4PersistentEffect {
  const V4PersistentEffect({
    required this.cardId,
    required this.targetPlayerId,
    required this.remainingActions,
  });

  final String cardId;
  final String targetPlayerId;
  final int remainingActions;
  String get identity => '$cardId::$targetPlayerId';

  V4PersistentEffect withRemaining(int value) => V4PersistentEffect(
    cardId: cardId,
    targetPlayerId: targetPlayerId,
    remainingActions: value,
  );

  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'target_player_id': targetPlayerId,
    'remaining_actions': remainingActions,
  };

  factory V4PersistentEffect.fromJson(Map<String, Object?> json) =>
      V4PersistentEffect(
        cardId: json['card_id']! as String,
        targetPlayerId: json['target_player_id']! as String,
        remainingActions: json['remaining_actions']! as int,
      );
}

final class V4PersistentEffectEngine {
  const V4PersistentEffectEngine();

  List<V4PersistentEffect> createForAction({
    required String cardId,
    required Iterable<String> targetPlayerIds,
    required int durationActions,
  }) => List.unmodifiable([
    for (final targetPlayerId in targetPlayerIds)
      V4PersistentEffect(
        cardId: cardId,
        targetPlayerId: targetPlayerId,
        remainingActions: durationActions,
      ),
  ]);

  List<V4PersistentEffect> closeAction({
    required Iterable<V4PersistentEffect> activeBeforeAction,
    V4PersistentEffect? producedEffect,
    Iterable<V4PersistentEffect> producedEffects = const [],
  }) {
    final next = <String, V4PersistentEffect>{};
    for (final effect in activeBeforeAction) {
      final remaining = effect.remainingActions - 1;
      if (remaining > 0) {
        next[effect.identity] = effect.withRemaining(remaining);
      }
    }
    if (producedEffect != null) {
      next[producedEffect.identity] = producedEffect;
    }
    for (final effect in producedEffects) {
      next[effect.identity] = effect;
    }
    return List.unmodifiable(next.values);
  }
}

final class V4ActionTargetResolver {
  const V4ActionTargetResolver();

  List<String> resolve({
    required String ownerPlayerId,
    required Iterable<String> playerIds,
    required CardOccurrenceDirection direction,
  }) {
    final players = playerIds.toList(growable: false);
    final partnerId = players.firstWhere(
      (id) => id != ownerPlayerId,
      orElse: () => ownerPlayerId,
    );
    return List.unmodifiable(switch (direction) {
      CardOccurrenceDirection.FAIRE => [partnerId],
      CardOccurrenceDirection.RECEVOIR ||
      CardOccurrenceDirection.SOLO => [ownerPlayerId],
      CardOccurrenceDirection.MUTUEL ||
      CardOccurrenceDirection.SIMULTANE ||
      CardOccurrenceDirection.GENERAL => players,
    });
  }
}

enum V4AccessoryTag { anal, vaginal, buccal, phallus, externe, vibrant }

final class V4AccessoryRequirements {
  V4AccessoryRequirements._({
    required this.requiredTags,
    required this.requiresAccessory,
    required this.requiresRemoteControl,
    required this.supported,
  });

  factory V4AccessoryRequirements.fromTokens(Iterable<String> tokens) {
    final tags = <V4AccessoryTag>{};
    var requiresAccessory = false;
    var requiresRemoteControl = false;
    var supported = true;
    for (final raw in tokens) {
      switch (raw.toUpperCase()) {
        case 'SEXTOY':
          requiresAccessory = true;
        case 'VIBRANT' || 'VIBRATING_TOY':
          requiresAccessory = true;
          tags.add(V4AccessoryTag.vibrant);
        case 'REMOTE_CONTROL_TOY':
          requiresAccessory = true;
          requiresRemoteControl = true;
        case 'ANAL':
          requiresAccessory = true;
          tags.add(V4AccessoryTag.anal);
        case 'VAGINAL':
          requiresAccessory = true;
          tags.add(V4AccessoryTag.vaginal);
        case 'BUCCAL':
          requiresAccessory = true;
          tags.add(V4AccessoryTag.buccal);
        case 'PHALLUS':
          requiresAccessory = true;
          tags.add(V4AccessoryTag.phallus);
        case 'EXTERNE':
          requiresAccessory = true;
          tags.add(V4AccessoryTag.externe);
        default:
          supported = false;
      }
    }
    return V4AccessoryRequirements._(
      requiredTags: Set.unmodifiable(tags),
      requiresAccessory: requiresAccessory,
      requiresRemoteControl: requiresRemoteControl,
      supported: supported,
    );
  }

  final Set<V4AccessoryTag> requiredTags;
  final bool requiresAccessory;
  final bool requiresRemoteControl;
  final bool supported;

  bool accepts(V4Accessory accessory) =>
      supported &&
      (!requiresAccessory || accessory.supports(requiredTags)) &&
      (!requiresRemoteControl || accessory.remoteControllable);
}

final class V4Accessory {
  V4Accessory({
    required this.id,
    required this.name,
    required this.ownerPlayerId,
    required Set<V4AccessoryTag> tags,
    this.normallyActive = true,
    this.temporary = false,
    this.remoteControllable = false,
  }) : tags = Set.unmodifiable(tags);

  final String id;
  final String name;
  final String ownerPlayerId;
  final Set<V4AccessoryTag> tags;
  final bool normallyActive;
  final bool temporary;
  final bool remoteControllable;

  bool supports(Set<V4AccessoryTag> required) => required.every(tags.contains);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'owner_player_id': ownerPlayerId,
    'tags': tags.map((tag) => tag.name).toList()..sort(),
    'normally_active': normallyActive,
    'temporary': temporary,
    'remote_controllable': remoteControllable,
  };

  factory V4Accessory.fromJson(Map<String, Object?> json) => V4Accessory(
    id: json['id']! as String,
    name: json['name']! as String,
    ownerPlayerId: json['owner_player_id']! as String,
    tags: {
      for (final value in json['tags']! as List)
        V4AccessoryTag.values.byName(value! as String),
    },
    normallyActive: (json['normally_active'] as bool?) ?? true,
    temporary: (json['temporary'] as bool?) ?? false,
    remoteControllable: (json['remote_controllable'] as bool?) ?? false,
  );
}

final class V4SessionAccessoryPool {
  V4SessionAccessoryPool({
    required Iterable<V4Accessory> profileAccessories,
    Iterable<String> disabledIds = const [],
    Iterable<V4Accessory> temporaryAccessories = const [],
  }) : _profileAccessories = List.unmodifiable(profileAccessories),
       _disabledIds = Set.unmodifiable(disabledIds),
       _temporaryAccessories = List.unmodifiable(temporaryAccessories);

  final List<V4Accessory> _profileAccessories;
  final Set<String> _disabledIds;
  final List<V4Accessory> _temporaryAccessories;

  List<V4Accessory> get available => List.unmodifiable([
    ..._profileAccessories.where(
      (item) => item.normallyActive && !_disabledIds.contains(item.id),
    ),
    ..._temporaryAccessories.where((item) => !_disabledIds.contains(item.id)),
  ]);

  V4Accessory? selectCompatible(Set<V4AccessoryTag> required, Random random) {
    final compatible = available
        .where((item) => item.supports(required))
        .toList();
    if (compatible.isEmpty) return null;
    return compatible[random.nextInt(compatible.length)];
  }

  Map<String, Object?> toJson() => {
    'profile_accessories': [
      for (final item in _profileAccessories) item.toJson(),
    ],
    'disabled_ids': _disabledIds.toList()..sort(),
    'temporary_accessories': [
      for (final item in _temporaryAccessories) item.toJson(),
    ],
  };

  factory V4SessionAccessoryPool.fromJson(
    Map<String, Object?> json,
  ) => V4SessionAccessoryPool(
    profileAccessories: [
      for (final raw in (json['profile_accessories'] as List?) ?? const [])
        V4Accessory.fromJson(Map<String, Object?>.from(raw! as Map)),
    ],
    disabledIds: ((json['disabled_ids'] as List?) ?? const []).cast<String>(),
    temporaryAccessories: [
      for (final raw in (json['temporary_accessories'] as List?) ?? const [])
        V4Accessory.fromJson(Map<String, Object?>.from(raw! as Map)),
    ],
  );
}

final class V4AccessoryPreferenceBook {
  V4AccessoryPreferenceBook([Map<String, double?> values = const {}])
    : _values = Map.of(values);

  final Map<String, double?> _values;

  static String canonicalTagSet(Iterable<V4AccessoryTag> tags) =>
      (tags.map((tag) => tag.name).toList()..sort()).join('+');

  static String key(Iterable<V4AccessoryTag> tags, String role) =>
      '${canonicalTagSet(tags)}|$role';

  double? value(Iterable<V4AccessoryTag> tags, String role) =>
      _values[key(tags, role)] ?? 18;

  bool excluded(Iterable<V4AccessoryTag> tags, String role) =>
      _values.containsKey(key(tags, role)) && _values[key(tags, role)] == null;
}

final class V4PaCalculator {
  const V4PaCalculator();

  int combine(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) throw ArgumentError('At least one PA is required');
    if (list.any((value) => value < 1 || value > 20)) {
      throw RangeError('PA values must be between 1 and 20');
    }
    if (list.length == 1) return list.single.round();
    list.sort();
    final highest = list.removeLast();
    final othersAverage = list.reduce((a, b) => a + b) / list.length;
    return (highest * .5 + othersAverage * .5).round();
  }
}
