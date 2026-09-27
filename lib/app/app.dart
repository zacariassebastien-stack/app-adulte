import 'package:flutter/material.dart';

/// Minimal buildable shell. Gameplay and profile UI belong to later phases.
class CoupleCardsApp extends StatelessWidget {
  const CoupleCardsApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Couple Cards',
    home: Scaffold(body: Center(child: Text('Couple Cards'))),
  );
}
