import 'package:flutter/material.dart';

import 'game_history.dart';

class GameHistoryScreen extends StatelessWidget {
  const GameHistoryScreen({required this.store, super.key});
  final GameHistoryStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Historique des parties')),
    body: FutureBuilder<List<GameHistoryEntry>>(
      future: store.load(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const [];
        if (entries.isEmpty) {
          return const Center(child: Text('Aucune partie terminée.'));
        }
        return ListView.separated(
          key: const Key('game-history-list'),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final date = entry.endedAt.toLocal();
            return ListTile(
              title: Text(entry.title),
              subtitle: Text(
                entry.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '${date.day.toString().padLeft(2, '0')}/'
                '${date.month.toString().padLeft(2, '0')}/${date.year}',
              ),
            );
          },
        );
      },
    ),
  );
}
