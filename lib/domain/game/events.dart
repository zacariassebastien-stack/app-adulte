// ignore_for_file: constant_identifier_names
enum GameEventType {
  ROUND_STARTED,
  CARD_SELECTED,
  CARD_COMMITTED,
  CARDS_REVEALED,
  DUEL_RESOLVED,
  PA_SPENT,
  AUCTION_STARTED,
  AUCTION_COMMITTED,
  AUCTION_RESOLVED,
  CORRUPTION_PROPOSED,
  ACTION_ACCEPTED,
  ACTION_SKIPPED,
  ACTION_COMPLETED,
  STATE_UPDATED,
  CARD_DISCARDED,
  CARD_EXHAUSTED,
  ROUND_CLOSED,
  STRATEGIC_RENUNCIATION,
  MUTUAL_PA_EXTENSION,
  CONSENT_STOP,
  CONTEXTUAL_REFRESH,
}

final class GameEvent {
  GameEvent(this.type, [Map<String, Object?> payload = const {}])
    : payload = Map.unmodifiable(payload) {
    _assertNoMedia(payload);
  }
  final GameEventType type;
  final Map<String, Object?> payload;

  static void _assertNoMedia(Object? value) {
    const forbidden = {
      'photo',
      'video',
      'media',
      'bytes',
      'blob',
      'path',
      'url',
    };
    if (value is Map) {
      for (final entry in value.entries) {
        if (forbidden.contains(entry.key.toString().toLowerCase())) {
          throw ArgumentError('Media is forbidden in game events');
        }
        _assertNoMedia(entry.value);
      }
    } else if (value is Iterable) {
      for (final item in value) {
        _assertNoMedia(item);
      }
    }
  }
}

abstract interface class ProfileEngine {
  const ProfileEngine();
}

abstract interface class AnalyticsEngine {
  const AnalyticsEngine();
}
