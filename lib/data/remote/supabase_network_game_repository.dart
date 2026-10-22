import 'dart:async';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/game/game_models.dart';
import '../../engines/corruption/corruption_engine.dart';
import '../../engines/deck/deck_cycle_state.dart';
import '../../engines/recovery/recovery_engine.dart';
import '../../engines/runtime/v4_runtime_engine.dart';
import '../../sync/sync.dart';
import '../../sync/rounds/session_consent.dart';

final class SupabaseNetworkGameRepository
    implements
        NetworkGameRepository,
        NetworkNegotiationRepository,
        NetworkSessionFlowRepository,
        NetworkSessionSetupRepository,
        NetworkSessionConsentRepository,
        NetworkSessionConsentEvents,
        NetworkPrivateInitialResolutionRepository,
        NetworkV4ActionRepository,
        NetworkCommitCancellationRepository,
        NetworkSessionClosureRepository {
  SupabaseNetworkGameRepository({
    required this.client,
    this.requestTimeout = const Duration(seconds: 10),
  });

  final SupabaseClient client;
  final Duration requestTimeout;

  @override
  Stream<int> watchSessionConsent(String sessionId) async* {
    await _identity();
    await for (final rows
        in client
            .from('network_session_consent_revisions')
            .stream(primaryKey: ['session_id'])
            .eq('session_id', sessionId)) {
      if (rows.isNotEmpty) yield rows.single['revision'] as int;
    }
  }

  @override
  Future<SessionConsentState> publishSessionConsent({
    required String sessionId,
    required Set<String> allowed,
    required String commandId,
  }) async {
    await _identity();
    final result = await client
        .rpc<Map<String, dynamic>>(
          'publish_session_consent',
          params: {
            'p_session_id': sessionId,
            'p_allowed': allowed.toList()..sort(),
            'p_command_id': commandId,
          },
        )
        .timeout(requestTimeout);
    return SessionConsentState.fromJson(result);
  }

  @override
  Future<SessionConsentState> getSessionConsent(String sessionId) async {
    await _identity();
    final result = await client
        .rpc<Map<String, dynamic>>(
          'get_session_consent',
          params: {'p_session_id': sessionId},
        )
        .timeout(requestTimeout);
    return SessionConsentState.fromJson(result);
  }

  Future<String> _identity() async {
    final existing = client.auth.currentUser;
    if (existing != null) return existing.id;
    final response = await client.auth.signInAnonymously();
    final id = response.user?.id;
    if (id == null) throw const NetworkRoundException('ROUND_AUTH_REQUIRED');
    return id;
  }

  @override
  Future<NetworkGameRoundStateDto> openCurrentRound({
    required NetworkCommandDto command,
  }) => _rpc('open_network_game_round', command);

  @override
  Future<V4SessionSetupDto> registerSetupAccessories({
    required String sessionId,
    required List<V4Accessory> accessories,
  }) async {
    await _identity();
    return _setupMap(
      await client.rpc<Object?>(
        'register_v4_setup_accessories',
        params: {
          'p_session_id': sessionId,
          'p_accessories': [for (final a in accessories) a.toJson()],
        },
      ),
    );
  }

  @override
  Future<V4SessionSetupDto> proposeSessionSetup({
    required String sessionId,
    required V4SessionMode mode,
    required PlayerStyle style,
    required List<V4PlayerSessionSetupDto> players,
    required int expectedRevision,
    required String commandId,
  }) async {
    await _identity();
    return _setupMap(
      await client.rpc<Object?>(
        'propose_v4_session_setup',
        params: {
          'p_session_id': sessionId,
          'p_mode': mode.name,
          'p_style': style.name,
          'p_players': {for (final p in players) p.playerId: p.toJson()},
          'p_expected_revision': expectedRevision,
          'p_command_id': commandId,
        },
      ),
    );
  }

  @override
  Future<V4SessionSetupDto> respondSessionSetup({
    required String sessionId,
    required int revision,
    required bool accepted,
    V4PlayerSessionSetupDto? environment,
    required String commandId,
  }) async {
    await _identity();
    return _setupMap(
      await client.rpc<Object?>(
        'respond_v4_session_setup',
        params: {
          'p_session_id': sessionId,
          'p_revision': revision,
          'p_accepted': accepted,
          'p_environment': environment?.toJson(),
          'p_command_id': commandId,
        },
      ),
    );
  }

  @override
  Future<V4SessionSetupDto> getV4SessionSetup(String sessionId) async {
    await _identity();
    return _setupMap(
      await client.rpc<Object?>(
        'get_v4_session_setup',
        params: {'p_session_id': sessionId},
      ),
    );
  }

  @override
  Stream<V4SessionSetupDto> watchV4SessionSetup(String sessionId) async* {
    yield await getV4SessionSetup(sessionId);
    await for (final _
        in client
            .from('session_players')
            .stream(primaryKey: ['session_id', 'user_id'])
            .eq('session_id', sessionId)) {
      yield await getV4SessionSetup(sessionId);
    }
  }

  V4SessionSetupDto _setupMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return V4SessionSetupDto.fromJson(value.cast<String, Object?>());
    }
    if (value is List && value.length == 1 && value.first is Map) {
      return V4SessionSetupDto.fromJson(
        Map<String, Object?>.from(value.first! as Map),
      );
    }
    throw const FormatException('Invalid V4 session setup response');
  }

  @override
  Future<NetworkGameRoundStateDto> getCurrentRound({
    required String sessionId,
  }) {
    final pending = _currentReads[sessionId];
    if (pending != null) return pending;
    // Bound the shared future itself: a stalled offline request must not keep
    // every later reconciliation/retry attached to that request indefinitely.
    final read = _readCurrentRound(sessionId).timeout(requestTimeout);
    _currentReads[sessionId] = read;
    return read.whenComplete(() {
      if (identical(_currentReads[sessionId], read)) {
        _currentReads.remove(sessionId);
      }
    });
  }

  final Map<String, Future<NetworkGameRoundStateDto>> _currentReads = {};

  Future<NetworkGameRoundStateDto> _readCurrentRound(String sessionId) async {
    final playerId = await _identity();
    final current = await _call('get_current_network_game_round', {
      'p_session_id': sessionId,
      'p_player_id': playerId,
    });
    return _refreshWithCanonicalRevision(
      sessionId: sessionId,
      playerId: playerId,
      current: current,
    );
  }

  @override
  Future<NetworkGameRoundStateDto> getRound({
    required String sessionId,
    required String roundId,
  }) async {
    final identity = await _identity();
    final round = await _call('network_round_json', {
      'p_round_id': roundId,
      'p_requester': identity,
    });
    if (round.sessionId != sessionId) {
      throw const NetworkRoundException('ROUND_NOT_FOUND');
    }
    return round;
  }

  @override
  Future<NetworkGameRoundStateDto> submitCommit({
    required NetworkCommandDto command,
    required ChoiceCommitmentDto commitment,
  }) {
    _matching(command, commitment.playerId);
    return _rpc(
      'submit_network_round_commit',
      command,
      extra: {'p_digest': commitment.digest},
    );
  }

  @override
  Future<NetworkGameRoundStateDto> submitReveal({
    required NetworkCommandDto command,
    required ChoiceRevealDto reveal,
  }) {
    _matching(command, reveal.playerId);
    return _rpc(
      'submit_network_round_reveal',
      command,
      extra: {
        'p_choice_payload': reveal.choice.toJson(),
        'p_nonce': reveal.nonce,
      },
    );
  }

  @override
  Future<NetworkGameRoundStateDto> cancelCommit({
    required NetworkCommandDto command,
  }) => _rpc('cancel_network_round_commit', command);

  @override
  Future<NetworkGameRoundStateDto> closeSession({
    required NetworkCommandDto command,
  }) => _rpc('close_network_game_session', command);

  @override
  Future<NetworkGameRoundStateDto> resolveInitialPrivately({
    required NetworkCommandDto command,
  }) => _rpc('resolve_network_initial_private', command);

  @override
  Future<NetworkGameRoundStateDto> submitInitialResolution({
    required NetworkCommandDto command,
    required NetworkInitialResolutionDto resolution,
  }) => _rpc(
    'submit_network_initial_resolution',
    command,
    extra: {'p_resolution': resolution.toJson()},
  );

  @override
  Future<NetworkGameRoundStateDto> submitNegotiationProposal({
    required NetworkCommandDto command,
    required NetworkNegotiationOfferDto offer,
  }) => _rpc(
    'submit_network_negotiation_proposal',
    command,
    extra: {'p_offer': offer.toJson(includePrivateSnapshots: true)},
  );

  @override
  Future<NetworkGameRoundStateDto> respondNegotiation({
    required NetworkCommandDto command,
    required NetworkNegotiationResponseDto response,
  }) => _rpc(
    'respond_network_negotiation',
    command,
    extra: {'p_response': response.toCommandJson()},
  );

  @override
  Future<NetworkGameRoundStateDto> adaptNegotiation({
    required NetworkCommandDto command,
    required NetworkNegotiationOfferDto offer,
  }) => _rpc(
    'adapt_network_negotiation',
    command,
    extra: {'p_offer': offer.toJson(includePrivateSnapshots: true)},
  );

  @override
  Future<NetworkGameRoundStateDto> validateNegotiation({
    required NetworkCommandDto command,
    required bool accepted,
  }) => _rpc(
    'validate_network_negotiation',
    command,
    extra: {'p_accepted': accepted},
  );

  @override
  Future<NetworkGameRoundStateDto> setHybridOrientation({
    required NetworkCommandDto command,
    required HybridDeckOrientation orientation,
  }) => _rpc(
    'set_network_hybrid_orientation',
    command,
    extra: {
      'p_orientation': orientation == HybridDeckOrientation.faceToFace
          ? 'FACE_TO_FACE'
          : 'DISTANCE',
    },
  );

  @override
  Future<NetworkGameRoundStateDto> reportHybridAvailability({
    required NetworkCommandDto command,
    required NetworkHybridAvailabilityDto availability,
    required int generation,
  }) => _rpc(
    'report_network_hybrid_availability',
    command,
    extra: {
      'p_orientation':
          availability.orientation == HybridDeckOrientation.faceToFace
          ? 'FACE_TO_FACE'
          : 'DISTANCE',
      'p_generation': generation,
      'p_has_playable_current': availability.hasPlayableCurrentOrientation,
      'p_has_playable_alternate': availability.hasPlayableAlternateOrientation,
    },
  );

  @override
  Future<NetworkGameRoundStateDto> continueDeckCycle({
    required NetworkCommandDto command,
    required DeckExhaustionChoice choice,
    required int expectedCycle,
    int expectedStyleRevision = 0,
  }) => _rpc(
    'continue_network_deck_cycle',
    command,
    extra: {
      'p_choice': switch (choice) {
        DeckExhaustionChoice.keepStyle => 'CONTINUE_SAME',
        DeckExhaustionChoice.refuseStyle => 'REFUSE_STYLE',
        DeckExhaustionChoice.continueSpicier => 'CONTINUE_SPICIER',
        DeckExhaustionChoice.continueIntenable => 'CONTINUE_INTENABLE',
        DeckExhaustionChoice.infinite => 'INFINITE',
        DeckExhaustionChoice.newCustomizedGame => 'NEW_GAME',
        DeckExhaustionChoice.finish => 'FINISH',
      },
      'p_adjustment': {
        'expected_cycle': expectedCycle,
        'style_revision': expectedStyleRevision,
      },
    },
  );

  @override
  Future<NetworkGameRoundStateDto> publishUnlockedSpice({
    required NetworkCommandDto command,
    required int unlockedSpice,
  }) => _rpc(
    'publish_network_v4_unlocked_spice',
    command,
    extra: {'p_unlocked_spice': unlockedSpice},
  );

  @override
  Future<NetworkGameRoundStateDto> submitTieDecision({
    required NetworkCommandDto command,
    required TieDecision decision,
  }) => _rpc(
    'submit_network_tie_decision',
    command,
    extra: {'p_decision': decision.name.toUpperCase()},
  );

  @override
  Future<NetworkGameRoundStateDto> submitCorruptionOffer({
    required NetworkCommandDto command,
    required CorruptionObjective objective,
    required List<NetworkCorruptionActionDto> actions,
  }) => _rpc(
    'submit_network_corruption_offer',
    command,
    extra: {
      'p_objective': objective.name,
      'p_card_ids': [for (final action in actions) action.usage.toJson()],
    },
  );

  @override
  Future<NetworkGameRoundStateDto> respondCorruption({
    required NetworkCommandDto command,
    required bool accepted,
  }) => _rpc(
    'respond_network_corruption',
    command,
    extra: {'p_accepted': accepted},
  );

  @override
  Future<NetworkGameRoundStateDto> resolveCorruption({
    required NetworkCommandDto command,
    required List<NetworkCorruptionActionDto> actions,
  }) => _rpc(
    'resolve_network_corruption',
    command,
    extra: {
      'p_actions': [for (final action in actions) action.toJson()],
    },
  );

  @override
  Future<NetworkGameRoundStateDto> skipCorruption({
    required NetworkCommandDto command,
  }) => _rpc('skip_network_corruption', command);

  @override
  Future<NetworkGameRoundStateDto> submitRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  }) => _rpc(
    'submit_network_recovery',
    command,
    extra: {'p_recovery': recovery.toJson()},
  );

  @override
  Future<NetworkGameRoundStateDto> respondRecovery({
    required NetworkCommandDto command,
    required RecoveryResponse response,
  }) => _rpc(
    'respond_network_recovery',
    command,
    extra: {'p_response': response.name},
  );

  @override
  Future<NetworkGameRoundStateDto> resolveRecovery({
    required NetworkCommandDto command,
    required NetworkRecoveryDto recovery,
  }) => _rpc(
    'resolve_network_recovery',
    command,
    extra: {'p_recovery': recovery.toJson()},
  );

  @override
  Future<NetworkGameRoundStateDto> skipRecovery({
    required NetworkCommandDto command,
  }) => _rpc('skip_network_recovery', command);

  @override
  Future<NetworkGameRoundStateDto> readyNextRound({
    required NetworkCommandDto command,
    bool noPlayableOccurrences = false,
    bool hasPlayableAlternateOrientation = false,
    int? clothingCount,
  }) => _rpc(
    'ready_network_next_round',
    command,
    extra: {
      'p_no_playable_occurrences': noPlayableOccurrences,
      'p_has_playable_alternate': hasPlayableAlternateOrientation,
      'p_clothing_count': clothingCount,
    },
  );

  @override
  Future<NetworkGameRoundStateDto> repairV4ActionParameters({
    required NetworkCommandDto command,
  }) => _rpc('repair_v4_action_parameters', command);

  @override
  Future<NetworkGameRoundStateDto> publishV4ActionProjection({
    required NetworkCommandDto command,
    required NetworkResolvedActionProjectionDto projection,
  }) => _rpc(
    'publish_v4_action_projection',
    command,
    extra: {'p_projection': projection.toJson()},
  );

  @override
  Stream<NetworkGameRoundStateDto> watchRound({
    required String sessionId,
    required String roundId,
  }) async* {
    await _identity();
    yield await getCurrentRound(sessionId: sessionId);
    await for (final _
        in client
            .from('network_round_public_events')
            .stream(primaryKey: ['round_id'])
            // A new round has a new ID. Watching the session also observes its
            // insertion, so clients waiting on the closed round can advance.
            .eq('session_id', sessionId)) {
      yield await getCurrentRound(sessionId: sessionId);
    }
  }

  Future<NetworkGameRoundStateDto> _rpc(
    String function,
    NetworkCommandDto command, {
    Map<String, Object?> extra = const {},
  }) => _executeRpc(function, command, extra: extra).timeout(requestTimeout);

  Future<NetworkGameRoundStateDto> _executeRpc(
    String function,
    NetworkCommandDto command, {
    Map<String, Object?> extra = const {},
  }) async {
    final identity = await _identity();
    _matching(command, identity);
    final roundId = command.payload['round_id'] as String?;
    final result = await _call(function, {
      'p_session_id': command.sessionId,
      'p_round_id': ?roundId,
      'p_player_id': command.playerId,
      'p_command_id': command.commandId,
      ...extra,
    });
    return _refreshWithCanonicalRevision(
      sessionId: command.sessionId,
      playerId: identity,
      current: result,
    );
  }

  Future<NetworkGameRoundStateDto> _refreshWithCanonicalRevision({
    required String sessionId,
    required String playerId,
    required NetworkGameRoundStateDto current,
  }) async {
    var candidate = current;
    for (var attempt = 0; attempt < 3; attempt++) {
      final revisionBefore = await _roundRevision(candidate.roundId);
      final refreshed = await _call('get_current_network_game_round', {
        'p_session_id': sessionId,
        'p_player_id': playerId,
      });
      if (refreshed.roundId != candidate.roundId) {
        candidate = refreshed;
        continue;
      }
      final revisionAfter = await _roundRevision(candidate.roundId);
      if (revisionBefore != null && revisionBefore == revisionAfter) {
        return refreshed.withRoundRevision(revisionBefore);
      }
      candidate = refreshed;
    }
    return candidate;
  }

  Future<int?> _roundRevision(String roundId) async {
    final event = await client
        .from('network_round_public_events')
        .select('revision')
        .eq('round_id', roundId)
        .maybeSingle();
    return (event?['revision'] as num?)?.toInt();
  }

  Future<NetworkGameRoundStateDto> _call(
    String function,
    Map<String, Object?> parameters,
  ) async {
    try {
      return _map(await client.rpc<Object?>(function, params: parameters));
    } on PostgrestException catch (error) {
      final diagnostic =
          '$function: PostgREST ${error.code} ${_safeMessage(error.message)}';
      developer.log('Network game RPC failed: $diagnostic');
      throw NetworkRoundException(
        _knownCode('${error.message} ${error.details ?? ''}'),
        diagnostic: diagnostic,
      );
    } on AuthException {
      throw const NetworkRoundException('ROUND_AUTH_REQUIRED');
    }
  }

  void _matching(NetworkCommandDto command, String playerId) {
    if (command.playerId != playerId) {
      throw const NetworkRoundException('ROUND_IDENTITY_MISMATCH');
    }
  }

  NetworkGameRoundStateDto _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return NetworkGameRoundStateDto.fromJson(value.cast<String, Object?>());
    }
    if (value is List && value.length == 1 && value.first is Map) {
      return NetworkGameRoundStateDto.fromJson(
        Map<String, Object?>.from(value.first! as Map),
      );
    }
    throw const FormatException('Invalid Supabase network game response');
  }

  String _knownCode(String marker) {
    const codes = [
      'ROUND_AUTH_REQUIRED',
      'ROUND_IDENTITY_MISMATCH',
      'ROUND_NOT_MEMBER',
      'ROUND_SESSION_NOT_READY',
      'ROUND_NOT_FOUND',
      'ROUND_COMMAND_CONFLICT',
      'ROUND_COMMIT_CLOSED',
      'ROUND_CANCEL_CLOSED',
      'ROUND_REVEAL_CLOSED',
      'ROUND_COMMIT_MISSING',
      'ROUND_REVEAL_MISMATCH',
      'ROUND_INVALID_ARGUMENT',
      'ROUND_INVALID_PHASE',
      'ROUND_NOT_ACTIVE_PLAYER',
      'ROUND_INVALID_BID',
      'ROUND_INSUFFICIENT_PA',
      'ROUND_INVERSION_FORBIDDEN',
      'ROUND_AUCTION_CARD_REUSED',
      'ROUND_NEGOTIATION_INVALID',
      'ROUND_RESOLUTION_MISMATCH',
      'ROUND_DIRECTION_MISMATCH',
      'ROUND_ACTION_IDENTITY_MISMATCH',
      'ROUND_CORRUPTION_FORBIDDEN',
      'ROUND_RECOVERY_NOT_ELIGIBLE',
      'ROUND_RECOVERY_PROPOSAL_PRIVATE',
    ];
    return codes.firstWhere(
      marker.contains,
      orElse: () => 'ROUND_NETWORK_ERROR',
    );
  }

  String _safeMessage(String message) => message
      .replaceAll(RegExp(r"'([^']|'')*'"), "'<redacted>'")
      .replaceAll(RegExp(r'\{[^}]*\}'), '<redacted-json>')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '<redacted-json>')
      .replaceAll(
        RegExp(
          r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
        ),
        '<redacted-id>',
      )
      .replaceAll(RegExp(r'\b[0-9a-fA-F]{32,}\b'), '<redacted-secret>')
      .replaceAll(RegExp(r'eyJ[A-Za-z0-9._-]+'), '<redacted-token>');
}
