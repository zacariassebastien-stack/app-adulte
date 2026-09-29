import 'dart:async';

import 'package:couple_cards/app/bootstrap.dart';
import 'package:couple_cards/features/lobby/lobby_repository.dart';
import 'package:couple_cards/features/lobby/two_phone_lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a Flutter frame before repository initialization ends', (
    tester,
  ) async {
    final repository = Completer<LobbyRepository>();

    await tester.pumpWidget(
      CoupleCardsBootstrap(initializeRepository: () => repository.future),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-progress')), findsOneWidget);

    repository.complete(const UnavailableLobbyRepository());
    await tester.pumpAndSettle();
    expect(find.byType(TwoPhoneLobbyScreen), findsOneWidget);
  });

  testWidgets('falls back to the lobby when initialization times out', (
    tester,
  ) async {
    final repository = Completer<LobbyRepository>();
    await tester.pumpWidget(
      CoupleCardsBootstrap(
        initializeRepository: () => repository.future,
        initializationTimeout: const Duration(milliseconds: 10),
      ),
    );
    await tester.pump(const Duration(milliseconds: 11));
    await tester.pump();

    expect(find.byType(TwoPhoneLobbyScreen), findsOneWidget);
    expect(find.text('Jouer à deux'), findsNWidgets(2));
  });
}
