import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/domain.dart';
import '../../engines/engines.dart';
import '../../sync/sync.dart';
import '../lobby/lobby_models.dart';
import 'network_duel_secret_store.dart';

enum NetworkDuelViewState {
  loading,
  choosing,
  committing,
  waitingForPartner,
  revealing,
  resolved,
  error,
}

final class NetworkDuelCard {
  const NetworkDuelCard({
    required this.definition,
    required this.engine,
    required this.variant,
    required this.role,
    required this.preference,
    this.occurrenceId,
    this.nativeDirection = CardOccurrenceDirection.GENERAL,
    this.effectiveDirection = CardOccurrenceDirection.GENERAL,
  });

  final CardDefinition definition;
  final EngineCard engine;
  final EngineVariant variant;
  final ProfileRole role;
  final UserPreference preference;
  final String? occurrenceId;
  final CardOccurrenceDirection nativeDirection;
  final CardOccurrenceDirection effectiveDirection;

  String get id => engine.id;
  String get identity => occurrenceId ?? id;
  String get title => definition.title ?? definition.titleKey ?? id;
  int get chiliLevel => variant.chiliLevel;
  int get personalValue => switch (role) {
    ProfileRole.GENERAL => preference.generalValue!,
    ProfileRole.FAIRE => preference.faireValue!,
    ProfileRole.RECEVOIR => preference.recevoirValue!,
  };
  int? get oppositePersonalValue => switch (role) {
    ProfileRole.FAIRE => preference.recevoirValue,
    ProfileRole.RECEVOIR => preference.faireValue,
    ProfileRole.GENERAL => null,
  };
  ProfileRole? get oppositeRole => switch (role) {
    ProfileRole.FAIRE => ProfileRole.RECEVOIR,
    ProfileRole.RECEVOIR => ProfileRole.FAIRE,
    ProfileRole.GENERAL => null,
  };
}

/// Prototype orchestration for the single network round. Domain decisions stay
/// in EligibilityEngine, DrawEngine and DuelEngine.
final class NetworkDuelController extends ChangeNotifier {
  NetworkDuelController({
    required this.session,
    required this.playerId,
    required this.repository,
    required this.secretStore,
    required Catalog catalog,
    this.contract = const CommitRevealContract(),
    this.duelEngine = const DuelEngine(),
    DateTime Function()? clock,
    String Function()? nonceFactory,
  }) : clock = clock ?? DateTime.now,
       nonceFactory = nonceFactory ?? _secureNonce,
       _catalog = catalog {
    final playerIds = session.players.map((player) => player.userId).toList()
      ..sort();
    if (!session.ready || !playerIds.contains(playerId)) {
      throw ArgumentError('A ready lobby membership is required');
    }
    _playerIds = List.unmodifiable(playerIds);
    hand = _buildPrivateHand(catalog);
    if (hand.length != duelEngine.config.handSize) {
      throw StateError('Le catalogue ne permet pas de constituer une main');
    }
  }

  final LobbySession session;
  final String playerId;
  final NetworkRoundRepository repository;
  final NetworkDuelSecretStore secretStore;
  final CommitRevealContract contract;
  final DuelEngine duelEngine;
  final DateTime Function() clock;
  final String Function() nonceFactory;
  final Catalog _catalog;
  late final List<String> _playerIds;
  late final List<NetworkDuelCard> hand;

  NetworkDuelViewState state = NetworkDuelViewState.loading;
  NetworkRoundStateDto? round;
  NetworkDuelCard? selectedCard;
  ChoiceRevealDto? _localReveal;
  DuelResolution? resolution;
  String? errorMessage;
  int resolutionCount = 0;

  StreamSubscription<NetworkRoundStateDto>? _subscription;
  bool _committing = false;
  bool _revealing = false;

  String get opponentId => _playerIds.firstWhere((id) => id != playerId);
  ChoiceRevealDto? get localRevealedChoice =>
      round?.phase == NetworkRoundPhase.ready ? round?.ownReveal : null;
  ChoiceRevealDto? get opponentRevealedChoice =>
      round?.phase == NetworkRoundPhase.ready ? round?.opponentReveal : null;

  Future<void> start() async {
    if (_subscription != null) return;
    try {
      final created = await repository.createRound(
        command: _command('CREATE', roundId: null),
        roundNumber: 1,
      );
      final stored = await secretStore.load(
        sessionId: session.id,
        playerId: playerId,
      );
      if (stored?.sessionRound == created.sessionRound) _localReveal = stored;
      await _apply(created);
      _subscription = repository
          .watchRoundState(sessionId: session.id, roundId: created.roundId)
          .listen(
            (value) => unawaited(_apply(value)),
            onError: (Object error) => _fail(error),
          );
    } catch (error) {
      _fail(error);
    }
  }

  void selectCard(String cardId) {
    if (state != NetworkDuelViewState.choosing) return;
    selectedCard = hand.where((card) => card.id == cardId).firstOrNull;
    notifyListeners();
  }

  Future<void> confirmSelection() async {
    final card = selectedCard;
    final current = round;
    if (card == null ||
        current == null ||
        _committing ||
        state != NetworkDuelViewState.choosing) {
      return;
    }
    _committing = true;
    state = NetworkDuelViewState.committing;
    notifyListeners();
    try {
      final choice = ChoicePayload(
        cardId: card.id,
        variantId: card.variant.id,
        parameters: {
          'role': card.role.name,
          'personal_value': card.personalValue,
          'committed_at': clock().toUtc().toIso8601String(),
        },
      );
      final reveal = ChoiceRevealDto(
        sessionRound: current.sessionRound,
        playerId: playerId,
        choice: choice,
        nonce: nonceFactory(),
      );
      _localReveal = reveal;
      await secretStore.save(
        sessionId: session.id,
        playerId: playerId,
        reveal: reveal,
      );
      final commitment = contract.commit(
        sessionRound: current.sessionRound,
        playerId: playerId,
        choice: choice,
        nonce: reveal.nonce,
      );
      await _apply(
        await repository.submitCommit(
          command: _command('COMMIT', roundId: current.roundId),
          commitment: commitment,
        ),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _committing = false;
    }
  }

  Future<void> _apply(NetworkRoundStateDto value) async {
    if (value.sessionId != session.id || value.roundNumber != 1) {
      _fail(const NetworkRoundException('ROUND_NOT_FOUND'));
      return;
    }
    round = value;
    if (value.phase == NetworkRoundPhase.ready) {
      _resolveOnce(value);
      return;
    }
    if (value.phase == NetworkRoundPhase.reveal) {
      state = NetworkDuelViewState.revealing;
      notifyListeners();
      if (!value.ownRevealRecorded) await _revealOnce(value);
      return;
    }
    if (value.ownCommitRecorded) {
      if (_localReveal == null) {
        _fail(const NetworkRoundException('ROUND_LOCAL_SECRET_MISSING'));
      } else {
        state = NetworkDuelViewState.waitingForPartner;
        notifyListeners();
      }
      return;
    }
    state = NetworkDuelViewState.choosing;
    notifyListeners();
  }

  Future<void> _revealOnce(NetworkRoundStateDto value) async {
    final reveal = _localReveal;
    if (_revealing || reveal == null) {
      if (reveal == null) {
        _fail(const NetworkRoundException('ROUND_LOCAL_SECRET_MISSING'));
      }
      return;
    }
    _revealing = true;
    try {
      await _apply(
        await repository.submitReveal(
          command: _command('REVEAL', roundId: value.roundId),
          reveal: reveal,
        ),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _revealing = false;
    }
  }

  void _resolveOnce(NetworkRoundStateDto value) {
    if (resolution != null) {
      state = NetworkDuelViewState.resolved;
      notifyListeners();
      return;
    }
    final own = value.ownReveal;
    final opponent = value.opponentReveal;
    if (own == null || opponent == null) {
      _fail(const NetworkRoundException('ROUND_READY_INCOMPLETE'));
      return;
    }
    try {
      final reveals = {own.playerId: own, opponent.playerId: opponent};
      final commitments = {
        for (final id in _playerIds) id: _duelCommitment(reveals[id]!),
      };
      resolution = duelEngine.resolve(
        first: commitments[_playerIds[0]]!,
        second: commitments[_playerIds[1]]!,
        actionPoints: {
          for (final id in _playerIds) id: duelEngine.config.initialPa,
        },
      );
      resolutionCount++;
      state = NetworkDuelViewState.resolved;
      notifyListeners();
    } catch (error) {
      _fail(error);
    }
  }

  DuelCommitment _duelCommitment(ChoiceRevealDto reveal) {
    final card = _catalog.cards
        .where((item) => item.stableId == reveal.choice.cardId)
        .firstOrNull;
    final variant = card?.variants
        .where((item) => item.stableId == reveal.choice.variantId)
        .firstOrNull;
    if (card == null || variant == null) {
      throw StateError('Le choix révélé ne correspond pas au catalogue');
    }
    final roleName = reveal.choice.parameters['role'];
    final value = reveal.choice.parameters['personal_value'];
    final committedAt = reveal.choice.parameters['committed_at'];
    if (roleName is! String ||
        value is! int ||
        value < 1 ||
        value > 20 ||
        committedAt is! String) {
      throw StateError('Le snapshot révélé est invalide');
    }
    final role = ProfileRole.values.byName(roleName);
    final expectedRole = _roleFor(card, variant);
    if (role != expectedRole) throw StateError('Le rôle révélé est invalide');
    return duelEngine.commit(
      playerId: reveal.playerId,
      cardId: card.stableId,
      variantId: variant.stableId,
      voluntaryRole: role,
      preference: _preference('prototype.network', role, value),
      committedAt: DateTime.parse(committedAt),
      cardInvertible:
          (variant.inversionOverride ?? card.inversionPolicy) !=
          InversionPolicy.NONE,
    );
  }

  List<NetworkDuelCard> _buildPrivateHand(Catalog catalog) {
    const adapter = CatalogEngineAdapter();
    const eligibility = EligibilityEngine();
    const draw = DrawEngine();
    final actor = _profile(catalog, playerId);
    final partner = _profile(catalog, opponentId);
    final hierarchy = ProfileHierarchy({
      for (final element in catalog.profileElements)
        element.stableId: element.parentId,
    });
    final context = EngineSessionContext(
      mode: SessionMode.face_to_face,
      proximity: ProximityState.TOGETHER,
      chiliActive: 2,
      chiliUnlocked: 2,
      physicalStateByPlayer: {playerId: 'available', opponentId: 'available'},
      clothesByPlayer: {playerId: 5, opponentId: 5},
    );
    final definitions = {for (final item in catalog.cards) item.stableId: item};
    final engines = [for (final item in catalog.cards) adapter.card(item)];
    final drawn = draw.refill(
      currentHand: const [],
      cards: engines,
      context: context,
      actor: actor,
      partner: partner,
      hierarchy: hierarchy,
      style: PlayerStyle.EPICE,
      history: DrawHistory(),
      random: SeededRandomSource(_stableHash(playerId)),
    );
    return List.unmodifiable([
      for (final engine in drawn)
        if (definitions[engine.id] case final definition?)
          if (eligibility
                  .evaluate(
                    card: engine,
                    context: context,
                    actor: actor,
                    partner: partner,
                    hierarchy: hierarchy,
                    requirePersonalValue: true,
                  )
                  .eligibleVariants
                  .firstOrNull
              case final variant?)
            NetworkDuelCard(
              definition: definition,
              engine: engine,
              variant: variant,
              role: _roleFor(
                definition,
                definition.variants.firstWhere(
                  (item) => item.stableId == variant.id,
                ),
              ),
              preference: _preferenceForVariant(
                definition,
                definition.variants.firstWhere(
                  (item) => item.stableId == variant.id,
                ),
              ),
            ),
    ]);
  }

  PlayerGameProfile _profile(Catalog catalog, String id) => PlayerGameProfile(
    playerId: id,
    preferences: {
      for (final element in catalog.profileElements)
        element.stableId: PreferenceValue(
          status: PreferenceStatus.ACCEPTED,
          general: _fixtureValue(id, element.stableId, ProfileRole.GENERAL),
          faire: _fixtureValue(id, element.stableId, ProfileRole.FAIRE),
          recevoir: _fixtureValue(id, element.stableId, ProfileRole.RECEVOIR),
        ),
    },
  );

  UserPreference _preferenceForVariant(
    CardDefinition card,
    CardVariantDefinition variant,
  ) {
    final role = _roleFor(card, variant);
    final requirements = [
      ...card.profileRequirements,
      ...variant.profileRequirements,
    ];
    final elementId =
        requirements
            .where((item) => item.role == role)
            .map((item) => item.elementId)
            .firstOrNull ??
        requirements.map((item) => item.elementId).firstOrNull ??
        'prototype.network';
    return _preference(
      elementId,
      role,
      _fixtureValue(playerId, elementId, role),
    );
  }

  static ProfileRole _roleFor(
    CardDefinition card,
    CardVariantDefinition variant,
  ) {
    final requirements = [
      ...card.profileRequirements,
      ...variant.profileRequirements,
    ];
    final directed = requirements
        .map((item) => item.role)
        .where((role) => role != ProfileRole.GENERAL)
        .firstOrNull;
    if (directed != null) return directed;
    return switch (card.directionality) {
      CardDirectionality.FAIRE => ProfileRole.FAIRE,
      CardDirectionality.RECEVOIR => ProfileRole.RECEVOIR,
      _ => ProfileRole.GENERAL,
    };
  }

  static UserPreference _preference(
    String elementId,
    ProfileRole role,
    int value,
  ) => UserPreference.fromJson({
    'profile_element_id': elementId,
    'status': PreferenceStatus.ACCEPTED.name,
    'general_value': role == ProfileRole.GENERAL ? value : null,
    'faire_value': role == ProfileRole.FAIRE ? value : null,
    'recevoir_value': role == ProfileRole.RECEVOIR ? value : null,
    'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    'source': PreferenceSource.ONBOARDING.name,
  });

  int _fixtureValue(String id, String element, ProfileRole role) =>
      8 + (_stableHash('$id/$element/${role.name}') % 11);

  NetworkCommandDto _command(String type, {required String? roundId}) =>
      NetworkCommandDto(
        commandId: 'round-1:${session.id}:$playerId:${type.toLowerCase()}',
        sessionId: session.id,
        playerId: playerId,
        type: type,
        payload: {'round_id': ?roundId},
      );

  void _fail(Object error) {
    state = NetworkDuelViewState.error;
    errorMessage = error is NetworkRoundException
        ? error.code
        : 'Le duel réseau est momentanément indisponible.';
    notifyListeners();
  }

  static int _stableHash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  static String _secureNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
