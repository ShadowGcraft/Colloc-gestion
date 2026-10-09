import 'dart:async';

import 'package:flutter/material.dart';

import '../../donnees/depots.dart';
import '../../etat/modele_vue.dart';
import '../../etat/reseau.dart';
import '../../etat/services.dart';
import '../../modeles/vie_commune.dart';
import '../../widgets/etats.dart';

class CoursesModele extends ModeleVue {
  CoursesModele(this._depot, EtatReseau reseau, this.colocationId, this._moi)
    : super(reseau) {
    _ecoute = _depot.ecouter(colocationId, (
      surEvenement: _surEvenement,
      surReconnexion: () => unawaited(charger()),
      surCoupure: () => unawaited(reseau.verifier()),
    ));
  }

  final CoursesDepot _depot;
  final String colocationId;
  final String _moi;
  late final Ecoute _ecoute;

  List<ArticleCourse>? _articles;

  List<ArticleCourse>? get articles => _articles;
  List<ArticleCourse> get aAcheter =>
      (_articles ?? const []).where((a) => !a.coche).toList();
  List<ArticleCourse> get dansLePanier =>
      (_articles ?? const []).where((a) => a.coche).toList();

  @override
  Future<void> charger() => suivreChargement(() async {
    _articles = await _depot.articles(colocationId);
  });

  void _surEvenement(Evenement<ArticleCourse> evenement) {
    final articles = _articles;
    if (articles == null) return;
    _articles = switch (evenement) {
      Ajout(:final element) when articles.any((a) => a.id == element.id) =>
        articles,
      Ajout(:final element) => [...articles, element],
      Modification(:final element) => [
        for (final a in articles) a.id == element.id ? element : a,
      ],
      Suppression(:final id) => articles.where((a) => a.id != id).toList(),
    };
    notifyListeners();
  }

  Future<String?> ajouter(String libelle, String? quantite) => agir(() async {
    _surEvenement(Ajout(await _depot.ajouter(colocationId, libelle, quantite)));
  });

  /// Coche tout de suite à l'écran, puis confirme avec le serveur (annulé en cas d'échec).
  Future<String?> basculer(ArticleCourse article) async {
    _surEvenement(Modification(article.avecCoche(!article.coche, _moi)));
    final erreur = await agir(() async {
      _surEvenement(
        Modification(await _depot.cocher(article.id, !article.coche)),
      );
    });
    if (erreur != null) _surEvenement(Modification(article));
    return erreur;
  }

  Future<String?> supprimer(ArticleCourse article) => agir(() async {
    _surEvenement(Suppression(article.id));
    try {
      await _depot.supprimer([article.id]);
    } catch (_) {
      _surEvenement(Ajout(article));
      rethrow;
    }
  });

  Future<String?> viderPanier() => agir(() async {
    final ids = dansLePanier.map((a) => a.id).toList();
    if (ids.isEmpty) return;
    await _depot.supprimer(ids);
    for (final id in ids) {
      _surEvenement(Suppression(id));
    }
  });

  @override
  void dispose() {
    unawaited(_ecoute.fermer());
    super.dispose();
  }
}

class CoursesOnglet extends StatefulWidget {
  const CoursesOnglet({super.key, required this.colocationId});

  final String colocationId;

  @override
  State<CoursesOnglet> createState() => _CoursesOngletState();
}

class _CoursesOngletState extends State<CoursesOnglet> {
  late final CoursesModele _modele;
  final _libelle = TextEditingController();
  final _quantite = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final services = context.services;
    _modele = CoursesModele(
      services.depots.courses,
      services.reseau,
      widget.colocationId,
      services.session.moi!,
    );
    unawaited(_modele.charger());
  }

  @override
  void dispose() {
    _modele.dispose();
    _libelle.dispose();
    _quantite.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ajouter() async {
    final libelle = _libelle.text.trim();
    if (libelle.isEmpty) return;
    final quantite = _quantite.text;
    _libelle.clear();
    _quantite.clear();
    _focus.requestFocus();
    final erreur = await _modele.ajouter(libelle, quantite);
    if (erreur != null && mounted) {
      _libelle.text = libelle; // on rend la saisie pour pouvoir réessayer
      _quantite.text = quantite;
      afficherErreur(context, erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([_modele, session]),
            builder: (context, _) => VueListe(
              chargement: _modele.chargement,
              erreur: _modele.erreur,
              estVide: _modele.articles?.isEmpty,
              reessayer: _modele.charger,
              vide: const EtatVide(
                icone: Icons.shopping_basket_outlined,
                titre: 'La liste de courses est vide',
                explication: 'Ajoutez un article ci-dessous : il apparaît aussitôt chez tous les colocataires.',
              ),
              contenu: () {
                final aAcheter = _modele.aAcheter;
                final panier = _modele.dansLePanier;
                return RefreshIndicator(
                  onRefresh: _modele.charger,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      _Titre('À acheter (${aAcheter.length})'),
                      if (aAcheter.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text('Tout est dans le panier.'),
                        ),
                      for (final a in aAcheter)
                        _LigneArticle(
                          article: a,
                          detail: 'Ajouté par ${session.pseudo(a.ajoutePar)}',
                          basculer: () =>
                              signalerResultat(context, _modele.basculer(a)),
                          supprimer: () =>
                              signalerResultat(context, _modele.supprimer(a)),
                        ),
                      if (panier.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Dans le panier (${panier.length})',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => signalerResultat(
                                  context,
                                  _modele.viderPanier(),
                                ),
                                icon: const Icon(Icons.delete_sweep_outlined),
                                label: const Text('Retirer'),
                              ),
                            ],
                          ),
                        ),
                        for (final a in panier)
                          _LigneArticle(
                            article: a,
                            detail:
                                'Coché par ${a.cochePar == null ? '…' : session.pseudo(a.cochePar!)}',
                            basculer: () =>
                                signalerResultat(context, _modele.basculer(a)),
                            supprimer: () =>
                                signalerResultat(context, _modele.supprimer(a)),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Material(
          elevation: 3,
          color: theme.colorScheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _libelle,
                      focusNode: _focus,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: 'Ajouter un article',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _ajouter(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _quantite,
                      decoration: const InputDecoration(
                        hintText: 'Qté',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _ajouter(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ajouter',
                    onPressed: _ajouter,
                    icon: const Icon(Icons.add_circle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LigneArticle extends StatelessWidget {
  const _LigneArticle({
    required this.article,
    required this.detail,
    required this.basculer,
    required this.supprimer,
  });

  final ArticleCourse article;
  final String detail;
  final VoidCallback basculer;
  final VoidCallback supprimer;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(article.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: couleurs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: couleurs.onErrorContainer),
      ),
      onDismissed: (_) => supprimer(),
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: article.coche,
        onChanged: (_) => basculer(),
        title: Text(
          article.quantite == null
              ? article.libelle
              : '${article.libelle} · ${article.quantite}',
          style: article.coche
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: couleurs.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: Text(detail),
        secondary: IconButton(
          tooltip: 'Supprimer',
          icon: const Icon(Icons.close),
          onPressed: supprimer,
        ),
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(texte, style: Theme.of(context).textTheme.titleSmall),
  );
}
