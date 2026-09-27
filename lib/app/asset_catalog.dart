import 'package:flutter/services.dart';
import '../data/catalog_loader/catalog_loader.dart';
import '../domain/catalog/catalog.dart';

/// Flutter adapter; the domain and data loader remain usable in pure Dart.
Future<Catalog> loadAssetCatalog({AssetBundle? bundle}) => const CatalogLoader()
    .load((path) => (bundle ?? rootBundle).loadString(path));
