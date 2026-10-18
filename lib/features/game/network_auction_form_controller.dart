import 'package:flutter/widgets.dart';

/// Owns negotiation input that is valid only for one network round.
final class NetworkAuctionFormController {
  final directPaAmount = TextEditingController();

  int? _roundNumber;

  bool enterRound(int roundNumber) {
    if (_roundNumber == roundNumber) return false;
    _roundNumber = roundNumber;
    directPaAmount.clear();
    return true;
  }

  void dispose() {
    directPaAmount.dispose();
  }
}
