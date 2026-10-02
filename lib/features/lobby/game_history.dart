import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class GameHistoryEntry {
  const GameHistoryEntry({
    required this.endedAt,
    required this.title,
    required this.description,
  });

  final DateTime endedAt;
  final String title, description;

  Map<String, Object?> toJson() => {
    'ended_at': endedAt.toUtc().toIso8601String(),
    'title': title,
    'description': description,
  };

  factory GameHistoryEntry.fromJson(Map<String, Object?> json) =>
      GameHistoryEntry(
        endedAt: DateTime.parse(json['ended_at']! as String),
        title: json['title']! as String,
        description: json['description']! as String,
      );

  factory GameHistoryEntry.forRounds(int rounds, {DateTime? endedAt}) {
    final (title, description) = switch (rounds) {
      >= 8 => ('ENDURANT', 'garde le rythme et va au bout de ses choix'),
      >= 5 => ('STRATÈGE', 'prend son temps et choisit le bon moment'),
      _ => ('EXPLORATEUR', 'avance avec curiosité et varie ses approches'),
    };
    return GameHistoryEntry(
      endedAt: endedAt ?? DateTime.now(),
      title: title,
      description: description,
    );
  }
}

abstract interface class GameHistoryStore {
  Future<List<GameHistoryEntry>> load();
  Future<void> add(GameHistoryEntry entry);
}

final class SharedPreferencesGameHistoryStore implements GameHistoryStore {
  const SharedPreferencesGameHistoryStore();
  static const _key = 'game_history_v1';

  @override
  Future<List<GameHistoryEntry>> load() async {
    final encoded = (await SharedPreferences.getInstance()).getString(_key);
    if (encoded == null) return const [];
    final entries = [
      for (final raw in jsonDecode(encoded) as List)
        GameHistoryEntry.fromJson(Map<String, Object?>.from(raw as Map)),
    ]..sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return entries.take(10).toList(growable: false);
  }

  @override
  Future<void> add(GameHistoryEntry entry) async {
    final entries = [entry, ...await load()]
      ..sort((a, b) => b.endedAt.compareTo(a.endedAt));
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode([for (final item in entries.take(10)) item.toJson()]),
    );
  }
}

final class MemoryGameHistoryStore implements GameHistoryStore {
  final List<GameHistoryEntry> entries = [];
  @override
  Future<List<GameHistoryEntry>> load() async => List.unmodifiable(entries);
  @override
  Future<void> add(GameHistoryEntry entry) async {
    entries.add(entry);
    entries.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    if (entries.length > 10) entries.removeRange(10, entries.length);
  }
}
