import 'dart:math';

final class JoinCode {
  static const length = 6;
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final RegExp _pattern = RegExp(r'^[A-HJ-NP-Z2-9]{6}$');

  static String normalize(String value) => value.trim().toUpperCase();
  static bool isValid(String value) => _pattern.hasMatch(normalize(value));
}

final class JoinCodeGenerator {
  JoinCodeGenerator({Random? random}) : _random = random ?? Random.secure();
  final Random _random;

  String generate() => String.fromCharCodes([
    for (var index = 0; index < JoinCode.length; index++)
      JoinCode.alphabet.codeUnitAt(_random.nextInt(JoinCode.alphabet.length)),
  ]);
}
