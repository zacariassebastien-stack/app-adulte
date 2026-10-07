import '../../domain/catalog/v4_catalog.dart';
import '../../domain/profile/v4_profile.dart';

final class QuestionAxisKey {
  const QuestionAxisKey(this.questionId, this.axisId);
  final String questionId;
  final String axisId;

  String get storageKey => '$questionId|$axisId';
}

final class InitialQuestionnaireEngine {
  const InitialQuestionnaireEngine();

  V4Profile initialize({
    required String profileId,
    required ProfileQuestionnaire questionnaire,
    required Map<String, InitialQuestionResponse> responses,
  }) {
    final expected = <String>{
      for (final question in questionnaire.questions)
        for (final axis in question.axes)
          QuestionAxisKey(question.stableId, axis.axisId).storageKey,
    };
    if (!responses.keys.toSet().containsAll(expected) ||
        responses.keys.any((key) => !expected.contains(key))) {
      throw const FormatException(
        'Every questionnaire axis must be answered exactly once',
      );
    }

    final direct = <String, ProfilePreference>{};
    final merged = <String, List<InitialQuestionResponse>>{};
    for (final question in questionnaire.questions) {
      for (final axis in question.axes) {
        final response =
            responses[QuestionAxisKey(
              question.stableId,
              axis.axisId,
            ).storageKey]!;
        for (final write in axis.writes) {
          final key = ProfilePreferenceKey(
            tagId: write.tagId,
            role: write.role,
            zoneId: write.zoneId,
          );
          if (write.mergeStrategy == QuestionMergeStrategy.mostRestrictive) {
            merged.putIfAbsent(key.storageKey, () => []).add(response);
            continue;
          }
          if (direct.containsKey(key.storageKey)) {
            throw FormatException(
              'Undeclared write collision for ${key.storageKey}',
            );
          }
          direct[key.storageKey] = _preference(profileId, key, response);
        }
      }
    }
    for (final entry in merged.entries) {
      final pieces = entry.key.split('|');
      final key = ProfilePreferenceKey(
        tagId: pieces[0],
        role: ProfilePreferenceRole.values.byName(pieces[1]),
        zoneId: pieces.length == 3 ? pieces[2] : null,
      );
      final response = _mostRestrictive(entry.value);
      direct[key.storageKey] = _preference(profileId, key, response);
    }
    return V4Profile(profileId: profileId, preferences: direct);
  }

  ProfilePreference _preference(
    String profileId,
    ProfilePreferenceKey key,
    InitialQuestionResponse response,
  ) => ProfilePreference(
    profileId: profileId,
    key: key,
    pa: response.pa,
    excluded: response == InitialQuestionResponse.excluded,
    source: ProfilePreferenceSource.initialQuestionnaire,
  );

  InitialQuestionResponse _mostRestrictive(
    List<InitialQuestionResponse> values,
  ) {
    if (values.contains(InitialQuestionResponse.excluded)) {
      return InitialQuestionResponse.excluded;
    }
    return values.reduce((left, right) => left.pa! >= right.pa! ? left : right);
  }
}
