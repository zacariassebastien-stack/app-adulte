import 'package:test/test.dart';
import 'support/concept_deck_checks.dart';
import 'support/concept_progression_checks.dart';

// The V4 fixed-occurrence generator is replaced by the conceptual engine.
void main(){
 for(final entry in {...conceptDeckChecks(),...conceptProgressionChecks()}.entries){test(entry.key,entry.value);}
}
