import 'dart:async';

import 'package:flutter/material.dart';

import '../card_themes/card_theme_models.dart';
import '../card_themes/card_theme_registry.dart';
import '../card_themes/card_theme_repository.dart';
import '../features/lobby/lobby_repository.dart';
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
