import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/catalog/concept_catalog.dart';
import '../../domain/game/game_models.dart';
import '../../domain/profile/adaptive_profile.dart';
import '../../domain/profile/v4_profile.dart';
import '../../engines/eligibility/concept_runtime_catalog.dart';
import '../../engines/profile/v4_card_rating_engine.dart';
import '../game/network_profile_learning.dart';

/// A catalogue presentation, never an additional occurrence in the game deck.
final class ProfileCatalogItem {
  const ProfileCatalogItem(
    this.concept,
    this.actionId,
    this.actionTitle,
    this.direction,
    this.chili,
  );
  final CardConcept concept;
  final String actionId, actionTitle;
  final CardOccurrenceDirection direction;
  final int chili;
  String get id => '${concept.id}|$actionId|${direction.name}';
  CardRatingKey ratingKey(String profileId) => CardRatingKey(
    profileId: profileId,
    cardId: concept.id,
    variantId: actionId,
    role: ProfilePreferenceRole.parse(direction.name),
  );
}

final class CatalogProfileController extends ChangeNotifier {
  CatalogProfileController({
    required this.catalog,
    required this.playerId,
    this.profileStore = const SharedPreferencesV4ProfileStore(),
    this.learningStore = const SharedPreferencesNetworkProfileLearningStore(),
    this.ratingStore = const SharedPreferencesV4CardLearningStore(),
  }) {
    runtime = ConceptRuntimeCatalog(
      concepts: catalog.concepts!,
      source: catalog,
      rules: catalog.conceptRules!,
    );
    final bindings = (catalog.conceptRules!['bindings'] as List)
        .cast<Map<String, Object?>>();
    items = List.unmodifiable([
      for (final concept in catalog.concepts!.concepts)
        for (final action in [
          ...concept.stages.map((a) => (a.id, a.title, a.chili)),
          ...concept.variants.map(
            (a) => (a.id, a.title, a.chili ?? concept.intrinsicChili!),
          ),
        ])
          for (final tag
              in ((((bindings.singleWhere(
                                        (b) => b['concept_id'] == concept.id,
                                      )['actions']
                                      as List)
                                  .cast<Map<String, Object?>>()
                                  .singleWhere(
                                    (a) => a['action_id'] == action.$1,
                                  )['editorial']
                              as Map)['tags']
                          as List)
                      .cast<String>())
                  .where((t) => t.startsWith('v3.direction.')))
            ProfileCatalogItem(
              concept,
              action.$1,
              action.$2,
              CardOccurrenceDirection.values.byName(
                tag.split('.').last.toUpperCase(),
              ),
              action.$3,
            ),
    ]);
  }
  final Catalog catalog;
  final String playerId;
  final V4ProfileStore profileStore;
  final V4CardLearningStore ratingStore;
  final NetworkProfileLearningStore learningStore;
  AdaptiveProfileState? learnedState;
  V4Profile get effectiveProfile =>
      mergeV4ProfileLearning(profile, learnedState);
  late final ConceptRuntimeCatalog runtime;
  late final List<ProfileCatalogItem> items;
  late V4Profile profile;
  CardSpecificLearningStore ratings = CardSpecificLearningStore();
  bool ready = false, saving = false;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    profile =
        await profileStore.load(playerId) ??
        (throw StateError('Crée d’abord ton profil.'));
    ratings = await ratingStore.load(playerId);
    learnedState = await learningStore.load(playerId);
    ready = true;
    _changed();
  }

  bool explicit(ProfileCatalogItem item) =>
      ratings.explicitlyRated(item.ratingKey(playerId)) ||
      profile.excludesStage(
        item.concept.id,
        item.actionId,
        item.direction.name,
      );
  List<ProfileCatalogItem> get remaining =>
      items.where((i) => !explicit(i)).toList();
  ProfileCatalogItem? randomNext({Random? random}) {
    final pool = remaining;
    return pool.isEmpty
        ? null
        : pool[(random ?? Random()).nextInt(pool.length)];
  }

  bool globalTagVeto(ProfileCatalogItem item) =>
      effectiveProfile.preferences.values.any(
        (p) =>
            p.excluded &&
            runtime.vetoTags(item.concept.id).contains(p.key.tagId),
      );
  bool cardExcluded(String id) =>
      profile.stageVetoes.any((v) => v.conceptId == id && v.actionId == '*');
  DetailedPreferenceCategory category(ProfileCatalogItem item) {
    if (profile.excludesStage(
      item.concept.id,
      item.actionId,
      item.direction.name,
    )) {
      return DetailedPreferenceCategory.excluded;
    }
    final estimate = ratings.explicitEstimate(item.ratingKey(playerId));
    if (estimate != null) {
      return DetailedPreferenceCategoryRules.fromPa(estimate);
    }
    final prior = const V4CardRatingEngine().initializeForDirection(
      profile: effectiveProfile,
      variant: runtime.ratingFor(item.concept.id, item.actionId),
      conceptId: item.concept.id,
      direction: item.direction.name,
      vetoTags: runtime.vetoTags(item.concept.id),
    );
    return DetailedPreferenceCategoryRules.fromPa(
      prior.rawScore,
      excluded: prior.kind == V4RatingResultKind.excluded,
    );
  }

  Future<void> rate(
    ProfileCatalogItem item,
    DetailedPreferenceCategory category,
  ) async {
    if (saving) return;
    saving = true;
    _changed();
    try {
      final role = ProfilePreferenceRole.parse(item.direction.name);
      final next = profile.copyWith(
        stageVetoes: [
          ...profile.stageVetoes.where(
            (v) =>
                !(v.conceptId == item.concept.id &&
                    v.actionId == item.actionId &&
                    (v.role == role ||
                        v.role == ProfilePreferenceRole.general)),
          ),
          if (category == DetailedPreferenceCategory.excluded)
            StageVeto(
              conceptId: item.concept.id,
              actionId: item.actionId,
              role: role,
            ),
        ],
      );
      final key = item.ratingKey(playerId);
      final old =
          ratings.read(key) ??
          CardRatingStateV4(
            key: key,
            initialScore: null,
            currentEstimate: null,
            observationCount: 0,
            acceptanceCount: 0,
            resistanceCount: 0,
            source: 'TAG_PRIOR',
          );
      // CARD_ESTIMATE is the existing explicit card-specific estimate marker.
      final updatedRatings = CardSpecificLearningStore()
        ..restore(ratings.toJson());
      updatedRatings.write(old.withOwnEstimate(category.personalPa ?? 20));
      await profileStore.save(next);
      await ratingStore.save(playerId, updatedRatings);
      ratings = updatedRatings;
      profile = next;
    } finally {
      saving = false;
      _changed();
    }
  }

  Future<void> excludeCard(String conceptId, {bool excluded = true}) async {
    if (saving) return;
    saving = true;
    _changed();
    try {
      final next = profile.copyWith(
        stageVetoes: [
          ...profile.stageVetoes.where(
            (v) => !(v.conceptId == conceptId && v.actionId == '*'),
          ),
          if (excluded)
            StageVeto(
              conceptId: conceptId,
              actionId: '*',
              role: ProfilePreferenceRole.general,
            ),
        ],
      );
      final updatedRatings = CardSpecificLearningStore()
        ..restore(ratings.toJson());
      if (excluded) {
        // A whole-card decision explicitly covers its current presentations too.
        // Keep that evidence if the user later lifts the veto: random mode must
        // not offer already assessed elements again.
        for (final item in items.where((i) => i.concept.id == conceptId)) {
          final key = item.ratingKey(playerId);
          final old =
              updatedRatings.read(key) ??
              CardRatingStateV4(
                key: key,
                initialScore: null,
                currentEstimate: null,
                observationCount: 0,
                acceptanceCount: 0,
                resistanceCount: 0,
                source: 'TAG_PRIOR',
              );
          updatedRatings.write(old.withOwnEstimate(old.currentEstimate ?? 20));
        }
      }
      await profileStore.save(next);
      if (excluded) await ratingStore.save(playerId, updatedRatings);
      ratings = updatedRatings;
      profile = next;
    } finally {
      saving = false;
      _changed();
    }
  }
}
