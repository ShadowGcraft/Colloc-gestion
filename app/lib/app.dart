import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'etat/services.dart';
import 'theme.dart';
import 'vues/porte_entree.dart';
import 'widgets/bandeau_reseau.dart';

class ColocApp extends StatelessWidget {
  const ColocApp({super.key, required this.services});

  final Services services;

  @override
  Widget build(BuildContext context) => ServicesScope(
    services: services,
    child: MaterialApp(
      title: "Colloc'",
      debugShowCheckedModeBanner: false,
      theme: construireTheme(Brightness.light),
      darkTheme: construireTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          BandeauReseau(reseau: services.reseau, child: child!),
      home: const PorteEntree(),
    ),
  );
}

/// Affichée si l'application est lancée sans env.json (ex. depuis l'IDE sans configuration).
class ConfigurationManquante extends StatelessWidget {
  const ConfigurationManquante({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: construireTheme(Brightness.light),
    darkTheme: construireTheme(Brightness.dark),
    home: const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            "Configuration Supabase absente.\n\nLancez l'application avec lancer.sh (macOS/Linux) "
            'ou lancer.bat (Windows), ou ajoutez --dart-define-from-file=../env.json.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
