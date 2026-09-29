final class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.publishableKey});

  static const urlDefine = 'SUPABASE_URL';
  static const keyDefine = 'SUPABASE_PUBLISHABLE_KEY';

  final String url;
  final String publishableKey;

  bool get configured => url.isNotEmpty && publishableKey.isNotEmpty;

  factory SupabaseConfig.fromEnvironment() => const SupabaseConfig(
    url: String.fromEnvironment(urlDefine),
    publishableKey: String.fromEnvironment(keyDefine),
  );
}
