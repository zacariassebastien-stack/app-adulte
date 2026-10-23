import 'package:couple_cards/core/json.dart';
import 'package:couple_cards/engines/runtime/v4_runtime_engine.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/eligibility/anatomy_compatibility.dart';
import 'package:couple_cards/features/game/network_profile_learning.dart';
import 'package:couple_cards/sync/rounds/network_game.dart';

void main() {
  final raw =
      jsonDecode(
            File('assets/catalog/concepts/active.fr.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final catalog = ConceptCatalog.fromJson(raw);
  final expected = <String, String>{
    for (final id in ['002', '004', '005']) ...{
      '$id.zone.penis': 'PENIS',
      '$id.zone.vulva': 'VULVE',
    },
    for (final id in ['022', '027'])
      for (var stage = 1; stage <= 3; stage++) '$id.stage.$stage': 'VULVE',
    '055.action': 'PENIS',
  };
  bool allowed(
    String action,
    CardOccurrenceDirection direction,
    PlayerAnatomy owner,
    PlayerAnatomy partner,
  ) => AnatomyCompatibility.allows(
    concept: catalog.concepts.singleWhere(
      (c) => c.id == action.split('.').first,
    ),
    actionId: action,
    direction: direction,
    ownerId: 'owner',
    anatomies: {'owner': owner, 'partner': partner},
  );

  for (final action in expected.keys) {
    for (final owner in PlayerAnatomy.values) {
      for (final partner in PlayerAnatomy.values) {
        for (final direction in [
          CardOccurrenceDirection.FAIRE,
          CardOccurrenceDirection.RECEVOIR,
        ]) {
          test('$action $direction owner=$owner partner=$partner', () {
            final subject =
                action == '055.action' ||
                    direction == CardOccurrenceDirection.RECEVOIR
                ? owner
                : partner;
            expect(
              allowed(action, direction, owner, partner),
              subject.name == expected[action],
            );
          });
        }
      }
    }
  }
  test(
    'catalog has exactly the 13 restricted action identities, including inherited stages',
    () {
      final restricted = <String>{};
      for (final concept in catalog.concepts) {
        for (final stage in concept.stages) {
          if ((stage.anatomyRequirements ?? concept.anatomyRequirements) !=
              null) {
            restricted.add(stage.id);
          }
        }
        for (final variant in concept.variants) {
          if ((variant.anatomyRequirements ?? concept.anatomyRequirements) !=
              null) {
            restricted.add(variant.id);
          }
        }
      }
      expect(restricted, expected.keys.toSet());
    },
  );
  for (final action in [
    '065.action',
    '002.zone.free',
    '004.zone.free',
    '005.zone.free',
    '023.stage.1',
    '028.action',
    '025.stage.3',
    '031.action',
  ]) {
    test('$action remains unrestricted for both anatomies and directions', () {
      for (final owner in PlayerAnatomy.values) {
        for (final partner in PlayerAnatomy.values) {
          for (final direction in [
            CardOccurrenceDirection.FAIRE,
            CardOccurrenceDirection.RECEVOIR,
          ]) {
            expect(allowed(action, direction, owner, partner), isTrue);
          }
        }
      }
    });
  }
  test(
    'action override replaces inherited requirements, including explicit empty override',
    () {
      final concept = CardConcept.read(
        JsonReader({
          'id': 'test',
          'title': 'Test',
          'kind': 'action',
          'action_text': 'Test',
          'anatomy_requirements': {
            'FAIRE': {'OWNER': 'PENIS'},
          },
          'variants': [
            {
              'id': 'test.action',
              'title': 'Test',
              'chili': 1,
              'anatomy_requirements': <String, Object?>{},
            },
          ],
        }, 'test'),
      );
      expect(
        AnatomyCompatibility.allows(
          concept: concept,
          actionId: 'test.action',
          direction: CardOccurrenceDirection.FAIRE,
          ownerId: 'a',
          anatomies: {'a': PlayerAnatomy.VULVE, 'b': PlayerAnatomy.VULVE},
        ),
        isTrue,
      );
    },
  );
  for (final invalid in [
    {
      'INVALID': {'OWNER': 'PENIS'},
    },
    {
      'FAIRE': {'ACTOR': 'PENIS'},
    },
    {
      'FAIRE': {'OWNER': 'VAGIN'},
    },
    {'FAIRE': <Object?>[]},
  ]) {
    test(
      'invalid metadata rejected: $invalid',
      () => expect(
        () => AnatomyRequirements.read(invalid),
        throwsFormatException,
      ),
    );
  }
  test(
    '027 permits VULVE owner to penetrate VULVE partner',
    () => expect(
      allowed(
        '027.stage.3',
        CardOccurrenceDirection.FAIRE,
        PlayerAnatomy.VULVE,
        PlayerAnatomy.VULVE,
      ),
      isTrue,
    ),
  );
  for (final sex in ProfileSex.values) {
    test('strict profile roundtrip and learning merge preserve $sex', () {
      final profile = V4Profile(
        profileId: 'p',
        sex: sex,
        preferences: const {},
        gameNickname: 'Test',
        stageVetoes: const [
          StageVeto(
            conceptId: '056',
            actionId: '*',
            role: ProfilePreferenceRole.faire,
          ),
        ],
      );
      final restored = V4Profile.fromJson(profile.toJson());
      expect(restored.sex, sex);
      expect(
        restored.anatomy,
        sex == ProfileSex.HOMME ? PlayerAnatomy.PENIS : PlayerAnatomy.VULVE,
      );
      expect(restored.copyWith(gameNickname: 'Other').sex, sex);
      expect(mergeV4ProfileLearning(restored, null).sex, sex);
      expect(mergeV4ProfileLearning(restored, adaptiveProfileFromV4Profile(restored)).sex, sex);
      final changed = restored.copyWith(
        sex: sex == ProfileSex.HOMME ? ProfileSex.FEMME : ProfileSex.HOMME,
      );
      final before = restored.toJson()..remove('sex');
      expect(changed.toJson()..remove('sex'), before);
      for (final invalid in [null, 'UNKNOWN', 'AUTRE', 'homme']) {
        expect(
          () => V4Profile.fromJson({...profile.toJson(), 'sex': invalid}),
          throwsFormatException,
        );
      }
    });
  }
  test(
    'setup cannot be complete before both participant anatomies are available',
    () {
      V4SessionSetupDto setup(PlayerAnatomy? anatomy) => V4SessionSetupDto(
        mode: V4SessionMode.presentiel,
        style: PlayerStyle.SOFT,
        status: 'ACCEPTED',
        players: [
          V4PlayerSessionSetupDto(
            playerId: 'a',
            clothingCount: 0,
            anatomy: PlayerAnatomy.PENIS,
            accessories: const [],
          ),
          V4PlayerSessionSetupDto(
            playerId: 'b',
            clothingCount: 0,
            anatomy: anatomy,
            accessories: const [],
          ),
        ],
      );
      expect(setup(null).complete, isFalse);
      final ready = setup(PlayerAnatomy.VULVE);
      expect(ready.complete, isTrue);
      final restored = V4PlayerSessionSetupDto.fromJson(
        ready.players.last.toJson(),
      );
      expect(restored.anatomy, PlayerAnatomy.VULVE);
      expect(ready.anatomies, {
        'a': PlayerAnatomy.PENIS,
        'b': PlayerAnatomy.VULVE,
      });
    },
  );
}
