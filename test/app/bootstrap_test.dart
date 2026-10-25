import 'dart:async';

import 'package:couple_cards/app/bootstrap.dart';
import 'package:couple_cards/features/lobby/lobby_repository.dart';
import 'package:couple_cards/features/lobby/two_phone_lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'timeout also covers identity restoration and ignores its late response',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final identity = Completer<String>();
      final repository = _PendingIdentityRepository(identity.future);
      await tester.pumpWidget(
        CoupleCardsBootstrap(
          initializeRepository: () async => repository,
          initializationTimeout: const Duration(milliseconds: 20),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 30));
      expect(find.byType(TwoPhoneLobbyScreen), findsOneWidget);
      expect(find.byKey(const Key('bootstrap-progress')), findsNothing);
      expect(repository.identityCalls, 1);
      identity.complete('alice');
      await tester.pumpAndSettle();
      expect(find.byType(TwoPhoneLobbyScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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

final class _PendingIdentityRepository implements NetworkLobbyRepository {
  _PendingIdentityRepository(this.identity);
  final Future<String> identity;
  int identityCalls = 0;
  @override
  Future<String> currentPlayerId() {
    identityCalls++;
    return identity;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
