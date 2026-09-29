import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/bootstrap.dart';
import 'data/remote/supabase_config.dart';
import 'data/remote/supabase_lobby_repository.dart';
import 'features/lobby/lobby_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseConfig.fromEnvironment();
  runApp(
    CoupleCardsBootstrap(
      initializeRepository: () => _initializeRepository(config),
    ),
  );
}

Future<LobbyRepository> _initializeRepository(SupabaseConfig config) async {
  if (!config.configured) return const UnavailableLobbyRepository();
  await Supabase.initialize(
    url: config.url,
    publishableKey: config.publishableKey,
  );
  return SupabaseLobbyRepository(client: Supabase.instance.client);
}
