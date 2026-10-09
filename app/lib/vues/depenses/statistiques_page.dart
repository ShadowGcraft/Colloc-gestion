import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../donnees/depots.dart';
import '../../etat/modele_vue.dart';
import '../../etat/reseau.dart';
import '../../etat/services.dart';
import '../../modeles/argent.dart';
import '../../outils/dates.dart';
import '../../outils/montants.dart';
import '../../widgets/etats.dart';

/// Fonctionnalité bonus : statistiques des dépenses en graphiques, dessinés avec
/// de simples widgets (aucune bibliothèque de graphiques).
class StatistiquesModele extends ModeleVue {
  StatistiquesModele(this._depot, EtatReseau reseau, this.colocationId)
    : super(reseau);

  static const nombreMois = 6;

  final DepenseDepot _depot;
  final String colocationId;

  List<Depense>? _depenses;

  List<Depense>? get depenses => _depenses;

  int get total => _depenses!.fold(0, (s, d) => s + d.montantCentimes);

  /// Total par mois sur les [nombreMois] derniers mois, du plus ancien au plus récent
  List<(DateTime, int)> get parMois {
    final maintenant = DateTime.now();
    final mois = [
      for (var i = nombreMois - 1; i >= 0; i--)
        DateTime(maintenant.year, maintenant.month - i),
    ];
    return [
      for (final m in mois)
        (
          m,
          _depenses!
              .where((d) => d.date.year == m.year && d.date.month == m.month)
              .fold(0, (s, d) => s + d.montantCentimes),
        ),
    ];
  }

  /// Total avancé par chaque payeur, du plus grand au plus petit
  List<(String, int)> get parPayeur {
    final totaux = <String, int>{};
    for (final d in _depenses!) {
      totaux[d.payeurId] = (totaux[d.payeurId] ?? 0) + d.montantCentimes;
    }
    return totaux.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  @override
  Future<void> charger() => suivreChargement(() async {
    _depenses = await _depot.resumePourStatistiques(colocationId);
  });
}

class StatistiquesPage extends StatefulWidget {
  const StatistiquesPage({super.key, required this.colocationId});

  final String colocationId;

  @override
  State<StatistiquesPage> createState() => _StatistiquesPageState();
}

class _StatistiquesPageState extends State<StatistiquesPage> {
  late final StatistiquesModele _modele;

  @override
  void initState() {
    super.initState();
    final services = context.services;
    _modele = StatistiquesModele(
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

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: ListenableBuilder(
        listenable: _modele,
        builder: (context, _) => VueListe(
          chargement: _modele.chargement,
          erreur: _modele.erreur,
          estVide: _modele.depenses?.isEmpty,
          reessayer: _modele.charger,
          vide: const EtatVide(
            icone: Icons.bar_chart,
            titre: 'Pas encore de statistiques',
            explication: 'Elles apparaîtront après les premières dépenses.',
          ),
          contenu: () {
            final depenses = _modele.depenses!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Chiffre(
                        libelle: 'Total dépensé',
                        valeur: formaterEuros(_modele.total),
                      ),
                    ),
                    Expanded(
                      child: _Chiffre(
                        libelle: 'Dépenses',
                        valeur: '${depenses.length}',
                      ),
                    ),
                    Expanded(
                      child: _Chiffre(
                        libelle: 'Moyenne',
                        valeur: formaterEuros(_modele.total ~/ depenses.length),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('Dépenses par mois', style: theme.textTheme.titleMedium),
                Text(
                  '6 derniers mois — touchez une barre pour voir le montant',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _BarresVerticales(donnees: _modele.parMois),
                const SizedBox(height: 32),
                Text(
                  'Avancé par chaque colocataire',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _BarresHorizontales(
                  donnees: [
                    for (final (id, v) in _modele.parPayeur)
                      (session.pseudo(id), v),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.libelle, required this.valeur});

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        FittedBox(child: Text(valeur, style: theme.textTheme.titleLarge)),
        Text(
          libelle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Une seule série → une seule teinte, pas de légende (le titre la nomme).
class _BarresVerticales extends StatelessWidget {
  const _BarresVerticales({required this.donnees});

  final List<(DateTime, int)> donnees;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximum = donnees.map((d) => d.$2).fold(0, max);
    const hauteur = 160.0;
    return SizedBox(
      height: hauteur + 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (mois, valeur) in donnees)
            Expanded(
              child: Tooltip(
                message:
                    '${nomDuMois(mois.month)} ${mois.year} : ${formaterEuros(valeur)}',
                triggerMode: TooltipTriggerMode.tap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      // barre fine, coins arrondis seulement côté valeur, ligne de base franche
                      width: 28,
                      height: maximum == 0
                          ? 0
                          : max(2, hauteur * valeur / maximum),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    Container(
                      height: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nomDuMois(mois.month),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarresHorizontales extends StatelessWidget {
  const _BarresHorizontales({required this.donnees});

  final List<(String, int)> donnees;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximum = donnees.map((d) => d.$2).fold(0, max);
    return Column(
      children: [
        for (final (nom, valeur) in donnees)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(nom, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: maximum == 0
                          ? 0
                          : max(0.01, valeur / maximum),
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // valeur en couleur de texte, jamais dans la couleur de la barre
                SizedBox(
                  width: 90,
                  child: Text(formaterEuros(valeur), textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
