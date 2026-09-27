import '../../domain/domain.dart';

/// Structural checks run in model readers; this pass checks the complete graph.
final class CatalogValidator {
  const CatalogValidator();
  List<CatalogIssue> validate(Catalog catalog) {
    final issues = <CatalogIssue>[];
    void issue(
      String type,
      String id,
      String property,
      String code,
      String message,
    ) {
      issues.add(
        CatalogIssue(
          code: code,
          objectType: type,
          stableId: id,
          property: property,
          message: message,
        ),
      );
    }

    final ids = <String>{};
    void register(String type, String id) {
      if (!ids.add(id)) {
        issue(type, id, 'stable_id', 'duplicate_id', 'Duplicate stable_id');
      }
    }

    final profiles = {for (final p in catalog.profileElements) p.stableId: p};
    final tags = {for (final t in catalog.tags) t.stableId};
    for (final p in catalog.profileElements) {
      register('ProfileElementDefinition', p.stableId);
      if (p.parentId != null && !profiles.containsKey(p.parentId)) {
        issue(
          'ProfileElementDefinition',
          p.stableId,
          'parent_id',
          'missing_parent',
          'Unknown parent ${p.parentId}',
        );
      }
      for (var i = 0; i < p.childrenOrder.length; i++) {
        final child = profiles[p.childrenOrder[i]];
        if (child == null || child.parentId != p.stableId) {
          issue(
            'ProfileElementDefinition',
            p.stableId,
            'children_order[$i]',
            'invalid_child',
            'Expected an immediate child ID',
          );
        }
      }
      // Iterative ancestry walk also handles very deep externally supplied trees.
      final seen = <String>{};
      String? current = p.stableId;
      while (current != null && profiles.containsKey(current)) {
        if (!seen.add(current)) {
          issue(
            'ProfileElementDefinition',
            p.stableId,
            'parent_id',
            'profile_cycle',
            'Cycle through $current',
          );
          break;
        }
        current = profiles[current]!.parentId;
      }
    }
    for (final t in catalog.tags) {
      register('TagDefinition', t.stableId);
    }
    for (final c in catalog.cards) {
      final variantIds = c.variants.map((v) => v.stableId).toSet();
      void action(
        ActionDefinition a,
        String type,
        List<String> tagRefs,
        String tagProperty,
      ) {
        register(type, a.stableId);
        for (var i = 0; i < tagRefs.length; i++) {
          final id = tagRefs[i];
          // The seed uses namespace-relative references; definitions retain their
          // exact stable IDs. Resolve only existing definitions, never create one.
          if (!tags.contains(id) && !tags.contains('tag.$id')) {
            issue(
              type,
              a.stableId,
              '$tagProperty[$i]',
              'missing_tag',
              'Unknown Tag $id',
            );
          }
        }
        for (var i = 0; i < a.profileRequirements.length; i++) {
          final r = a.profileRequirements[i];
          if (!profiles.containsKey(r.elementId)) {
            issue(
              type,
              a.stableId,
              'profile_requirements[$i].element_id',
              'missing_profile',
              'Unknown ProfileElement ${r.elementId}',
            );
          }
          if (r.appliesToVariantId != null &&
              (!variantIds.contains(r.appliesToVariantId) ||
                  (a is CardVariantDefinition &&
                      r.appliesToVariantId != a.stableId))) {
            issue(
              type,
              a.stableId,
              'profile_requirements[$i].applies_to_variant_id',
              'invalid_variant_reference',
              'Variant must belong to this action',
            );
          }
        }
        for (final p in a.parameters) {
          register('CardParameterDefinition', p.stableId);
        }
      }

      action(c, 'CardDefinition', c.baseTags, 'base_tags');
      for (final v in c.variants) {
        action(v, 'CardVariantDefinition', v.additionalTags, 'additional_tags');
        if (v.cardId != null && v.cardId != c.stableId) {
          issue(
            'CardVariantDefinition',
            v.stableId,
            'card_id',
            'invalid_card_reference',
            'Expected ${c.stableId}',
          );
        }
        for (var i = 0; i < v.removedTags.length; i++) {
          final id = v.removedTags[i];
          if (!tags.contains(id) && !tags.contains('tag.$id')) {
            issue(
              'CardVariantDefinition',
              v.stableId,
              'removed_tags[$i]',
              'missing_tag',
              'Unknown Tag $id',
            );
          }
        }
      }
    }
    return List.unmodifiable(issues);
  }

  void validateOrThrow(Catalog catalog) {
    final issues = validate(catalog);
    if (issues.isNotEmpty) throw CatalogException(issues);
  }
}
