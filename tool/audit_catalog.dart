import 'dart:convert';
import 'dart:io';
import 'package:couple_cards/data/catalog_loader/catalog_loader.dart';
import 'package:couple_cards/data/catalog_loader/catalog_validator.dart';
import 'package:couple_cards/domain/domain.dart';

/// Exit 1 means invalid catalogue. No allow-list or warning-only validation.
void main(List<String> args) {
  final path = args.isEmpty ? 'assets/catalog/source' : args.first;
  try {
    final catalog = const CatalogLoader().decode(
      cardsJson: File('$path/cards.v2.fr.json').readAsStringSync(),
      profilesJson: File(
        '$path/profile_elements.v1.fr.json',
      ).readAsStringSync(),
      tagsJson: File('$path/tags.v1.json').readAsStringSync(),
    );
    final issues = const CatalogValidator().validate(catalog);
    final report = {
      'valid': issues.isEmpty,
      'cards': catalog.cards.length,
      'variants': catalog.cards.fold(0, (n, c) => n + c.variants.length),
      'profile_elements': catalog.profileElements.length,
      'tags': catalog.tags.length,
      'issues': issues.map((e) => e.toJson()).toList(),
    };
    final output = const JsonEncoder.withIndent('  ').convert(report);
    if (args.length > 1) File(args[1]).writeAsStringSync('$output\n');
    stdout.writeln(output);
    if (issues.isNotEmpty) exitCode = 1;
  } on CatalogException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('Catalogue inaccessible: ${e.path}');
    exitCode = 2;
  }
}
