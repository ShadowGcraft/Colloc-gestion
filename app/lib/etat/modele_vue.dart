import 'dart:async';

import 'package:flutter/foundation.dart';

import '../donnees/erreurs.dart';
import 'reseau.dart';

/// Base des ViewModels d'écran : chargement, erreur, rechargement automatique
/// au retour du réseau, et protection contre les notifications après dispose().
abstract class ModeleVue extends ChangeNotifier {
  ModeleVue(this.reseau) : _etaitEnLigne = reseau.enLigne {
    reseau.addListener(_surChangementReseau);
  }

  final EtatReseau reseau;

  bool _chargement = false;
  String? _erreur;
  bool _detruit = false;
  bool _etaitEnLigne;

  /// Vrai pendant le premier chargement ou un rechargement
  bool get chargement => _chargement;

  /// Erreur du dernier chargement (null si tout va bien)
  String? get erreur => _erreur;

  bool get detruit => _detruit;

  /// Charge (ou recharge) les données de l'écran.
  Future<void> charger();

  /// Enveloppe un chargement : gère l'indicateur, l'erreur et l'état du réseau.
  @protected
  Future<void> suivreChargement(Future<void> Function() travail) async {
    _chargement = true;
    _erreur = null;
    notifyListeners();
    try {
      await travail();
      reseau.signalerSucces();
    } catch (e) {
      _erreur = messageErreur(e);
      reseau.signalerErreur(e);
    } finally {
      _chargement = false;
      notifyListeners();
    }
  }

  /// Exécute une action utilisateur. Renvoie un message d'erreur, ou null si tout s'est bien passé
  /// (l'écran affiche alors le message dans un SnackBar).
  @protected
  Future<String?> agir(Future<void> Function() action) async {
    try {
      await action();
      reseau.signalerSucces();
      return null;
    } catch (e) {
      reseau.signalerErreur(e);
      return messageErreur(e);
    } finally {
      notifyListeners();
    }
  }

  void _surChangementReseau() {
    final revenu = reseau.enLigne && !_etaitEnLigne;
    _etaitEnLigne = reseau.enLigne;
    if (revenu && !_detruit) unawaited(charger());
  }

  @override
  void notifyListeners() {
    if (!_detruit) super.notifyListeners();
  }

  @override
  void dispose() {
    _detruit = true;
    reseau.removeListener(_surChangementReseau);
    super.dispose();
  }
}
