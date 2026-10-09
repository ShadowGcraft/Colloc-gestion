import 'dart:async';

import 'package:flutter/foundation.dart';

import '../donnees/erreurs.dart';

/// Mode hors connexion « minimal » : dès qu'une requête échoue faute de réseau,
/// l'application passe hors ligne (bandeau affiché), puis sonde le serveur
/// régulièrement. Au retour du réseau, les écrans ouverts se rechargent.
class EtatReseau extends ChangeNotifier {
  EtatReseau({required Future<void> Function() sonde, this.intervalle = const Duration(seconds: 4)})
      : _sonde = sonde;

  final Future<void> Function() _sonde;
  final Duration intervalle;

  bool _enLigne = true;
  Timer? _minuterie;
  bool _detruit = false;

  bool get enLigne => _enLigne;

  /// À appeler avec toute erreur attrapée : ne fait rien si ce n'est pas un problème réseau.
  void signalerErreur(Object erreur) {
    if (estErreurReseau(erreur)) _passerHorsLigne();
  }

  /// Une requête vient de réussir : le réseau est donc là.
  void signalerSucces() {
    if (!_enLigne) _repasserEnLigne();
  }

  /// Vérifie tout de suite (ex. quand le temps réel signale une coupure).
  Future<void> verifier() async {
    try {
      await _sonde();
      signalerSucces();
    } catch (e) {
      signalerErreur(e);
    }
  }

  void _passerHorsLigne() {
    if (!_enLigne || _detruit) return;
    _enLigne = false;
    notifyListeners();
    _minuterie = Timer.periodic(intervalle, (_) => verifier());
  }

  void _repasserEnLigne() {
    _minuterie?.cancel();
    _minuterie = null;
    _enLigne = true;
    if (!_detruit) notifyListeners();
  }

  @override
  void dispose() {
    _detruit = true;
    _minuterie?.cancel();
    super.dispose();
  }
}
