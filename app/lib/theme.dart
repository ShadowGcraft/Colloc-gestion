import 'package:flutter/material.dart';

/// Thèmes clair et sombre générés à partir d'une seule couleur.
ThemeData construireTheme(Brightness luminosite) {
  final couleurs = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E7D6B),
    brightness: luminosite,
  );
  return ThemeData(
    colorScheme: couleurs,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
  );
}

/// Couleurs « argent » lisibles dans les deux thèmes.
extension CouleursColoc on ThemeData {
  Color get positif => brightness == Brightness.dark
      ? const Color(0xFF81C995)
      : const Color(0xFF1E7B34);
  Color get negatif => colorScheme.error;
  Color get alerte => brightness == Brightness.dark
      ? const Color(0xFFFFB74D)
      : const Color(0xFFB45309);
}
