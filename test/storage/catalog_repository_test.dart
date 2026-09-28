import 'package:couple_cards/data/local/app_database.dart';
import 'package:couple_cards/data/repositories/catalog_repository.dart';
import 'package:test/test.dart';

void main() {
  test('catalogue documents are installed atomically and versioned', () async {
    final database = AppDatabase.memory();
    final repository = CatalogRepository(database);
    final now = DateTime.utc(2026, 9, 28, 11);
    await repository.installAll([
      LocalCatalogDocument(
        documentId: 'cards',
        schemaVersion: 2,
        catalogVersion: '2.0.0',
        document: const {'cards': <Object?>[]},
        installedAt: now,
      ),
      LocalCatalogDocument(
        documentId: 'profiles',
        schemaVersion: 1,
        catalogVersion: '2.0.0',
        document: const {'profile_elements': <Object?>[]},
        installedAt: now,
      ),
    ]);
    final saved = (await repository.load('cards'))!;
    expect(saved.schemaVersion, 2);
    expect(saved.catalogVersion, '2.0.0');
    expect(saved.document, const {'cards': <Object?>[]});
    await database.close();
  });
}
