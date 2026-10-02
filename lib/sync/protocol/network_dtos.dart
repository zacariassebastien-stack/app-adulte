import 'dart:collection';

const networkSchemaVersion = 1;

enum PublicRoundPhase {
  choosing,
  committed,
  revealed,
  auction,
  execution,
  betweenRounds,
  complete,
}

enum ActionPointVisibility { visible, discreet }

final class PublicChoiceDto {
  const PublicChoiceDto({required this.cardId, required this.variantId});

  final String cardId;
  final String variantId;

  Map<String, Object?> toJson() => {'card_id': cardId, 'variant_id': variantId};

  factory PublicChoiceDto.fromJson(Map<String, Object?> json) =>
      PublicChoiceDto(
        cardId: json['card_id']! as String,
        variantId: json['variant_id']! as String,
      );
}

final class PublicResolutionDto {
  const PublicResolutionDto({
    this.winnerPlayerId,
    this.tied = false,
    this.cost,
  });

  final String? winnerPlayerId;
  final bool tied;
  final int? cost;

  Map<String, Object?> toJson() => {
    'winner_player_id': winnerPlayerId,
    'tied': tied,
    'cost': cost,
  };

  factory PublicResolutionDto.fromJson(Map<String, Object?> json) =>
      PublicResolutionDto(
        winnerPlayerId: json['winner_player_id'] as String?,
        tied: json['tied']! as bool,
        cost: json['cost'] as int?,
      );
}

final class PublicAuctionDto {
  const PublicAuctionDto({
    required this.active,
    this.bidderPlayerId,
    this.amount,
    this.target,
  });

  final bool active;
  final String? bidderPlayerId;
  final int? amount;
  final String? target;

  Map<String, Object?> toJson() => {
    'active': active,
    'bidder_player_id': bidderPlayerId,
    'amount': amount,
    'target': target,
  };

  factory PublicAuctionDto.fromJson(Map<String, Object?> json) =>
      PublicAuctionDto(
        active: json['active']! as bool,
        bidderPlayerId: json['bidder_player_id'] as String?,
        amount: json['amount'] as int?,
        target: json['target'] as String?,
      );
}

final class PublicExecutionDto {
  const PublicExecutionDto({
    required this.status,
    this.currentCardId,
    this.completedCount = 0,
  });

  final String status;
  final String? currentCardId;
  final int completedCount;

  Map<String, Object?> toJson() => {
    'status': status,
    'current_card_id': currentCardId,
    'completed_count': completedCount,
  };

  factory PublicExecutionDto.fromJson(Map<String, Object?> json) =>
      PublicExecutionDto(
        status: json['status']! as String,
        currentCardId: json['current_card_id'] as String?,
        completedCount: json['completed_count']! as int,
      );
}

/// Shareable state. Its type deliberately has no hand, preference, personal
/// value, nonce, style or private-profile field.
final class PublicGameStateDto {
  PublicGameStateDto({
    required this.sessionId,
    required this.roundId,
    required this.roundNumber,
    required this.phase,
    required this.proximity,
    required this.chiliActive,
    required this.chiliUnlocked,
    required List<String> playerIds,
    required Map<String, bool> selectionMade,
    Map<String, PublicChoiceDto> revealedChoices = const {},
    Map<String, int> visibleActionPoints = const {},
    this.resolution,
    this.auction,
    this.execution,
  }) : playerIds = List.unmodifiable(playerIds),
       selectionMade = Map.unmodifiable(selectionMade),
       revealedChoices = Map.unmodifiable(revealedChoices),
       visibleActionPoints = Map.unmodifiable(visibleActionPoints);

  final String sessionId;
  final String roundId;
  final int roundNumber;
  final PublicRoundPhase phase;
  final String proximity;
  final int chiliActive;
  final int chiliUnlocked;
  final List<String> playerIds;
  final Map<String, bool> selectionMade;
  final Map<String, PublicChoiceDto> revealedChoices;
  final Map<String, int> visibleActionPoints;
  final PublicResolutionDto? resolution;
  final PublicAuctionDto? auction;
  final PublicExecutionDto? execution;

  Map<String, Object?> toJson() => {
    'schema_version': networkSchemaVersion,
    'session_id': sessionId,
    'round_id': roundId,
    'round_number': roundNumber,
    'phase': phase.name,
    'proximity': proximity,
    'chili_active': chiliActive,
    'chili_unlocked': chiliUnlocked,
    'player_ids': playerIds,
    'selection_made': _sortedMap(selectionMade),
    'revealed_choices': _sortedMap({
      for (final entry in revealedChoices.entries)
        entry.key: entry.value.toJson(),
    }),
    'visible_action_points': _sortedMap(visibleActionPoints),
    'resolution': resolution?.toJson(),
    'auction': auction?.toJson(),
    'execution': execution?.toJson(),
  };

  factory PublicGameStateDto.fromJson(Map<String, Object?> json) {
    _requireVersion(json);
    return PublicGameStateDto(
      sessionId: json['session_id']! as String,
      roundId: json['round_id']! as String,
      roundNumber: json['round_number']! as int,
      phase: PublicRoundPhase.values.byName(json['phase']! as String),
      proximity: json['proximity']! as String,
      chiliActive: json['chili_active']! as int,
      chiliUnlocked: json['chili_unlocked']! as int,
      playerIds: List<String>.from(json['player_ids']! as List),
      selectionMade: _boolMap(json['selection_made']),
      revealedChoices: _objectMap(
        json['revealed_choices'],
        PublicChoiceDto.fromJson,
      ),
      visibleActionPoints: _intMap(json['visible_action_points']),
      resolution: _optionalObject(
        json['resolution'],
        PublicResolutionDto.fromJson,
      ),
      auction: _optionalObject(json['auction'], PublicAuctionDto.fromJson),
      execution: _optionalObject(
        json['execution'],
        PublicExecutionDto.fromJson,
      ),
    );
  }
}

final class PrivateCardDto {
  const PrivateCardDto({
    required this.cardId,
    required this.zone,
    this.occurrenceId,
    this.variantId,
    this.locked = false,
  });

  final String cardId;
  final String? occurrenceId;
  final String zone;
  final String? variantId;
  final bool locked;

  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'occurrence_id': occurrenceId,
    'zone': zone,
    'variant_id': variantId,
    'locked': locked,
  };

  factory PrivateCardDto.fromJson(Map<String, Object?> json) => PrivateCardDto(
    cardId: json['card_id']! as String,
    occurrenceId: json['occurrence_id'] as String?,
    zone: json['zone']! as String,
    variantId: json['variant_id'] as String?,
    locked: json['locked']! as bool,
  );
}

final class PrivatePreferenceDto {
  const PrivatePreferenceDto({
    required this.status,
    this.general,
    this.faire,
    this.recevoir,
  });

  final String status;
  final int? general;
  final int? faire;
  final int? recevoir;

  Map<String, Object?> toJson() => {
    'status': status,
    'general': general,
    'faire': faire,
    'recevoir': recevoir,
  };

  factory PrivatePreferenceDto.fromJson(Map<String, Object?> json) =>
      PrivatePreferenceDto(
        status: json['status']! as String,
        general: json['general'] as int?,
        faire: json['faire'] as int?,
        recevoir: json['recevoir'] as int?,
      );
}

final class PrivateRecoveryDto {
  const PrivateRecoveryDto({
    required this.available,
    required this.usedSinceLastNormalDuel,
    this.selectedCardId,
  });

  final bool available;
  final bool usedSinceLastNormalDuel;
  final String? selectedCardId;

  Map<String, Object?> toJson() => {
    'available': available,
    'used_since_last_normal_duel': usedSinceLastNormalDuel,
    'selected_card_id': selectedCardId,
  };

  factory PrivateRecoveryDto.fromJson(Map<String, Object?> json) =>
      PrivateRecoveryDto(
        available: json['available']! as bool,
        usedSinceLastNormalDuel: json['used_since_last_normal_duel']! as bool,
        selectedCardId: json['selected_card_id'] as String?,
      );
}

final class PrivatePlayerStateDto {
  PrivatePlayerStateDto({
    required this.sessionId,
    required this.roundId,
    required this.playerId,
    required List<PrivateCardDto> hand,
    required Map<String, int> personalValues,
    required Map<String, PrivatePreferenceDto> preferences,
    required this.drawStyle,
    this.lockedCardId,
    this.committedChoice,
    this.commitNonce,
    this.recovery,
    this.actionPoints,
  }) : hand = List.unmodifiable(hand),
       personalValues = Map.unmodifiable(personalValues),
       preferences = Map.unmodifiable(preferences);

  final String sessionId;
  final String roundId;
  final String playerId;
  final List<PrivateCardDto> hand;
  final String? lockedCardId;
  final PublicChoiceDto? committedChoice;
  final String? commitNonce;
  final Map<String, int> personalValues;
  final Map<String, PrivatePreferenceDto> preferences;
  final String drawStyle;
  final PrivateRecoveryDto? recovery;
  final int? actionPoints;

  Map<String, Object?> toJson() => {
    'schema_version': networkSchemaVersion,
    'session_id': sessionId,
    'round_id': roundId,
    'player_id': playerId,
    'hand': [for (final card in hand) card.toJson()],
    'locked_card_id': lockedCardId,
    'committed_choice': committedChoice?.toJson(),
    'commit_nonce': commitNonce,
    'personal_values': _sortedMap(personalValues),
    'preferences': _sortedMap({
      for (final entry in preferences.entries) entry.key: entry.value.toJson(),
    }),
    'draw_style': drawStyle,
    'recovery': recovery?.toJson(),
    'action_points': actionPoints,
  };

  factory PrivatePlayerStateDto.fromJson(Map<String, Object?> json) {
    _requireVersion(json);
    return PrivatePlayerStateDto(
      sessionId: json['session_id']! as String,
      roundId: json['round_id']! as String,
      playerId: json['player_id']! as String,
      hand: [
        for (final item in json['hand']! as List)
          PrivateCardDto.fromJson(Map<String, Object?>.from(item! as Map)),
      ],
      lockedCardId: json['locked_card_id'] as String?,
      committedChoice: _optionalObject(
        json['committed_choice'],
        PublicChoiceDto.fromJson,
      ),
      commitNonce: json['commit_nonce'] as String?,
      personalValues: _intMap(json['personal_values']),
      preferences: _objectMap(
        json['preferences'],
        PrivatePreferenceDto.fromJson,
      ),
      drawStyle: json['draw_style']! as String,
      recovery: _optionalObject(json['recovery'], PrivateRecoveryDto.fromJson),
      actionPoints: json['action_points'] as int?,
    );
  }
}

SplayTreeMap<String, Object?> _sortedMap(Map<String, Object?> values) =>
    SplayTreeMap<String, Object?>.from(values);

void _requireVersion(Map<String, Object?> json) {
  if (json['schema_version'] != networkSchemaVersion) {
    throw FormatException('Unsupported network schema version');
  }
}

Map<String, int> _intMap(Object? value) => {
  for (final entry in (value! as Map).entries)
    entry.key as String: entry.value! as int,
};

Map<String, bool> _boolMap(Object? value) => {
  for (final entry in (value! as Map).entries)
    entry.key as String: entry.value! as bool,
};

Map<String, T> _objectMap<T>(
  Object? value,
  T Function(Map<String, Object?>) parse,
) => {
  for (final entry in (value! as Map).entries)
    entry.key as String: parse(Map<String, Object?>.from(entry.value! as Map)),
};

T? _optionalObject<T>(Object? value, T Function(Map<String, Object?>) parse) =>
    value == null ? null : parse(Map<String, Object?>.from(value as Map));
