import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/profile/initial_questionnaire_engine.dart';
import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';
import 'package:test/test.dart';

void main() {
  test('production loader uses exactly the 65 V4 cards', () async {
    final catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
    );
    expect(catalog.catalogVersion, 4);
    expect(catalog.cards, hasLength(65));
    expect(
      catalog.cards.map((item) => item.order),
      orderedEquals(List.generate(65, (i) => i + 1)),
    );
    expect(
      catalog.cards.every((item) => item.stableId.startsWith('card.v4.')),
      isTrue,
    );
    expect(catalog.cards.expand((item) => item.variants), hasLength(155));
  });

  test('scoring audit is 65 OK, 0 partial, 0 missing', () {
    final source = File(
      'assets/catalog/source/catalog_v4_scoring.json',
    ).readAsStringSync();
    final json = jsonDecode(source) as Map<String, Object?>;
    expect(json['coverage'], {'ok': 65, 'partial': 0, 'missing': 0});
    final scoring = V4ScoringCatalog.decode(source);
    expect(scoring.cards, hasLength(65));
    expect(scoring.cards.expand((item) => item.variants), hasLength(155));
  });

  test('legacy catalogues are archived outside the production asset path', () {
    expect(
      File('assets/catalog/source/cards.v1.fr.json').existsSync(),
      isFalse,
    );
    expect(
      File('assets/catalog/source/cards.v2.fr.json').existsSync(),
      isFalse,
    );
    expect(File('assets/catalog/legacy/cards.v1.fr.json').existsSync(), isTrue);
    expect(File('assets/catalog/legacy/cards.v2.fr.json').existsSync(), isTrue);
  });

  test('every scoreable variant has explicit primary tags', () {
    final scoring = V4ScoringCatalog.decode(
      File('assets/catalog/source/catalog_v4_scoring.json').readAsStringSync(),
    );
    for (final variant in scoring.cards.expand((item) => item.variants)) {
      expect(
        variant.primaryPreferenceTags,
        isNotEmpty,
        reason: variant.variantId,
      );
      expect(
        variant.primaryPreferenceTags.toSet().intersection(
          variant.secondaryPreferenceTags.toSet(),
        ),
        isEmpty,
        reason: variant.variantId,
      );
    }
  });

  test('the 17 questions initialize every preference used by V4 scoring', () {
    final questionnaire = ProfileQuestionnaire.decode(
      File(
        'assets/catalog/source/profile_questions.v1.fr.json',
      ).readAsStringSync(),
    );
    final scoring = V4ScoringCatalog.decode(
      File('assets/catalog/source/catalog_v4_scoring.json').readAsStringSync(),
    );
    final initializedTags = {
      for (final question in questionnaire.questions)
        for (final axis in question.axes)
          for (final write in axis.writes) write.tagId,
    };
    final scoredTags = {
      for (final variant in scoring.cards.expand((card) => card.variants))
        ...variant.primaryPreferenceTags,
      for (final variant in scoring.cards.expand((card) => card.variants))
        ...variant.secondaryPreferenceTags,
    };

    expect(scoredTags.difference(initializedTags), isEmpty);
  });

  test('a complete questionnaire initializes all 155 scoreable variants', () {
    final questionnaire = ProfileQuestionnaire.decode(
      File(
        'assets/catalog/source/profile_questions.v1.fr.json',
      ).readAsStringSync(),
    );
    final profile = const InitialQuestionnaireEngine().initialize(
      profileId: 'p',
      questionnaire: questionnaire,
      responses: {
        for (final question in questionnaire.questions)
          for (final axis in question.axes)
            '${question.stableId}|${axis.axisId}': InitialQuestionResponse.like,
      },
    );
    final scoring = V4ScoringCatalog.decode(
      File('assets/catalog/source/catalog_v4_scoring.json').readAsStringSync(),
    );
    const engine = V4CardRatingEngine();
    for (final variant in scoring.cards.expand((card) => card.variants)) {
      final results = [
        for (final role in ProfilePreferenceRole.values)
          engine.initialize(
            profile: profile,
            variant: variant,
            effectiveRole: role,
          ),
      ];
      expect(
        results.any((result) => result.kind == V4RatingResultKind.rated),
        isTrue,
        reason: variant.variantId,
      );
    }
  });

  test('normative variant classifications remain exact', () {
    final scoring = V4ScoringCatalog.decode(
      File('assets/catalog/source/catalog_v4_scoring.json').readAsStringSync(),
    );
    V4VariantRatingDefinition variant(String id) => scoring.cards
        .expand((card) => card.variants)
        .singleWhere((variant) => variant.variantId == id);

    for (final stage in [1, 2, 3]) {
      final spanking = variant('variant.v4.037.s$stage');
      expect(spanking.primaryPreferenceTags, ['frapper']);
      expect(spanking.nonPreferenceData, contains('fesses'));
    }
    expect(variant('variant.v4.034.s3').primaryPreferenceTags, ['immobiliser']);
    expect(variant('variant.v4.034.s3').secondaryPreferenceTags, [
      'attacher',
      'controle',
    ]);
    expect(variant('variant.v4.049.phallus.s1').primaryPreferenceTags, [
      'sextoy',
    ]);
    expect(
      variant('variant.v4.049.phallus.s1').nonPreferenceData,
      contains('phallus'),
    );
    expect(variant('variant.v4.064.nourriture').primaryPreferenceTags, [
      'nourriture',
    ]);
    expect(variant('variant.v4.064.boisson').primaryPreferenceTags, [
      'boisson',
    ]);
  });
}
