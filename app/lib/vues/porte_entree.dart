import 'dart:async';

import 'package:flutter/material.dart';

import '../etat/services.dart';
import '../widgets/etats.dart';
import 'accueil/accueil_page.dart';
import 'auth/connexion_page.dart';
import 'colocs/mes_colocs_page.dart';

/// Redirection automatique selon l'état de connexion :
/// pas de session → Connexion ; pas de coloc → Mes colocations ; sinon → Accueil.
class PorteEntree extends StatefulWidget {
  const PorteEntree({super.key});

  @override
  State<PorteEntree> createState() => _PorteEntreeState();
}

class _PorteEntreeState extends State<PorteEntree> {
  late final Services _services;
  StreamSubscription<bool>? _abonnement;
  late bool _connecte;

  @override
  void initState() {
    super.initState();
    _services = context.services;
    _connecte = _services.depots.auth.utilisateurId != null;
    if (_connecte) unawaited(_services.session.charger());

    _abonnement = _services.depots.auth.changements.listen(
      (connecte) {
        if (connecte == _connecte) return;
        setState(() => _connecte = connecte);
        if (connecte) {
          unawaited(_services.session.charger());
        } else {
          _services.session.vider();
        }
      },
      // ex. rafraîchissement du jeton impossible hors connexion
      onError: (Object e) => _services.reseau.signalerErreur(e),
    );
  }

  @override
  void dispose() {
    unawaited(_abonnement?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_connecte) return ConnexionPage(auth: _services.depots.auth);

    final session = _services.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.estCharge) {
          return Scaffold(
            body: session.erreur != null
                ? EtatErreur(
                    message: session.erreur!,
                    reessayer: session.charger,
                  )
                : const Chargement(message: 'Chargement de vos colocations…'),
          );
        }
        final courante = session.courante;
        if (courante == null) return const MesColocsPage(racine: true);
        // la clé recrée tout l'accueil (et ses abonnements) quand on change de coloc
        return AccueilPage(key: ValueKey(courante.id));
      },
    );
  }
}
