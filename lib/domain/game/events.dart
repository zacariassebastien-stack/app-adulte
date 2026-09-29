import '../../core/json.dart';
import '../session/session_state.dart';
import 'analytics_models.dart';

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
  PLAYER_STYLE_CHANGED,
  CHILI_INCREASE_PROPOSED,
  CHILI_INCREASE_ACCEPTED,
  CHILI_INCREASE_DECLINED,
  CHILI_DECREASE_PROPOSED,
  CHILI_DECREASE_ACCEPTED,
  CHILI_DECREASE_DECLINED,
  CHILI_LEVEL_CHANGED,
  DECISION_OPPORTUNITY,
  DECISION_PASSED,
  CORRUPTION_RESOLVED,
  ACTION_EXECUTION_RECORDED,
  INVERSION_ATTEMPTED,
  INVERSION_RETAINED,
  RECOVERY_PROPOSED,
  RECOVERY_RESOLVED,
  CARD_DRAWN_PRIVATE,
  CARD_LOCK_CHANGED_PRIVATE,
}

final class GameEvent {
  GameEvent(this.type, [Map<String, Object?> payload = const {}])
    : payload = freezeJson(payload)! as JsonMap,
      version = 1,
      visibility = DataVisibility.SESSION_PRIVATE_INTERNAL,
      ownerPlayerId = null,
      analytics = const [] {
    _assertNoMedia(payload);
  }
  GameEvent.record(
    this.type,
    Map<String, Object?> payload, {
    this.visibility = DataVisibility.SESSION_PRIVATE_INTERNAL,
    this.ownerPlayerId,
    Iterable<PrivateAnalyticsContext> analytics = const [],
  }) : version = 2,
       payload = freezeJson(payload)! as JsonMap,
       analytics = List.unmodifiable(analytics) {
    _assertNoMedia(toJson());
    if (visibility == DataVisibility.PLAYER_PRIVATE && ownerPlayerId == null) {
      throw ArgumentError('Private event requires owner');
    }
    if (visibility == DataVisibility.PLAYER_PRIVATE &&
        this.analytics.any((a) => a.playerId != ownerPlayerId)) {
      throw ArgumentError('Private event contains another owner');
    }
  }
  final GameEventType type;
  final Map<String, Object?> payload;
  final int version;
  final DataVisibility visibility;
  final String? ownerPlayerId;
  final List<PrivateAnalyticsContext> analytics;

  Map<String, Object?> toJson() => {
    'event_version': version,
    'type': type.name,
    'visibility': visibility.name,
    if (ownerPlayerId != null) 'owner_player_id': ownerPlayerId,
    'facts': payload,
    'private_analytics': analytics.map((a) => a.toJson()).toList(),
  };
  StoredEvent toStored({
    required String sessionId,
    required String eventId,
    required int sequence,
    required DateTime at,
  }) => StoredEvent(
    sessionId: sessionId,
    eventId: eventId,
    sequence: sequence,
    type: type.name,
    payload: toJson(),
    createdAt: at,
  );

  /// Legacy payloads remain readable. Unknown versions are rejected explicitly;
  /// the repository still returns the intact raw StoredEvent for recovery.
  factory GameEvent.fromStored(StoredEvent stored) {
    final type = GameEventType.values
        .where((t) => t.name == stored.type)
        .firstOrNull;
    if (type == null) {
      throw UnsupportedError('Unknown game event ${stored.type}');
    }
    if (!stored.payload.containsKey('event_version')) {
      return GameEvent(type, stored.payload);
    }
    final r = JsonReader(stored.payload, 'GameEvent');
    final version = r.integer('event_version');
    if (version != 1 && version != 2) {
      throw UnsupportedError('Unsupported game event version $version');
    }
    if (r.string('type') != stored.type) {
      throw FormatException('Event type mismatch');
    }
    final facts = r
        .child(stored.payload['facts'], 'facts', 'GameEventFacts')
        .json;
    if (version == 1) return GameEvent(type, facts);
    return GameEvent.record(
      type,
      facts,
      visibility: r.enumeration('visibility', DataVisibility.values),
      ownerPlayerId: r.optionalString('owner_player_id'),
      analytics: r.objects(
        'private_analytics',
        (r) => PrivateAnalyticsContext.fromJson(r.json),
        'PrivateAnalyticsContext',
      ),
    );
  }

  List<PrivateAnalyticsContext> analyticsFor(String playerId) =>
      List.unmodifiable(analytics.where((a) => a.playerId == playerId));

  /// Allow-list, never a serialization of the internal event or private context.
  Map<String, Object?> publicProjection() {
    if (visibility != DataVisibility.PUBLIC) return const {};
    final allowed = switch (type) {
      GameEventType.ROUND_STARTED || GameEventType.ROUND_CLOSED => {'round_id'},
      GameEventType.CHILI_LEVEL_CHANGED => {'previous_level', 'new_level'},
      _ => <String>{},
    };
    if (allowed.isEmpty) return const {};
    return {
      'type': type.name,
      for (final k in allowed)
        if (payload[k] is String || payload[k] is int) k: payload[k],
    };
  }

  static void _assertNoMedia(Object? value) {
    const forbidden = {
      'photo',
      'video',
      'media',
      'bytes',
      'blob',
      'path',
      'url',
      'photos',
      'photo_url',
      'photo_path',
      'videos',
      'video_url',
      'video_path',
      'media_url',
      'media_path',
      'thumbnail',
      'binary',
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
