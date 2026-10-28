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
    this.sexLocked = false,
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
  final bool sexLocked;
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

  Future<void> setSex(ProfileSex sex) async {
    if (sexLocked) throw StateError('Sex is locked during a game');
    final updated = profile.copyWith(sex: sex);
    await profileStore.save(updated);
    profile = updated;
    _changed();
  }

  Future<void> setGameNickname(String value) async {
    final updated = profile.copyWith(
      gameNickname: GameNickname.normalize(value),
    );
    await profileStore.save(updated);
    profile = updated;
    _changed();
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
      !profile.allowsPresentation(
        item.concept.id,
        item.actionId,
        item.direction.name,
      ) &&
      effectiveProfile.preferences.values.any(
        (p) =>
            p.excluded &&
            (p.key.role == ProfilePreferenceRole.general ||
                V4CardRatingEngine.rolesForDirection(
                  item.concept.id,
                  item.direction.name,
                ).any((role) => V4CardRatingEngine.preferenceAppliesToRole(p, item.concept.id, role))) &&
            runtime
                .vetoTags(item.concept.id, actionId: item.actionId)
                .contains(p.key.tagId),
      );
  bool cardExcluded(String id) =>
      !profile.presentationAllowances.any((a) => a.conceptId == id) &&
      profile.stageVetoes.any(
        (v) =>
            v.conceptId == id &&
            v.actionId == '*' &&
            v.role == ProfilePreferenceRole.general,
      );
  DetailedPreferenceCategory? category(ProfileCatalogItem item) {
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
    final rating = runtime.optionalRatingFor(item.concept.id, item.actionId);
    if (rating == null) return null;
    final prior = const V4CardRatingEngine().initializeForDirection(
      profile: effectiveProfile,
      variant: rating,
      conceptId: item.concept.id,
      direction: item.direction.name,
      vetoTags: runtime.vetoTags(item.concept.id, actionId: item.actionId),
    );
    return DetailedPreferenceCategoryRules.fromPa(
      prior.rawScore,
      excluded: prior.kind == V4RatingResultKind.excluded,
    );
  }

  Future<void> rate(
    ProfileCatalogItem item,
    DetailedPreferenceCategory category, {
    bool preserveExclusions = false,
  }) async {
    if (saving) return;
    saving = true;
    _changed();
    try {
      final role = ProfilePreferenceRole.parse(item.direction.name);
      final next = profile.copyWith(
        presentationAllowances: [
          ...profile.presentationAllowances.where(
            (a) =>
                !(a.conceptId == item.concept.id &&
                    a.actionId == item.actionId &&
                    a.role == role),
          ),
          if (category != DetailedPreferenceCategory.excluded)
            StageVeto(
              conceptId: item.concept.id,
              actionId: item.actionId,
              role: role,
            ),
        ],
        stageVetoes: [
          ...profile.stageVetoes.where(
            (v) =>
                preserveExclusions ||
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
      if (category.personalPa case final score?) {
        final rating = runtime.optionalRatingFor(
          item.concept.id,
          item.actionId,
        );
        final tags = <String, double>{
          for (final tag in rating?.primaryPreferenceTags ?? <String>[])
            (item.concept.id == '039' &&
                        role == ProfilePreferenceRole.recevoir &&
                        tag == 'etre_regarde'
                    ? 'regarder'
                    : tag):
                1,
          for (final tag in rating?.secondaryPreferenceTags ?? <String>[])
            tag: .5,
        };
        updatedRatings.write(
          CardRatingStateV4.fromJson({
            ...old.withOwnEstimate(score).toJson(),
            'personalization': {
              ...old.withOwnEstimate(score).personalization,
              'tags': tags,
            },
          }),
        );
      }
      // A failed appreciation write must not grant a new consent exception.
      // An explicit veto is persisted first, even if its assessment marker fails.
      if (category == DetailedPreferenceCategory.excluded) {
        await profileStore.save(next);
      }
      ratings = await ratingStore.mutate(playerId, (current) {
        if (category.personalPa case final score?) {
          final desired = updatedRatings.read(key)!;
          final latest = (current.read(key) ?? old).withOwnEstimate(score);
          current.write(
            CardRatingStateV4.fromJson({
              ...latest.toJson(),
              'personalization': {
                ...latest.personalization,
                'excluded': false,
                'tags': desired.personalization['tags'],
              },
            }),
          );
        } else {
          final latest = current.read(key) ?? old;
          current.write(
            CardRatingStateV4.fromJson({
              ...latest.toJson(),
              'source': 'EXCLUSION_MARKER',
              'personalization': {
                ...latest.personalization,
                'excluded': true,
                'pending': null,
              },
            }),
          );
        }
      });
      if (category != DetailedPreferenceCategory.excluded) {
        await profileStore.save(next);
      }
      profile = next;
    } finally {
      saving = false;
      _changed();
    }
  }

  Future<void> allowStage(ProfileCatalogItem item) async {
    if (saving) return;
    saving = true;
    _changed();
    try {
      final role = ProfilePreferenceRole.parse(item.direction.name);
      final next = profile.copyWith(
        stageVetoes: [
          for (final veto in profile.stageVetoes)
            if (!(veto.conceptId == item.concept.id &&
                veto.actionId == item.actionId &&
                (veto.role == role ||
                    veto.role == ProfilePreferenceRole.general)))
              veto,
        ],
      );
      await profileStore.save(next);
      profile = next;
    } finally {
      saving = false;
      _changed();
    }
  }

  Future<void> excludeCard(
    String conceptId, {
    bool excluded = true,
    ProfilePreferenceRole role = ProfilePreferenceRole.general,
  }) async {
    if (saving) return;
    saving = true;
    _changed();
    try {
      final next = profile.copyWith(
        presentationAllowances: excluded
            ? [
                for (final a in profile.presentationAllowances)
                  if (a.conceptId != conceptId ||
                      (role != ProfilePreferenceRole.general && a.role != role))
                    a,
              ]
            : profile.presentationAllowances,
        stageVetoes: [
          ...profile.stageVetoes.where(
            (v) =>
                !(v.conceptId == conceptId &&
                    v.actionId == '*' &&
                    (role == ProfilePreferenceRole.general || v.role == role)),
          ),
          if (excluded)
            StageVeto(conceptId: conceptId, actionId: '*', role: role),
        ],
      );
      final updatedRatings = CardSpecificLearningStore()
        ..restore(ratings.toJson());
      if (excluded) {
        // A whole-card decision explicitly covers its current presentations too.
        // Keep that evidence if the user later lifts the veto: random mode must
        // not offer already assessed elements again.
        for (final item in items.where(
          (i) =>
              i.concept.id == conceptId &&
              (role == ProfilePreferenceRole.general ||
                  i.direction.name == role.wireName),
        )) {
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
          updatedRatings.write(
            CardRatingStateV4.fromJson({
              ...old.withOwnEstimate(old.currentEstimate ?? 20).toJson(),
              'source': 'EXCLUSION_MARKER',
              'personalization': {
                ...old.personalization,
                'excluded': true,
                'pending': null,
              },
            }),
          );
        }
      }
      await profileStore.save(next);
      ratings = excluded
          ? await ratingStore.mutate(playerId, (current) {
              for (final item in items.where(
                (i) =>
                    i.concept.id == conceptId &&
                    (role == ProfilePreferenceRole.general ||
                        i.direction.name == role.wireName),
              )) {
                final key = item.ratingKey(playerId);
                final latest = current.read(key) ?? updatedRatings.read(key)!;
                current.write(
                  CardRatingStateV4.fromJson({
                    ...latest.toJson(),
                    'current_estimate': latest.currentEstimate ?? 20,
                    'source': 'EXCLUSION_MARKER',
                    'personalization': {
                      ...latest.personalization,
                      'excluded': true,
                      'pending': null,
                    },
                  }),
                );
              }
            })
          : await ratingStore.load(playerId);
      profile = next;
    } finally {
      saving = false;
      _changed();
    }
  }
}
