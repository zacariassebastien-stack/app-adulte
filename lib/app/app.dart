import 'package:flutter/material.dart';

import '../features/lobby/lobby_repository.dart';
import '../features/lobby/two_phone_lobby_screen.dart';

class CoupleCardsApp extends StatelessWidget {
  const CoupleCardsApp({this.lobbyRepository, super.key});

  final LobbyRepository? lobbyRepository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Couple Cards',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF73546F),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF9F7F8),
      useMaterial3: true,
    ),
    home: TwoPhoneLobbyScreen(
      repository: lobbyRepository ?? const UnavailableLobbyRepository(),
    ),
  );
}
