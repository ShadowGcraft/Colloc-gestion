import 'dart:async';

import 'package:flutter/material.dart';

import '../../donnees/depots.dart';
import '../../etat/modele_vue.dart';
import '../../etat/reseau.dart';
import '../../etat/services.dart';
import '../../modeles/vie_commune.dart';
import '../../outils/dates.dart';
import '../../widgets/avatar.dart';
import '../../widgets/etats.dart';

class ChatModele extends ModeleVue {
  ChatModele(
    this._depot,
    EtatReseau reseau,
    this.colocationId,
    this.moi, {
    this.surLu,
  }) : super(reseau) {
    _ecoute = _depot.ecouter(colocationId, (
      surEvenement: _surEvenement,
      surReconnexion: () => unawaited(charger()),
      surCoupure: () => unawaited(reseau.verifier()),
    ));
  }

  static const taillePage = 30;

  final ChatDepot _depot;
  final String colocationId;
  final String moi;
  final VoidCallback? surLu;
  late final Ecoute _ecoute;

  /// Du plus récent au plus ancien (la liste est affichée à l'envers)
  List<Message>? _messages;
  bool _toutCharge = false;
  bool _chargementAnciens = false;
  int? _dernierLuALOuverture;
  bool _premierChargement = true;
  int _dernierMarque = 0;
  int _nouveaux = 0;

  /// L'écran indique si l'utilisateur voit le bas de la conversation
  bool enBas = true;

  List<Message>? get messages => _messages;
  bool get toutCharge => _toutCharge;
  bool get chargementAnciens => _chargementAnciens;

  /// Messages arrivés pendant que l'utilisateur lisait plus haut
  int get nouveaux => _nouveaux;

  /// Le séparateur « Nouveaux messages » se place au-dessus de ce message
  bool premierNonLu(int index) {
    final dernierLu = _dernierLuALOuverture;
    final liste = _messages!;
    if (dernierLu == null) return false;
    final m = liste[index];
    final precedentLu =
        index + 1 < liste.length && liste[index + 1].id <= dernierLu;
    return m.id > dernierLu && m.auteurId != moi && precedentLu;
  }

  @override
  Future<void> charger() => suivreChargement(() async {
    if (_premierChargement) {
      _dernierLuALOuverture = await _depot.dernierLu(colocationId);
      _premierChargement = false;
    }
    final page = await _depot.messages(colocationId, limite: taillePage);
    _messages = page;
    _toutCharge = page.length < taillePage;
    _nouveaux = 0;
    await _marquerLu();
  });

  /// Pagination « par clé » : les [taillePage] messages précédant le plus ancien affiché
  Future<String?> chargerAnciens() async {
    final liste = _messages;
    if (liste == null || liste.isEmpty || _toutCharge || _chargementAnciens) {
      return null;
    }
    _chargementAnciens = true;
    notifyListeners();
    final erreur = await agir(() async {
      final page = await _depot.messages(
        colocationId,
        avantId: liste.last.id,
        limite: taillePage,
      );
      _messages = [...?_messages, ...page];
      _toutCharge = page.length < taillePage;
    });
    _chargementAnciens = false;
    notifyListeners();
    return erreur;
  }

  Future<String?> envoyer(String texte) => agir(() async {
    _surEvenement(Ajout(await _depot.envoyer(colocationId, texte)));
  });

  Future<String?> supprimer(Message message) => agir(() async {
    await _depot.supprimer(message.id);
    _surEvenement(Suppression(message.id));
  });

  /// L'utilisateur est revenu en bas : les nouveaux messages sont vus.
  void voirNouveaux() {
    if (_nouveaux == 0) return;
    _nouveaux = 0;
    notifyListeners();
    unawaited(_marquerLu());
  }

  void _surEvenement(Evenement<Message> evenement) {
    final liste = _messages;
    if (liste == null) return;
    switch (evenement) {
      case Ajout(:final element):
        if (liste.any((m) => m.id == element.id)) return;
        _messages = [element, ...liste]..sort((a, b) => b.id.compareTo(a.id));
        if (element.auteurId == moi || enBas) {
          unawaited(_marquerLu());
        } else {
          _nouveaux++;
        }
      case Modification(:final element):
        _messages = [for (final m in liste) m.id == element.id ? element : m];
      case Suppression(:final id):
        _messages = liste.where((m) => m.id != id).toList();
    }
    notifyListeners();
  }

  Future<void> _marquerLu() async {
    final plusRecent = _messages?.firstOrNull?.id;
    if (plusRecent == null || plusRecent <= _dernierMarque) return;
    _dernierMarque = plusRecent;
    try {
      await _depot.marquerLu(colocationId, plusRecent);
      surLu?.call();
    } catch (e) {
      _dernierMarque = 0; // on réessaiera au prochain message
      reseau.signalerErreur(e);
    }
  }

  @override
  void dispose() {
    unawaited(_ecoute.fermer());
    super.dispose();
  }
}

class ChatOnglet extends StatefulWidget {
  const ChatOnglet({super.key, required this.colocationId, this.surLu});

  final String colocationId;

  /// Prévient l'accueil (badge de l'onglet) que des messages ont été lus
  final VoidCallback? surLu;

  @override
  State<ChatOnglet> createState() => _ChatOngletState();
}

class _ChatOngletState extends State<ChatOnglet> {
  late final ChatModele _modele;
  final _defilement = ScrollController();
  final _saisie = TextEditingController();
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    final services = context.services;
    _modele = ChatModele(
      services.depots.chat,
      services.reseau,
      widget.colocationId,
      services.session.moi!,
      surLu: widget.surLu,
    );
    unawaited(_modele.charger());
    _defilement.addListener(_surDefilement);
  }

  @override
  void dispose() {
    _modele.dispose();
    _defilement.dispose();
    _saisie.dispose();
    super.dispose();
  }

  void _surDefilement() {
    final position = _defilement.position;
    // liste inversée : 0 = en bas (messages récents), max = en haut (anciens)
    _modele.enBas = position.pixels <= 80;
    if (_modele.enBas) _modele.voirNouveaux();
    if (position.pixels >= position.maxScrollExtent - 400) {
      unawaited(
        _modele.chargerAnciens().then(
          (e) => mounted ? afficherErreur(context, e) : null,
        ),
      );
    }
  }

  Future<void> _descendre() async {
    await _defilement.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _modele.voirNouveaux();
  }

  Future<void> _envoyer() async {
    final texte = _saisie.text.trim();
    if (texte.isEmpty || _envoi) return;
    setState(() => _envoi = true);
    final erreur = await _modele.envoyer(texte);
    if (!mounted) return;
    setState(() => _envoi = false);
    if (erreur != null) return afficherErreur(context, erreur);
    _saisie.clear();
    if (_defilement.hasClients) await _descendre();
  }

  Future<void> _supprimer(Message message) async {
    final ok = await confirmer(
      context,
      titre: 'Supprimer ce message ?',
      message: message.contenu,
    );
    if (ok && mounted) {
      await signalerResultat(context, _modele.supprimer(message));
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
              estVide: _modele.messages?.isEmpty,
              reessayer: _modele.charger,
              vide: const EtatVide(
                icone: Icons.forum_outlined,
                titre: 'Aucun message',
                explication: 'Lancez la conversation avec vos colocataires !',
              ),
              contenu: () {
                final messages = _modele.messages!;
                return Stack(
                  children: [
                    ListView.builder(
                      controller: _defilement,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: messages.length + 1,
                      itemBuilder: (context, i) {
                        if (i == messages.length) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: _modele.toutCharge
                                  ? Text(
                                      'Début de la conversation',
                                      style: theme.textTheme.bodySmall,
                                    )
                                  : const CircularProgressIndicator(),
                            ),
                          );
                        }
                        final m = messages[i];
                        final plusAncien = i + 1 < messages.length
                            ? messages[i + 1]
                            : null;
                        final bulle = _Bulle(
                          message: m,
                          deMoi: m.auteurId == session.moi,
                          auteur: session.pseudo(m.auteurId),
                          afficherAuteur: plusAncien?.auteurId != m.auteurId,
                          supprimer:
                              m.auteurId == session.moi || session.suisAdmin
                              ? () => _supprimer(m)
                              : null,
                        );
                        if (!_modele.premierNonLu(i)) return bulle;
                        return Column(
                          children: [const _SeparateurNonLus(), bulle],
                        );
                      },
                    ),
                    if (_modele.nouveaux > 0)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: ActionChip(
                            avatar: const Icon(Icons.arrow_downward, size: 18),
                            label: Text(
                              '${_modele.nouveaux} nouveau${_modele.nouveaux > 1 ? 'x' : ''} message${_modele.nouveaux > 1 ? 's' : ''}',
                            ),
                            onPressed: _descendre,
                          ),
                        ),
                      ),
                  ],
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
                    child: TextField(
                      controller: _saisie,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        isDense: true,
                        counterText: '',
                      ),
                      onSubmitted: (_) => _envoyer(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Envoyer',
                    onPressed: _envoi ? null : _envoyer,
                    icon: const Icon(Icons.send),
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

class _Bulle extends StatelessWidget {
  const _Bulle({
    required this.message,
    required this.deMoi,
    required this.auteur,
    required this.afficherAuteur,
    required this.supprimer,
  });

  final Message message;
  final bool deMoi;
  final String auteur;
  final bool afficherAuteur;
  final VoidCallback? supprimer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleurs = theme.colorScheme;
    final bulle = GestureDetector(
      onLongPress: supprimer,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: deMoi
              ? couleurs.primaryContainer
              : couleurs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!deMoi && afficherAuteur)
              Text(
                auteur,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: couleurs.primary,
                ),
              ),
            Text(
              message.contenu,
              style: TextStyle(
                color: deMoi ? couleurs.onPrimaryContainer : couleurs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formaterHorodatage(message.envoyeLe),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: afficherAuteur ? 10 : 2),
      child: Row(
        mainAxisAlignment: deMoi
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!deMoi) ...[
            afficherAuteur
                ? AvatarMembre(utilisateurId: message.auteurId, rayon: 14)
                : const SizedBox(width: 28),
            const SizedBox(width: 8),
          ],
          bulle,
        ],
      ),
    );
  }
}

class _SeparateurNonLus extends StatelessWidget {
  const _SeparateurNonLus();

  @override
  Widget build(BuildContext context) {
    final couleur = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: couleur)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('Nouveaux messages', style: TextStyle(color: couleur)),
          ),
          Expanded(child: Divider(color: couleur)),
        ],
      ),
    );
  }
}
