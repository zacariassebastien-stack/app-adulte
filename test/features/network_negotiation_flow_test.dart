import 'package:couple_cards/features/game/network_duel_screen.dart';
import 'package:couple_cards/sync/rounds/network_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('winner sees the complete proposal before deciding', (
    tester,
  ) async {
    final offer = NetworkNegotiationOfferDto(
      inversionRequested: true,
      directPa: 7,
      cards: const [
        NetworkCompromiseCardDto(
          occurrenceId: 'occurrence-1',
          cardId: 'card.first',
          variantId: 'variant.first',
          ownerPlayerId: 'loser',
          nativeDirection: NetworkCardDirection.FAIRE,
          effectiveDirection: NetworkCardDirection.FAIRE,
          origin: NetworkCompromiseOrigin.AUCTION,
          snapshotValue: 0,
          effectiveSpice: 3,
        ),
        NetworkCompromiseCardDto(
          occurrenceId: 'occurrence-2',
          cardId: 'card.second',
          variantId: 'variant.second',
          ownerPlayerId: 'loser',
          nativeDirection: NetworkCardDirection.RECEVOIR,
          effectiveDirection: NetworkCardDirection.RECEVOIR,
          origin: NetworkCompromiseOrigin.AUCTION,
          snapshotValue: 0,
          effectiveSpice: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkNegotiationOfferSummary(
            offer: offer,
            titleForCard: (id) => switch (id) {
              'card.first' => 'Première action',
              _ => 'Deuxième action',
            },
          ),
        ),
      ),
    );

    expect(find.text('• Inversion de la carte initiale'), findsOneWidget);
    expect(find.text('• 7 PA personnels'), findsOneWidget);
    expect(find.text('Première action'), findsOneWidget);
    expect(find.text('Faire · 🌶️🌶️🌶️'), findsOneWidget);
    expect(find.text('Deuxième action'), findsOneWidget);
    expect(find.text('Recevoir · 🌶️🌶️'), findsOneWidget);
  });

  test('response DTO exposes only the single final decision', () {
    const response = NetworkNegotiationResponseDto(accepted: true);
    expect(response.toCommandJson(), {'accepted': true});
    expect(response.toCommandJson(), isNot(contains('accept_inversion')));
    expect(response.toCommandJson(), isNot(contains('accept_auction')));
  });

  test('legacy component response survives state reconstruction', () {
    const response = NetworkNegotiationResponseDto(
      accepted: true,
      acceptInversion: true,
      acceptAuction: true,
    );
    final restored = NetworkNegotiationResponseDto.fromJson(response.toJson());
    expect(restored.acceptInversion, isTrue);
    expect(restored.acceptAuction, isTrue);
  });
}
