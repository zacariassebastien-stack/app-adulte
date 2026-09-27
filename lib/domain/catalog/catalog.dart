import '../../core/json.dart';
import 'definitions.dart';

/// Parsed data, not proof of referential validity. Use CatalogValidator before
/// passing it to a future engine. Source documents are preserved without loss.
final class Catalog {
  Catalog({
    required JsonMap cardsDocument,
    required JsonMap profilesDocument,
    required JsonMap tagsDocument,
  }) : cardsDocument = freezeJson(cardsDocument)! as JsonMap,
       profilesDocument = freezeJson(profilesDocument)! as JsonMap,
       tagsDocument = freezeJson(tagsDocument)! as JsonMap {
    final cr = JsonReader(this.cardsDocument, 'Catalog', ownerId: 'cards');
    final pr = JsonReader(
      this.profilesDocument,
      'Catalog',
      ownerId: 'profiles',
    );
    final tr = JsonReader(this.tagsDocument, 'Catalog', ownerId: 'tags');
    for (final r in [cr, pr, tr]) {
      r.integer('schema_version', min: 1, max: 1);
    }
    catalogVersion = cr.integer('catalog_version', min: 1);
    locale = cr.string('locale');
    localeVersion = cr.optionalInteger('locale_version', min: 1);
    profileVersion = pr.integer('profile_version', min: 1);
    cards = cr.objects('cards', CardDefinition.read, 'CardDefinition');
    profileElements = pr.objects(
      'elements',
      ProfileElementDefinition.read,
      'ProfileElementDefinition',
    );
    tags = tr.objects('tags', TagDefinition.read, 'TagDefinition');
  }
  final JsonMap cardsDocument;
  final JsonMap profilesDocument;
  final JsonMap tagsDocument;
  int get schemaVersion => 1;
  late final int catalogVersion;
  late final int profileVersion;
  late final int? localeVersion;
  late final String locale;
  late final List<CardDefinition> cards;
  late final List<ProfileElementDefinition> profileElements;
  late final List<TagDefinition> tags;
}
