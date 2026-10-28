import '../../domain/game/game_models.dart';
import '../../domain/profile/v4_profile.dart';
import '../runtime/v4_runtime_engine.dart';

/// Resolve optional requirements from explicit context and structured profile data.
/// No accessory ID, free-text name or sextoy boolean grants restraint capability.
abstract final class ConceptContext {
  static EngineSessionContext resolve({
    required EngineSessionContext context,
    required V4Profile? profile,
    required Iterable<V4Accessory> accessories,
  }) {
    final roleplay = profile?.preference(
      const ProfilePreferenceKey(
        tagId: 'jeu_role',
        role: ProfilePreferenceRole.mutuel,
      ),
    );
    return context.copyWith(
      flags: {
        'roleplayEnabled':
            (roleplay != null && !roleplay.excluded && roleplay.pa != null) ||
            profile?.allowsPresentation('048', '048.action', 'MUTUEL') == true,
        'hasConstraintAccessory': accessories.any(
          (a) => a.tags.contains(V4AccessoryTag.entrave),
        ),
        ...context.flags,
      },
    );
  }
}
