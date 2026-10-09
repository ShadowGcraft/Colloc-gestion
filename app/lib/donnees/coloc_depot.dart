import 'package:supabase_flutter/supabase_flutter.dart';

import '../modeles/argent.dart';
import '../modeles/coloc.dart';
import 'fichiers.dart';

/// Profil, colocations et membres. Les arrivées, départs et changements de rôle
/// passent par des RPC : la base décide seule de ce qui est autorisé.
abstract interface class ColocDepot {
  Future<Profil> monProfil();
  Future<void> modifierPseudo(String pseudo);
  Future<void> changerAvatar(PhotoTicket photo);
  Future<String> urlAvatar(String chemin);

  Future<List<Colocation>> mesColocations();
  Future<List<Membre>> membres(String colocationId);

  /// Renvoient l'identifiant de la colocation
  Future<String> creer(String nom);
  Future<String> rejoindre(String code);

  Future<void> renommer(String colocationId, String nom);
  Future<String> regenererCode(String colocationId);
  Future<void> retirer(String colocationId, String utilisateurId);
  Future<void> quitter(String colocationId);
}

class ColocDepotSupabase implements ColocDepot {
  ColocDepotSupabase(this._client, this._urls);

  final SupabaseClient _client;
  final UrlsSignees _urls;

  String get _moi => _client.auth.currentUser!.id;

  @override
  Future<Profil> monProfil() async =>
      Profil.depuisJson(await _client.from('profils').select().eq('id', _moi).single());

  @override
  Future<void> modifierPseudo(String pseudo) =>
      _client.from('profils').update({'pseudo': pseudo.trim()}).eq('id', _moi);

  @override
  Future<void> changerAvatar(PhotoTicket photo) async {
    final ancien = (await monProfil()).avatarChemin;
    final chemin = await envoyerImage(
      _client,
      bucket: 'avatars',
      dossier: _moi,
      octets: photo.octets,
      typeMime: photo.typeMime,
    );
    await _client.from('profils').update({'avatar_chemin': chemin}).eq('id', _moi);
    if (ancien != null) await supprimerSansErreur(_client, 'avatars', ancien);
  }

  @override
  Future<String> urlAvatar(String chemin) => _urls.pour('avatars', chemin);

  @override
  Future<List<Colocation>> mesColocations() async {
    // Le filtre sur « moi » sert à l'affichage : la sécurité, elle, est assurée par la RLS.
    final lignes = await _client
        .from('membres')
        .select('role, colocation:colocations(id, nom, code_invitation)')
        .eq('utilisateur_id', _moi)
        .isFilter('parti_le', null);
    return lignes.map(Colocation.depuisAppartenance).toList()
      ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
  }

  @override
  Future<List<Membre>> membres(String colocationId) async {
    final lignes = await _client
        .from('membres')
        .select('*, profil:profils(pseudo, avatar_chemin)')
        .eq('colocation_id', colocationId)
        .order('rejoint_le');
    return lignes.map(Membre.depuisJson).toList();
  }

  @override
  Future<String> creer(String nom) async =>
      await _client.rpc<String>('creer_colocation', params: {'p_nom': nom.trim()});

  @override
  Future<String> rejoindre(String code) async =>
      await _client.rpc<String>('rejoindre_colocation', params: {'p_code': code});

  @override
  Future<void> renommer(String colocationId, String nom) =>
      _client.from('colocations').update({'nom': nom.trim()}).eq('id', colocationId);

  @override
  Future<String> regenererCode(String colocationId) async =>
      await _client.rpc<String>('regenerer_code', params: {'p_colocation_id': colocationId});

  @override
  Future<void> retirer(String colocationId, String utilisateurId) => _client.rpc<void>(
        'retirer_membre',
        params: {'p_colocation_id': colocationId, 'p_utilisateur_id': utilisateurId},
      );

  @override
  Future<void> quitter(String colocationId) =>
      _client.rpc<void>('quitter_colocation', params: {'p_colocation_id': colocationId});
}
