import '../../core/json.dart';
import '../catalog/enums.dart';

/// A committed private value; inversion cannot mutate this snapshot.
final class CombatValueSnapshot extends JsonModel {
  CombatValueSnapshot.fromJson(JsonMap json)
    : super(
        JsonReader(
          json,
          'CombatValueSnapshot',
          ownerId: json['card_id'] is String
              ? json['card_id']! as String
              : '<missing>',
        ),
      ) {
    playerId;
    cardId;
    variantId;
    roleAtCommit;
    personalValue;
    committedAt;
  }
  String get playerId => reader.string('player_id');
  String get cardId => reader.string('card_id');
  String get variantId => reader.string('variant_id');
  ProfileRole get roleAtCommit =>
      reader.enumeration('role_at_commit', ProfileRole.values);
  int get personalValue => reader.integer('personal_value', min: 1, max: 20);
  DateTime get committedAt => reader.dateTime('committed_at');
}
