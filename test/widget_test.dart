import 'package:couple_cards/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('minimal application shell compiles and renders', (tester) async {
    await tester.pumpWidget(const CoupleCardsApp());
    expect(find.text('Couple Cards'), findsOneWidget);
  });
}
