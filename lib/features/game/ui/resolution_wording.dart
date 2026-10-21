import '../../../sync/sync.dart';

/// Presentation only. Roles come from the retained snapshot, never the auction.
final class ResolutionWording {
  const ResolutionWording({required this.localPlayerId, this.names = const {}});
  final String localPlayerId;
  final Map<String, String> names;

  String name(String id, {bool subject = false}) {
    final nickname = names[id]?.trim();
    if (nickname != null && nickname.isNotEmpty) return nickname;
    return id == localPlayerId
        ? (subject ? 'Toi' : 'toi')
        : (subject ? 'Ton partenaire' : 'ton partenaire');
  }

  String retained(String owner) => owner == localPlayerId
      ? 'Ta carte est retenue.'
      : 'La carte de ${name(owner)} est retenue.';

  String describe(NetworkResolvedActionCardDto card, String title) {
    final action = card.usage.resolvedAction;
    final actors = (action['actor_player_ids']! as List).cast<String>();
    final targets = (action['target_player_ids']! as List).cast<String>();
    String people(List<String> ids, {bool subject = false}) => [
      for (var i = 0; i < ids.length; i++)
        name(ids[i], subject: subject && i == 0),
    ].join(' et ');
    final localUnnamed =
        actors.contains(localPlayerId) &&
        (names[localPlayerId]?.trim().isEmpty ?? true);
    final who = actors.length == 1 && localUnnamed
        ? 'Tu'
        : people(actors, subject: true);
    final verb = actors.length > 1
        ? (localUnnamed ? 'réalisez' : 'réalisent')
        : (localUnnamed ? 'réalises' : 'réalise');
    if (card.direction == NetworkCardDirection.MUTUEL) {
      return '$who $verb « $title » ensemble.';
    }
    if (card.direction == NetworkCardDirection.SIMULTANE) {
      return '$who $verb « $title » simultanément, chacun de son côté.';
    }
    if (card.direction == NetworkCardDirection.SOLO || targets.isEmpty) {
      return '$who $verb « $title » en solo.';
    }
    // For photo/video the actor denotes the subject, not the camera operator.
    if (card.cardId == '044' || card.cardId == '046') {
      return '$who ${localUnnamed ? 'es' : 'est'} le sujet de « $title » pour ${people(targets)}. '
          'La personne qui tient l’appareil est libre.';
    }
    // "Pour" also fits performances/orders/media; it does not invent contact.
    // Anatomical zone actions can explicitly describe the physical target.
    final relation = card.zoneId == null ? 'pour' : 'sur';
    return '$who $verb « $title » $relation ${people(targets)}.';
  }
}
