import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/core/json.dart';
import 'package:couple_cards/domain/catalog/concept_catalog.dart';
import 'package:couple_cards/domain/catalog/concept_editorial.dart';
import 'package:couple_cards/domain/game/game_models.dart';
import 'package:test/test.dart';

void main() {
  late JsonMap document;
  late ConceptCatalog catalog;
  late ConceptEditorialRenderer renderer;

  setUpAll(() {
    document =
        jsonDecode(
              File('assets/catalog/concepts/active.fr.json').readAsStringSync(),
            )
            as JsonMap;
    catalog = ConceptCatalog.fromJson(document);
    renderer = ConceptEditorialRenderer(catalog);
  });

  CardConcept concept(String id) =>
      catalog.concepts.singleWhere((item) => item.id == id);

  test('renders simple anatomical forms for FAIRE and RECEVOIR', () {
    expect(
      renderer
          .render(
            concept: concept('002'),
            actionId: '002.zone.buttocks',
            direction: CardOccurrenceDirection.FAIRE,
          )
          .actionText,
      'Embrasse les fesses de ton partenaire.',
    );
    expect(
      renderer
          .render(
            concept: concept('002'),
            actionId: '002.zone.buttocks',
            direction: CardOccurrenceDirection.RECEVOIR,
          )
          .actionText,
      'Laisse ton partenaire embrasser tes fesses.',
    );
  });

  test('renders composed anatomy and appends its optional precision', () {
    final text = renderer.render(
      concept: concept('002'),
      actionId: '002.zone.neck_nape',
      direction: CardOccurrenceDirection.FAIRE,
    );
    expect(text.actionText, 'Embrasse le cou et la nuque de ton partenaire.');
    expect(
      text.detailsText,
      'À une ou plusieurs reprises, cela dépend de toi. '
      'Tu peux choisir l’une des deux ou les deux.',
    );
  });

  test('LIBRE keeps a dedicated action without anatomical substitution', () {
    final faire = renderer.render(
      concept: concept('004'),
      actionId: '004.zone.free',
      direction: CardOccurrenceDirection.FAIRE,
    );
    final recevoir = renderer.render(
      concept: concept('005'),
      actionId: '005.zone.free',
      direction: CardOccurrenceDirection.RECEVOIR,
    );
    expect(
      faire.actionText,
      'Choisis librement une partie du corps de ton partenaire et la manière '
      'd’utiliser ta bouche.',
    );
    expect(
      recevoir.actionText,
      'Laisse ton partenaire choisir librement une partie de ton corps et la '
      'manière d’utiliser ses mains.',
    );
    expect(faire.actionText, isNot(contains('fesses')));
    expect(recevoir.actionText, isNot(contains('vulve')));
  });

  test('new anatomical player copy never exposes the technical word zone', () {
    final technicalWord = RegExp(r'\bzone\b', caseSensitive: false);
    for (final id in ['002', '004', '005']) {
      final item = concept(id);
      for (final variant in item.variants) {
        for (final direction in [
          CardOccurrenceDirection.FAIRE,
          CardOccurrenceDirection.RECEVOIR,
        ]) {
          final text = renderer.render(
            concept: item,
            actionId: variant.id,
            direction: direction,
          );
          expect(text.actionText, isNot(matches(technicalWord)));
          expect(text.detailsText ?? '', isNot(matches(technicalWord)));
        }
      }
    }
  });

  test('direction and stage templates remain natural and stage-specific', () {
    expect(
      renderer
          .render(
            concept: concept('032'),
            actionId: '032.action',
            direction: CardOccurrenceDirection.RECEVOIR,
          )
          .actionText,
      'Laisse ton partenaire choisir l’ordre que tu devras suivre.',
    );
    expect(
      renderer
          .render(
            concept: concept('057'),
            actionId: '057.stage.3',
            direction: CardOccurrenceDirection.FAIRE,
          )
          .actionText,
      'Supplie ton partenaire : Supplication intense / pratiquement à genoux.',
    );
  });

  test('a specific action can override a shared template', () {
    final copy = jsonDecode(jsonEncode(document)) as JsonMap;
    final concepts = copy['concepts']! as List<Object?>;
    final kiss = concepts.cast<JsonMap>().singleWhere(
      (item) => item['id'] == '002',
    );
    final variants = kiss['variants']! as List<Object?>;
    final face = variants.cast<JsonMap>().singleWhere(
      (item) => item['id'] == '002.zone.face_hair',
    );
    face['action_templates'] = {
      'FAIRE': 'Texte spécifique pour {partie_corps}.',
    };
    face['details_text'] = 'Précision spécifique.';
    final overridden = ConceptCatalog.fromJson(copy);
    final text = ConceptEditorialRenderer(overridden).render(
      concept: overridden.concepts.singleWhere((item) => item.id == '002'),
      actionId: '002.zone.face_hair',
      direction: CardOccurrenceDirection.FAIRE,
    );
    expect(text.actionText, 'Texte spécifique pour le visage et les cheveux.');
    expect(
      text.detailsText,
      'Précision spécifique. Tu peux choisir l’une des deux ou les deux.',
    );
  });

  test('editorial metadata preserves catalogue and runtime identities', () {
    final actionIds = {
      for (final item in catalog.concepts) ...{
        ...item.stages.map((stage) => stage.id),
        ...item.variants.map((variant) => variant.id),
      },
    };
    final rules =
        jsonDecode(
              File(
                'assets/catalog/concepts/runtime_rules.fr.json',
              ).readAsStringSync(),
            )
            as JsonMap;
    var representations = 0;
    for (final binding
        in (rules['bindings']! as List<Object?>).cast<JsonMap>()) {
      for (final action
          in (binding['actions']! as List<Object?>).cast<JsonMap>()) {
        expect(actionIds, contains(action['action_id']));
        final editorial = action['editorial']! as JsonMap;
        representations += (editorial['tags']! as List<Object?>)
            .where((tag) => (tag! as String).startsWith('v3.direction.'))
            .length;
      }
    }
    expect(catalog.concepts, hasLength(55));
    expect(actionIds, hasLength(146));
    expect(representations, 268);
  });
  test(
    'V1 copy renders stage directions, semantic exceptions and camera subjects',
    () {
      String text(
        String id,
        String action,
        CardOccurrenceDirection direction,
      ) => renderer
          .render(concept: concept(id), actionId: action, direction: direction)
          .actionText;
      expect(
        text('055', '055.action', CardOccurrenceDirection.FAIRE),
        startsWith('Lors de ta prochaine éjaculation, choisis'),
      );
      expect(
        text('055', '055.action', CardOccurrenceDirection.RECEVOIR),
        contains('tu éjaculeras'),
      );
      expect(
        concept('055').detailsText,
        'Dans tous les cas, le choix doit convenir aux deux partenaires.',
      );
      expect(
        text('033', '033.action', CardOccurrenceDirection.FAIRE),
        startsWith('Tu ne peux plus toucher'),
      );
      expect(
        text('061', '061.action', CardOccurrenceDirection.FAIRE),
        startsWith('Garde un silence complet'),
      );
      for (final id in ['044', '046']) {
        expect(
          text(id, '$id.stage.1', CardOccurrenceDirection.FAIRE),
          contains('de toi'),
        );
        expect(
          text(id, '$id.stage.1', CardOccurrenceDirection.RECEVOIR),
          contains('de sa personne'),
        );
      }
      for (final c in catalog.concepts) {
        for (final a in [
          ...c.stages.map((a) => a.id),
          ...c.variants.map((a) => a.id),
        ]) {
          for (final d in CardOccurrenceDirection.values) {
            final rendered = renderer.render(
              concept: c,
              actionId: a,
              direction: d,
            );
            expect(rendered.actionText, isNot(contains('{')));
            expect(rendered.actionText, isNot(contains('miroir sémantique')));
          }
        }
      }
      expect(catalog.concepts.map((c) => c.id), isNot(contains('060')));
    },
  );
}
