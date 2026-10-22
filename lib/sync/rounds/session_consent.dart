/// Session permissions contain no preference values, veto tags or explanations.
/// Keys describe potential occurrences, never a player's actual private hand.
final class SessionConsentState {
  SessionConsentState({
    required this.revision,
    required this.ready,
    required Iterable<String> allowed,
  }) : allowed = Set.unmodifiable(allowed);
  final int revision;
  final bool ready;
  final Set<String> allowed;
  factory SessionConsentState.fromJson(Map<String, Object?> json) =>
      SessionConsentState(
        revision: json['revision']! as int,
        ready: json['ready']! as bool,
        allowed: (json['allowed']! as List).cast<String>(),
      );
}

abstract interface class NetworkSessionConsentRepository {
  Future<SessionConsentState> publishSessionConsent({
    required String sessionId,
    required Set<String> allowed,
    required String commandId,
  });
  Future<SessionConsentState> getSessionConsent(String sessionId);
}

/// Realtime is a wake-up hint only; canonical reads and polling remain required.
abstract interface class NetworkSessionConsentEvents {
  Stream<int> watchSessionConsent(String sessionId);
}

String sessionConsentKey(
  String owner,
  String concept,
  String action,
  String direction,
) => '$owner/$concept/$action/$direction';
