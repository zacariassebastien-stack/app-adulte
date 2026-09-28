import 'dart:convert';

import '../local/app_database.dart';

final class LocalCatalogDocument {
  const LocalCatalogDocument({
    required this.documentId,
    required this.schemaVersion,
    required this.catalogVersion,
    required this.document,
    required this.installedAt,
  });
  final String documentId;
  final int schemaVersion;
  final String catalogVersion;
  final Map<String, Object?> document;
  final DateTime installedAt;
}

final class CatalogRepository {
  CatalogRepository(this.database);
  final AppDatabase database;

  Future<void> installAll(List<LocalCatalogDocument> documents) async {
    await database.transaction(() async {
      for (final document in documents) {
        await database
            .into(database.catalogDocuments)
            .insertOnConflictUpdate(
              CatalogDocumentsCompanion.insert(
                documentId: document.documentId,
                schemaVersion: document.schemaVersion,
                catalogVersion: document.catalogVersion,
                json: jsonEncode(document.document),
                installedAt: document.installedAt,
              ),
            );
      }
    });
  }

  Future<LocalCatalogDocument?> load(String id) async {
    final query = database.select(database.catalogDocuments)
      ..where((d) => d.documentId.equals(id));
    final row = await query.getSingleOrNull();
    return row == null
        ? null
        : LocalCatalogDocument(
            documentId: row.documentId,
            schemaVersion: row.schemaVersion,
            catalogVersion: row.catalogVersion,
            document: (jsonDecode(row.json) as Map).cast<String, Object?>(),
            installedAt: row.installedAt,
          );
  }
}
