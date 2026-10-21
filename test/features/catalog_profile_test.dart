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
import 'package:couple_cards/features/profile/radial_appreciation.dart';
import 'package:couple_cards/card_themes/card_renderer.dart';
import 'package:couple_cards/features/lobby/two_phone_lobby_screen.dart';
import 'package:couple_cards/features/lobby/lobby_repository.dart';
import 'package:couple_cards/engines/eligibility/concept_action_options.dart';
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
    'explicit positive estimate never bypasses the existing global tag veto',
    () async {
      const key = ProfilePreferenceKey(
        tagId: 'degradant',
        role: ProfilePreferenceRole.faire,
      );
      await profiles.save(
        V4Profile(
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
      expect(c.globalTagVeto(target), isTrue);
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
      expect(options.containsKey('056'), isFalse);
      c.dispose();
    },
  );
  testWidgets(
    'catalogue deck remains usable on a small phone with enlarged text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 480),
              textScaler: TextScaler.linear(1.4),
            ),
            child: CatalogProfileScreen(controller: editor()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cartes'));
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'catalogue list consult filters swipe deck and random are reachable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: CatalogProfileScreen(controller: editor())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Personnaliser mon profil'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('profile-catalog-search')),
        'Paroles dégradantes',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsWidgets);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cartes'));
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aléatoire'));
      await tester.pumpAndSettle();
      expect(find.byType(RadialAppreciation), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('profile cards receive the exact anatomical occurrence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CatalogProfileScreen(controller: editor())),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-catalog-search')),
      'Embrasser',
    );
    await tester.pumpAndSettle();
    final neck = find.widgetWithText(ListTile, 'Embrasser · Cou / nuque').first;
    await tester.ensureVisible(neck);
    await tester.tap(neck);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CardRenderer>(find.byType(CardRenderer)).definition.zones,
      ['Cou / nuque'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'random appreciation renders its successor immediately without a null crash',
    (tester) async {
      final c = editor();
      await tester.pumpWidget(
        MaterialApp(home: CatalogProfileScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aléatoire'));
      await tester.pumpAndSettle();
      final radial = tester.widget<RadialAppreciation>(
        find.byType(RadialAppreciation),
      );
      final before = c.remaining.length;
      final previous = tester
          .widget<CardRenderer>(find.byType(CardRenderer))
          .definition;
      radial.onSelected(DetailedPreferenceCategory.like);
      await tester.pumpAndSettle();
      expect(c.remaining.length, before - 1);
      final next = tester
          .widget<CardRenderer>(find.byType(CardRenderer))
          .definition;
      expect(
        '${next.cardId}/${next.variantId}/${next.direction}',
        isNot('${previous.cardId}/${previous.variantId}/${previous.direction}'),
      );
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
    expect(find.byType(ListTile), findsWidgets);
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
