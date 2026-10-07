import 'dart:async';

import 'package:flutter/material.dart';

import '../card_themes/card_theme_models.dart';
import '../card_themes/card_theme_registry.dart';
import '../card_themes/card_theme_repository.dart';
import '../domain/catalog/v4_catalog.dart';
import '../features/game/network_profile_learning.dart';
import '../features/lobby/lobby_repository.dart';
import '../features/profile/initial_profile_screen.dart';
import 'asset_catalog.dart';
import 'app.dart';

typedef LobbyRepositoryInitializer = Future<LobbyRepository> Function();

class CoupleCardsBootstrap extends StatefulWidget {
  const CoupleCardsBootstrap({
    required this.initializeRepository,
    this.initializationTimeout = const Duration(seconds: 15),
    super.key,
  });

  final LobbyRepositoryInitializer initializeRepository;
  final Duration initializationTimeout;

  @override
  State<CoupleCardsBootstrap> createState() => _CoupleCardsBootstrapState();
}

class _CoupleCardsBootstrapState extends State<CoupleCardsBootstrap> {
  LobbyRepository? _repository;
  final NetworkProfileLearningStore _profileStore =
      const SharedPreferencesNetworkProfileLearningStore();
  final V4ProfileStore _v4ProfileStore =
      const SharedPreferencesV4ProfileStore();
  String? _profilePlayerId;
  ProfileQuestionnaire? _questionnaire;
  bool _needsInitialProfile = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final stopwatch = Stopwatch()..start();
    debugPrint('Bootstrap: starting lobby repository initialization');
    try {
      final result = await Future.wait<Object>([
        widget.initializeRepository(),
        _loadCanonicalThemes(),
      ]).timeout(widget.initializationTimeout);
      final repository = result[0] as LobbyRepository;
      final themes = result[1] as List<ThemeBundle>;
      CardThemeRegistry.installClassic(
        themes.firstWhere((theme) => theme.pack.id == 'classic_v1'),
      );
      CardThemeRegistry.installSignature(
        themes.firstWhere((theme) => theme.pack.id == 'enchaire_signature_v1'),
      );
      if (repository is NetworkLobbyRepository) {
        final playerId = await repository.currentPlayerId();
        final profile = await _loadProfile(playerId);
        if (profile == null) {
          _profilePlayerId = playerId;
          _questionnaire = await loadAssetProfileQuestionnaire();
          _needsInitialProfile = true;
        }
      }
      debugPrint(
        'Bootstrap: lobby repository ready in ${stopwatch.elapsedMilliseconds} ms',
      );
      if (mounted) setState(() => _repository = repository);
    } catch (error, stackTrace) {
      debugPrint('Bootstrap: lobby repository unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _repository = const UnavailableLobbyRepository());
      }
    }
  }

  Future<Object?> _loadProfile(String playerId) async {
    try {
      return await _profileStore.load(playerId);
    } on Object catch (error) {
      debugPrint('Bootstrap: invalid local profile ignored: $error');
      return null;
    }
  }

  Future<List<ThemeBundle>> _loadCanonicalThemes() async {
    try {
      return await const AssetCardThemeLoader().loadAll();
    } on Object catch (error) {
      debugPrint('Bootstrap: canonical theme asset fallback used: $error');
      return [CardThemeRegistry.signature, CardThemeRegistry.classic];
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    if (repository != null) {
      if (_needsInitialProfile) {
        final playerId = _profilePlayerId;
        final questionnaire = _questionnaire;
        if (playerId != null && questionnaire != null) {
          return MaterialApp(
            title: 'Couple Cards',
            debugShowCheckedModeBanner: false,
            home: InitialProfileScreen(
              playerId: playerId,
              questionnaire: questionnaire,
              adaptiveStore: _profileStore,
              profileStore: _v4ProfileStore,
              onCompleted: () => setState(() => _needsInitialProfile = false),
            ),
          );
        }
      }
      return CoupleCardsApp(lobbyRepository: repository);
    }

    return MaterialApp(
      title: 'Couple Cards',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Jouer à deux')),
        body: const Center(
          child: CircularProgressIndicator(key: Key('bootstrap-progress')),
        ),
      ),
    );
  }
}
