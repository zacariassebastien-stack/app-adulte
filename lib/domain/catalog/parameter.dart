import '../../core/json.dart';
import 'enums.dart';

final class CardParameterDefinition extends JsonModel {
  CardParameterDefinition.fromJson(JsonMap json)
    : this.read(JsonReader(json, 'CardParameterDefinition'));
  CardParameterDefinition.read(super.reader) {
    reader.only({
      'stable_id',
      'type',
      'values',
      'range',
      'selection_by',
      'visibility',
      'consent_relevant',
      'state_relevant',
    });
    stableId;
    type;
    selectionBy;
    visibility;
    consentRelevant;
    stateRelevant;
    final hasValues = reader.json.containsKey('values');
    final hasRange = reader.json.containsKey('range');
    if (hasValues == hasRange) {
      reader.fail('values/range', 'Provide exactly one of values or range');
    }
    if (hasRange) {
      if (type != ParameterType.INTEGER) {
        reader.fail('range', 'Only INTEGER supports range');
      }
      final range = reader.child(
        reader.json['range'],
        'range',
        'CardParameterDefinition',
      );
      range.only({'min', 'max'});
      final min = range.integer('min');
      range.integer('max', min: min);
    } else {
      final values = reader.list('values');
      if (values.isEmpty) reader.fail('values', 'Values must not be empty');
      if (values.toSet().length != values.length) {
        reader.fail('values', 'Duplicate value');
      }
      for (var i = 0; i < values.length; i++) {
        final v = values[i];
        final valid = switch (type) {
          ParameterType.INTEGER => v is int,
          ParameterType.BOOLEAN => v is bool,
          ParameterType.ENUM ||
          ParameterType.DURATION_HINT => v is String && v.trim().isNotEmpty,
        };
        if (!valid) {
          reader.fail('values[$i]', 'Value does not match ${type.name}');
        }
      }
    }
  }
  String get stableId => reader.string('stable_id');
  ParameterType get type => reader.enumeration('type', ParameterType.values);
  SelectionBy get selectionBy =>
      reader.enumeration('selection_by', SelectionBy.values);
  ParameterVisibility get visibility =>
      reader.enumeration('visibility', ParameterVisibility.values);
  bool get consentRelevant => reader.boolean('consent_relevant');
  bool get stateRelevant => reader.boolean('state_relevant');
  List<Object?> get values => reader.list('values', optional: true);
  int? get minimum => reader.json.containsKey('range')
      ? reader
            .child(reader.json['range'], 'range', 'CardParameterDefinition')
            .integer('min')
      : null;
  int? get maximum => reader.json.containsKey('range')
      ? reader
            .child(reader.json['range'], 'range', 'CardParameterDefinition')
            .integer('max')
      : null;
}
