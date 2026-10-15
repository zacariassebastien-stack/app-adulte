import '../../core/json.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/catalog/concept_catalog.dart';
import '../../domain/catalog/definitions.dart';

/// New concepts expressed in the existing V4 engine/view definition types.
/// Source cards contribute rules only; their IDs, spice and stock are not used.
final class ConceptRuntimeCatalog {
  ConceptRuntimeCatalog({
    required this.concepts,
    required Catalog source,
    required JsonMap rules,
  }) {
    final byId = {for (final card in source.cards) card.stableId: card};
    final bindings = <String, List<String>>{};
    for (final value in rules['bindings']! as List) {
      final binding = value as JsonMap;
      final id = binding['concept_id']! as String;
      if (bindings.containsKey(id)) {
        throw FormatException('Duplicate binding $id');
      }
      bindings[id] = (binding['source_card_ids']! as List).cast<String>();
    }
    if (bindings.length != concepts.concepts.length) {
      throw const FormatException(
        'Every active concept needs one rule binding',
      );
    }
    definitions = Map.unmodifiable({
      for (final concept in concepts.concepts)
        concept.id: _definition(concept, [
          for (final id in bindings[concept.id] ?? <String>[])
            byId[id] ?? (throw FormatException('Unknown rule source $id')),
        ]),
    });
  }

  final ConceptCatalog concepts;
  late final Map<String, CardDefinition> definitions;

  CardDefinition _definition(
    CardConcept concept,
    List<CardDefinition> sources,
  ) {
    if (sources.isEmpty) {
      throw FormatException('Missing rule source ${concept.id}');
    }
    final source = sources.first;
    final actions = <JsonMap>[];
    final definitions = [
      for (final stage in concept.stages) (stage.id, stage.title, stage.chili),
      for (final variant in concept.variants)
        (variant.id, variant.title, variant.chili ?? concept.intrinsicChili!),
    ];
    for (var index = 0; index < definitions.length; index++) {
      final action = definitions[index];
      final actionSource =
          sources[index < sources.length ? index : sources.length - 1];
      final sourceVariant = concept.id == '022' || concept.id == '023'
          ? actionSource.variants.firstWhere(
              (v) => v.stableId == 'variant.anal_manual.internal',
            )
          : actionSource.variants.first;
      final editorial = <String, Object?>{
        ...?(sourceVariant.reader.json['v3'] ?? source.reader.json['v3'])
            as JsonMap?,
      };
      final tags = ((editorial['tags'] as List?) ?? <Object?>[])
          .cast<String>()
          .toSet();
      final requirements = <String, Object?>{
        ...?editorial['requirements'] as JsonMap?,
      };
      final technical = [
        ...actionSource.technicalRequirements.map((r) => r.toJson()),
        ...sourceVariant.technicalRequirements.map((r) => r.toJson()),
      ];
      void preferences(List<String> ids) {
        tags.removeWhere((t) => t.startsWith('v3.preference.'));
        tags.addAll(ids.map((id) => 'v3.preference.$id'));
      }

      void direction(List<String> ids) {
        tags.removeWhere((t) => t.startsWith('v3.direction.'));
        tags.addAll(ids.map((id) => 'v3.direction.$id'));
      }

      void modes({required bool distance}) {
        requirements['DISTANCE_EXCLUE'] = !distance;
        technical.removeWhere((r) => r['type'] == 'SESSION_MODE_IN');
        technical.add({
          'type': 'SESSION_MODE_IN',
          'values': ['face_to_face', 'hybrid', if (distance) 'distance'],
        });
      }

      switch (concept.id) {
        case '022':
          preferences(['penetrer', 'doigts']);
          tags.removeWhere((t) => t.startsWith('v3.zone.'));
          tags.add('v3.zone.vaginal');
          direction(['faire', 'recevoir']);
          modes(distance: false);
        case '065':
          preferences(['masturbation']);
          tags.add('v3.zone.pieds');
          direction(['faire', 'recevoir']);
          modes(distance: false);
        case '004':
          // Technique is chosen later; do not inherit an intimate practice.
          preferences([]);
          tags.removeWhere((t) => t.startsWith('v3.zone.'));
          direction(['faire', 'recevoir']);
          modes(distance: false);
        case '013':
          preferences(['tenue']);
          direction(['solo']);
          modes(distance: true);
        case '044' || '046':
          modes(distance: true);
        case '045' || '047':
          preferences([
            concept.id == '045' ? 'photo' : 'video',
            'etre_regarde',
          ]);
          direction(['mutuel']);
          modes(distance: true);
        case '049' || '050' || '051' || '052':
          preferences([
            'sextoy',
            if (concept.id == '050') 'masturbation',
            if (action.$1.endsWith('vaginal_insertion') ||
                action.$1.endsWith('anal_insertion'))
              'penetrer',
            if (concept.id == '052') ...[
              'vibrant',
              'controle_distance',
              'controle',
            ],
          ]);
          tags.removeWhere((t) => t.startsWith('v3.zone.'));
          if (action.$1.endsWith('vaginal_insertion')) {
            tags.add('v3.zone.vaginal');
          }
          if (action.$1.endsWith('anal_insertion')) tags.add('v3.zone.anal');
          direction(concept.id == '050' ? ['solo'] : ['faire', 'recevoir']);
          modes(distance: concept.id == '050' || concept.id == '052');
      }
      if (concept.kind == ConceptKind.zones) {
        tags.removeWhere((t) => t.startsWith('v3.zone.'));
      }
      editorial['taxonomy_version'] = 1;
      editorial['tags'] = tags.toList();
      editorial['requirements'] = requirements;
      editorial['baseEngagementLevel'] = action.$3;
      actions.add({
        ...sourceVariant.reader.json,
        'stable_id': action.$1,
        'card_id': concept.id,
        'enabled': true,
        'v3_deck_enabled': true,
        'title': action.$2,
        'action_text': concept.actionText,
        'details_text': concept.detailsText,
        'chili_level': action.$3,
        'technical_requirements': technical,
        'v3': editorial,
      });
    }
    return CardDefinition.fromJson({
      ...source.reader.json,
      'stable_id': concept.id,
      'enabled': true,
      'v3_deck_enabled': true,
      'title': concept.title,
      'action_text': concept.actionText,
      'details_text': concept.detailsText,
      'technical_requirements': <Object?>[],
      'variants': actions,
      'v3': actions.first['v3'],
    });
  }
}
