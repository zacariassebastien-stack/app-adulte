import '../../domain/game/game_models.dart';
import '../../domain/profile/adaptive_profile.dart';
import 'catalog_profile_controller.dart';

/// Display choices only: no persistence, aggregation or profile mutation.
enum ProfileBinderSort {
  defaultOrder('Ordre par défaut'),
  favorites('Préférences'),
  leastFavorites('Non-préférences'),
  spiceAscending('Piment croissant'),
  spiceDescending('Piment décroissant'),
  unevaluated('Non évaluées'),
  alphabetical('Ordre alphabétique');

  const ProfileBinderSort(this.label);
  final String label;
}

enum ProfileBinderEvaluation { all, evaluated, unevaluated }

abstract final class ProfileBinderOrder {
  static List<ProfileCatalogItem> select({
    required List<ProfileCatalogItem> items,
    required bool Function(ProfileCatalogItem) isEvaluated,
    required DetailedPreferenceCategory? Function(ProfileCatalogItem)
    categoryFor,
    required double? Function(ProfileCatalogItem) estimateFor,
    ProfileBinderSort sort = ProfileBinderSort.defaultOrder,
    Set<CardOccurrenceDirection> roles = const {},
    Set<int> spices = const {},
    ProfileBinderEvaluation evaluation = ProfileBinderEvaluation.all,
    String query = '',
  }) {
    final search = _textKey(query.trim());
    final entries =
        [
          for (var index = 0; index < items.length; index++)
            (
              item: items[index],
              index: index,
              evaluated: isEvaluated(items[index]),
              category: categoryFor(items[index]),
              estimate: estimateFor(items[index]),
            ),
        ].where((entry) {
          final item = entry.item;
          return (roles.isEmpty || roles.contains(item.direction)) &&
              (spices.isEmpty || spices.contains(item.chili)) &&
              (evaluation == ProfileBinderEvaluation.all ||
                  entry.evaluated ==
                      (evaluation == ProfileBinderEvaluation.evaluated)) &&
              _textKey(
                '${item.concept.title} ${item.actionTitle}',
              ).contains(search);
        }).toList();

    entries.sort((a, b) {
      var result = 0;
      switch (sort) {
        case ProfileBinderSort.defaultOrder:
          break;
        case ProfileBinderSort.favorites:
        case ProfileBinderSort.leastFavorites:
          // Explicit assessments first. Unassessed priors are not user ratings.
          result = (a.evaluated ? 0 : 1).compareTo(b.evaluated ? 0 : 1);
          if (result == 0 && a.evaluated) {
            final aScore = a.category == DetailedPreferenceCategory.excluded
                ? double.infinity
                : a.estimate ?? a.category?.personalPa ?? double.infinity;
            final bScore = b.category == DetailedPreferenceCategory.excluded
                ? double.infinity
                : b.estimate ?? b.category?.personalPa ?? double.infinity;
            result = aScore.compareTo(bScore);
            if (sort == ProfileBinderSort.leastFavorites) result = -result;
          }
        case ProfileBinderSort.spiceAscending:
          result = a.item.chili.compareTo(b.item.chili);
        case ProfileBinderSort.spiceDescending:
          result = b.item.chili.compareTo(a.item.chili);
        case ProfileBinderSort.unevaluated:
          result = (a.evaluated ? 1 : 0).compareTo(b.evaluated ? 1 : 0);
        case ProfileBinderSort.alphabetical:
          result = _textKey(
            a.item.concept.title,
          ).compareTo(_textKey(b.item.concept.title));
      }
      // The catalogue groups concept, stage/variant, region and role. Preserve
      // that proximity only after the exact presentation's primary sort value.
      return result != 0 ? result : a.index.compareTo(b.index);
    });
    return [for (final entry in entries) entry.item];
  }

  static String _textKey(String value) => value.toLowerCase().replaceAllMapped(
    RegExp('[àâäéèêëîïôöùûüçœ]'),
    (match) => const {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'œ': 'oe',
    }[match[0]]!,
  );
}
