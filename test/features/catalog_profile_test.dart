import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/catalog/catalog.dart';
import 'package:couple_cards/domain/catalog/concept_catalog.dart';
import 'package:couple_cards/domain/catalog/v4_catalog.dart';
import 'package:couple_cards/domain/profile/adaptive_profile.dart';
import 'package:couple_cards/domain/profile/v4_profile.dart';
import 'package:couple_cards/engines/profile/initial_questionnaire_engine.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:couple_cards/features/profile/catalog_profile_controller.dart';
import 'package:couple_cards/features/profile/catalog_profile_screen.dart';
import 'package:couple_cards/features/profile/catalog_profile_binder_order.dart';
import 'package:couple_cards/features/profile/radial_appreciation.dart';
import 'package:couple_cards/card_themes/card_renderer.dart';
import 'package:couple_cards/features/lobby/two_phone_lobby_screen.dart';
import 'package:couple_cards/features/lobby/lobby_repository.dart';
import 'package:couple_cards/engines/eligibility/concept_action_options.dart';
import 'package:couple_cards/engines/eligibility/session_occurrence_consent.dart';
import 'package:couple_cards/domain/catalog/enums.dart';
import 'package:couple_cards/domain/game/game_models.dart';

void main() {
  late Catalog catalog;
  late V4Profile base;
  late MemoryV4ProfileStore profiles;
  late MemoryV4CardLearningStore ratings;
  late MemoryNetworkProfileLearningStore learning;
  setUpAll(() async {
    catalog = await const CatalogLoader().load(
      (p) => File(p).readAsString(),
      includeConcepts: true,
    );
    final q = ProfileQuestionnaire.decode(
      File(
        'assets/catalog/source/profile_questions.v1.fr.json',
      ).readAsStringSync(),
    );
    base = const InitialQuestionnaireEngine().initialize(
      sex: ProfileSex.HOMME,
      profileId: 'p',
      questionnaire: q,
      responses: {
        for (final question in q.questions)
          for (final axis in question.axes)
            '${question.stableId}|${axis.axisId}': InitialQuestionResponse.like,
      },
    );
  });
  setUp(() async {
    profiles = MemoryV4ProfileStore();
    ratings = MemoryV4CardLearningStore();
    learning = MemoryNetworkProfileLearningStore();
    await profiles.save(base);
  });
  CatalogProfileController editor([Catalog? data]) => CatalogProfileController(
    catalog: data ?? catalog,
    playerId: 'p',
    profileStore: profiles,
    ratingStore: ratings,
    learningStore: learning,
  );
  ProfileCatalogItem item(
    CatalogProfileController c,
    String action, [
    String role = 'FAIRE',
  ]) => c.items.singleWhere(
    (i) => i.actionId == action && i.direction.name == role,
  );

  test(
    'explicit appreciation uses existing values and only the selected stage and role',
    () async {
      final c = editor();
      await c.load();
      final target = item(c, '056.stage.2');
      final preferences = jsonEncode(
        c.profile.preferences.map((k, v) => MapEntry(k, v.toJson())),
      );
      await c.rate(target, DetailedPreferenceCategory.love);
      expect(c.category(target), DetailedPreferenceCategory.love);
      expect(c.ratings.explicitEstimate(target.ratingKey('p')), 3.5);
      expect(c.explicit(item(c, '056.stage.1')), isFalse);
      expect(c.explicit(item(c, '056.stage.2', 'RECEVOIR')), isFalse);
      expect(
        jsonEncode(
          c.profile.preferences.map((k, v) => MapEntry(k, v.toJson())),
        ),
        preferences,
      );
      final reopened = editor();
      await reopened.load();
      expect(
        reopened.category(item(reopened, '056.stage.2')),
        DetailedPreferenceCategory.love,
      );
      expect(reopened.remaining.map((i) => i.id), isNot(contains(target.id)));
      c.dispose();
      reopened.dispose();
    },
  );
  test(
    'every random successor has a valid nullable prior after persistence',
    () async {
      final c = editor();
      await c.load();
      while (c.remaining.isNotEmpty) {
        final next = c.randomNext(random: math.Random(42));
        expect(next, isNotNull);
        expect(() => c.category(next!), returnsNormally);
        await c.rate(next!, DetailedPreferenceCategory.like);
        expect(c.remaining.map((i) => i.id), isNot(contains(next.id)));
        final following = c.randomNext(random: math.Random(42));
        if (following != null) {
          expect(() => c.category(following), returnsNormally);
        }
      }
      c.dispose();
    },
  );

  test(
    'lifting a stage veto preserves its previous appreciation and survives reload',
    () async {
      final c = editor();
      await c.load();
      final target = item(c, '056.stage.2');
      await c.rate(target, DetailedPreferenceCategory.like);
      await c.rate(target, DetailedPreferenceCategory.excluded);
      final estimate = c.ratings.explicitEstimate(target.ratingKey('p'));
      await c.allowStage(target);
      final reopened = editor();
      await reopened.load();
      expect(
        reopened.profile.excludesStage('056', target.actionId, 'FAIRE'),
        isFalse,
      );
      expect(
        reopened.ratings.explicitEstimate(target.ratingKey('p')),
        estimate,
      );
      c.dispose();
      reopened.dispose();
    },
  );
  test(
    'role-scoped whole-card vetoes persist independently without rating the opposite role',
    () async {
      final c = editor();
      await c.load();
      await c.excludeCard('012', role: ProfilePreferenceRole.faire);
      expect(c.profile.excludesStage('012', '012.action', 'FAIRE'), isTrue);
      expect(c.profile.excludesStage('012', '012.action', 'RECEVOIR'), isFalse);
      final receive = c.items.singleWhere(
        (i) => i.concept.id == '012' && i.direction.name == 'RECEVOIR',
      );
      expect(c.ratings.explicitEstimate(receive.ratingKey('p')), isNull);
      expect(c.cardExcluded('012'), isFalse, reason: 'Not a global veto');
      await c.excludeCard('012', role: ProfilePreferenceRole.recevoir);
      final reopened = editor();
      await reopened.load();
      await reopened.excludeCard(
        '012',
        role: ProfilePreferenceRole.faire,
        excluded: false,
      );
      expect(
        reopened.profile.excludesStage('012', '012.action', 'FAIRE'),
        isFalse,
      );
      expect(
        reopened.profile.excludesStage('012', '012.action', 'RECEVOIR'),
        isTrue,
      );
      c.dispose();
      reopened.dispose();
    },
  );
  test(
    'stage and whole-card exclusions reuse vetoes and remain private and reversible',
    () async {
      final c = editor();
      await c.load();
      final target = item(c, '056.stage.3');
      await c.rate(target, DetailedPreferenceCategory.excluded);
      expect(c.profile.excludesStage('056', '056.stage.3', 'FAIRE'), isTrue);
      expect(c.profile.excludesStage('056', '056.stage.2', 'FAIRE'), isFalse);
      expect(
        c.profile.excludesStage('056', '056.stage.3', 'RECEVOIR'),
        isFalse,
      );
      await c.rate(target, DetailedPreferenceCategory.like);
      expect(c.profile.excludesStage('056', '056.stage.3', 'FAIRE'), isFalse);
      await c.excludeCard('056');
      expect(c.profile.excludesStage('056', '056.stage.1', 'RECEVOIR'), isTrue);
      expect(c.profile.excludesStage('056', '056.stage.4', 'FAIRE'), isTrue);
      expect(c.profile.excludesStage('057', '057.stage.1', 'FAIRE'), isFalse);
      final reopened = editor();
      await reopened.load();
      expect(reopened.remaining.where((i) => i.concept.id == '056'), isEmpty);
      await reopened.excludeCard('056', excluded: false);
      expect(
        reopened.profile.excludesStage('056', '056.stage.1', 'FAIRE'),
        isFalse,
      );
      expect(reopened.remaining.where((i) => i.concept.id == '056'), isEmpty);
      expect(reopened.profile.preferences.length, base.preferences.length);
      c.dispose();
      reopened.dispose();
    },
  );
  test(
    'random never repeats explicit choices across reload and discovers new catalogue identities',
    () async {
      final c = editor();
      await c.load();
      final seen = <String>{};
      while (true) {
        final next = c.randomNext(random: math.Random(12));
        if (next == null) break;
        expect(seen.add(next.id), isTrue);
        await c.rate(next, DetailedPreferenceCategory.unsure);
      }
      expect(seen.length, c.items.length);
      final copy =
          jsonDecode(jsonEncode(catalog.concepts!.toJson()))
              as Map<String, Object?>;
      final concepts = copy['concepts'] as List;
      final added =
          jsonDecode(
                jsonEncode(
                  concepts.cast<Map<String, Object?>>().singleWhere(
                    (x) => x['id'] == '065',
                  ),
                ),
              )
              as Map<String, Object?>;
      added['id'] = '066';
      (added['variants'] as List).cast<Map<String, Object?>>().single['id'] =
          '066.action';
      concepts.add(added);
      final rules =
          jsonDecode(jsonEncode(catalog.conceptRules)) as Map<String, Object?>;
      final bindings = rules['bindings'] as List;
      final binding =
          jsonDecode(
                jsonEncode(
                  bindings.cast<Map<String, Object?>>().singleWhere(
                    (b) => b['concept_id'] == '065',
                  ),
                ),
              )
              as Map<String, Object?>;
      binding['concept_id'] = '066';
      (binding['actions'] as List)
              .cast<Map<String, Object?>>()
              .single['action_id'] =
          '066.action';
      bindings.add(binding);
      final updated = Catalog(
        cardsDocument: catalog.cardsDocument,
        profilesDocument: catalog.profilesDocument,
        tagsDocument: catalog.tagsDocument,
        concepts: ConceptCatalog.fromJson(copy),
        conceptRules: rules,
      );
      final reopened = editor(updated);
      await reopened.load();
      expect(reopened.remaining, isNotEmpty);
      expect(reopened.remaining.every((i) => i.concept.id == '066'), isTrue);
      c.dispose();
      reopened.dispose();
    },
  );
  test(
    'real local stores preserve explicit category and veto without altering old profiles',
    () async {
      SharedPreferences.setMockInitialValues({
        'profile_preferences_v4.p': jsonEncode(
          base.toJson()..remove('stage_vetoes'),
        ),
      });
      CatalogProfileController local() =>
          CatalogProfileController(catalog: catalog, playerId: 'p');
      final c = local();
      await c.load();
      expect(c.profile.stageVetoes, isEmpty);
      await c.rate(
        item(c, '056.stage.1'),
        DetailedPreferenceCategory.atMyLimit,
      );
      await c.rate(
        item(c, '056.stage.3', 'RECEVOIR'),
        DetailedPreferenceCategory.excluded,
      );
      final reopened = local();
      await reopened.load();
      expect(
        reopened.category(item(reopened, '056.stage.1')),
        DetailedPreferenceCategory.atMyLimit,
      );
      expect(
        reopened.profile.excludesStage('056', '056.stage.3', 'RECEVOIR'),
        isTrue,
      );
      expect(
        reopened.explicit(item(reopened, '056.stage.3', 'RECEVOIR')),
        isTrue,
      );
      c.dispose();
      reopened.dispose();
    },
  );
  test(
    'explicit positive estimate authorizes only its exact vetoed presentation',
    () async {
      const key = ProfilePreferenceKey(
        tagId: 'degradant',
        role: ProfilePreferenceRole.faire,
      );
      await profiles.save(
        V4Profile(
          sex: ProfileSex.HOMME,
          profileId: 'p',
          preferences: {
            ...base.preferences,
            key.storageKey: const ProfilePreference(
              profileId: 'p',
              key: key,
              pa: null,
              excluded: true,
              source: ProfilePreferenceSource.manualCustomized,
            ),
          },
        ),
      );
      final c = editor();
      await c.load();
      final target = item(c, '056.stage.1');
      await c.rate(target, DetailedPreferenceCategory.love);
      expect(c.globalTagVeto(target), isFalse);
      expect(c.globalTagVeto(item(c, '056.stage.2')), isTrue);
      final options = const ConceptActionOptions().evaluate(
        catalog: c.runtime,
        profile: c.profile,
        cardRatings: c.ratings,
        context: EngineSessionContext(
          mode: SessionMode.face_to_face,
          proximity: ProximityState.TOGETHER,
          chiliActive: 4,
          chiliUnlocked: 4,
        ),
        actor: PlayerGameProfile(playerId: 'p', preferences: const {}),
        partner: PlayerGameProfile(playerId: 'other', preferences: const {}),
        hierarchy: ProfileHierarchy(const {}),
      );
      expect(
        options.containsKey('056'),
        isTrue,
        reason: 'The precise exception and the opposite role are allowed',
      );
      expect(c.globalTagVeto(item(c, '056.stage.1', 'RECEVOIR')), isFalse);
      expect(c.profile.preferences[key.storageKey]!.excluded, isTrue);
      c.dispose();
    },
  );
  test('precise exception never overrides partner veto or authorizes other stages', () async {
    const key = ProfilePreferenceKey(tagId: 'degradant', role: ProfilePreferenceRole.general);
    final veto = ProfilePreference(profileId: 'p', key: key, pa: null,
      excluded: true, source: ProfilePreferenceSource.initialQuestionnaire);
    await profiles.save(V4Profile(profileId: 'p', sex: ProfileSex.HOMME,
      preferences: {...base.preferences, key.storageKey: veto}));
    final c = editor();
    await c.load();
    await c.rate(item(c, '056.stage.1'), DetailedPreferenceCategory.love);
    bool allows(V4Profile p, String subject, String action, CardOccurrenceDirection direction) =>
      const SessionOccurrenceConsent().allows(catalog: c.runtime, profile: p,
        subjectId: subject, ownerId: 'p', playerIds: const ['p', 'other'],
        conceptId: '056', actionId: action, direction: direction);
    expect(allows(c.profile, 'p', '056.stage.1', CardOccurrenceDirection.FAIRE), true);
    expect(allows(c.profile, 'p', '056.stage.2', CardOccurrenceDirection.FAIRE), false);
    expect(allows(c.profile, 'p', '056.stage.1', CardOccurrenceDirection.RECEVOIR), false);
    final partner = V4Profile(profileId: 'other', sex: ProfileSex.FEMME,
      preferences: {...base.preferences, key.storageKey: veto});
    expect(allows(partner, 'other', '056.stage.1', CardOccurrenceDirection.FAIRE), false);
    c.dispose();
  });

  test('legacy CARD_ESTIMATE from exclusion creates no positive permission', () async {
    final c = editor();
    await c.load();
    await c.excludeCard('056');
    final legacyJson = c.profile.toJson()..remove('presentation_allowances');
    final legacy = V4Profile.fromJson(legacyJson);
    expect(legacy.presentationAllowances, isEmpty);
    expect(legacy.excludesStage('056', '056.stage.1', 'FAIRE'), true);
    expect(c.ratings.read(item(c, '056.stage.1').ratingKey('p'))!.source, 'EXCLUSION_MARKER');
    c.dispose();
  });

  List<ProfileCatalogItem> arrange(
    CatalogProfileController c,
    ProfileBinderSort sort, {
    Set<CardOccurrenceDirection> roles = const {},
    Set<int> spices = const {},
    ProfileBinderEvaluation evaluation = ProfileBinderEvaluation.all,
    String query = '',
  }) => ProfileBinderOrder.select(
    items: c.items,
    isEvaluated: c.explicit,
    categoryFor: c.category,
    estimateFor: (i) => c.ratings.explicitEstimate(i.ratingKey('p')),
    sort: sort,
    roles: roles,
    spices: spices,
    evaluation: evaluation,
    query: query,
  );

  test(
    'binder ranks precise assessments before proximity without averaging a concept',
    () async {
      final c = editor();
      await c.load();
      addTearDown(c.dispose);
      final favorite = item(c, '004.stage.2.region.lower_body');
      final kiss = item(c, '002.stage.1.region.upper_body');
      final receive = item(c, '002.stage.1.region.upper_body', 'RECEVOIR');
      final hand = item(c, '005.stage.1.region.upper_body');
      final excluded = item(c, '002.stage.1.region.lower_body');
      final unsure = item(c, '004.stage.1.region.free');
      await c.rate(favorite, DetailedPreferenceCategory.essential);
      await c.rate(kiss, DetailedPreferenceCategory.love);
      await c.rate(receive, DetailedPreferenceCategory.atMyLimit);
      await c.rate(hand, DetailedPreferenceCategory.love);
      await c.rate(excluded, DetailedPreferenceCategory.excluded);
      await c.rate(unsure, DetailedPreferenceCategory.unsure);
      final profileBefore = jsonEncode(c.profile.toJson());
      final ratingsBefore = jsonEncode(c.ratings.toJson());
      expect(arrange(c, ProfileBinderSort.favorites).take(6), [
        favorite,
        kiss,
        hand,
        receive,
        unsure,
        excluded,
      ]);
      expect(arrange(c, ProfileBinderSort.leastFavorites).take(6), [
        excluded,
        unsure,
        receive,
        kiss,
        hand,
        favorite,
      ]);
      expect(
        arrange(
          c,
          ProfileBinderSort.unevaluated,
        ).take(214).every((i) => !c.explicit(i)),
        isTrue,
      );
      for (final sort in ProfileBinderSort.values) {
        final ordered = arrange(c, sort);
        expect(ordered.map((i) => i.id).toSet(), hasLength(220));
        expect(c.profile.toJson(), jsonDecode(profileBefore));
        expect(c.ratings.toJson(), jsonDecode(ratingsBefore));
      }
      expect(await learning.load('p'), isNull);
    },
  );

  test(
    'binder exact scores outrank proximity even inside the same visible category',
    () async {
      final c = editor();
      addTearDown(c.dispose);
      final near = item(c, '002.stage.1.region.upper_body');
      final other = item(c, '005.stage.1.region.upper_body');
      final ordered = ProfileBinderOrder.select(
        items: [near, other],
        isEvaluated: (_) => true,
        categoryFor: (_) => DetailedPreferenceCategory.like,
        estimateFor: (i) => i == other ? 7.1 : 7.4,
        sort: ProfileBinderSort.favorites,
      );
      expect(ordered, [other, near]);
    },
  );

  test(
    'binder all sorts and combined filters retain the twelve exact generic identities',
    () async {
      final c = editor();
      await c.load();
      addTearDown(c.dispose);
      for (final concept in ['002', '004', '005']) {
        final original = c.items.where((i) => i.concept.id == concept).toList();
        expect(original, hasLength(12));
        for (final sort in ProfileBinderSort.values) {
          final ordered = arrange(
            c,
            sort,
          ).where((i) => i.concept.id == concept).toList();
          expect(
            ordered.map((i) => i.ratingKey('p').storageKey).toSet(),
            original.map((i) => i.ratingKey('p').storageKey).toSet(),
          );
          expect(ordered.any((i) => i.actionId.contains('.zone.')), isFalse);
        }
        final filtered = arrange(
          c,
          ProfileBinderSort.favorites,
          roles: {CardOccurrenceDirection.RECEVOIR},
          spices: {3},
        ).where((i) => i.concept.id == concept);
        expect(filtered, hasLength(3));
        expect(
          filtered.every((i) => i.actionId.contains('.stage.2.region.')),
          isTrue,
        );
      }
      final ascending = arrange(
        c,
        ProfileBinderSort.spiceAscending,
      ).map((i) => i.chili).toList();
      final descending = arrange(
        c,
        ProfileBinderSort.spiceDescending,
      ).map((i) => i.chili).toList();
      expect(ascending, orderedEquals([...ascending]..sort()));
      expect(
        descending,
        orderedEquals(<int>[...descending]..sort((a, b) => b.compareTo(a))),
      );
      final alphabetical = arrange(c, ProfileBinderSort.alphabetical)
          .map((i) => i.concept.title).toSet().toList();
      expect(alphabetical.take(3), ['69', 'Ailleurs en privé', 'Câlin']);
      expect(alphabetical.indexOf('Entrave'), lessThan(alphabetical.indexOf('Être en sous-vêtements')));
      expect(alphabetical.indexOf('Être en sous-vêtements'), lessThan(alphabetical.indexOf('Exposition / sensation')));
      final noAccents = arrange(c, ProfileBinderSort.defaultOrder, query: 'calin');
      expect(noAccents, hasLength(1));
      expect(noAccents.single.concept.id, '001');
      expect(
        arrange(c, ProfileBinderSort.defaultOrder),
        orderedEquals(c.items),
      );
    },
  );

  for (final size in [const Size(360, 800), const Size(320, 480)]) {
    testWidgets('binder portrait $size stays readable with enlarged text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.4),
            ),
            child: CatalogProfileScreen(controller: editor()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(RadialAppreciation), findsNWidgets(4));
      await tester.tap(find.byKey(const Key('profile-binder-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Filtrer le classeur'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('binder-apply-filters')));
      await tester.tap(find.byKey(const Key('binder-apply-filters')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'binder shows four exact presentations in a 2 by 2 page and swipes horizontally',
    (tester) async {
      final c = editor();
      await tester.pumpWidget(
        MaterialApp(home: CatalogProfileScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      final before = jsonEncode(c.ratings.toJson());
      expect(find.byType(RadialAppreciation), findsNWidgets(4));
      final rects = [
        for (final i in c.items.take(4))
          tester.getRect(find.byKey(ValueKey(i.id))),
      ];
      expect(rects[0].top, rects[1].top);
      expect(rects[0].left, rects[2].left);
      expect(rects[2].top, rects[3].top);
      expect(rects[1].left, greaterThan(rects[0].left));
      expect(rects[2].top, greaterThan(rects[0].top));
      expect(find.text('1 / 55'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 55'), findsOneWidget);
      expect(find.byKey(ValueKey(c.items[4].id)), findsOneWidget);
      expect(jsonEncode(c.ratings.toJson()), before);
      await tester.enterText(
        find.byKey(const Key('profile-catalog-search')),
        'Paroles dégradantes',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('binder-next-page')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byType(RadialAppreciation), findsNWidgets(2));
      await tester.enterText(find.byKey(const Key('profile-catalog-search')), 'aucun-resultat');
      await tester.pumpAndSettle();
      expect(find.text('0 / 0'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('profile-catalog-search')), '');
      await tester.pumpAndSettle();
      expect(find.text('1 / 55'), findsOneWidget);
      expect(find.byKey(ValueKey(c.items.first.id)), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('binder consultation keeps the exact stage region and role', (
    tester,
  ) async {
    final c = editor();
    await tester.pumpWidget(
      MaterialApp(home: CatalogProfileScreen(controller: c)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-catalog-search')),
      'Embrasser',
    );
    await tester.pumpAndSettle();
    final target = item(c, '002.stage.1.region.upper_body', 'RECEVOIR');
    await tester.tap(find.byKey(ValueKey(target.id)));
    await tester.pumpAndSettle();
    final definition = tester
        .widget<CardRenderer>(find.byType(CardRenderer))
        .definition;
    expect(definition.variantId, target.actionId);
    expect(definition.direction, 'RECEVOIR');
    expect(definition.spice, 2);
    expect(definition.zones, ['Haut du corps']);
    expect(definition.action, contains('Laisse'));
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'binder miniature long hold drag release rates only that precise presentation',
    (tester) async {
      final c = editor();
      await tester.pumpWidget(
        MaterialApp(home: CatalogProfileScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-catalog-search')),
        'Embrasser',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final target = item(c, '002.stage.1.region.upper_body');
      final opposite = item(c, target.actionId, 'RECEVOIR');
      final oldOpposite = c.category(opposite);
      final positionBefore = tester
          .widget<Text>(find.byKey(const Key('profile-binder-position')))
          .data;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey(target.id))),
      );
      await tester.pump(const Duration(milliseconds: 650));
      final center = tester.getCenter(
        find.byKey(const Key('appreciation-radial')),
      );
      final angle = -math.pi / 2 + math.pi / 5;
      await gesture.moveTo(
        center + Offset(math.cos(angle) * 105, math.sin(angle) * 105),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.category(target), DetailedPreferenceCategory.love);
      expect(c.explicit(target), isTrue);
      expect(c.explicit(opposite), isFalse);
      expect(c.category(opposite), oldOpposite);
      expect(
        (await ratings.load('p')).explicitEstimate(target.ratingKey('p')),
        3.5,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('profile-binder-position')))
            .data,
        positionBefore,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'binder combines RECEVOIR P3 unassessed filter and preference sort without writing data',
    (tester) async {
      final c = editor();
      await tester.pumpWidget(
        MaterialApp(home: CatalogProfileScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-catalog-search')),
        'Embrasser',
      );
      await tester.pumpAndSettle();
      final beforeProfile = jsonEncode(c.profile.toJson());
      final beforeRatings = jsonEncode(c.ratings.toJson());
      await tester.tap(find.byKey(const Key('profile-binder-filters')));
      await tester.pumpAndSettle();
      for (final key in [
        'binder-role-RECEVOIR',
        'binder-spice-3',
        'binder-evaluation-unevaluated',
      ]) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('binder-apply-filters')));
      await tester.pumpAndSettle();
      expect(find.text('3 cartes · 3 non évaluées'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-binder-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Préférences').last);
      await tester.pumpAndSettle();
      final cards = tester.widgetList<RadialAppreciation>(
        find.byType(RadialAppreciation),
      );
      expect(cards, hasLength(3));
      for (final card in cards) {
        expect(
          (card.key! as ValueKey<String>).value,
          contains('.stage.2.region.'),
        );
        expect((card.key! as ValueKey<String>).value, endsWith('|RECEVOIR'));
      }
      expect(jsonEncode(c.profile.toJson()), beforeProfile);
      expect(jsonEncode(c.ratings.toJson()), beforeRatings);
      final firstId = (cards.first.key! as ValueKey<String>).value;
      cards.first.onSelected(DetailedPreferenceCategory.like);
      await tester.pumpAndSettle();
      expect(find.text('2 cartes · 2 non évaluées'), findsOneWidget);
      expect(find.byKey(ValueKey(firstId)), findsNothing);
      final reopened = editor();
      await reopened.load();
      expect(
        reopened.explicit(reopened.items.singleWhere((i) => i.id == firstId)),
        isTrue,
      );
      reopened.dispose();
      await tester.enterText(
        find.byKey(const Key('profile-catalog-search')),
        'aucun-resultat',
      );
      await tester.pumpAndSettle();
      expect(find.text('Aucune carte pour ces filtres.'), findsOneWidget);
      expect(find.text('0 / 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('home access keeps one editor when keyboard rebuilds the route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_preferences_v4.p': jsonEncode(base.toJson()),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TwoPhoneLobbyScreen(
          repository: _ProfileLobbyRepository(),
          profileCatalogLoader: () async => catalog,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-catalog-profile')));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogProfileScreen), findsOneWidget);
    final before = tester
        .widget<CatalogProfileScreen>(find.byType(CatalogProfileScreen))
        .controller;
    await tester.enterText(
      find.byKey(const Key('profile-catalog-search')),
      'Paroles',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(
      identical(
        tester
            .widget<CatalogProfileScreen>(find.byType(CatalogProfileScreen))
            .controller,
        before,
      ),
      isTrue,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(RadialAppreciation), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (
    var index = 0;
    index < DetailedPreferenceCategory.values.length;
    index++
  ) {
    testWidgets(
      'radial continuous hold drag release selects existing sector $index',
      (tester) async {
        DetailedPreferenceCategory? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RadialAppreciation(
                  onSelected: (v) => selected = v,
                  child: const SizedBox(width: 300, height: 300),
                ),
              ),
            ),
          ),
        );
        final origin = tester.getCenter(find.byType(RadialAppreciation));
        final gesture = await tester.startGesture(origin);
        await tester.pump(const Duration(milliseconds: 650));
        expect(find.byKey(const Key('appreciation-radial')), findsOneWidget);
        final angle = -math.pi / 2 + index * math.pi / 5;
        await gesture.moveTo(
          origin + Offset(math.cos(angle) * 105, math.sin(angle) * 105),
        );
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(selected, DetailedPreferenceCategory.values[index]);
        expect(find.byKey(const Key('appreciation-radial')), findsNothing);
      },
    );
  }
  testWidgets(
    'returning to center cancels selection and disposal removes overlay',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RadialAppreciation(
                onSelected: (_) => calls++,
                child: const SizedBox(width: 300, height: 300),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getCenter(find.byType(RadialAppreciation));
      final gesture = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 650));
      await gesture.moveTo(origin + const Offset(0, -100));
      await gesture.moveTo(origin);
      await gesture.up();
      await tester.pump();
      expect(calls, 0);
      final next = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpWidget(const SizedBox.shrink());
      await next.cancel();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

class _ProfileLobbyRepository implements NetworkLobbyRepository {
  @override
  Future<String> currentPlayerId() async => 'p';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not used by profile navigation');
}
