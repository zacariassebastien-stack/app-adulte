import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/data/catalog_loader/catalog_validator.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:test/test.dart';

JsonMap document(String path) =>
    jsonDecode(File(path).readAsStringSync()) as JsonMap;

void main() {
  const path = 'assets/catalog/source';
  late Catalog catalog;
  setUp(() async {
    catalog = await const CatalogLoader().load((p) => File(p).readAsString());
  });
  test('production loader accepts real catalog and audit is current', () {
    expect(catalog.cards.length, 100);
    expect(catalog.cards.expand((c) => c.variants).length, 134);
    expect(catalog.profileElements.length, 133);
    expect(catalog.tags.length, 105);
    expect(catalog.cardsDocument, document('$path/cards.v2.fr.json'));
    expect(
      catalog.profilesDocument,
      document('$path/profile_elements.v1.fr.json'),
    );
    expect(catalog.tagsDocument, document('$path/tags.v1.json'));
    final issues = const CatalogValidator().validate(catalog);
    expect(issues, isEmpty);
    expect(document('docs/catalog_audit.json'), {
      'valid': true,
      'cards': catalog.cards.length,
      'variants': catalog.cards.expand((c) => c.variants).length,
      'profile_elements': catalog.profileElements.length,
      'tags': catalog.tags.length,
      'issues': issues.map((e) => e.toJson()).toList(),
    });
  });
  test(
    'repair preserves original IDs, profiles, tags and all requirements',
    () {
      final baseline = document('test/fixtures/catalog_baseline.json');
      final profiles = {for (final p in catalog.profileElements) p.stableId: p};
      for (final p in (baseline['profiles'] as List).cast<JsonMap>()) {
        expect(profiles[p['stable_id']]?.toJson(), p);
      }
      final tags = {for (final t in catalog.tags) t.stableId: t};
      for (final t in (baseline['tags'] as List).cast<JsonMap>()) {
        expect(tags[t['stable_id']]?.toJson(), t);
      }
      final actions = <String, ActionDefinition>{
        for (final c in catalog.cards) c.stableId: c,
        for (final c in catalog.cards)
          for (final v in c.variants) v.stableId: v,
      };
      final original = baseline['actions'] as JsonMap;
      expect(actions.keys, unorderedEquals(original.keys));
      for (final entry in original.entries) {
        final action = actions[entry.key]!;
        final before = entry.value as JsonMap;
        expect(action.enabled, before['enabled']);
        expect(
          action.profileRequirements.map((r) => r.toJson()),
          containsAll(before['profile_requirements'] as List),
          reason: entry.key,
        );
        expect(
          action.technicalRequirements.map((r) => r.toJson()),
          containsAll(before['technical_requirements'] as List),
          reason: entry.key,
        );
      }
      expect(
        actions.values.expand((a) => a.parameters).map((p) => p.stableId),
        unorderedEquals(baseline['parameter_ids'] as List),
      );
    },
  );
  test('hierarchy keeps explicit acceptance at every level', () {
    final profiles = {for (final p in catalog.profileElements) p.stableId: p};
    for (final p in catalog.profileElements) {
      expect(p.explicitAcceptanceRequired, isTrue, reason: p.stableId);
      expect(p.enabled, isTrue, reason: p.stableId);
      final segments = p.stableId.split('.');
      expect(
        p.parentId,
        segments.length == 2
            ? isNull
            : segments.take(segments.length - 1).join('.'),
      );
      if (p.parentId != null) expect(profiles, contains(p.parentId));
    }
    expect(
      profiles['profile.media.video.nude']!.parentId,
      'profile.media.video',
    );
    expect(profiles['profile.media.video']!.parentId, 'profile.media');
    expect(
      profiles['profile.power.order.receive']!.parentId,
      'profile.power.order',
    );
    expect(profiles['profile.power.order']!.parentId, 'profile.power');
  });
  test('reviewed variant dimensions require explicit accepted consent', () {
    final additions = document('test/fixtures/catalog_consent_additions.json');
    final variants = {
      for (final c in catalog.cards)
        for (final v in c.variants) v.stableId: v,
    };
    for (final entry in additions.entries) {
      for (final id in entry.value as List) {
        expect(
          variants[entry.key]!.profileRequirements.any(
            (r) =>
                r.elementId == id &&
                r.role == ProfileRole.GENERAL &&
                r.requirement == RequirementKind.REQUIRED &&
                r.minimumStatus == PreferenceStatus.ACCEPTED &&
                r.oneOfGroupId == null &&
                r.appliesToVariantId == null,
          ),
          isTrue,
          reason: '${entry.key}: $id',
        );
      }
    }
    // Acceptance of the reviewed seed, never runtime consent inference.
    final tags = {for (final t in catalog.tags) t.stableId: t};
    for (final c in catalog.cards) {
      for (final v in c.variants) {
        final requirements = [
          ...c.profileRequirements,
          ...v.profileRequirements,
        ];
        for (final tag in v.additionalTags) {
          if (tags['tag.$tag']!.technicalOnly) continue;
          expect(
            requirements.any(
              (r) =>
                  r.elementId == 'profile.$tag' &&
                  r.requirement == RequirementKind.REQUIRED &&
                  r.minimumStatus == PreferenceStatus.ACCEPTED,
            ),
            isTrue,
            reason: '${v.stableId}: $tag',
          );
        }
      }
    }
    expect(
      tags.values.where((t) => t.technicalOnly).map((t) => t.stableId),
      unorderedEquals(['tag.duration.long', 'tag.simulation.guided']),
    );
  });
}
