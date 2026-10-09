import '../donnees/depots.dart';
import '../modeles/argent.dart';
import '../modeles/coloc.dart';
import 'modele_vue.dart';
import 'reseau.dart';

/// État partagé par toute l'application une fois connecté : mon profil,
/// mes colocations, la colocation affichée et ses membres.
class Session extends ModeleVue {
  Session(this._depots, EtatReseau reseau) : super(reseau);

  final Depots _depots;

  Profil? _profil;
  List<Colocation> _colocs = const [];
  Colocation? _courante;
  List<Membre> _membres = const [];

  String? get moi => _depots.auth.utilisateurId;
  Profil? get profil => _profil;
  List<Colocation> get colocs => _colocs;
  Colocation? get courante => _courante;

  /// Membres actuels ET anciens (pour afficher les noms dans l'historique)
  List<Membre> get membres => _membres;
  List<Membre> get membresActifs => _membres.where((m) => m.estActif).toList();

  bool get estCharge => _profil != null;
  bool get suisAdmin => _courante?.suisAdmin ?? false;

  Membre? membre(String utilisateurId) {
    for (final m in _membres) {
      if (m.utilisateurId == utilisateurId) return m;
    }
    return null;
  }

  String pseudo(String utilisateurId) {
    if (utilisateurId == moi) return _profil?.pseudo ?? 'Moi';
    return membre(utilisateurId)?.pseudo ?? 'Ancien membre';
  }

  @override
  Future<void> charger() async {
    if (moi == null) {
      return; // déconnecté (ex. retour du réseau sur l'écran de connexion)
    }
    await suivreChargement(() async {
      _profil = await _depots.colocs.monProfil();
      await _rechargerColocs();
    });
  }

  /// Bascule vers une autre de mes colocations.
  Future<String?> choisir(Colocation coloc) => agir(() async {
    _courante = coloc;
    _membres = const [];
    notifyListeners();
    _membres = await _depots.colocs.membres(coloc.id);
  });

  Future<String?> rechargerMembres() => agir(() async {
    final courante = _courante;
    if (courante != null) _membres = await _depots.colocs.membres(courante.id);
  });

  Future<String?> creer(String nom) => agir(() async {
    final id = await _depots.colocs.creer(nom);
    await _rechargerColocs(choisirId: id);
  });

  Future<String?> rejoindre(String code) => agir(() async {
    final id = await _depots.colocs.rejoindre(code);
    await _rechargerColocs(choisirId: id);
  });

  Future<String?> quitter() => agir(() async {
    await _depots.colocs.quitter(_courante!.id);
    _courante = null;
    await _rechargerColocs();
  });

  Future<String?> renommer(String nom) => agir(() async {
    await _depots.colocs.renommer(_courante!.id, nom);
    await _rechargerColocs(choisirId: _courante!.id);
  });

  Future<String?> regenererCode() => agir(() async {
    await _depots.colocs.regenererCode(_courante!.id);
    await _rechargerColocs(choisirId: _courante!.id);
  });

  Future<String?> retirer(Membre membre) => agir(() async {
    await _depots.colocs.retirer(_courante!.id, membre.utilisateurId);
    _membres = await _depots.colocs.membres(_courante!.id);
  });

  Future<String?> modifierPseudo(String pseudo) => agir(() async {
    await _depots.colocs.modifierPseudo(pseudo);
    await _rechargerProfilEtMembres();
  });

  Future<String?> changerAvatar(PhotoTicket photo) => agir(() async {
    await _depots.colocs.changerAvatar(photo);
    await _rechargerProfilEtMembres();
  });

  Future<String> urlAvatar(String chemin) => _depots.colocs.urlAvatar(chemin);

  /// À la déconnexion : on oublie tout.
  void vider() {
    _profil = null;
    _colocs = const [];
    _courante = null;
    _membres = const [];
    notifyListeners();
  }

  Future<void> _rechargerColocs({String? choisirId}) async {
    _colocs = await _depots.colocs.mesColocations();
    final voulue = choisirId ?? _courante?.id;
    _courante =
        _colocs.where((c) => c.id == voulue).firstOrNull ?? _colocs.firstOrNull;
    _membres = _courante == null
        ? const []
        : await _depots.colocs.membres(_courante!.id);
  }

  Future<void> _rechargerProfilEtMembres() async {
    _profil = await _depots.colocs.monProfil();
    if (_courante != null) {
      _membres = await _depots.colocs.membres(_courante!.id);
    }
  }
}
