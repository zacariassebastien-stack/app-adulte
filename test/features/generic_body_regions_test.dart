import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/catalog/catalog.dart';
import 'package:couple_cards/domain/catalog/concept_editorial.dart';
import 'package:couple_cards/domain/game/game_models.dart';
import 'package:couple_cards/domain/profile/adaptive_profile.dart';
import 'package:couple_cards/domain/profile/v4_profile.dart';
import 'package:couple_cards/domain/profile/generic_body_limits.dart';
import 'package:couple_cards/engines/deck/concept_deck_engine.dart';
import 'package:couple_cards/engines/eligibility/concept_runtime_catalog.dart';
import 'package:couple_cards/engines/eligibility/session_occurrence_consent.dart';
import 'package:couple_cards/engines/eligibility/anatomy_compatibility.dart';
import 'package:couple_cards/engines/profile/card_personalization_engine.dart';
import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';
import 'package:couple_cards/features/profile/catalog_profile_controller.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';

void main() {
  late Catalog catalog;
  late ConceptRuntimeCatalog runtime;
  setUpAll(() async {
    catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
      includeConcepts: true,
    );
    runtime = ConceptRuntimeCatalog(
      concepts: catalog.concepts!,
      source: catalog,
      rules: catalog.conceptRules!,
    );
  });
  V4Profile profile({
    List<StageVeto> vetoes = const [],
    bool scopedVeto = false,
  }) => V4Profile(
    profileId: 'alice',
    sex: ProfileSex.HOMME,
    preferences: {
      for (final tag in ['embrasser', 'bouche', 'main'])
        for (final role in [
          ProfilePreferenceRole.faire,
          ProfilePreferenceRole.recevoir,
        ])
          ProfilePreferenceKey(
            tagId: tag,
            role: role,
          ).storageKey: ProfilePreference(
            profileId: 'alice',
            key: ProfilePreferenceKey(tagId: tag, role: role),
            pa: 10,
            excluded: false,
            source: ProfilePreferenceSource.initialQuestionnaire,
          ),
      if (scopedVeto)
        'scoped': const ProfilePreference(
          profileId: 'alice',
          key: ProfilePreferenceKey(
            tagId: 'embrasser',
            role: ProfilePreferenceRole.recevoir,
            zoneId: 'chest',
          ),
          pa: null,
          excluded: true,
          source: ProfilePreferenceSource.manualCustomized,
        ),
    },
    stageVetoes: vetoes,
  );
  for (final conceptId in ['002', '004', '005']) {
    for (var stage = 1; stage <= 2; stage++) {
      for (final region in ['upper_body', 'lower_body', 'free']) {
        for (final direction in [
          CardOccurrenceDirection.FAIRE,
          CardOccurrenceDirection.RECEVOIR,
        ]) {
          final action = '$conceptId.stage.$stage.region.$region';
          test(
            '$action $direction has its own identity, fixed spice, natural text and anatomy',
            () {
              final concept = catalog.concepts!.concepts.singleWhere(
                (c) => c.id == conceptId,
              );
              expect(concept.stages, hasLength(2));
              expect(concept.variants, isEmpty);
              expect(concept.presentationStages, hasLength(6));
              final presentation = concept.presentationStages.singleWhere(
                (s) => s.id == action,
              );
              expect(presentation.chili, stage == 1 ? 2 : 3);
              expect(presentation.zoneId, region);
              final copy = ConceptEditorialRenderer(catalog.concepts!).render(
                concept: concept,
                actionId: action,
                direction: direction,
              );
              expect(copy.actionText, isNot(contains('{')));
              expect(copy.actionText, isNot(contains('zone indiquée')));
              expect(
                copy.actionText.toLowerCase(),
                contains(
                  {
                            '002': 'embrasser',
                            '004': 'bouche',
                            '005': 'mains',
                          }[conceptId] ==
                          'embrasser'
                      ? 'embrass'
                      : {'004': 'bouche', '005': 'mains'}[conceptId]!,
                ),
              );
              expect(
                copy.detailsText,
                contains(stage == 1 ? 'sensualité' : 'si l’envie s’y prête'),
              );
              expect(copy.detailsText, contains('Respectez les exclusions'));
              for (final owner in PlayerAnatomy.values) {
                for (final partner in PlayerAnatomy.values) {
                  expect(
                    AnatomyCompatibility.allows(
                      concept: concept,
                      actionId: action,
                      direction: direction,
                      ownerId: 'alice',
                      anatomies: {'alice': owner, 'bob': partner},
                    ),
                    isTrue,
                  );
                }
              }
            },
          );
        }
      }
    }
    test(
      '$conceptId profile retains twelve independent assessments and old data without fusion',
      () async {
        final profiles = MemoryV4ProfileStore();
        final oldVeto = StageVeto(
          conceptId: conceptId,
          actionId: '$conceptId.zone.chest',
          role: ProfilePreferenceRole.recevoir,
        );
        await profiles.save(profile(vetoes: [oldVeto]));
        final ratings = MemoryV4CardLearningStore();
        final oldKey = CardRatingKey(
          profileId: 'alice',
          cardId: conceptId,
          variantId: '$conceptId.zone.belly',
          role: ProfilePreferenceRole.recevoir,
        );
        final store = CardSpecificLearningStore()
          ..write(
            CardRatingStateV4(
              key: oldKey,
              initialScore: 3.5,
              currentEstimate: 3.5,
              observationCount: 1,
              acceptanceCount: 0,
              resistanceCount: 0,
              source: 'CARD_ESTIMATE',
            ),
          );
        await ratings.save('alice', store);
        final editor = CatalogProfileController(
          catalog: catalog,
          playerId: 'alice',
          profileStore: profiles,
          ratingStore: ratings,
          learningStore: MemoryNetworkProfileLearningStore(),
        );
        addTearDown(editor.dispose);
        await editor.load();
        final items = editor.items
            .where((i) => i.concept.id == conceptId)
            .toList();
        expect(items, hasLength(12));
        expect(
          items.map((i) => i.ratingKey('alice').storageKey).toSet(),
          hasLength(12),
        );
        expect(
          items.any((i) => GenericBodyLimits.isLegacy(i.actionId)),
          isFalse,
        );
        expect(
          items.every(
            (i) => editor.category(i) == DetailedPreferenceCategory.tempted,
          ),
          isTrue,
        );
        for (var i = 0; i < items.length; i++) {
          await editor.rate(items[i], DetailedPreferenceCategory.values[i % 9]);
        }
        final saved = await ratings.load('alice');
        for (var i = 0; i < items.length; i++) {
          expect(
            saved.explicitEstimate(items[i].ratingKey('alice')),
            DetailedPreferenceCategory.values[i % 9].personalPa,
          );
        }
        expect(saved.explicitEstimate(oldKey), 3.5);
        expect(
          (await profiles.load('alice'))!.stageVetoes.single.toJson(),
          oldVeto.toJson(),
        );
        expect(editor.items, hasLength(220));
      },
    );
  }
  test(
    'targeted legacy limits remain private per role and region without blanket veto',
    () {
      final p = profile(
        vetoes: const [
          StageVeto(
            conceptId: '002',
            actionId: '002.zone.chest',
            role: ProfilePreferenceRole.recevoir,
          ),
        ],
        scopedVeto: true,
      );
      for (final region in ['upper_body', 'lower_body', 'free']) {
        final action = '002.stage.1.region.$region';
        expect(
          GenericBodyLimits.forPresentation(p, '002', action, 'RECEVOIR'),
          region == 'lower_body' ? isEmpty : ['Poitrine / seins'],
        );
        expect(
          GenericBodyLimits.forPresentation(p, '002', action, 'FAIRE'),
          isEmpty,
        );
        for (final direction in [
          CardOccurrenceDirection.FAIRE,
          CardOccurrenceDirection.RECEVOIR,
        ]) {
          expect(
            const SessionOccurrenceConsent().allows(
              catalog: runtime,
              profile: p,
              subjectId: 'alice',
              ownerId: 'alice',
              playerIds: const ['alice', 'bob'],
              conceptId: '002',
              actionId: action,
              direction: direction,
            ),
            isTrue,
          );
        }
        final prior = const V4CardRatingEngine().initializeForDirection(
          profile: p,
          variant: runtime.ratingFor('002', action),
          conceptId: '002',
          direction: 'RECEVOIR',
          vetoTags: runtime.vetoTags('002', actionId: action),
        );
        expect(prior.rawScore, 10);
      }
    },
  );
  test(
    'new precise veto blocks only its presentation and whole-card veto remains blocking',
    () {
      const action = '002.stage.1.region.upper_body';
      for (final all in [false, true]) {
        final p = profile(
          vetoes: [
            StageVeto(
              conceptId: '002',
              actionId: all ? '*' : action,
              role: ProfilePreferenceRole.recevoir,
            ),
          ],
        );
        bool allows(String id, CardOccurrenceDirection direction) =>
            const SessionOccurrenceConsent().allows(
              catalog: runtime,
              profile: p,
              subjectId: 'alice',
              ownerId: 'alice',
              playerIds: const ['alice', 'bob'],
              conceptId: '002',
              actionId: id,
              direction: direction,
            );
        expect(allows(action, CardOccurrenceDirection.RECEVOIR), isFalse);
        expect(
          allows(
            '002.stage.2.region.lower_body',
            CardOccurrenceDirection.RECEVOIR,
          ),
          !all,
        );
        expect(allows(action, CardOccurrenceDirection.FAIRE), isTrue);
      }
    },
  );
  test(
    'old exact appreciation evidence does not seed new regional discovery scores',
    () {
      final store = CardSpecificLearningStore();
      const old = CardRatingKey(
        profileId: 'alice',
        cardId: '002',
        variantId: '002.zone.chest',
        role: ProfilePreferenceRole.faire,
      );
      store.write(
        const CardRatingStateV4(
          key: old,
          initialScore: 10,
          currentEstimate: 1.5,
          observationCount: 20,
          acceptanceCount: 0,
          resistanceCount: 0,
          source: 'CARD_ESTIMATE',
          personalization: {
            'tag_evidence': {'embrasser': -20},
          },
        ),
      );
      const fresh = CardRatingKey(
        profileId: 'alice',
        cardId: '002',
        variantId: '002.stage.1.region.upper_body',
        role: ProfilePreferenceRole.faire,
      );
      const engine = CardPersonalizationEngine();
      expect(
        engine.drawWeight(store, fresh, 10, {'embrasser': 1}),
        engine.drawWeight(CardSpecificLearningStore(), fresh, 10, {
          'embrasser': 1,
        }),
      );
    },
  );
  test(
    'new regional tag exclusions block their region without reviving old anatomical vetoes',
    () {
      final base = profile();
      final p = V4Profile(
        profileId: base.profileId,
        sex: base.sex,
        preferences: {
          ...base.preferences,
          'region': const ProfilePreference(
            profileId: 'alice',
            key: ProfilePreferenceKey(
              tagId: 'embrasser',
              role: ProfilePreferenceRole.recevoir,
              zoneId: 'upper_body',
            ),
            pa: null,
            excluded: true,
            source: ProfilePreferenceSource.manualCustomized,
          ),
        },
      );
      bool allows(String region, CardOccurrenceDirection direction) =>
          const SessionOccurrenceConsent().allows(
            catalog: runtime,
            profile: p,
            subjectId: 'alice',
            ownerId: 'alice',
            playerIds: const ['alice', 'bob'],
            conceptId: '002',
            actionId: '002.stage.1.region.$region',
            direction: direction,
          );
      expect(allows('upper_body', CardOccurrenceDirection.RECEVOIR), isFalse);
      expect(allows('lower_body', CardOccurrenceDirection.RECEVOIR), isTrue);
      expect(allows('upper_body', CardOccurrenceDirection.FAIRE), isTrue);
    },
  );
  test(
    'one concept quota follows its two editorial stages, not six or twelve presentations',
    () {
      final stock = ConceptDeckStock.startCycle(
        catalog: catalog.concepts!,
        initialClothing: 5,
      );
      for (final id in ['002', '004', '005']) {
        expect(stock.remainingFor(id), 2);
      }
    },
  );
}
