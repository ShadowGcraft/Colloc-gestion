import 'dart:async';

import 'package:flutter/material.dart';

import '../../donnees/depots.dart';
import '../../etat/modele_vue.dart';
import '../../etat/reseau.dart';
import '../../etat/services.dart';
import '../../modeles/vie_commune.dart';
import '../chat/chat_onglet.dart';
import '../colocs/mes_colocs_page.dart';
import '../colocs/parametres_coloc_page.dart';
import '../courses/courses_onglet.dart';
import '../depenses/depenses_onglet.dart';
import '../depenses/statistiques_page.dart';
import '../profil/profil_page.dart';
import '../taches/taches_onglet.dart';

/// Accueil d'une colocation : 4 onglets. Chaque onglet est reconstruit quand on
/// y revient, donc ses abonnements temps réel s'ouvrent et se ferment avec lui.
class AccueilPage extends StatefulWidget {
  const AccueilPage({super.key});

  @override
  State<AccueilPage> createState() => _AccueilPageState();
}

class _AccueilPageState extends State<AccueilPage> {
  static const _ongletChat = 3;

  var _onglet = 0;
  late final CompteurNonLus _nonLus;

  @override
  void initState() {
    super.initState();
    final services = context.services;
    unawaited(services.session.rechargerMembres());
    _nonLus = CompteurNonLus(
      services.depots.chat,
      services.reseau,
      services.session.courante!.id,
      services.session.moi!,
    );
    unawaited(_nonLus.charger());
  }

  @override
  void dispose() {
    _nonLus.dispose();
    super.dispose();
  }

  void _changerOnglet(int index) {
    setState(() => _onglet = index);
    _nonLus.chatOuvert = index == _ongletChat;
  }

  Future<void> _ouvrir(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    final coloc = session.courante!;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _ouvrir(const MesColocsPage()),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(coloc.nom, overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [
          PopupMenuButton<VoidCallback>(
            tooltip: 'Menu',
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              _entree(
                Icons.settings_outlined,
                'Paramètres de la coloc',
                () => _ouvrir(const ParametresColocPage()),
              ),
              _entree(
                Icons.bar_chart,
                'Statistiques',
                () => _ouvrir(StatistiquesPage(colocationId: coloc.id)),
              ),
              _entree(
                Icons.swap_horiz,
                'Changer de colocation',
                () => _ouvrir(const MesColocsPage()),
              ),
              _entree(
                Icons.account_circle_outlined,
                'Mon profil',
                () => _ouvrir(const ProfilPage()),
              ),
            ],
          ),
        ],
      ),
      body: switch (_onglet) {
        0 => DepensesOnglet(colocationId: coloc.id),
        1 => TachesOnglet(colocationId: coloc.id),
        2 => CoursesOnglet(colocationId: coloc.id),
        _ => ChatOnglet(
          colocationId: coloc.id,
          surLu: () => unawaited(_nonLus.charger()),
        ),
      },
      bottomNavigationBar: ListenableBuilder(
        listenable: _nonLus,
        builder: (context, _) => NavigationBar(
          selectedIndex: _onglet,
          onDestinationSelected: _changerOnglet,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.euro_outlined),
              selectedIcon: Icon(Icons.euro),
              label: 'Dépenses',
            ),
            const NavigationDestination(
              icon: Icon(Icons.cleaning_services_outlined),
              selectedIcon: Icon(Icons.cleaning_services),
              label: 'Tâches',
            ),
            const NavigationDestination(
              icon: Icon(Icons.shopping_cart_outlined),
              selectedIcon: Icon(Icons.shopping_cart),
              label: 'Courses',
            ),
            NavigationDestination(
              // lecteur d'écran : « 3 non lus » plutôt qu'un simple « 3 »
              icon: Semantics(
                label: _nonLus.nombre > 0 ? '${_nonLus.nombre} non lus' : null,
                child: ExcludeSemantics(
                  child: Badge(
                    isLabelVisible: _nonLus.nombre > 0,
                    label: Text(
                      _nonLus.nombre > 99 ? '99+' : '${_nonLus.nombre}',
                    ),
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                ),
              ),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: 'Chat',
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<VoidCallback> _entree(
    IconData icone,
    String texte,
    VoidCallback action,
  ) => PopupMenuItem(
    value: action,
    child: ListTile(
      leading: Icon(icone),
      title: Text(texte),
      contentPadding: EdgeInsets.zero,
    ),
  );
}

/// Nombre de messages non lus, affiché sur l'onglet Chat (mis à jour en temps réel).
class CompteurNonLus extends ModeleVue {
  CompteurNonLus(this._depot, EtatReseau reseau, this._colocationId, this._moi)
    : super(reseau) {
    _ecoute = _depot.ecouter(_colocationId, (
      surEvenement: (evenement) {
        if (evenement is Ajout<Message> &&
            evenement.element.auteurId != _moi &&
            !_chatOuvert) {
          _nombre++;
          notifyListeners();
        }
      },
      surReconnexion: () => unawaited(charger()),
      surCoupure: () => unawaited(reseau.verifier()),
    ));
  }

  final ChatDepot _depot;
  final String _colocationId;
  final String _moi;
  late final Ecoute _ecoute;

  int _nombre = 0;
  bool _chatOuvert = false;

  int get nombre => _chatOuvert ? 0 : _nombre;

  set chatOuvert(bool ouvert) {
    if (ouvert == _chatOuvert) return;
    _chatOuvert = ouvert;
    // en quittant le chat, les messages viennent d'être marqués comme lus
    if (!ouvert) unawaited(charger());
    notifyListeners();
  }

  @override
  Future<void> charger() => suivreChargement(() async {
    _nombre = await _depot.nombreNonLus(_colocationId);
  });

  @override
  void dispose() {
    unawaited(_ecoute.fermer());
    super.dispose();
  }
}
