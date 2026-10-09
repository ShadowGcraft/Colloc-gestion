import 'dart:async';

import 'package:flutter/material.dart';

import '../../donnees/depots.dart';
import '../../etat/modele_vue.dart';
import '../../etat/reseau.dart';
import '../../etat/services.dart';
import '../../modeles/argent.dart';
import '../../outils/dates.dart';
import '../../outils/montants.dart';
import '../../outils/simplification.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/etats.dart';

class SoldesModele extends ModeleVue {
  SoldesModele(this._depot, EtatReseau reseau, this.colocationId)
    : super(reseau);

  final DepenseDepot _depot;
  final String colocationId;

  List<Solde>? _soldes;
  List<Remboursement> _remboursements = const [];
  List<Virement> _virements = const [];

  /// Membres dont le solde n'est pas nul, plus les membres actifs à zéro
  List<Solde>? get soldes => _soldes;
  List<Remboursement> get remboursements => _remboursements;

  /// Minimum de virements pour que tout le monde soit quitte
  List<Virement> get virements => _virements;

  @override
  Future<void> charger() => suivreChargement(() async {
    final resultats = await Future.wait([
      _depot.soldes(colocationId),
      _depot.remboursements(colocationId),
    ]);
    final soldes = resultats[0] as List<Solde>;
    _remboursements = resultats[1] as List<Remboursement>;
    _soldes = soldes.where((s) => !s.aQuitte || s.centimes != 0).toList()
      ..sort((a, b) => b.centimes.compareTo(a.centimes));
    _virements = simplifierDettes({
      for (final s in soldes) s.utilisateurId: s.centimes,
    });
  });

  Future<String?> rembourser(Virement virement) => agir(() async {
    await _depot.rembourser(colocationId, virement);
    await charger();
  });

  Future<String?> annuler(Remboursement remboursement) => agir(() async {
    await _depot.annulerRemboursement(remboursement.id);
    await charger();
  });
}

class SoldesPage extends StatefulWidget {
  const SoldesPage({super.key, required this.colocationId});

  final String colocationId;

  @override
  State<SoldesPage> createState() => _SoldesPageState();
}

class _SoldesPageState extends State<SoldesPage> {
  late final SoldesModele _modele;

  @override
  void initState() {
    super.initState();
    final services = context.services;
    _modele = SoldesModele(
      services.depots.depenses,
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

  Future<void> _rembourser(Virement v) async {
    final session = context.services.session;
    final ok = await confirmer(
      context,
      titre: 'Remboursement effectué ?',
      message:
          '${session.pseudo(v.de)} a versé ${formaterEuros(v.montant)} à ${session.pseudo(v.vers)}.',
      action: 'Confirmer',
    );
    if (ok && mounted) await signalerResultat(context, _modele.rembourser(v));
  }

  Future<void> _annuler(Remboursement r) async {
    final ok = await confirmer(
      context,
      titre: 'Annuler ce remboursement ?',
      message: 'Les soldes reviendront comme avant ce remboursement.',
      action: 'Annuler le remboursement',
    );
    if (ok && mounted) await signalerResultat(context, _modele.annuler(r));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Soldes')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_modele, session]),
        builder: (context, _) => VueListe(
          chargement: _modele.chargement,
          erreur: _modele.erreur,
          estVide: _modele.soldes?.isEmpty,
          reessayer: _modele.charger,
          vide: const EtatVide(
            icone: Icons.group_outlined,
            titre: 'Aucun membre',
          ),
          contenu: () => RefreshIndicator(
            onRefresh: _modele.charger,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const _Titre('Soldes'),
                for (final s in _modele.soldes!)
                  ListTile(
                    leading: AvatarMembre(utilisateurId: s.utilisateurId),
                    title: Text(
                      session.pseudo(s.utilisateurId) +
                          (s.utilisateurId == session.moi ? ' (vous)' : ''),
                    ),
                    subtitle: Text(
                      s.aQuitte
                          ? 'A quitté la coloc'
                          : s.centimes > 0
                          ? 'On lui doit de l\'argent'
                          : s.centimes < 0
                          ? 'Doit de l\'argent'
                          : 'À l\'équilibre',
                    ),
                    trailing: Text(
                      formaterEuros(s.centimes, signe: true),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: s.centimes > 0
                            ? theme.positif
                            : (s.centimes < 0 ? theme.negatif : null),
                      ),
                    ),
                  ),
                const _Titre('Remboursements à faire'),
                if (_modele.virements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Tout est réglé : personne ne doit rien à personne.',
                    ),
                  ),
                for (final v in _modele.virements)
                  Card(
                    child: ListTile(
                      title: _DeVers(
                        session.pseudo(v.de),
                        session.pseudo(v.vers),
                      ),
                      subtitle: Text(
                        formaterEuros(v.montant),
                        style: theme.textTheme.titleMedium,
                      ),
                      // la base n'accepte que si je suis le débiteur ou le créancier
                      trailing: v.de == session.moi || v.vers == session.moi
                          ? FilledButton.tonal(
                              onPressed: () => _rembourser(v),
                              child: const Text('Remboursé'),
                            )
                          : null,
                    ),
                  ),
                if (_modele.virements.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      '${_modele.virements.length} virement${_modele.virements.length > 1 ? 's' : ''} '
                      'suffisent pour que tout le monde soit quitte.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (_modele.remboursements.isNotEmpty) ...[
                  const _Titre('Derniers remboursements'),
                  for (final r in _modele.remboursements)
                    ListTile(
                      leading: const Icon(Icons.swap_horiz),
                      title: _DeVers(
                        session.pseudo(r.debiteurId),
                        session.pseudo(r.crediteurId),
                      ),
                      subtitle: Text(formaterHorodatage(r.creeLe)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formaterEuros(r.montantCentimes),
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (r.creePar == session.moi || session.suisAdmin)
                            IconButton(
                              tooltip: 'Annuler',
                              icon: const Icon(Icons.undo),
                              onPressed: () => _annuler(r),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// « Dan → Bob » (flèche en icône : toujours affichable, quelle que soit la police)
class _DeVers extends StatelessWidget {
  const _DeVers(this.de, this.vers);

  final String de;
  final String vers;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: de),
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward,
              size: 16,
              semanticLabel: 'rembourse',
            ),
          ),
        ),
        TextSpan(text: vers),
      ],
    ),
  );
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(texte, style: Theme.of(context).textTheme.titleSmall),
  );
}
