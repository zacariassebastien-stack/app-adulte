import '../../core/json.dart';
import 'enums.dart';
import 'parameter.dart';
import 'requirements.dart';
import 'v3_rules.dart';

abstract base class ContentDefinition extends JsonModel {
  ContentDefinition(super.reader) {
    stableId;
    schemaVersion;
    contentVersion;
    localeKey;
  }
  String get stableId => reader.string('stable_id');
  int get schemaVersion =>
      reader.integer('schema_version', fallback: 1, min: 1, max: 1);
  int? get contentVersion => reader.optionalInteger('content_version', min: 1);
  String? get localeKey => reader.optionalString('locale_key');
}

final class TagDefinition extends ContentDefinition {
  TagDefinition.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'TagDefinition'));
  TagDefinition.read(super.reader) {
    namespace;
    titleKey;
    technicalOnly;
  }
  String get namespace => reader.string('namespace');
  String? get titleKey => reader.optionalString('title_key');
  bool get technicalOnly => reader.boolean('technical_only');
}

final class ProfileElementDefinition extends ContentDefinition {
  ProfileElementDefinition.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'ProfileElementDefinition'));
  ProfileElementDefinition.read(super.reader) {
    parentId;
    titleKey;
    descriptionKey;
    title;
    kind;
    directionality;
    searchableKeywords;
    childrenOrder;
    explicitAcceptanceRequired;
    enabled;
  }
  String? get parentId => reader.optionalString('parent_id');
  String? get titleKey => reader.optionalString('title_key');
  String? get descriptionKey => reader.optionalString('description_key');
  String? get title => reader.optionalString('title');
  ProfileKind get kind => reader.enumeration('kind', ProfileKind.values);
  ProfileDirectionality get directionality =>
      reader.enumeration('directionality', ProfileDirectionality.values);
  List<String> get searchableKeywords =>
      reader.strings('searchable_keywords', optional: true);
  List<String> get childrenOrder =>
      reader.strings('children_order', optional: true);
  bool get explicitAcceptanceRequired =>
      reader.boolean('explicit_acceptance_required');
  bool get enabled => reader.boolean('enabled');
}

abstract base class ActionDefinition extends ContentDefinition {
  ActionDefinition(super.reader) {
    enabled;
    title;
    titleKey;
    actionText;
    detailsText;
    illustrationKey;
    profileRequirements = reader.objects(
      'profile_requirements',
      ProfileRequirement.read,
      'ProfileRequirement',
    );
    technicalRequirements = reader.objects(
      'technical_requirements',
      TechnicalRequirement.read,
      'TechnicalRequirement',
    );
    parameters = reader.objects(
      'parameters',
      CardParameterDefinition.read,
      'CardParameterDefinition',
      optional: true,
    );
  }
  bool get enabled => reader.boolean('enabled');
  String? get title => reader.optionalString('title');
  String? get titleKey => reader.optionalString('title_key');
  String? get actionText => reader.optionalString('action_text');
  String? get detailsText => reader.optionalString('details_text');
  String? get illustrationKey => reader.optionalString('illustration_key');
  late final List<ProfileRequirement> profileRequirements;
  late final List<TechnicalRequirement> technicalRequirements;
  late final List<CardParameterDefinition> parameters;
  List<ParticipantRole> roles(String key) {
    final values = reader.strings(key, optional: true);
    return List.unmodifiable([
      for (var i = 0; i < values.length; i++)
        ParticipantRole.values.firstWhere(
          (r) => r.name == values[i],
          orElse: () => reader.fail(
            '$key[$i]',
            'Unknown participant role',
            code: 'unknown_enum',
          ),
        ),
    ]);
  }
}

final class CardDefinition extends ActionDefinition {
  CardDefinition.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'CardDefinition'));
  CardDefinition.read(super.reader) {
    reader.integer('content_version', min: 1);
    reader.string('title_key');
    precision;
    frequency;
    repeatability;
    baseTags;
    participants;
    inversionPolicy;
    descriptionKey;
    directionality;
    order;
    v3DeckEnabled;
    v3ReplacementCardId;
    v3ReplacementVariantId;
    v3ReplacementSessionField;
    v3;
    variants = reader.objects(
      'variants',
      CardVariantDefinition.read,
      'CardVariantDefinition',
    );
    if (variants.isEmpty) {
      reader.fail(
        'variants',
        'Card must have at least one variant',
        code: 'missing_variant',
      );
    }
  }
  Precision get precision => reader.enumeration('precision', Precision.values);
  EditorialFrequency get frequency =>
      reader.enumeration('frequency', EditorialFrequency.values);
  Repeatability get repeatability =>
      reader.enumeration('repeatability', Repeatability.values);
  List<String> get baseTags => reader.strings('base_tags');
  List<ParticipantRole> get participants => roles('participants');
  InversionPolicy get inversionPolicy =>
      reader.enumeration('inversion_policy', InversionPolicy.values);
  String? get descriptionKey => reader.optionalString('description_key');
  CardDirectionality? get directionality =>
      reader.json.containsKey('directionality')
      ? reader.enumeration('directionality', CardDirectionality.values)
      : null;
  int? get order => reader.optionalInteger('order', min: 0);
  bool get v3DeckEnabled => reader.boolean('v3_deck_enabled', fallback: true);
  String? get v3ReplacementCardId =>
      reader.optionalString('v3_replacement_card_id');
  String? get v3ReplacementVariantId =>
      reader.optionalString('v3_replacement_variant_id');
  String? get v3ReplacementSessionField =>
      reader.optionalString('v3_replacement_session_field');
  V3EditorialData? get v3 => reader.json['v3'] == null
      ? null
      : V3EditorialData.fromJson(reader.json['v3']! as JsonMap);
  late final List<CardVariantDefinition> variants;
}

final class CardVariantDefinition extends ActionDefinition {
  CardVariantDefinition.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'CardVariantDefinition'));
  CardVariantDefinition.read(super.reader) {
    cardId;
    instructionKey;
    chiliLevel;
    additionalTags;
    removedTags;
    participantOverrides;
    inversionOverride;
    v3DeckEnabled;
    v3ReplacementCardId;
    v3ReplacementVariantId;
    v3;
    stateEffects = reader.objects(
      'state_effects',
      StateEffect.read,
      'StateEffect',
    );
  }
  String? get cardId => reader.optionalString('card_id');
  String? get instructionKey => reader.optionalString('instruction_key');
  int get chiliLevel => reader.integer('chili_level', min: 1, max: 5);
  List<String> get additionalTags => reader.strings('additional_tags');
  List<String> get removedTags =>
      reader.strings('removed_tags', optional: true);
  List<ParticipantRole> get participantOverrides =>
      roles('participant_overrides');
  InversionPolicy? get inversionOverride =>
      reader.json['inversion_override'] == null
      ? null
      : reader.enumeration('inversion_override', InversionPolicy.values);
  bool get v3DeckEnabled => reader.boolean('v3_deck_enabled', fallback: true);
  String? get v3ReplacementCardId =>
      reader.optionalString('v3_replacement_card_id');
  String? get v3ReplacementVariantId =>
      reader.optionalString('v3_replacement_variant_id');
  V3EditorialData? get v3 => reader.json['v3'] == null
      ? null
      : V3EditorialData.fromJson(reader.json['v3']! as JsonMap);
  late final List<StateEffect> stateEffects;
}
