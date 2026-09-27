import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/data/catalog_loader/catalog_validator.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  const path = 'assets/catalog/source';
  test(
    'provided V2 decodes losslessly; audit records all unresolved references',
    () {
      final cards = File('$path/cards.v2.fr.json').readAsStringSync();
      final profiles = File(
        '$path/profile_elements.v1.fr.json',
      ).readAsStringSync();
      final tags = File('$path/tags.v1.json').readAsStringSync();
      final c = const CatalogLoader().decode(
        cardsJson: cards,
        profilesJson: profiles,
        tagsJson: tags,
      );
      expect(c.cards.length, 100);
      expect(c.cards.expand((v) => v.variants).length, 134);
      expect(c.profileElements.length, 98);
      expect(c.tags.length, 98);
      expect(c.cardsDocument, jsonDecode(cards));
      expect(c.profilesDocument, jsonDecode(profiles));
      expect(c.tagsDocument, jsonDecode(tags));
      final issues = const CatalogValidator().validate(c);
      final audit =
          jsonDecode(File('docs/catalog_audit.json').readAsStringSync())
              as JsonMap;
      expect(issues.map((e) => e.toJson()).toList(), audit['issues']);
      expect(
        issues,
        isNotEmpty,
        reason:
            'Source is unresolved; this is a regression audit, not an acceptance gate.',
      );
    },
  );
  test(
    'production loader refuses supplied V2 until editorial repair',
    () async {
      await expectLater(
        const CatalogLoader().load((p) => File(p).readAsString()),
        throwsA(isA<CatalogException>()),
      );
    },
  );
}
