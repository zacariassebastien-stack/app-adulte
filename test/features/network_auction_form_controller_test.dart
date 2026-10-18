import 'package:couple_cards/features/game/network_auction_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new round clears only transient auction input', () {
    final form = NetworkAuctionFormController();
    final actionPoints = {'alice': 84, 'bob': 68};

    expect(form.enterRound(3), isTrue);
    form.directPaAmount.text = '5';

    expect(form.enterRound(3), isFalse);
    expect(form.directPaAmount.text, '5');

    expect(form.enterRound(4), isTrue);
    expect(form.directPaAmount.text, isEmpty);
    expect(actionPoints, {'alice': 84, 'bob': 68});

    form.dispose();
  });
}
