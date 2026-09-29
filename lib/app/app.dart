import 'package:flutter/material.dart';

import '../features/game/game_screen.dart';
import '../features/game/local_game_controller.dart';
import '../features/game/local_game_fixture.dart';

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
    home: const _LocalGameHost(),
  );
}

class _LocalGameHost extends StatefulWidget {
  const _LocalGameHost();

  @override
  State<_LocalGameHost> createState() => _LocalGameHostState();
}

class _LocalGameHostState extends State<_LocalGameHost> {
  late final LocalGameController controller;

  @override
  void initState() {
    super.initState();
    controller = createLocalGameFixture();
  }

  @override
  Widget build(BuildContext context) =>
      GameScreen(data: controller.screenData, controller: controller);
}
