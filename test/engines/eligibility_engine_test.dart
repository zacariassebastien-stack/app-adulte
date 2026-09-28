import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:test/test.dart';

import 'engine_fixture.dart';
import '../fixtures/catalog_fixture.dart';

void main() {
  const engine = EligibilityEngine();
  bool eligible(
    EngineCard card, {
    PlayerGameProfile? actor,
    PlayerGameProfile? partner,
    EngineSessionContext? context,
    ProfileHierarchy? hierarchy,
    bool recovery = false,
  }) => engine
      .evaluate(
        card: card,
        context: context ?? gameContext(),
        actor: actor ?? gameProfile('a'),
        partner: partner ?? gameProfile('b'),
        hierarchy: hierarchy ?? emptyHierarchy,
        recovery: recovery,
      )
      .eligible;

  test('1 EXCLUDED parent blocks accepted descendant', () {
    final card = gameCard(
      consent: const [ConsentRule(elementId: 'child', role: ProfileRole.FAIRE)],
    );
    final actor = gameProfile(
      'a',
      preferences: {
        'parent': const PreferenceValue(status: PreferenceStatus.EXCLUDED),
        'child': accepted(),
      },
    );
    final result = engine.evaluate(
      card: card,
      context: gameContext(),
      actor: actor,
      partner: gameProfile('b'),
      hierarchy: ProfileHierarchy(const {'child': 'parent', 'parent': null}),
    );
    expect(result.eligible, isFalse);
    expect(
      result.variants.single.reasons.single.code,
      IneligibilityCode.PARENT_EXCLUDED,
    );
  });

  test('2 ACCEPTED parent does not accept descendant', () {
    final actor = gameProfile('a', preferences: {'parent': accepted()});
    expect(
      eligible(
        gameCard(
          consent: const [
            ConsentRule(elementId: 'child', role: ProfileRole.FAIRE),
          ],
        ),
        actor: actor,
        hierarchy: ProfileHierarchy(const {'child': 'parent'}),
      ),
      isFalse,
    );
  });

  test('3 DISCOVER never authorizes a precise practice', () {
    final actor = gameProfile(
      'a',
      preferences: {
        'practice': const PreferenceValue(
          status: PreferenceStatus.DISCOVER,
          faire: 20,
        ),
      },
    );
    expect(
      eligible(
        gameCard(
          consent: const [
            ConsentRule(elementId: 'practice', role: ProfileRole.FAIRE),
          ],
        ),
        actor: actor,
      ),
      isFalse,
    );
  });

  test('4 FAIRE actor and RECEVOIR partner are checked separately', () {
    final card = gameCard(
      consent: const [
        ConsentRule(elementId: 'massage', role: ProfileRole.FAIRE),
        ConsentRule(
          elementId: 'massage',
          role: ProfileRole.RECEVOIR,
          subject: RequirementSubject.PARTNER,
        ),
      ],
    );
    expect(
      eligible(
        card,
        actor: gameProfile('a', preferences: {'massage': accepted()}),
      ),
      isFalse,
    );
    expect(
      eligible(
        card,
        actor: gameProfile('a', preferences: {'massage': accepted()}),
        partner: gameProfile('b', preferences: {'massage': accepted()}),
      ),
      isTrue,
    );
  });

  test('5 reciprocal action checks both players explicitly', () {
    final card = gameCard(
      consent: const [
        ConsentRule(
          elementId: 'reciprocal',
          role: ProfileRole.GENERAL,
          subject: RequirementSubject.BOTH,
        ),
      ],
    );
    expect(
      eligible(
        card,
        actor: gameProfile('a', preferences: {'reciprocal': accepted()}),
      ),
      isFalse,
    );
  });

  test('6 sensitive combination requires its own consent', () {
    final actor = gameProfile(
      'a',
      preferences: {'a': accepted(), 'b': accepted()},
    );
    final card = gameCard(
      consent: const [
        ConsentRule(elementId: 'a', role: ProfileRole.GENERAL),
        ConsentRule(elementId: 'b', role: ProfileRole.GENERAL),
        ConsentRule(elementId: 'a+b', role: ProfileRole.GENERAL),
      ],
    );
    expect(eligible(card, actor: actor), isFalse);
  });

  test('7 accessory availability never replaces consent', () {
    final card = gameCard(
      consent: const [
        ConsentRule(elementId: 'restraint', role: ProfileRole.FAIRE),
      ],
      technical: const [
        TechnicalRule(
          kind: TechnicalRuleKind.ACCESSORY,
          values: {'accessory.tie'},
        ),
      ],
    );
    expect(
      eligible(card, context: gameContext(accessories: {'accessory.tie'})),
      isFalse,
    );
  });

  test('8 accessory alternatives A OR B are supported', () {
    final card = gameCard(
      alternatives: const [
        TechnicalRuleGroup(
          operator: RuleOperator.ANY,
          rules: [
            TechnicalRule(kind: TechnicalRuleKind.ACCESSORY, values: {'a'}),
            TechnicalRule(kind: TechnicalRuleKind.ACCESSORY, values: {'b'}),
          ],
        ),
      ],
    );
    expect(eligible(card, context: gameContext(accessories: {'b'})), isTrue);
  });

  test('9 technical media availability never replaces media consent', () {
    final card = gameCard(
      consent: const [
        ConsentRule(elementId: 'media.photo', role: ProfileRole.FAIRE),
      ],
      technical: const [
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          values: {'PHOTO_CAPTURE'},
        ),
      ],
    );
    expect(
      eligible(
        card,
        context: gameContext(
          media: {
            'a': {MediaCapability.PHOTO_CAPTURE},
          },
        ),
      ),
      isFalse,
    );
  });

  test('10 photographer simulation without capture needs no camera', () {
    final card = gameCard(
      consent: const [
        ConsentRule(
          elementId: 'roleplay.photographer',
          role: ProfileRole.GENERAL,
        ),
      ],
    );
    expect(
      eligible(
        card,
        actor: gameProfile(
          'a',
          preferences: {'roleplay.photographer': accepted()},
        ),
      ),
      isTrue,
    );
  });

  test('11 actual photo needs consent and capability', () {
    final card = gameCard(
      consent: const [
        ConsentRule(elementId: 'media.photo', role: ProfileRole.FAIRE),
      ],
      technical: const [
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          values: {'PHOTO_CAPTURE'},
        ),
      ],
    );
    final actor = gameProfile('a', preferences: {'media.photo': accepted()});
    expect(eligible(card, actor: actor), isFalse);
    expect(
      eligible(
        card,
        actor: actor,
        context: gameContext(
          media: {
            'a': {MediaCapability.PHOTO_CAPTURE},
          },
        ),
      ),
      isTrue,
    );
  });

  test('12 open card does not broaden concrete practice consent', () {
    final card = gameCard(
      consent: const [
        ConsentRule(elementId: 'media.video', role: ProfileRole.FAIRE),
        ConsentRule(elementId: 'practice.concrete', role: ProfileRole.FAIRE),
      ],
    );
    expect(
      eligible(
        card,
        actor: gameProfile('a', preferences: {'media.video': accepted()}),
      ),
      isFalse,
    );
  });

  test('13 physical partner action is blocked while separated', () {
    final card = gameCard(
      technical: const [
        TechnicalRule(kind: TechnicalRuleKind.PROXIMITY, values: {'TOGETHER'}),
      ],
    );
    expect(
      eligible(
        card,
        context: gameContext(
          mode: SessionMode.distance,
          proximity: ProximityState.SEPARATED,
        ),
      ),
      isFalse,
    );
  });

  test('14 explicit self-performed distance variant is allowed', () {
    final card = gameCard(
      technical: const [
        TechnicalRule(
          kind: TechnicalRuleKind.SESSION_MODE,
          values: {'distance'},
        ),
        TechnicalRule(kind: TechnicalRuleKind.PROXIMITY, values: {'SEPARATED'}),
      ],
    );
    expect(
      eligible(
        card,
        context: gameContext(
          mode: SessionMode.distance,
          proximity: ProximityState.SEPARATED,
        ),
      ),
      isTrue,
    );
  });

  test('15 chili active level is an absolute ceiling', () {
    expect(
      eligible(gameCard(chili: 4), context: gameContext(chiliActive: 3)),
      isFalse,
    );
    expect(
      eligible(gameCard(chili: 3), context: gameContext(chiliActive: 3)),
      isTrue,
    );
  });

  test('16 mode-dependent media rule only applies at distance', () {
    final card = gameCard(
      technical: const [
        TechnicalRule(
          kind: TechnicalRuleKind.MEDIA_CAPABILITY,
          values: {'LIVE_CAMERA'},
          applicableModes: {SessionMode.distance},
        ),
      ],
    );
    expect(
      eligible(card, context: gameContext(mode: SessionMode.face_to_face)),
      isTrue,
    );
    expect(
      eligible(card, context: gameContext(mode: SessionMode.distance)),
      isFalse,
    );
  });

  test('70 accessory conjunction A AND B is supported', () {
    final card = gameCard(
      alternatives: const [
        TechnicalRuleGroup(
          operator: RuleOperator.ALL,
          rules: [
            TechnicalRule(kind: TechnicalRuleKind.ACCESSORY, values: {'a'}),
            TechnicalRule(kind: TechnicalRuleKind.ACCESSORY, values: {'b'}),
          ],
        ),
      ],
    );
    expect(eligible(card, context: gameContext(accessories: {'a'})), isFalse);
    expect(
      eligible(card, context: gameContext(accessories: {'a', 'b'})),
      isTrue,
    );
  });

  test('71 clothes, physical state and flags are absolute filters', () {
    final card = gameCard(
      technical: const [
        TechnicalRule(kind: TechnicalRuleKind.CLOTHES_AT_LEAST, minimum: 2),
        TechnicalRule(
          kind: TechnicalRuleKind.PHYSICAL_STATE,
          values: {'ready'},
        ),
        TechnicalRule(
          kind: TechnicalRuleKind.SESSION_FLAG,
          values: {'safe'},
          expected: true,
        ),
      ],
    );
    expect(
      eligible(
        card,
        context: gameContext(
          clothes: {'a': 2},
          physical: {'a': 'ready'},
          flags: {'safe': true},
        ),
      ),
      isTrue,
    );
    expect(eligible(card), isFalse);
  });

  test('72 variant removed after consent withdrawal is ineligible', () {
    expect(
      eligible(
        gameCard(),
        context: gameContext(removed: {'variant.card.test'}),
      ),
      isFalse,
    );
  });

  test('73 card is candidate when at least one variant is playable', () {
    final card = EngineCard(
      id: 'multi',
      variants: const [
        EngineVariant(id: 'too-hot', chiliLevel: 5),
        EngineVariant(id: 'playable', chiliLevel: 2),
      ],
    );
    final result = engine.evaluate(
      card: card,
      context: gameContext(chiliActive: 2),
      actor: gameProfile('a'),
      partner: gameProfile('b'),
      hierarchy: emptyHierarchy,
    );
    expect(result.eligibleVariants.single.id, 'playable');
  });

  test(
    '80 catalogue photo variants receive capture send receive capabilities',
    () {
      final data = fixture();
      card(data)['stable_id'] = 'card.suggestive_photo';
      variant(data)
        ..['stable_id'] = 'variant.suggestive_photo.base'
        ..['card_id'] = 'card.suggestive_photo';
      final adapted = const CatalogEngineAdapter().card(
        CardDefinition.fromJson(card(data)),
      );
      expect(
        adapted.variants.single.technicalRules
            .where((rule) => rule.kind == TechnicalRuleKind.MEDIA_CAPABILITY)
            .length,
        3,
      );
    },
  );

  test('81 photographer roleplay simulation gets no automatic camera rule', () {
    final data = fixture();
    card(data)['stable_id'] = 'card.rp_photographer';
    variant(data)
      ..['stable_id'] = 'variant.rp_photographer.base'
      ..['card_id'] = 'card.rp_photographer';
    final adapted = const CatalogEngineAdapter().card(
      CardDefinition.fromJson(card(data)),
    );
    expect(
      adapted.variants.single.technicalRules.where(
        (rule) => rule.kind == TechnicalRuleKind.MEDIA_CAPABILITY,
      ),
      isEmpty,
    );
  });

  test('82 ambiguous restraint catalogue variant requires together state', () {
    final data = fixture();
    card(data)['stable_id'] = 'card.dominate_me';
    variant(data)
      ..['stable_id'] = 'variant.dominate_me.restraint'
      ..['card_id'] = 'card.dominate_me';
    final adapted = const CatalogEngineAdapter().card(
      CardDefinition.fromJson(card(data)),
    );
    expect(
      adapted.variants.single.technicalRules.any(
        (rule) =>
            rule.kind == TechnicalRuleKind.PROXIMITY &&
            rule.values.contains('TOGETHER'),
      ),
      isTrue,
    );
  });
}
