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
import 'historique_tache_page.dart';
import 'nouvelle_tache_page.dart';

class TachesModele extends ModeleVue {
  TachesModele(this._depot, EtatReseau reseau, this.colocationId)
    : super(reseau) {
    _ecoute = _depot.ecouter(colocationId, (
      surEvenement: _surEvenement,
      surReconnexion: () => unawaited(charger()),
      surCoupure: () => unawaited(reseau.verifier()),
    ));
  }

  final TacheDepot _depot;
  final String colocationId;
  late final Ecoute _ecoute;

  List<Tache>? _taches;
  final _enCours = <String>{};

  List<Tache>? get taches => _taches;
  bool enCours(Tache t) => _enCours.contains(t.id);

  @override
  Future<void> charger() => suivreChargement(() async {
    _taches = await _depot.taches(colocationId);
  });

  void _surEvenement(Evenement<Tache> evenement) {
    final taches = _taches;
    if (taches == null) return;
    switch (evenement) {
      case Ajout(:final element) || Modification(:final element):
        _taches = [...taches.where((t) => t.id != element.id), element];
      case Suppression(:final id):
        _taches = taches.where((t) => t.id != id).toList();
    }
    _trier();
    notifyListeners();
  }

  void _trier() => _taches?.sort((a, b) {
    final parDate = a.prochaineEcheance.compareTo(b.prochaineEcheance);
    return parDate != 0 ? parDate : a.titre.compareTo(b.titre);
  });

  /// Renvoie (erreur, tâche mise à jour)
  Future<(String?, Tache?)> terminer(Tache tache) async {
    _enCours.add(tache.id);
    notifyListeners();
    Tache? suivante;
    final erreur = await agir(() async {
      suivante = await _depot.terminer(tache.id);
      _surEvenement(Modification(suivante!));
    });
    _enCours.remove(tache.id);
    notifyListeners();
    return (erreur, suivante);
  }

  Future<String?> supprimer(Tache tache) => agir(() async {
    await _depot.supprimer(tache.id);
    _surEvenement(Suppression(tache.id));
  });

  @override
  void dispose() {
    unawaited(_ecoute.fermer());
    super.dispose();
  }
}

class TachesOnglet extends StatefulWidget {
  const TachesOnglet({super.key, required this.colocationId});

  final String colocationId;

  @override
  State<TachesOnglet> createState() => _TachesOngletState();
}

class _TachesOngletState extends State<TachesOnglet> {
  late final TachesModele _modele;

  @override
  void initState() {
    super.initState();
    final services = context.services;
    _modele = TachesModele(
      services.depots.taches,
      services.reseau,
      widget.colocationId,
    );
    unawaited(_modele.charger());
  }

  @override
  void dispose() {
    _modele.dispose();
    super.dispose();
  }

  Future<void> _nouvelle() async {
    final creee = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NouvelleTachePage(colocationId: widget.colocationId),
      ),
    );
    // le temps réel l'ajoute déjà ; on recharge quand même au cas où il serait coupé
    if (creee == true) await _modele.charger();
  }

  Future<void> _terminer(Tache tache) async {
    final session = context.services.session;
    final (erreur, suivante) = await _modele.terminer(tache);
    if (!mounted) return;
    if (erreur != null) return afficherErreur(context, erreur);
    if (suivante != null) {
      afficherInfo(
        context,
        'Bravo ! Prochain tour : ${session.pseudo(suivante.responsableId)}, '
        '${formaterEcheance(suivante.prochaineEcheance)}.',
      );
    }
  }

  Future<void> _supprimer(Tache tache) async {
    final ok = await confirmer(
      context,
      titre: 'Supprimer « ${tache.titre} » ?',
      message: 'Son historique sera supprimé aussi.',
    );
    if (ok && mounted) {
      await signalerResultat(context, _modele.supprimer(tache));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nouvelle,
        icon: const Icon(Icons.add),
        label: const Text('Tâche'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_modele, session]),
        builder: (context, _) => VueListe(
          chargement: _modele.chargement,
          erreur: _modele.erreur,
          estVide: _modele.taches?.isEmpty,
          reessayer: _modele.charger,
          vide: EtatVide(
            icone: Icons.cleaning_services_outlined,
            titre: 'Aucune tâche ménagère',
            explication: 'Ajoutez les tâches récurrentes : chacun son tour, la rotation est automatique.',
            action: FilledButton.icon(
              onPressed: _nouvelle,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une tâche'),
            ),
          ),
          contenu: () => RefreshIndicator(
            onRefresh: _modele.charger,
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              children: [
                for (final tache in _modele.taches!)
                  _CarteTache(
                    tache: tache,
                    moi: session.moi!,
                    responsable: session.pseudo(tache.responsableId),
                    enCours: _modele.enCours(tache),
                    peutSupprimer:
                        tache.creePar == session.moi || session.suisAdmin,
                    terminer: () => _terminer(tache),
                    supprimer: () => _supprimer(tache),
                    historique: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => HistoriqueTachePage(tache: tache),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CarteTache extends StatelessWidget {
  const _CarteTache({
    required this.tache,
    required this.moi,
    required this.responsable,
    required this.enCours,
    required this.peutSupprimer,
    required this.terminer,
    required this.supprimer,
    required this.historique,
  });

  final Tache tache;
  final String moi;
  final String responsable;
  final bool enCours;
  final bool peutSupprimer;
  final VoidCallback terminer;
  final VoidCallback supprimer;
  final VoidCallback historique;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monTour = tache.responsableId == moi;
    final retard = aujourdhui().difference(tache.prochaineEcheance).inDays;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            AvatarMembre(utilisateurId: tache.responsableId),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tache.titre, style: theme.textTheme.titleMedium),
                  Text(
                    monTour ? "C'est votre tour !" : 'Au tour de $responsable',
                    style: monTour
                        ? TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (tache.enRetard)
                        // le retard n'est jamais signalé par la couleur seule : icône + texte
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: theme.alerte,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'En retard de $retard jour${retard > 1 ? 's' : ''}',
                                style: TextStyle(
                                  color: theme.alerte,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'Pour ${formaterEcheance(tache.prochaineEcheance)}',
                        ),
                      Text(
                        '· ${tache.frequence.libelle}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (enCours)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              )
            else
              FilledButton.tonal(
                onPressed: terminer,
                child: const Text('Fait'),
              ),
            PopupMenuButton<VoidCallback>(
              tooltip: 'Plus',
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: historique,
                  child: const Text('Historique'),
                ),
                if (peutSupprimer)
                  PopupMenuItem(
                    value: supprimer,
                    child: const Text('Supprimer'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
