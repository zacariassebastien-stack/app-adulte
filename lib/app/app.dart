import 'package:flutter/material.dart';

import '../domain/game/game_screen_data.dart';
import '../features/game/game_screen.dart';

class CoupleCardsApp extends StatelessWidget {
  const CoupleCardsApp({super.key});

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
    home: GameScreen(data: _fixture()),
  );

  static GameScreenData _fixture() => GameScreenData(
    playerId: 'local-player',
    chiliActive: 2,
    elapsedSeconds: 12 * 60 + 34,
    actionPoints: 76,
    indicativeDurationMinutes: 30,
    privateDataHidden: false,
    centralActions: [
      GameCardView(
        cardId: 'revealed-action',
        category: 'ACTION DUO',
        chiliLevels: const [2],
        locked: false,
        titleKey: 'Action révélée',
        descriptionKey: 'La carte active apparaît ici pendant la partie.',
      ),
    ],
    discard: [
      GameCardView(
        cardId: 'discarded-action',
        category: 'ACTION',
        chiliLevels: const [1],
        locked: false,
      ),
    ],
    hand: [
      for (var index = 0; index < 4; index++)
        GameCardView(
          cardId: 'hand-$index',
          category: index.isEven ? 'FAIRE' : 'RECEVOIR',
          chiliLevels: [index % 3 + 1],
          locked: index == 1,
          titleKey: 'Carte ${index + 1}',
          personalValue: 12 + index,
        ),
    ],
  );
}
