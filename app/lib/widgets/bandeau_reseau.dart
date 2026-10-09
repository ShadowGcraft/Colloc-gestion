import 'package:flutter/material.dart';

import '../etat/reseau.dart';

/// Bandeau affiché en haut de l'application tant que le réseau est absent.
class BandeauReseau extends StatelessWidget {
  const BandeauReseau({super.key, required this.reseau, required this.child});

  final EtatReseau reseau;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: reseau,
    builder: (context, _) {
      if (reseau.enLigne) return child;
      final couleurs = Theme.of(context).colorScheme;

      // région « vivante » : annoncée par les lecteurs d'écran dès son apparition
      final bandeau = Semantics(
        container: true,
        liveRegion: true,
        child: Material(
          color: couleurs.errorContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_off,
                    size: 18,
                    color: couleurs.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Hors connexion : les données affichées peuvent ne pas être à jour. '
                      'Reconnexion automatique…',
                      style: TextStyle(color: couleurs.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // verticalDirection.up : le bandeau reste visuellement en haut, mais il est
      // dessiné APRÈS les pages. Sinon, une page modale (BlockSemantics) le
      // masquerait aux lecteurs d'écran.
      return Column(
        verticalDirection: VerticalDirection.up,
        children: [
          // le bandeau occupe déjà la zone de la barre d'état
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
          bandeau,
        ],
      );
    },
  );
}
