import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final catalog =
      jsonDecode(
            File('assets/catalog/source/cards.v2.fr.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final audit =
      jsonDecode(
            File('docs/catalog_v3_editorial_audit.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final cards = (catalog['cards']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final titles = <String, String>{};
  for (final card in cards) {
    titles[card['stable_id']! as String] = card['title']! as String;
    for (final variant
        in (card['variants']! as List<Object?>).cast<Map<String, Object?>>()) {
      titles[variant['stable_id']! as String] = variant['title']! as String;
    }
  }

  test('audit covers every playable V3 card and variant title', () {
    expect(audit['audited_card_titles'], 96);
    expect(audit['audited_variant_titles'], 141);
    final corrections = (audit['corrections']! as List<Object?>);
    expect(audit['correction_count'], corrections.length);
    expect(audit['unchanged_title_count'], 237 - corrections.length);
  });

  test('every reported correction exists under the same stable ID', () {
    final corrections = (audit['corrections']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      corrections.map((item) => item['stable_id']).toSet(),
      hasLength(corrections.length),
    );
    for (final correction in corrections) {
      final id = correction['stable_id']! as String;
      expect(titles[id], correction['new_title'], reason: id);
      expect(
        correction['old_title'],
        isNot(correction['new_title']),
        reason: id,
      );
    }
  });

  test('audit records that catalogue semantics were preserved', () {
    expect(audit['invariants'], {
      'stable_ids_changed': 0,
      'engagement_levels_changed': 0,
      'requirements_changed': 0,
      'regard_exterieur_playable_variants': 0,
      'directional_mirror_cards_disabled': 8,
      'directional_mirror_variants_disabled': 56,
    });
  });
}
