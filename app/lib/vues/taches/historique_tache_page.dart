import 'dart:async';

import 'package:flutter/material.dart';

import '../../donnees/depots.dart';
import '../../etat/modele_vue.dart';
import '../../etat/reseau.dart';
import '../../etat/services.dart';
import '../../modeles/vie_commune.dart';
import '../../outils/dates.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/etats.dart';

class HistoriqueModele extends ModeleVue {
  HistoriqueModele(this._depot, EtatReseau reseau, this.tacheId)
    : super(reseau);

  final TacheDepot _depot;
  final String tacheId;
  List<RealisationTache>? realisations;

  @override
  Future<void> charger() => suivreChargement(() async {
    realisations = await _depot.historique(tacheId);
  });
}

class HistoriqueTachePage extends StatefulWidget {
  const HistoriqueTachePage({super.key, required this.tache});

  final Tache tache;

  @override
  State<HistoriqueTachePage> createState() => _HistoriqueTachePageState();
}

class _HistoriqueTachePageState extends State<HistoriqueTachePage> {
  late final HistoriqueModele _modele;

  @override
  void initState() {
    super.initState();
    final services = context.services;
    _modele = HistoriqueModele(
      services.depots.taches,
      services.reseau,
      widget.tache.id,
    );
    unawaited(_modele.charger());
  }

  @override
  void dispose() {
    _modele.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.tache.titre)),
      body: ListenableBuilder(
        listenable: _modele,
        builder: (context, _) => VueListe(
          chargement: _modele.chargement,
          erreur: _modele.erreur,
          estVide: _modele.realisations?.isEmpty,
          reessayer: _modele.charger,
          vide: const EtatVide(
            icone: Icons.history,
            titre: 'Pas encore faite',
            explication: "L'historique se remplit à chaque « Fait ».",
          ),
          contenu: () => ListView(
            children: [
              for (final r in _modele.realisations!)
                ListTile(
                  leading: AvatarMembre(utilisateurId: r.faitPar),
                  title: Text('Faite par ${session.pseudo(r.faitPar)}'),
                  subtitle: Text(
                    '${formaterHorodatage(r.faitLe)} · prévue ${formaterDate(r.echeance).toLowerCase()}'
                    '${r.faitPar != r.responsablePrevu ? ' (tour de ${session.pseudo(r.responsablePrevu)})' : ''}',
                  ),
                  trailing: r.enRetard
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule, size: 16, color: theme.alerte),
                            const SizedBox(width: 4),
                            Text(
                              'En retard',
                              style: TextStyle(color: theme.alerte),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
