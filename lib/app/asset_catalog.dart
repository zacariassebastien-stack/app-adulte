import 'package:flutter/services.dart';
import '../data/catalog_loader/catalog_loader.dart';
import '../domain/domain.dart';

/// Flutter adapter; the domain and data loader remain usable in pure Dart.
Future<Catalog> loadAssetCatalog({
  AssetBundle? bundle,
  String assetPrefix = '',
}) => const CatalogLoader().load(
  (path) => (bundle ?? rootBundle).loadString('$assetPrefix$path'),
);

Future<RoleplayScenarioLibrary> loadAssetRoleplayScenarios({
  AssetBundle? bundle,
  String assetPrefix = '',
}) async => RoleplayScenarioLibrary.decode(
  await (bundle ?? rootBundle).loadString(
    '${assetPrefix}assets/catalog/source/roleplay_scenarios.v1.fr.json',
  ),
);

Future<V3CatalogView> loadAssetV3Catalog({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  final values = await Future.wait([
    loadAssetCatalog(bundle: assets),
    assets.loadString('assets/catalog/source/catalog_v4_taxonomy.json'),
    loadAssetRoleplayScenarios(bundle: assets),
  ]);
  return V3CatalogView(
    catalog: values[0] as Catalog,
    taxonomy: V3Taxonomy.decode(values[1] as String),
    roleplayScenarios: values[2] as RoleplayScenarioLibrary,
  );
}

Future<ProfileQuestionnaire> loadAssetProfileQuestionnaire({
  AssetBundle? bundle,
}) async => ProfileQuestionnaire.decode(
  await (bundle ?? rootBundle).loadString(
    'assets/catalog/source/profile_questions.v1.fr.json',
  ),
);

Future<V4ScoringCatalog> loadAssetV4ScoringCatalog({
  AssetBundle? bundle,
}) async => V4ScoringCatalog.decode(
  await (bundle ?? rootBundle).loadString(
    'assets/catalog/source/catalog_v4_scoring.json',
  ),
);
