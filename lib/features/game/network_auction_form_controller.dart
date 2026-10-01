import 'package:flutter/widgets.dart';

import '../../engines/auction/auction_engine.dart';

/// Owns negotiation input that is valid only for one network round.
final class NetworkAuctionFormController {
  final counterAmount = TextEditingController();
  final defenseAmount = TextEditingController();

  AuctionTarget counterTarget = AuctionTarget.OWN_INITIAL_ACTION;
  int? _roundNumber;

  bool enterRound(int roundNumber) {
    if (_roundNumber == roundNumber) return false;
    _roundNumber = roundNumber;
    counterAmount.clear();
    defenseAmount.clear();
    counterTarget = AuctionTarget.OWN_INITIAL_ACTION;
    return true;
  }

  void dispose() {
    counterAmount.dispose();
    defenseAmount.dispose();
  }
}
