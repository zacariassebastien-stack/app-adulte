import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'data/remote/supabase_config.dart';
import 'data/remote/supabase_lobby_repository.dart';
import 'features/lobby/lobby_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseConfig.fromEnvironment();
  LobbyRepository repository = const UnavailableLobbyRepository();
  if (config.configured) {
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
    );
    repository = SupabaseLobbyRepository(client: Supabase.instance.client);
  }
  runApp(CoupleCardsApp(lobbyRepository: repository));
}
