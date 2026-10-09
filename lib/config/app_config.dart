class AppConfig {
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.2.0',
  );
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://aqfsrolvaewcpkdkttiz.supabase.co',
  );
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_zQjtjtIkiJuxXeXOFe468Q_fe68wSbI',
  );
}
