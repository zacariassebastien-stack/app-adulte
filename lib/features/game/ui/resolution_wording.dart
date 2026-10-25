import '../../../sync/sync.dart';

/// Presentation only. Roles come from the retained snapshot, never the auction.
final class ResolutionWording {
  const ResolutionWording({required this.localPlayerId, this.names = const {}});
  final String localPlayerId;
  final Map<String, String> names;

  String participant(String id) => id == localPlayerId ? 'toi' : name(id);

  String reminder(String id) => id == localPlayerId
      ? 'Tu dois continuer cette action.'
      : '${name(id, subject: true)} doit continuer cette action.';

  String concerned(String id) => id == localPlayerId
      ? 'Tu es concerné(e) par cette action.'
      : '${name(id, subject: true)} est concerné(e) par cette action.';

  static const silenceDetails =
      'Ne parle pas et ne fais volontairement aucun bruit. '
      'Tu peux uniquement rompre le silence lorsqu’une décision de jeu nécessite de communiquer.';

  String silenceInstruction(String actorId, int actions) =>
      '${actorId == localPlayerId ? 'Garde' : '${name(actorId, subject: true)} garde'} '
      'un silence complet pendant les $actions prochaines actions.';

  String silenceDetailsFor(String actorId) => actorId == localPlayerId
      ? silenceDetails
      : '${name(actorId, subject: true)} ne parle pas et ne fait volontairement aucun bruit. '
            'Cette personne peut uniquement rompre le silence lorsqu’une décision de jeu nécessite de communiquer.';

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
    // Some cards describe the performer's state/performance; adding a generic
    // recipient would imply a different clothing or participation action.
    const actorCentred = {
      '006',
      '007',
      '008',
      '009',
      '010',
      '013',
      '018',
      '033',
      '038',
      '039',
      '050',
      '054',
      '057',
      '058',
      '061',
    };
    const physicalTarget = {
      '019',
      '022',
      '023',
      '025',
      '027',
      '028',
      '030',
      '031',
      '034',
      '035',
      '037',
      '049',
      '051',
      '060',
      '062',
      '063',
      '065',
    };
    final relation = card.zoneId != null || physicalTarget.contains(card.cardId)
        ? 'sur'
        : 'pour';
    final suffix = actorCentred.contains(card.cardId)
        ? ''
        : ' $relation ${people(targets)}';
    final duration = card.parameters['duration_actions'] as int?;
    final durationText = duration == null
        ? ''
        : ' pendant les $duration prochaines actions';
    return '$who $verb « $title »$suffix$durationText.';
  }
}
