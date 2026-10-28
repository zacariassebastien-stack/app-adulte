import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/eligibility/concept_action_options.dart';
import 'package:couple_cards/engines/eligibility/concept_context.dart';
import 'package:couple_cards/engines/eligibility/concept_runtime_catalog.dart';
import 'package:couple_cards/engines/eligibility/session_occurrence_consent.dart';
import 'package:couple_cards/engines/profile/initial_questionnaire_engine.dart';
import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';
import 'package:couple_cards/engines/runtime/v4_runtime_engine.dart';

void main() {
  late ConceptRuntimeCatalog catalog;
  late ProfileQuestionnaire questionnaire;
  setUpAll(() async {
    final source = await const CatalogLoader().load(
      (p) => File(p).readAsString(),
      includeConcepts: true,
    );
    catalog = ConceptRuntimeCatalog(
      concepts: source.concepts!,
      source: source,
      rules: source.conceptRules!,
    );
    questionnaire = ProfileQuestionnaire.decode(
      File(
        'assets/catalog/source/profile_questions.v1.fr.json',
      ).readAsStringSync(),
    );
  });
  V4Profile profile([
    Map<String, InitialQuestionResponse> overrides = const {},
  ]) => const InitialQuestionnaireEngine().initialize(
    profileId: 'a',
    sex: ProfileSex.HOMME,
    questionnaire: questionnaire,
    responses: {
      for (final q in questionnaire.questions)
        for (final a in q.axes)
          '${q.stableId}|${a.axisId}': InitialQuestionResponse.like,
      ...overrides,
    },
  );
  Map<String, List<ConceptActionOption>> options({
    V4Profile? p,
    int ownerClothes = 3,
    int partnerClothes = 3,
    SessionMode mode = SessionMode.face_to_face,
    ProximityState proximity = ProximityState.TOGETHER,
    Set<MediaCapability> media = const {},
    Set<MediaCapability> partnerMedia = const {},
    List<V4Accessory> accessories = const [],
    Map<String, bool> flags = const {},
    bool send = false,
    CardSpecificLearningStore? ratings,
  }) {
    final context = ConceptContext.resolve(
      context: EngineSessionContext(
        mode: mode,
        proximity: proximity,
        chiliActive: 4,
        chiliUnlocked: 4,
        clothesByPlayer: {'a': ownerClothes, 'b': partnerClothes},
        mediaCapabilitiesByPlayer: {'a': media, 'b': partnerMedia},
        flags: flags,
      ),
      profile: p ?? profile(),
      accessories: accessories,
    );
    return const ConceptActionOptions().evaluate(
      catalog: catalog,
      context: context,
      actor: PlayerGameProfile(playerId: 'a'),
      partner: PlayerGameProfile(playerId: 'b'),
      hierarchy: ProfileHierarchy({}),
      profile: p ?? profile(),
      cardRatings: ratings,
      mediaSendRequired: send,
    );
  }

  V4RatingResult rate(String id, String direction, V4Profile p) =>
      const V4CardRatingEngine().initializeForDirection(
        profile: p,
        variant: catalog.ratingFor(
          id,
          catalog.definitions[id]!.variants.first.stableId,
        ),
        conceptId: id,
        direction: direction,
        vetoTags: catalog.vetoTags(id),
      );
  test(
    '058 respects its structural presence constraint including hybrid orientation',
    () {
      expect(options(), contains('058'));
      expect(options(mode: SessionMode.hybrid), contains('058'));
      expect(
        options(
          mode: SessionMode.distance,
          proximity: ProximityState.SEPARATED,
        ),
        isNot(contains('058')),
      );
      expect(
        options(mode: SessionMode.hybrid, proximity: ProximityState.SEPARATED),
        isNot(contains('058')),
      );
    },
  );
  for (final pair in [
    (MediaCapability.PHOTO_CAPTURE, ['044', '045'], ['046', '047']),
    (MediaCapability.RECORDED_VIDEO, ['046', '047'], ['044', '045']),
  ]) {
    test('media capability ${pair.$1} enables only compatible actions', () {
      final available = options(media: {pair.$1});
      for (final id in pair.$2) {
        expect(available, contains(id));
      }
      for (final id in pair.$3) {
        expect(available, isNot(contains(id)));
      }
      for (final id in [...pair.$2, ...pair.$3]) {
        expect(options(), isNot(contains(id)));
      }
    });
  }
  test(
    'capture and conditional send receive capabilities remain independent',
    () {
      final capture = options(media: {MediaCapability.PHOTO_CAPTURE});
      expect(
        capture['044']!.first.variant.tags,
        isNot(contains('v3.preference.envoyer')),
      );
      expect(
        options(media: {MediaCapability.PHOTO_CAPTURE}, send: true),
        isNot(contains('044')),
      );
      final sent = options(
        media: {MediaCapability.PHOTO_CAPTURE, MediaCapability.MEDIA_SEND},
        partnerMedia: {MediaCapability.MEDIA_RECEIVE},
        send: true,
      );
      expect(
        sent['044']!.first.variant.tags,
        contains('v3.preference.envoyer'),
      );
    },
  );
  V4Accessory restraint({
    String name = 'Sangle',
    Set<V4AccessoryTag> tags = const {V4AccessoryTag.entrave},
  }) =>
      V4Accessory(id: 'restraint', name: name, ownerPlayerId: 'a', tags: tags);
  test(
    '034 requires an explicit available restraint capability not a name or toy tag',
    () {
      expect(options(), isNot(contains('034')));
      expect(options(accessories: [restraint()]), contains('034'));
      expect(
        options(
          accessories: [
            restraint(name: 'Entrave', tags: {V4AccessoryTag.externe}),
          ],
        ),
        isNot(contains('034')),
      );
      expect(
        options(
          accessories: [restraint()],
          flags: {'hasConstraintAccessory': false},
        ),
        isNot(contains('034')),
      );
      final disabled = V4SessionAccessoryPool(
        profileAccessories: [restraint()],
        disabledIds: ['restraint'],
      );
      expect(options(accessories: disabled.available), isNot(contains('034')));
      for (final id in ['049', '050', '051', '052']) {
        expect(options(accessories: [restraint()]), isNot(contains(id)));
      }
    },
  );
  test(
    '048 derives roleplay availability from the real profile and respects veto or explicit context',
    () {
      expect(options(), contains('048'));
      expect(
        options(
          p: profile({
            'question.v1.14|general': InitialQuestionResponse.excluded,
          }),
        ),
        isNot(contains('048')),
      );
      expect(
        options(flags: {'roleplayEnabled': false}),
        isNot(contains('048')),
      );
    },
  );
  for (final entry in [('006', 1), ('007', 2)]) {
    for (final clothes in [(0, 3), (3, 0), (3, 3), (0, 0), (1, 1)]) {
      test(
        '${entry.$1} removal checks actual target for clothing ${clothes.$1}/${clothes.$2}',
        () {
          final option = options(
            ownerClothes: clothes.$1,
            partnerClothes: clothes.$2,
          )[entry.$1]?.single;
          expect(
            option?.allowsDirection(CardOccurrenceDirection.FAIRE) ?? false,
            clothes.$2 >= entry.$2,
          );
          expect(
            option?.allowsDirection(CardOccurrenceDirection.RECEVOIR) ?? false,
            clothes.$1 >= entry.$2,
          );
        },
      );
    }
  }
  for (final id in ['006', '007', '012']) {
    test(
      '$id Q05 bootstrap follows whose outfit changes while effective roles stay independent',
      () {
        final different = profile({
          'question.v1.05|moi': InitialQuestionResponse.love,
          'question.v1.05|partenaire': InitialQuestionResponse.unsure,
        });
        expect(rate(id, 'FAIRE', different).componentValues.first, 18);
        expect(rate(id, 'RECEVOIR', different).componentValues.first, 5);
        final veto = profile({
          'question.v1.05|moi': InitialQuestionResponse.excluded,
        });
        expect(rate(id, 'FAIRE', veto).kind, V4RatingResultKind.rated);
        expect(rate(id, 'RECEVOIR', veto).kind, V4RatingResultKind.excluded);
        bool permits(String owner, CardOccurrenceDirection d) =>
            const SessionOccurrenceConsent().allows(
              catalog: catalog,
              profile: veto,
              subjectId: 'a',
              ownerId: owner,
              playerIds: ['a', 'b'],
              conceptId: id,
              actionId: '$id.action',
              direction: d,
            );
        expect(permits('a', CardOccurrenceDirection.FAIRE), isTrue);
        expect(permits('a', CardOccurrenceDirection.RECEVOIR), isFalse);
        expect(permits('b', CardOccurrenceDirection.FAIRE), isFalse);
        expect(permits('b', CardOccurrenceDirection.RECEVOIR), isTrue);
      },
    );
  }
  test(
    'Q05 translation does not invert manual or learned effective role preferences',
    () {
      for (final source in [
        ProfilePreferenceSource.manualCustomized,
        ProfilePreferenceSource.autoLearned,
      ]) {
        final p = profile();
        const key = ProfilePreferenceKey(
          tagId: 'enlever',
          role: ProfilePreferenceRole.faire,
        );
        final changed = V4Profile(
          profileId: p.profileId,
          sex: p.sex,
          preferences: {
            ...p.preferences,
            key.storageKey: ProfilePreference(
              profileId: 'a',
              key: key,
              pa: null,
              excluded: true,
              source: source,
            ),
            'enlever|recevoir': ProfilePreference(
              profileId: 'a',
              key: const ProfilePreferenceKey(
                tagId: 'enlever',
                role: ProfilePreferenceRole.recevoir,
              ),
              pa: 12,
              excluded: false,
              source: source,
            ),
          },
        );
        expect(rate('006', 'FAIRE', changed).kind, V4RatingResultKind.excluded);
        expect(rate('006', 'RECEVOIR', changed).kind, V4RatingResultKind.rated);
      }
    },
  );
  test('personal clothing and self outfit keep their original Q05 meaning', () {
    final p = profile({
      'question.v1.05|moi': InitialQuestionResponse.love,
      'question.v1.05|partenaire': InitialQuestionResponse.unsure,
    });
    for (final id in ['008', '009']) {
      expect(rate(id, 'FAIRE', p).componentValues.first, 5);
      expect(rate(id, 'RECEVOIR', p).componentValues.first, 18);
    }
    expect(rate('013', 'SOLO', p).componentValues.first, 5);
  });
  for (final response in InitialQuestionResponse.values) {
    test(
      'Q01 initializes 031 through the generic frotter preference: $response',
      () {
        final axis = questionnaire.questions
            .singleWhere((q) => q.stableId == 'question.v1.01')
            .axes
            .single;
        final write = axis.writes.singleWhere((w) => w.tagId == 'frotter');
        expect(write.role, ProfilePreferenceRole.mutuel);
        expect(write.zoneId, isNull);
        expect(write.weight, 1);
        final p = profile({'question.v1.01|mutuel': response});
        final preference = p.preference(
          const ProfilePreferenceKey(
            tagId: 'frotter',
            role: ProfilePreferenceRole.mutuel,
          ),
        )!;
        expect(preference.pa, response.pa);
        expect(
          preference.excluded,
          response == InitialQuestionResponse.excluded,
        );
        final definition = catalog.ratingFor('031', '031.action');
        expect(definition.primaryPreferenceTags, ['frotter']);
        expect(definition.secondaryPreferenceTags, isEmpty);
        // No concept ID is supplied: the generic preference resolver suffices.
        final generic = const V4CardRatingEngine().initialize(
          profile: p,
          variant: definition,
          effectiveRole: ProfilePreferenceRole.mutuel,
        );
        final actual = rate('031', 'MUTUEL', p);
        expect(actual.kind, generic.kind);
        expect(actual.rawScore, generic.rawScore);
        expect(
          actual.kind,
          response == InitialQuestionResponse.excluded
              ? V4RatingResultKind.excluded
              : V4RatingResultKind.rated,
        );
        expect(actual.rawScore, response.pa);
        expect(
          options(p: p).containsKey('031'),
          response != InitialQuestionResponse.excluded,
        );
        expect(
          const SessionOccurrenceConsent().allows(
            catalog: catalog,
            profile: p,
            subjectId: 'a',
            ownerId: 'a',
            playerIds: ['a', 'b'],
            conceptId: '031',
            actionId: '031.action',
            direction: CardOccurrenceDirection.MUTUEL,
          ),
          response != InitialQuestionResponse.excluded,
        );
      },
    );
  }
  test(
    'frotter preferences from every existing source survive reconstruction',
    () {
      const key = ProfilePreferenceKey(
        tagId: 'frotter',
        role: ProfilePreferenceRole.mutuel,
      );
      for (final source in ProfilePreferenceSource.values) {
        final p = V4Profile(
          profileId: 'a',
          sex: ProfileSex.HOMME,
          preferences: {
            key.storageKey: ProfilePreference(
              profileId: 'a',
              key: key,
              pa: null,
              excluded: true,
              source: source,
            ),
          },
        );
        final restored = V4Profile.fromJson(p.toJson());
        expect(restored.preferences[key.storageKey]!.excluded, isTrue);
        expect(restored.preferences[key.storageKey]!.source, source);
      }
    },
  );
  test(
    'questionnaire covers all 51 non-suspended concepts and 44 scoring preferences',
    () {
      final p = profile();
      final covered = <String>{};
      final scoringTags = <String>{};
      var actions = 0;
      var presentations = 0;
      for (final entry in catalog.definitions.entries) {
        for (final action in entry.value.variants) {
          final rating = catalog.optionalRatingFor(entry.key, action.stableId);
          if (const {'049', '050', '051', '052'}.contains(entry.key)) {
            expect(rating, isNull);
            continue;
          }
          expect(rating, isNotNull);
          actions++;
          scoringTags.addAll(rating!.primaryPreferenceTags);
          scoringTags.addAll(rating.secondaryPreferenceTags);
          for (final tag in action.v3!.tags.where(
            (t) => t.startsWith('v3.direction.'),
          )) {
            final direction = tag.split('.').last.toUpperCase();
            final result = const V4CardRatingEngine().initializeForDirection(
              profile: p,
              variant: rating,
              conceptId: entry.key,
              direction: direction,
            );
            expect(
              result.kind,
              V4RatingResultKind.rated,
              reason: '${entry.key}/${action.stableId}/$direction',
            );
            presentations++;
            covered.add(entry.key);
          }
        }
      }
      expect(covered.length, 51);
      expect(actions, 130);
      expect(presentations, 240);
      expect(scoringTags.length, 44);
      expect(
        p.preference(
          const ProfilePreferenceKey(
            tagId: 'frotter',
            role: ProfilePreferenceRole.mutuel,
          ),
        ),
        isNotNull,
      );
      expect(
        p.preferences.values.where((v) => v.key.tagId == 'penetrer'),
        isEmpty,
      );
      expect(rate('022', 'FAIRE', p).kind, V4RatingResultKind.rated);
      for (final id in ['049', '050', '051', '052']) {
        expect(options(), isNot(contains(id)));
      }
    },
  );
  test('044 stage 2 is not vetoed by an unrelated underwear exclusion', () {
    final p = profile();
    const key = ProfilePreferenceKey(
      tagId: 'sous_vetements',
      role: ProfilePreferenceRole.faire,
    );
    final excluded = V4Profile(
      profileId: p.profileId,
      sex: p.sex,
      preferences: {
        ...p.preferences,
        key.storageKey: ProfilePreference(
          profileId: 'a',
          key: key,
          pa: null,
          excluded: true,
          source: ProfilePreferenceSource.manualCustomized,
        ),
      },
    );
    final stage = options(
      p: excluded,
      media: {MediaCapability.PHOTO_CAPTURE},
    )['044']!.singleWhere((o) => o.choice.actionId == '044.stage.2');
    expect(stage.allowsDirection(CardOccurrenceDirection.FAIRE), isTrue);
    expect(
      catalog.vetoTags('044', actionId: '044.stage.2'),
      isNot(contains('sous_vetements')),
    );
  });
  test(
    'media stages render distinct boundaries and stage 3 details never leak backwards',
    () {
      final renderer = ConceptEditorialRenderer(catalog.concepts);
      for (final id in ['044', '045', '046', '047']) {
        final c = catalog.concepts.concepts.singleWhere((c) => c.id == id);
        expect(
          c.stages.map((s) => s.chili),
          id == '044' || id == '046' ? [1, 2, 3] : [1, 2, 4],
        );
        for (final direction
            in id == '044' || id == '046'
                ? [
                    CardOccurrenceDirection.FAIRE,
                    CardOccurrenceDirection.RECEVOIR,
                  ]
                : [CardOccurrenceDirection.MUTUEL]) {
          final texts = [
            for (final stage in c.stages)
              renderer.render(
                concept: c,
                actionId: stage.id,
                direction: direction,
              ),
          ];
          expect(
            texts[0].actionText,
            contains('sans nudité explicite ni activité sexuelle'),
          );
          expect(
            texts[1].actionText,
            contains('sans montrer d’activité sexuelle en cours'),
          );
          expect(
            texts[2].actionText,
            contains('pendant une activité sexuelle'),
          );
          if (id == '045' || id == '047') {
            for (final t in texts.take(2)) {
              expect(t.detailsText ?? '', isNot(contains('pénétration')));
            }
            expect(texts[2].detailsText, contains('sans l’imposer'));
          }
          if (id == '046' || id == '047') {
            for (final t in texts) {
              expect(
                t.detailsText,
                contains('Aucune durée minimale ou maximale'),
              );
            }
          }
        }
      }
      final fingers = catalog.concepts.concepts.singleWhere(
        (c) => c.id == '022',
      );
      expect(
        renderer
            .render(
              concept: fingers,
              actionId: '022.stage.3',
              direction: CardOccurrenceDirection.FAIRE,
            )
            .actionText,
        contains('que la personne'),
      );
      final oral = catalog.concepts.concepts.singleWhere((c) => c.id == '025');
      expect(oral.detailsText, isNot(contains('028')));
      expect(oral.detailsText, contains('Sexe oral anal'));
      expect(
        catalog.concepts.concepts.singleWhere((c) => c.id == '020').actionText,
        'Masturbez-vous l’un l’autre.',
      );
    },
  );
}
