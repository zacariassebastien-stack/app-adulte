import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/domain/domain.dart';
import 'package:couple_cards/engines/eligibility/concept_runtime_catalog.dart';
import 'package:couple_cards/engines/eligibility/session_occurrence_consent.dart';

void main() {
  late ConceptRuntimeCatalog runtime;
  const engine = SessionOccurrenceConsent();
  setUpAll(() async {
    final catalog = await const CatalogLoader().load(
      (path) => File(path).readAsString(),
      includeConcepts: true,
    );
    runtime = ConceptRuntimeCatalog(
      concepts: catalog.concepts!,
      source: catalog,
      rules: catalog.conceptRules!,
    );
  });
  V4Profile profile({
    ProfilePreferenceRole? role,
    String tag = 'degradant',
    String? stage,
    String concept = '056',
    String? zone,
  }) {
    final key = ProfilePreferenceKey(
      tagId: tag,
      role: role ?? ProfilePreferenceRole.general,
      zoneId: zone,
    );
    return V4Profile(
      profileId: 'a',
      preferences: {
        if (stage == null)
          key.storageKey: ProfilePreference(
            profileId: 'a',
            key: key,
            pa: null,
            excluded: true,
            source: ProfilePreferenceSource.manualCustomized,
          ),
      },
      stageVetoes: [
        if (stage != null)
          StageVeto(
            conceptId: concept,
            actionId: stage,
            role: role ?? ProfilePreferenceRole.general,
          ),
      ],
    );
  }

  bool allowed(
    V4Profile p,
    CardOccurrenceDirection d, {
    String owner = 'a',
    String concept = '056',
    String action = '056.stage.3',
  }) => engine.allows(
    catalog: runtime,
    profile: p,
    subjectId: 'a',
    ownerId: owner,
    playerIds: ['a', 'b'],
    conceptId: concept,
    actionId: action,
    direction: d,
  );

  test(
    'profile RECEVOIR veto preserves FAIRE, including partner-owned cards',
    () {
      final p = profile(role: ProfilePreferenceRole.recevoir);
      expect(allowed(p, CardOccurrenceDirection.FAIRE), isTrue);
      expect(allowed(p, CardOccurrenceDirection.RECEVOIR), isFalse);
      expect(allowed(p, CardOccurrenceDirection.FAIRE, owner: 'b'), isFalse);
      expect(allowed(p, CardOccurrenceDirection.RECEVOIR, owner: 'b'), isTrue);
    },
  );
  test(
    'stage veto maps partner direction onto the actual participant role',
    () {
      final p = profile(
        role: ProfilePreferenceRole.faire,
        stage: '056.stage.3',
      );
      expect(allowed(p, CardOccurrenceDirection.RECEVOIR, owner: 'b'), isFalse);
      expect(allowed(p, CardOccurrenceDirection.FAIRE, owner: 'b'), isTrue);
      expect(
        allowed(p, CardOccurrenceDirection.FAIRE, action: '056.stage.2'),
        isTrue,
      );
    },
  );
  test(
    'whole-card veto applies to every stage, undo and persistence are lossless',
    () {
      final p = V4Profile.fromJson(profile(stage: '*').toJson());
      for (final stage in [1, 2, 3]) {
        expect(
          allowed(p, CardOccurrenceDirection.FAIRE, action: '056.stage.$stage'),
          isFalse,
        );
      }
      expect(
        allowed(p.copyWith(stageVetoes: []), CardOccurrenceDirection.FAIRE),
        isTrue,
      );
    },
  );
  test(
    'MUTUEL checks participation roles without treating RECEVOIR as global',
    () {
      final p = profile(
        tag: runtime
            .ratingFor('003', '003.stage.1')
            .primaryPreferenceTags
            .first,
        role: ProfilePreferenceRole.recevoir,
      );
      expect(
        allowed(
          p,
          CardOccurrenceDirection.MUTUEL,
          concept: '003',
          action: '003.stage.1',
        ),
        isFalse,
      );
      expect(
        allowed(
          p,
          CardOccurrenceDirection.FAIRE,
          concept: '003',
          action: '003.stage.1',
        ),
        isTrue,
      );
    },
  );
  test(
    'a non-participant does not veto an action performed SOLO by the partner',
    () {
      final p = profile(stage: '*');
      expect(allowed(p, CardOccurrenceDirection.SOLO, owner: 'b'), isTrue);
    },
  );
  test('a general veto is still global to the involved participant', () {
    final p = profile();
    expect(allowed(p, CardOccurrenceDirection.FAIRE), isFalse);
    expect(allowed(p, CardOccurrenceDirection.RECEVOIR), isFalse);
  });
  test(
    'LIBRE never expands a concrete anatomical veto to the whole concept',
    () {
      final concept = runtime.concepts.concepts.singleWhere(
        (c) => c.id == '002',
      );
      final fixed = concept.variants.firstWhere((v) => v.zoneId != null);
      final free = concept.variants.singleWhere((v) => v.freeZone);
      final p = profile(tag: fixed.zoneId!);
      expect(
        allowed(
          p,
          CardOccurrenceDirection.FAIRE,
          concept: '002',
          action: fixed.id,
        ),
        isFalse,
      );
      expect(
        allowed(
          p,
          CardOccurrenceDirection.FAIRE,
          concept: '002',
          action: free.id,
        ),
        isTrue,
      );
    },
  );
}
