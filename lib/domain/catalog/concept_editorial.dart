import 'concept_catalog.dart';
import '../game/game_models.dart';

final class ConceptEditorialText {
  const ConceptEditorialText({required this.actionText, this.detailsText});

  final String actionText;
  final String? detailsText;
}

/// Resolves player-facing copy without changing action identity or gameplay.
/// Direction and grammatical body-part forms are editorial inputs only.
final class ConceptEditorialRenderer {
  const ConceptEditorialRenderer(this.catalog);

  final ConceptCatalog catalog;

  bool appliesTo({required CardConcept concept, required String actionId}) {
    final stage = concept.stages
        .where((item) => item.id == actionId)
        .firstOrNull;
    final variant = concept.variants
        .where((item) => item.id == actionId)
        .firstOrNull;
    return concept.actionTemplates.isNotEmpty ||
        concept.freeActionTemplates.isNotEmpty ||
        concept.composedDetailsText != null ||
        stage?.actionText != null ||
        stage?.detailsText != null ||
        stage?.actionTemplates.isNotEmpty == true ||
        variant?.actionText != null ||
        variant?.detailsText != null ||
        variant?.actionTemplates.isNotEmpty == true;
  }

  ConceptEditorialText render({
    required CardConcept concept,
    required String actionId,
    required CardOccurrenceDirection direction,
    String partnerLabel = 'ton partenaire',
  }) {
    final stage = concept.stages
        .where((item) => item.id == actionId)
        .firstOrNull;
    final variant = concept.variants
        .where((item) => item.id == actionId)
        .firstOrNull;
    if (stage == null && variant == null) {
      throw StateError('Unknown editorial action $actionId');
    }
    final zone = variant?.zoneId == null
        ? null
        : catalog.zones.singleWhere((item) => item.id == variant!.zoneId);
    final directionKey = direction.name;
    final specificTemplates =
        stage?.actionTemplates ?? variant!.actionTemplates;
    final specificText = stage?.actionText ?? variant?.actionText;
    final template =
        specificTemplates[directionKey] ??
        (variant?.freeZone == true
            ? concept.freeActionTemplates[directionKey]
            : concept.actionTemplates[directionKey]);
    final templated = template != null || specificText != null;
    var action = _substitute(
      template ?? specificText ?? concept.actionText,
      partnerLabel: partnerLabel,
      zone: zone,
      stageTitle: stage?.title,
    );
    if (!templated) {
      if (variant?.freeZone == true) {
        action = concept.actionText;
      } else {
        action = '$action · ${stage?.title ?? variant!.title}';
      }
    }

    var details =
        stage?.detailsText ?? variant?.detailsText ?? concept.detailsText;
    if (concept.id == '061' && direction == CardOccurrenceDirection.RECEVOIR) {
      details =
          'Cette personne ne parle pas et ne fait volontairement aucun bruit. '
          'Elle peut uniquement rompre le silence lorsqu’une décision de jeu nécessite de communiquer.';
    }
    if (zone?.composed == true && concept.composedDetailsText != null) {
      details = [?details, concept.composedDetailsText!].join(' ');
    }
    return ConceptEditorialText(actionText: action, detailsText: details);
  }

  String _substitute(
    String value, {
    required String partnerLabel,
    required ConceptBodyZone? zone,
    required String? stageTitle,
  }) => value
      .replaceAll('{ton_partenaire}', partnerLabel)
      .replaceAll('{partie_corps}', zone?.objectForm ?? '')
      .replaceAll('{ta_partie_corps}', zone?.possessiveForm ?? '')
      .replaceAll('{stade}', stageTitle ?? '');
}
