import 'dart:async';

import 'package:flutter/material.dart';

import '../../donnees/depots.dart';
import '../../etat/modele_vue.dart';
import '../../etat/reseau.dart';
import '../../etat/services.dart';
import '../../modeles/argent.dart';
import '../../outils/dates.dart';
import '../../outils/montants.dart';
import '../../widgets/avatar.dart';
import '../../widgets/etats.dart';
import 'detail_depense_page.dart';
import 'nouvelle_depense_page.dart';
import 'soldes_page.dart';

class DepensesModele extends ModeleVue {
  DepensesModele(this._depot, EtatReseau reseau, this.colocationId)
    : super(reseau);

  static const taillePage = 30;

  final DepenseDepot _depot;
  final String colocationId;

  List<Depense>? _depenses;
  bool _toutCharge = false;
  bool _chargementSuite = false;

  List<Depense>? get depenses => _depenses;
  bool get toutCharge => _toutCharge;
  bool get chargementSuite => _chargementSuite;

  @override
  Future<void> charger() => suivreChargement(() async {
    final page = await _depot.depenses(colocationId, taille: taillePage);
    _depenses = page;
    _toutCharge = page.length < taillePage;
  });

  /// Pagination : charge les dépenses plus anciennes
  Future<String?> chargerSuite() async {
    if (_chargementSuite || _toutCharge) return null;
    _chargementSuite = true;
    notifyListeners();
    final erreur = await agir(() async {
      final page = await _depot.depenses(
        colocationId,
        debut: _depenses!.length,
        taille: taillePage,
      );
      _depenses = [..._depenses!, ...page];
      _toutCharge = page.length < taillePage;
    });
    _chargementSuite = false;
    notifyListeners();
    return erreur;
  }
}

class DepensesOnglet extends StatefulWidget {
  const DepensesOnglet({super.key, required this.colocationId});

  final String colocationId;

  @override
  State<DepensesOnglet> createState() => _DepensesOngletState();
}

class _DepensesOngletState extends State<DepensesOnglet> {
  late final DepensesModele _modele;

  @override
  void initState() {
    super.initState();
    final services = context.services;
    _modele = DepensesModele(
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

  Future<void> _nouvelle() async {
    final services = context.services;
    final session = services.session;
    final creee = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NouvelleDepensePage(
          depot: services.depots.depenses,
          reseau: services.reseau,
          colocationId: widget.colocationId,
          membres: session.membresActifs,
          moi: session.moi!,
        ),
      ),
    );
    if (creee == true) {
      await _modele.charger();
      if (mounted) afficherInfo(context, 'Dépense enregistrée');
    }
  }

  Future<void> _ouvrir(Depense depense) async {
    final supprimee = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DetailDepensePage(depense: depense)),
    );
    if (supprimee == true) await _modele.charger();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nouvelle,
        icon: const Icon(Icons.add),
        label: const Text('Dépense'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_modele, session]),
        builder: (context, _) => VueListe(
          chargement: _modele.chargement,
          erreur: _modele.erreur,
          estVide: _modele.depenses?.isEmpty,
          reessayer: _modele.charger,
          vide: EtatVide(
            icone: Icons.receipt_long_outlined,
            titre: 'Aucune dépense pour le moment',
            explication: 'Ajoutez la première : courses, loyer, factures…\nLes soldes se calculent tout seuls.',
            action: FilledButton.icon(
              onPressed: _nouvelle,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une dépense'),
            ),
          ),
          contenu: () {
            final depenses = _modele.depenses!;
            return RefreshIndicator(
              onRefresh: _modele.charger,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: depenses.length + 2,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _CarteSoldes(colocationId: widget.colocationId);
                  }
                  if (i == depenses.length + 1) return _Suite(modele: _modele);
                  final d = depenses[i - 1];
                  return ListTile(
                    leading: AvatarMembre(utilisateurId: d.payeurId),
                    title: Text(
                      d.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${session.pseudo(d.payeurId)} · ${formaterDate(d.date)} · '
                      '${d.parts.length} participant${d.parts.length > 1 ? 's' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (d.ticketChemin != null) ...[
                          const Icon(
                            Icons.receipt_outlined,
                            size: 18,
                            semanticLabel: 'Ticket joint',
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          formaterEuros(d.montantCentimes),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    onTap: () => _ouvrir(d),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CarteSoldes extends StatelessWidget {
  const _CarteSoldes({required this.colocationId});

  final String colocationId;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.account_balance_wallet_outlined),
      title: const Text('Soldes et remboursements'),
      subtitle: const Text('Qui doit combien à qui'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SoldesPage(colocationId: colocationId),
        ),
      ),
    ),
  );
}

class _Suite extends StatelessWidget {
  const _Suite({required this.modele});

  final DepensesModele modele;

  @override
  Widget build(BuildContext context) {
    if (modele.toutCharge) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: modele.chargementSuite
            ? const CircularProgressIndicator()
            : TextButton.icon(
                onPressed: () =>
                    signalerResultat(context, modele.chargerSuite()),
                icon: const Icon(Icons.expand_more),
                label: const Text('Dépenses plus anciennes'),
              ),
      ),
    );
  }
}
