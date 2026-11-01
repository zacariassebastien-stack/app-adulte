import 'v4_profile.dart';

/// Retired identities remain readable history, never active sub-variants.
abstract final class GenericBodyLimits {
  static bool isAction(String id) => RegExp(
    r'^(002|004|005)\.stage\.[12]\.region\.(upper_body|lower_body|free)$',
  ).hasMatch(id);
  static bool isLegacy(String id) =>
      RegExp(r'^(002|004|005)\.zone\.').hasMatch(id);
  static String? region(String id) => isAction(id) ? id.split('.').last : null;
  static const _upper = {
    'face_hair',
    'neck_nape',
    'arms_hands',
    'back_shoulders',
    'belly',
    'chest',
  };
  static const _lower = {
    'legs',
    'feet',
    'thighs',
    'buttocks',
    'penis',
    'vulva',
    'anus',
  };
  static const _names = {
    'face_hair': 'Visage / cheveux',
    'neck_nape': 'Cou / nuque',
    'arms_hands': 'Bras / mains',
    'back_shoulders': 'Dos / épaules',
    'belly': 'Ventre',
    'chest': 'Poitrine / seins',
    'legs': 'Jambes hors cuisses',
    'feet': 'Pieds',
    'thighs': 'Cuisses',
    'buttocks': 'Fesses',
    'penis': 'Pénis',
    'vulva': 'Vulve',
    'anus': 'Anus',
    'free': 'Choix libre',
  };

  static List<String> forPresentation(
    V4Profile profile,
    String concept,
    String action,
    String direction,
  ) {
    final selected = region(action);
    if (selected == null) return const [];
    final zones = <String>{};
    bool roleMatches(ProfilePreferenceRole role) =>
        role == ProfilePreferenceRole.general || role.wireName == direction;
    for (final veto in profile.stageVetoes) {
      if (veto.conceptId == concept &&
          isLegacy(veto.actionId) &&
          roleMatches(veto.role)) {
        zones.add(veto.actionId.split('.').last);
      }
    }
    final practice = {
      '002': 'embrasser',
      '004': 'bouche',
      '005': 'main',
    }[concept];
    for (final preference in profile.preferences.values) {
      if (!preference.excluded || !roleMatches(preference.key.role)) continue;
      final tag = preference.key.tagId;
      if (_names.containsKey(tag)) zones.add(tag);
      if (tag == practice && preference.key.zoneId != null) {
        zones.add(preference.key.zoneId!.split('.').last);
      }
    }
    return [
      for (final zone in zones.toList()..sort())
        if (selected == 'free' ||
            (selected == 'upper_body' && _upper.contains(zone)) ||
            (selected == 'lower_body' && _lower.contains(zone)))
          _names[zone] ?? zone,
    ];
  }

  /// Old zone-scoped tag vetoes are execution limits for regional actions,
  /// not exclusions of an entire new presentation or another body part.
  static V4Profile ratingProfile(V4Profile profile, String action) =>
      !isAction(action)
      ? profile
      : V4Profile(
          profileId: profile.profileId,
          sex: profile.sex,
          gameNickname: profile.gameNickname,
          accessories: profile.accessories,
          consents: profile.consents,
          stageVetoes: profile.stageVetoes,
          presentationAllowances: profile.presentationAllowances,
          preferences: {
            for (final entry in profile.preferences.entries)
              if (entry.value.key.zoneId == null ||
                  entry.value.key.zoneId == region(action))
                entry.key: entry.value,
          },
        );
}
