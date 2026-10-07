import 'dart:convert';

import '../../core/json.dart';
import '../profile/v4_profile.dart';

enum InitialQuestionResponse { love, like, unsure, excluded }

extension InitialQuestionResponseValue on InitialQuestionResponse {
  double? get pa => switch (this) {
    InitialQuestionResponse.love => 5,
    InitialQuestionResponse.like => 12,
    InitialQuestionResponse.unsure => 20,
    InitialQuestionResponse.excluded => null,
  };
}

enum QuestionMergeStrategy { mostRestrictive }

final class ProfileQuestionWrite {
  const ProfileQuestionWrite({
    required this.tagId,
    required this.role,
    required this.weight,
    this.zoneId,
    this.mergeStrategy,
  });

  factory ProfileQuestionWrite.fromJson(
    JsonMap json,
    ProfilePreferenceRole axisRole,
  ) => ProfileQuestionWrite(
    tagId: json['tag_id']! as String,
    role: json['target_role'] == null
        ? axisRole
        : ProfilePreferenceRole.parse(json['target_role']! as String),
    zoneId: json['zone_id'] as String?,
    weight: (json['weight']! as num).toDouble(),
    mergeStrategy: switch (json['merge_strategy']) {
      null => null,
      'MOST_RESTRICTIVE' => QuestionMergeStrategy.mostRestrictive,
      final value => throw FormatException('Unknown merge strategy: $value'),
    },
  );

  final String tagId;
  final ProfilePreferenceRole role;
  final String? zoneId;
  final double weight;
  final QuestionMergeStrategy? mergeStrategy;
}

final class ProfileQuestionAxis {
  ProfileQuestionAxis({
    required this.axisId,
    required this.role,
    required this.label,
    required List<ProfileQuestionWrite> writes,
  }) : writes = List.unmodifiable(writes);

  factory ProfileQuestionAxis.fromJson(JsonMap json) {
    final role = ProfilePreferenceRole.parse(json['role']! as String);
    return ProfileQuestionAxis(
      axisId: json['axis_id']! as String,
      role: role,
      label: json['label'] as String?,
      writes: [
        for (final value in json['writes']! as List)
          ProfileQuestionWrite.fromJson(value as JsonMap, role),
      ],
    );
  }

  final String axisId;
  final ProfilePreferenceRole role;
  final String? label;
  final List<ProfileQuestionWrite> writes;
}

final class ProfileQuestion {
  ProfileQuestion({
    required this.stableId,
    required this.order,
    required this.label,
    required this.helpText,
    required List<ProfileQuestionAxis> axes,
  }) : axes = List.unmodifiable(axes);

  factory ProfileQuestion.fromJson(JsonMap json) => ProfileQuestion(
    stableId: json['stable_id']! as String,
    order: json['order']! as int,
    label: json['label']! as String,
    helpText: json['help_text'] as String?,
    axes: [
      for (final value in json['axes']! as List)
        ProfileQuestionAxis.fromJson(value as JsonMap),
    ],
  );

  final String stableId;
  final int order;
  final String label;
  final String? helpText;
  final List<ProfileQuestionAxis> axes;
}

final class ProfileQuestionnaire {
  ProfileQuestionnaire({
    required this.version,
    required List<ProfileQuestion> questions,
  }) : questions = List.unmodifiable(questions) {
    if (questions.map((item) => item.stableId).toSet().length !=
        questions.length) {
      throw const FormatException('Question stable IDs must be unique');
    }
  }

  factory ProfileQuestionnaire.decode(String source) {
    final json = jsonDecode(source) as JsonMap;
    return ProfileQuestionnaire(
      version: json['questionnaire_version']! as int,
      questions: [
        for (final value in json['questions']! as List)
          ProfileQuestion.fromJson(value as JsonMap),
      ]..sort((a, b) => a.order.compareTo(b.order)),
    );
  }

  final int version;
  final List<ProfileQuestion> questions;
}

final class V4VariantRatingDefinition {
  V4VariantRatingDefinition({
    required this.variantId,
    required this.stage,
    required this.scope,
    required List<String> primaryPreferenceTags,
    required List<String> secondaryPreferenceTags,
    required List<String> nonPreferenceData,
  }) : primaryPreferenceTags = List.unmodifiable(primaryPreferenceTags),
       secondaryPreferenceTags = List.unmodifiable(secondaryPreferenceTags),
       nonPreferenceData = List.unmodifiable(nonPreferenceData) {
    if (primaryPreferenceTags.isEmpty) {
      throw FormatException('$variantId has no primary preference tag');
    }
    if (primaryPreferenceTags
        .toSet()
        .intersection(secondaryPreferenceTags.toSet())
        .isNotEmpty) {
      throw FormatException('$variantId classifies a tag twice');
    }
  }

  factory V4VariantRatingDefinition.fromJson(JsonMap json) =>
      V4VariantRatingDefinition(
        variantId: json['variant_id']! as String,
        stage: json['stage'] as int?,
        scope: json['scope']! as String,
        primaryPreferenceTags: (json['primary_preference_tags']! as List)
            .cast<String>(),
        secondaryPreferenceTags: (json['secondary_preference_tags']! as List)
            .cast<String>(),
        nonPreferenceData: (json['non_preference_data']! as List)
            .cast<String>(),
      );

  final String variantId;
  final int? stage;
  final String scope;
  final List<String> primaryPreferenceTags;
  final List<String> secondaryPreferenceTags;
  final List<String> nonPreferenceData;
}

final class V4CardRatingDefinition {
  V4CardRatingDefinition({
    required this.cardId,
    required this.number,
    required List<V4VariantRatingDefinition> variants,
  }) : variants = List.unmodifiable(variants);

  factory V4CardRatingDefinition.fromJson(JsonMap json) =>
      V4CardRatingDefinition(
        cardId: json['card_id']! as String,
        number: json['number']! as String,
        variants: [
          for (final value in json['variants']! as List)
            V4VariantRatingDefinition.fromJson(value as JsonMap),
        ],
      );

  final String cardId;
  final String number;
  final List<V4VariantRatingDefinition> variants;
}

final class V4ScoringCatalog {
  V4ScoringCatalog({required List<V4CardRatingDefinition> cards})
    : cards = List.unmodifiable(cards) {
    if (cards.length != 65) throw const FormatException('V4 requires 65 cards');
    final numbers = cards.map((item) => item.number).toList();
    final expected = [
      for (var value = 1; value <= 65; value++)
        value.toString().padLeft(3, '0'),
    ];
    if (numbers.join(',') != expected.join(',')) {
      throw const FormatException('V4 card numbers must be exactly 001..065');
    }
  }

  factory V4ScoringCatalog.decode(String source) {
    final json = jsonDecode(source) as JsonMap;
    if (json['catalog_version'] != 4) {
      throw const FormatException('Expected catalog version 4');
    }
    return V4ScoringCatalog(
      cards: [
        for (final value in json['cards']! as List)
          V4CardRatingDefinition.fromJson(value as JsonMap),
      ],
    );
  }

  final List<V4CardRatingDefinition> cards;
}
