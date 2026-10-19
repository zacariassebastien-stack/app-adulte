import '../../core/json.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/catalog/concept_catalog.dart';
import '../../domain/catalog/definitions.dart';
import '../../domain/catalog/v4_catalog.dart';

/// V4 context/clothing/duration plus explicitly validated conceptual rules.
/// No legacy catalogue or stage occurrence is consulted.
final class ConceptRuntimeCatalog {
  ConceptRuntimeCatalog({
    required this.concepts,
    required Catalog source,
    required JsonMap rules,
  }) {
    final byId = {for (final card in source.cards) card.stableId: card};
    final bindings = <String, JsonMap>{};
    for (final raw in rules['bindings']! as List) {
      final binding = raw as JsonMap;
      final id = binding['concept_id']! as String;
      if (bindings.containsKey(id))
        throw FormatException('Duplicate binding $id');
      bindings[id] = binding;
    }
    if (bindings.length != concepts.concepts.length)
      throw const FormatException(
        'Every active concept needs one rule binding',
      );
    definitions = Map.unmodifiable({
      for (final concept in concepts.concepts)
        concept.id: _definition(concept, bindings[concept.id]!, byId),
    });
  }
  final ConceptCatalog concepts;
  late final Map<String, CardDefinition> definitions;
  V4VariantRatingDefinition ratingFor(String conceptId, String actionId) {
    final variant = definitions[conceptId]!.variants.singleWhere(
      (v) => v.stableId == actionId,
    );
    return V4VariantRatingDefinition.fromJson({
      ...variant.reader.json['v4']! as JsonMap,
      'variant_id': actionId,
      'stage': null,
      'scope': 'concept',
    });
  }

  Set<String> vetoTags(String conceptId) => {
    for (final variant in definitions[conceptId]!.variants) ...{
      for (final tag in variant.v3!.tags) tag.split('.').last,
      if (variant.reader.json['v4'] case final Map<String, Object?> rating) ...{
        ...(rating['primary_preference_tags'] as List).cast<String>(),
        ...(rating['secondary_preference_tags'] as List).cast<String>(),
        ...(rating['non_preference_data'] as List).cast<String>(),
      },
    },
    if (conceptId == '022') 'penetration_vaginale',
    if (concepts.concepts.singleWhere((c) => c.id == conceptId).kind ==
        ConceptKind.zones)
      for (final zone in concepts.zones) zone.id,
  };

  CardDefinition _definition(
    CardConcept concept,
    JsonMap binding,
    Map<String, CardDefinition> sources,
  ) {
    final ids = (binding['source_card_ids']! as List).cast<String>();
    if (ids.length != 1 || sources[ids.single] == null)
      throw FormatException('Unknown V4 metadata source for ${concept.id}');
    final source = sources[ids.single]!;
    final actionRules = {
      for (final raw in binding['actions']! as List)
        (raw as JsonMap)['action_id']! as String: raw,
    };
    final actions = [
      for (final stage in concept.stages) (stage.id, stage.title, stage.chili),
      for (final variant in concept.variants)
        (variant.id, variant.title, variant.chili ?? concept.intrinsicChili!),
    ];
    if (actionRules.length != actions.length)
      throw FormatException('Action rules mismatch ${concept.id}');
    return CardDefinition.fromJson({
      ...source.reader.json,
      'v4': {
        ...?source.reader.json['v4'] as JsonMap?,
        if (const {
          '013',
          '044',
          '045',
          '046',
          '047',
          '050',
          '052',
        }.contains(concept.id))
          'presence': 'BOTH',
      },
      'stable_id': concept.id,
      'enabled': true,
      'v3_deck_enabled': true,
      'title': concept.title,
      'action_text': concept.actionText,
      'details_text': concept.detailsText,
      'inversion_policy': binding['inversion_policy'],
      'technical_requirements': <Object?>[],
      'v3': actionRules[actions.first.$1]!['editorial'],
      'variants': [
        for (final action in actions)
          {
            ...source.variants.first.reader.json,
            'stable_id': action.$1,
            'card_id': concept.id,
            'enabled': true,
            'v3_deck_enabled': true,
            'title': action.$2,
            'action_text': concept.actionText,
            'details_text': concept.detailsText,
            'chili_level': action.$3,
            'technical_requirements':
                actionRules[action.$1]!['technical_requirements'],
            'state_effects': actionRules[action.$1]!['state_effects'],
            'inversion_override': actionRules[action.$1]!['inversion_override'],
            'v3': actionRules[action.$1]!['editorial'],
            'v4': actionRules[action.$1]!['rating'],
          },
      ],
    });
  }
}
