import 'package:flutter/foundation.dart';

/// Configuration injectée au lancement par `--dart-define-from-file=env.json`
/// (les lanceurs lancer.sh / lancer.bat s'en chargent). Aucune clé dans le code.
abstract final class Config {
  static const _url = String.fromEnvironment('SUPABASE_URL');

  /// Clé publique (« anon » ou « publishable ») : sans danger, c'est la RLS qui protège.
  /// La clé service_role ne doit JAMAIS se retrouver ici.
  static const clePublique = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get estComplete => _url.isNotEmpty && clePublique.isNotEmpty;

  /// Sur l'émulateur Android, 127.0.0.1 désigne l'émulateur lui-même :
  /// l'ordinateur hôte (Supabase local) est joignable via 10.0.2.2.
  static String get url {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return _url.replaceFirst(
        RegExp(r'//(127\.0\.0\.1|localhost)'),
        '//10.0.2.2',
      );
    }
    return _url;
  }
}
