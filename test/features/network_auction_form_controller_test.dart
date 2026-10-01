import 'package:couple_cards/engines/auction/auction_engine.dart';
import 'package:couple_cards/features/game/network_auction_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new round clears only transient auction input', () {
    final form = NetworkAuctionFormController();
    final actionPoints = {'alice': 84, 'bob': 68};

    expect(form.enterRound(3), isTrue);
    form.counterAmount.text = '5';
    form.defenseAmount.text = '6';
    form.counterTarget = AuctionTarget.INVERT_WINNING_ACTION;

    expect(form.enterRound(3), isFalse);
    expect(form.counterAmount.text, '5');
    expect(form.counterTarget, AuctionTarget.INVERT_WINNING_ACTION);

    expect(form.enterRound(4), isTrue);
    expect(form.counterAmount.text, isEmpty);
    expect(form.defenseAmount.text, isEmpty);
    expect(form.counterTarget, AuctionTarget.OWN_INITIAL_ACTION);
    expect(actionPoints, {'alice': 84, 'bob': 68});

    form.dispose();
  });
}
