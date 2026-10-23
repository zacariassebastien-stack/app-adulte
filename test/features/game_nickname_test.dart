import 'package:couple_cards/engines/profile/v4_card_rating_engine.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/engines/profile/initial_questionnaire_engine.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:couple_cards/features/profile/initial_profile_screen.dart';
import 'package:couple_cards/features/profile/catalog_profile_controller.dart';
import 'package:couple_cards/features/profile/catalog_profile_screen.dart';
import 'package:couple_cards/features/lobby/lobby_models.dart';
import 'package:couple_cards/features/game/ui/adaptive_card_page.dart';

void main() {
  test('nickname bounds and trimming are independent of preferences', () {
    for (final value in ['', '   ', 'a', 'x' * 21]) {
      expect(GameNickname.error(value), isNotNull);
    }
    for (final value in ['ab', 'x' * 20, '  Seb  ']) {
      expect(GameNickname.error(value), isNull);
    }
    expect(GameNickname.normalize('  Seb  '), 'Seb');
    final old = V4Profile.fromJson({'profile_id': 'p', 'sex': 'HOMME', 'preferences': []});
    expect(old.gameNickname, isNull);
    final named = old.copyWith(gameNickname: 'Seb');
    expect(V4Profile.fromJson(named.toJson()).gameNickname, 'Seb');
    expect(named.preferences, old.preferences);
    expect(mergeV4ProfileLearning(named, null).gameNickname, 'Seb');
    expect(
      adaptiveProfileFromV4Profile(named).toJson(),
      adaptiveProfileFromV4Profile(old).toJson(),
    );
  });

  test('nickname persists across independent store instances', () async {
    SharedPreferences.setMockInitialValues({});
    await const SharedPreferencesV4ProfileStore().save(
      V4Profile(sex: ProfileSex.HOMME, profileId: 'p', preferences: {}, gameNickname: 'Julie'),
    );
    expect(
      (await const SharedPreferencesV4ProfileStore().load('p'))!.gameNickname,
      'Julie',
    );
  });

  for (final sex in ProfileSex.values) {
  testWidgets(
    'pseudo then mandatory $sex keeps questionnaire scoring/count',
    (tester) async {
      final source = ProfileQuestionnaire.decode(
        File(
          'assets/catalog/source/profile_questions.v1.fr.json',
        ).readAsStringSync(),
      );
      final q = ProfileQuestionnaire(
        version: source.version,
        questions: [source.questions.first],
      );
      final profiles = MemoryV4ProfileStore();
      final adaptive = MemoryNetworkProfileLearningStore();
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: InitialProfileScreen(
            playerId: 'p',
            questionnaire: q,
            profileStore: profiles,
            adaptiveStore: adaptive,
            onCompleted: () {
              completed = true;
            },
          ),
        ),
      );
      expect(find.text('Quel est ton pseudo de jeu ?'), findsOneWidget);
      expect(find.text('1 / 1'), findsNothing);
      await tester.tap(find.byKey(const Key('save-game-nickname')));
      await tester.pumpAndSettle();
      expect(
        find.text('Choisis un pseudo de 2 à 20 caractères.'),
        findsOneWidget,
      );
      expect(await profiles.load('p'), isNull);
      await tester.enterText(
        find.byKey(const Key('game-nickname-input')),
        '  Seb  ',
      );
      await tester.tap(find.byKey(const Key('save-game-nickname')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsNothing);
      expect(find.text('Sexe du profil'), findsOneWidget);
      expect(await profiles.load('p'), isNull);
      await tester.tap(find.byKey(Key('initial-sex-${sex.name}')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);
      for (final chip
          in find
              .widgetWithText(ChoiceChip, 'Ça me plaît')
              .evaluate()
              .toList()) {
        await tester.tap(find.byWidget(chip.widget));
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('initial-profile-continue')),
      );
      await tester.tap(find.byKey(const Key('initial-profile-continue')));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      final saved = (await profiles.load('p'))!;
      expect(saved.gameNickname, 'Seb');
      expect(saved.sex, sex);
      final expected = const InitialQuestionnaireEngine().initialize(sex: sex,
        profileId: 'p',
        questionnaire: q,
        responses: {
          for (final axis in q.questions.first.axes)
            '${q.questions.first.stableId}|${axis.axisId}':
                InitialQuestionResponse.like,
        },
      );
      expect(saved.toJson()['preferences'], expected.toJson()['preferences']);
      expect(
        (await adaptive.load('p'))!.toJson(),
        adaptiveProfileFromV4Profile(expected).toJson(),
      );
    },
  );

  }

  testWidgets(
    'old profile can set and edit nickname without touching learning',
    (tester) async {
      final catalog = (await tester.runAsync(
        () => const CatalogLoader().load(
          (p) => File(p).readAsString(),
          includeConcepts: true,
        ),
      ))!;
      final profiles = MemoryV4ProfileStore();
      await profiles.save(V4Profile(sex: ProfileSex.HOMME, profileId: 'p', preferences: {}));
      final learning = MemoryNetworkProfileLearningStore();
      final editor = CatalogProfileController(
        catalog: catalog,
        playerId: 'p',
        profileStore: profiles,
        learningStore: learning,
        ratingStore: MemoryV4CardLearningStore(),
      );
      await editor.load();
      final before = jsonEncode(
        editor.profile.toJson()..remove('game_nickname'),
      );
      await tester.pumpWidget(
        MaterialApp(home: CatalogProfileScreen(controller: editor)),
      );
      await tester.pumpAndSettle();
      for (final name in ['Seb', 'Julie']) {
        await tester.tap(find.byKey(const Key('edit-game-nickname')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('game-nickname-input')),
          ' $name ',
        );
        await tester.tap(find.byKey(const Key('save-game-nickname')));
        await tester.pumpAndSettle();
        expect((await profiles.load('p'))!.gameNickname, name);
      }
      expect(
        jsonEncode(editor.profile.toJson()..remove('game_nickname')),
        before,
      );
      expect(await learning.load('p'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );


  for (final locked in [false, true]) {
    testWidgets('sex settings locked=$locked preserve all private data', (tester) async {
      final catalog = (await tester.runAsync(() => const CatalogLoader().load(
        (p) => File(p).readAsString(), includeConcepts: true)))!;
      final profiles = MemoryV4ProfileStore();
      final preferenceKey = ProfilePreferenceKey(tagId: 'embrasser', role: ProfilePreferenceRole.faire);
      final base = V4Profile(profileId: 'p', sex: ProfileSex.HOMME, preferences: {
        preferenceKey.storageKey: ProfilePreference(profileId: 'p', key: preferenceKey,
          pa: 7, excluded: false, source: ProfilePreferenceSource.manualCustomized),
      },
        gameNickname: 'Test', stageVetoes: const [StageVeto(conceptId: '056', actionId: '*', role: ProfilePreferenceRole.faire)],
        accessories: [V4ProfileAccessory(id: 'a', name: 'Test', ownerProfileId: 'p', tags: const {'EXTERNE'})]);
      await profiles.save(base);
      final learning = MemoryNetworkProfileLearningStore();
      final ratings = MemoryV4CardLearningStore();
      final ratingKey = CardRatingKey(profileId: 'p', cardId: '056', variantId: '056.stage.1', role: ProfilePreferenceRole.faire);
      final existingRatings = CardSpecificLearningStore()..write(CardRatingStateV4(
        key: ratingKey, initialScore: 12, currentEstimate: 7, observationCount: 2,
        acceptanceCount: 1, resistanceCount: 1, source: 'CARD_ESTIMATE'));
      await ratings.save('p', existingRatings);
      await learning.save(adaptiveProfileFromV4Profile(base));
      final beforeLearning = jsonEncode((await learning.load('p'))!.toJson());
      final beforeRatings = jsonEncode((await ratings.load('p')).toJson());
      final editor = CatalogProfileController(catalog: catalog, playerId: 'p', sexLocked: locked,
        profileStore: profiles, learningStore: learning, ratingStore: ratings);
      await editor.load();
      await tester.pumpWidget(MaterialApp(home: CatalogProfileScreen(controller: editor)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-sex')));
      await tester.pumpAndSettle();
      expect(find.text('Sexe : Homme'), findsOneWidget);
      if (locked) {
        expect(find.text('Non modifiable pendant la partie.'), findsOneWidget);
        expect(find.byKey(const Key('profile-sex-FEMME')), findsNothing);
        await expectLater(editor.setSex(ProfileSex.FEMME), throwsStateError);
        expect((await profiles.load('p'))!.sex, ProfileSex.HOMME);
      } else {
        await tester.tap(find.byKey(const Key('profile-sex-FEMME')));
        await tester.pumpAndSettle();
        expect((await profiles.load('p'))!.sex, ProfileSex.FEMME);
        expect((await profiles.load('p'))!.toJson()..remove('sex'), base.toJson()..remove('sex'));
      }
      expect(jsonEncode((await learning.load('p'))!.toJson()), beforeLearning);
      expect(jsonEncode((await ratings.load('p')).toJson()), beforeRatings);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test(
    'session names remain bound to IDs despite reversed roles/order and legacy data',
    () {
      final session = LobbySession.fromSupabaseJson({
        'id': 's',
        'join_code': 'ABCDEF',
        'status': 'ready',
        'expires_at': '2027-01-01T00:00:00Z',
        'players': [
          {'user_id': 'bob', 'role': 'PLAYER_1', 'game_nickname': 'Julie'},
          {'user_id': 'alice', 'role': 'PLAYER_2', 'game_nickname': 'Seb'},
        ],
      });
      expect(session.participantNames, {'alice': 'Seb', 'bob': 'Julie'});
      expect(
        const LobbyPlayer(
          userId: 'old',
          role: LobbyPlayerRole.player1,
        ).gameNickname,
        isNull,
      );
    },
  );

  testWidgets(
    'adaptive card grows with actual available height and fits long names',
    (tester) async {
      double? previous;
      for (final height in [360.0, 900.0]) {
        await tester.binding.setSurfaceSize(Size(600, height));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdaptiveCardPage(
                before: const [
                  Text('Tu as gagné !', textAlign: TextAlign.center),
                  Text(
                    'ABCDEFGHIJKLMNOPQRST réalise « Massage » pour UVWXYZABCDEFGHIJKLMN.',
                    textAlign: TextAlign.center,
                  ),
                ],
                card: const FittedActionCard(
                  child: ColoredBox(
                    key: Key('fitted-card'),
                    color: Colors.blue,
                  ),
                ),
                after: [
                  FilledButton(onPressed: () {}, child: const Text('Terminé')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byKey(const Key('fitted-card')));
        expect(size.width / size.height, closeTo(.68, .01));
        if (previous != null) expect(size.height, greaterThan(previous));
        previous = size.height;
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
}
