import 'dart:convert';
import '../../domain/domain.dart';
import 'catalog_validator.dart';

typedef CatalogTextReader = Future<String> Function(String path);

final class CatalogLoader {
  const CatalogLoader({this.validator = const CatalogValidator()});
  final CatalogValidator validator;

  /// Pure decoding is available to developer audit tools; it is not a validated
  /// catalogue. Production callers use load/loadJson, which always validate.
  Catalog decode({
    required String cardsJson,
    required String profilesJson,
    required String tagsJson,
  }) {
    JsonMap document(String text, String name) {
      try {
        final Object? value = jsonDecode(text);
        if (value is JsonMap) return value;
      } on FormatException catch (e) {
        throw CatalogException([
          CatalogIssue(
            code: 'invalid_json',
            objectType: 'Catalog',
            stableId: name,
            property: r'$',
            message: e.message,
          ),
        ]);
      }
      throw CatalogException([
        CatalogIssue(
          code: 'invalid_document',
          objectType: 'Catalog',
          stableId: name,
          property: r'$',
          message: 'Expected JSON object',
        ),
      ]);
    }

    return Catalog(
      cardsDocument: document(cardsJson, 'cards'),
      profilesDocument: document(profilesJson, 'profiles'),
      tagsDocument: document(tagsJson, 'tags'),
    );
  }

  Catalog loadJson({
    required String cardsJson,
    required String profilesJson,
    required String tagsJson,
  }) {
    final catalog = decode(
      cardsJson: cardsJson,
      profilesJson: profilesJson,
      tagsJson: tagsJson,
    );
    validator.validateOrThrow(catalog);
    return catalog;
  }

  Future<Catalog> load(
    CatalogTextReader read, {
    String basePath = 'assets/catalog/source',
  }) async {
    Future<String> readFile(String name) async {
      final path = '$basePath/$name';
      try {
        return await read(path);
      } on Exception catch (e) {
        throw CatalogException([
          CatalogIssue(
            code: 'read_failed',
            objectType: 'Catalog',
            stableId: name,
            property: path,
            message: e.toString(),
          ),
        ]);
      }
    }

    final sources = await Future.wait([
      readFile('cards.v4.fr.json'),
      readFile('profile_elements.v1.fr.json'),
      readFile('tags.v1.json'),
    ]);
    return loadJson(
      cardsJson: sources[0],
      profilesJson: sources[1],
      tagsJson: sources[2],
    );
  }

  /// Explicit access for migration/audit tests only. Production code must use
  /// [load], whose sole card source is V4.
  Future<Catalog> loadLegacyV3(
    CatalogTextReader read, {
    String basePath = 'assets/catalog',
  }) async {
    Future<String> readFile(String path) async => read('$basePath/$path');
    final sources = await Future.wait([
      readFile('legacy/cards.v2.fr.json'),
      readFile('source/profile_elements.v1.fr.json'),
      readFile('source/tags.v1.json'),
    ]);
    return loadJson(
      cardsJson: sources[0],
      profilesJson: sources[1],
      tagsJson: sources[2],
    );
  }
}
