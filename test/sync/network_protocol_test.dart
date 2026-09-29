import 'dart:convert';
import 'dart:io';

import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/engines.dart';
import 'package:couple_cards/sync/sync.dart';
import 'package:test/test.dart';

void main() {
  CompleteNetworkGameState truth({
    bool revealed = false,
  }) => CompleteNetworkGameState(
    sessionId: 'session-1',
    roundId: 'session-1.round-3',
    roundNumber: 3,
    phase: revealed ? PublicRoundPhase.revealed : PublicRoundPhase.committed,
    proximity: ProximityState.TOGETHER,
    chiliActive: 2,
    chiliUnlocked: 3,
    playerIds: const ['alice', 'bob'],
    actionPoints: const {'alice': 42, 'bob': 37},
    cardsByPlayer: const {
      'alice': [
        PrivateCardDto(
          cardId: 'alice.secret.card',
          variantId: 'alice.secret.variant',
          zone: 'HAND',
          locked: true,
        ),
      ],
      'bob': [
        PrivateCardDto(
          cardId: 'bob.secret.card',
          variantId: 'bob.secret.variant',
          zone: 'HAND',
        ),
      ],
    },
    committedChoices: const {
      'alice': PublicChoiceDto(
        cardId: 'alice.secret.card',
        variantId: 'alice.secret.variant',
      ),
      'bob': PublicChoiceDto(
        cardId: 'bob.secret.card',
        variantId: 'bob.secret.variant',
      ),
    },
    commitNonces: const {'alice': 'nonce-a', 'bob': 'nonce-b'},
    personalValues: const {
      'alice': {'alice.secret.variant': 17},
      'bob': {'bob.secret.variant': 8},
    },
    preferences: const {
      'alice': {
        'element-a': PreferenceValue(
          status: PreferenceStatus.ACCEPTED,
          faire: 17,
        ),
      },
      'bob': {'element-b': PreferenceValue(status: PreferenceStatus.EXCLUDED)},
    },
    drawStyles: const {'alice': PlayerStyle.EPICE, 'bob': PlayerStyle.SOFT},
    recoveryByPlayer: const {
      'alice': PrivateRecoveryDto(
        available: true,
        usedSinceLastNormalDuel: false,
        selectedCardId: 'alice.secret.card',
      ),
      'bob': PrivateRecoveryDto(
        available: false,
        usedSinceLastNormalDuel: true,
      ),
    },
    revealedChoices: const {
      'alice': PublicChoiceDto(
        cardId: 'alice.secret.card',
        variantId: 'alice.secret.variant',
      ),
      'bob': PublicChoiceDto(
        cardId: 'bob.secret.card',
        variantId: 'bob.secret.variant',
      ),
    },
    revealAllowed: revealed,
    resolution: const PublicResolutionDto(winnerPlayerId: 'alice', cost: 4),
  );

  PlayerNetworkProjection project(
    CompleteNetworkGameState state,
    String playerId, {
    ActionPointVisibility points = ActionPointVisibility.discreet,
  }) => const NetworkVisibilityProjection().project(
    state: state,
    playerId: playerId,
    configuration: NetworkVisibilityConfiguration(actionPoints: points),
  );

  test('public projection contains no hands, values or preferences', () {
    final json = project(truth(), 'alice').publicState.toJson();
    final encoded = jsonEncode(json);

    expect(json, isNot(contains('hand')));
    expect(json, isNot(contains('personal_values')));
    expect(json, isNot(contains('preferences')));
    expect(encoded, isNot(contains('bob.secret.card')));
    expect(encoded, isNot(contains('EXCLUDED')));
    expect(encoded, isNot(contains('nonce-b')));
    expect(encoded, isNot(contains('"8"')));
  });

  test('each player receives only their owner private state', () {
    final alice = project(truth(), 'alice').privateState;
    final bob = project(truth(), 'bob').privateState;

    expect(alice.playerId, 'alice');
    expect(alice.hand.single.cardId, 'alice.secret.card');
    expect(alice.lockedCardId, 'alice.secret.card');
    expect(alice.commitNonce, 'nonce-a');
    expect(alice.preferences, contains('element-a'));
    expect(jsonEncode(alice.toJson()), isNot(contains('bob.secret')));
    expect(bob.playerId, 'bob');
    expect(bob.hand.single.cardId, 'bob.secret.card');
    expect(jsonEncode(bob.toJson()), isNot(contains('alice.secret')));
  });

  test('visible and discreet modes place PA in the correct DTO', () {
    final discreet = project(truth(), 'alice');
    final visible = project(
      truth(),
      'alice',
      points: ActionPointVisibility.visible,
    );

    expect(discreet.publicState.visibleActionPoints, isEmpty);
    expect(discreet.privateState.actionPoints, 42);
    expect(visible.publicState.visibleActionPoints, {'alice': 42, 'bob': 37});
    expect(visible.privateState.actionPoints, isNull);
  });

  test('committed choices stay hidden until reveal is authorized', () {
    final hidden = project(truth(), 'alice').publicState;
    final revealed = project(truth(revealed: true), 'alice').publicState;

    expect(hidden.selectionMade.values, everyElement(isTrue));
    expect(hidden.revealedChoices, isEmpty);
    expect(hidden.resolution, isNull);
    expect(revealed.revealedChoices, hasLength(2));
    expect(revealed.resolution?.winnerPlayerId, 'alice');
  });

  test('public and private DTOs round-trip with explicit schema', () {
    final value = project(truth(revealed: true), 'alice');
    final publicJson = value.publicState.toJson();
    final privateJson = value.privateState.toJson();

    expect(publicJson['schema_version'], networkSchemaVersion);
    expect(PublicGameStateDto.fromJson(publicJson).toJson(), publicJson);
    expect(PrivatePlayerStateDto.fromJson(privateJson).toJson(), privateJson);
  });

  group('commit/reveal', () {
    const contract = CommitRevealContract();
    final choice = ChoicePayload(
      cardId: 'card-1',
      variantId: 'variant-2',
      parameters: {
        'duration': 10,
        'options': ['a', 'b'],
      },
    );
    final commitment = contract.commit(
      sessionRound: 'session-1.round-3',
      playerId: 'alice',
      choice: choice,
      nonce: 'secure-random-nonce',
    );

    ChoiceRevealDto reveal({
      ChoicePayload? value,
      String nonce = 'secure-random-nonce',
      String playerId = 'alice',
      String round = 'session-1.round-3',
    }) => ChoiceRevealDto(
      sessionRound: round,
      playerId: playerId,
      choice: value ?? choice,
      nonce: nonce,
    );

    test('identical reveal validates and DTOs round-trip', () {
      expect(contract.verify(commitment, reveal()), isTrue);
      expect(
        ChoiceCommitmentDto.fromJson(commitment.toJson()).toJson(),
        commitment.toJson(),
      );
      final revealJson = reveal().toJson();
      expect(ChoiceRevealDto.fromJson(revealJson).toJson(), revealJson);
    });

    test('modified choice fails', () {
      expect(
        contract.verify(
          commitment,
          reveal(
            value: ChoicePayload(
              cardId: 'card-2',
              variantId: 'variant-2',
              parameters: const {'duration': 10},
            ),
          ),
        ),
        isFalse,
      );
    });

    test('wrong nonce fails', () {
      expect(contract.verify(commitment, reveal(nonce: 'wrong')), isFalse);
    });

    test('wrong player or round fails', () {
      expect(contract.verify(commitment, reveal(playerId: 'bob')), isFalse);
      expect(contract.verify(commitment, reveal(round: 'round-4')), isFalse);
    });

    test('canonical payload order produces the same SHA-256 commitment', () {
      final reordered = ChoicePayload(
        cardId: 'card-1',
        variantId: 'variant-2',
        parameters: {
          'options': ['a', 'b'],
          'duration': 10,
        },
      );
      expect(
        contract
            .commit(
              sessionRound: 'session-1.round-3',
              playerId: 'alice',
              choice: reordered,
              nonce: 'secure-random-nonce',
            )
            .digest,
        commitment.digest,
      );
    });

    test('Phase 6.3B payload matches the PostgreSQL canonical envelope', () {
      final realisticChoice = ChoicePayload(
        cardId: 'card.kiss_me',
        variantId: 'variant.kiss_me.base',
        parameters: const {
          'role': 'RECEVOIR',
          'personal_value': 13,
          'committed_at': '2026-09-29T19:00:00.000Z',
        },
      );
      const canonicalChoice =
          '{"card_id":"card.kiss_me","parameters":{"committed_at":"2026-09-29T19:00:00.000Z","personal_value":13,"role":"RECEVOIR"},"variant_id":"variant.kiss_me.base"}';
      const sessionRound = '11111111-1111-1111-1111-111111111111.round-1';
      const playerId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      const nonce = 'fixed-test-nonce';
      const sqlEnvelope =
          '["11111111-1111-1111-1111-111111111111.round-1","aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","{\\"card_id\\":\\"card.kiss_me\\",\\"parameters\\":{\\"committed_at\\":\\"2026-09-29T19:00:00.000Z\\",\\"personal_value\\":13,\\"role\\":\\"RECEVOIR\\"},\\"variant_id\\":\\"variant.kiss_me.base\\"}","fixed-test-nonce"]';

      expect(realisticChoice.canonicalJson(), canonicalChoice);
      expect(
        jsonEncode([sessionRound, playerId, canonicalChoice, nonce]),
        sqlEnvelope,
      );
      expect(
        contract
            .commit(
              sessionRound: sessionRound,
              playerId: playerId,
              choice: realisticChoice,
              nonce: nonce,
            )
            .digest,
        '55d2ade39bca0c69e99682eec11441fcdb9bc5a92a83ebfbe507df0a77479410',
      );

      final migration = File(
        'supabase/migrations/202609290003_fix_network_reveal_digest.sql',
      ).readAsStringSync();
      expect(migration, contains('public.canonical_jsonb(p_choice_payload)'));
      expect(migration, contains('extensions.digest('));
      expect(migration, contains("'sha256'::text"));
    });
  });

  test('commandId round-trips and duplicate commands are recognized', () {
    final command = NetworkCommandDto(
      commandId: 'command-123',
      sessionId: 'session-1',
      playerId: 'alice',
      type: 'choose_card',
      payload: const {'variant_id': 'v1', 'card_id': 'c1'},
    );
    final decoded = NetworkCommandDto.fromJson(command.toJson());
    final registry = CommandIdRegistry();

    expect(decoded.commandId, 'command-123');
    expect(decoded.toJson(), command.toJson());
    expect(registry.accept(decoded.commandId), isTrue);
    expect(registry.accept(decoded.commandId), isFalse);
  });

  test('projection is pure and leaves engine inputs unchanged', () {
    final state = truth();
    final pointsBefore = Map<String, int>.of(state.actionPoints);
    final duel = const DuelEngine();

    project(state, 'alice');
    project(state, 'bob', points: ActionPointVisibility.visible);

    expect(state.actionPoints, pointsBefore);
    expect(duel.config.initialPa, const BalanceConfig().initialPa);
  });
}
