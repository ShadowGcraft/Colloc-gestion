import 'package:supabase_flutter/supabase_flutter.dart';

import '../modeles/vie_commune.dart';
import '../outils/dates.dart';
import 'ecoute.dart';

/// Paramètres communs à tous les abonnements temps réel d'un écran.
typedef Rappels<T> = ({
  void Function(Evenement<T>) surEvenement,
  void Function() surReconnexion,
  void Function() surCoupure,
});

// --- Tâches -----------------------------------------------------------------

abstract interface class TacheDepot {
  Future<List<Tache>> taches(String colocationId);
  Future<void> creer({
    required String colocationId,
    required String titre,
    required Frequence frequence,
    required String responsableId,
    required DateTime premiereEcheance,
  });

  /// Historique + échéance suivante + membre suivant, en une transaction (RPC)
  Future<Tache> terminer(String tacheId);
  Future<void> supprimer(String tacheId);
  Future<List<RealisationTache>> historique(String tacheId);
  Ecoute ecouter(String colocationId, Rappels<Tache> rappels);
}

class TacheDepotSupabase implements TacheDepot {
  TacheDepotSupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Tache>> taches(String colocationId) async {
    final lignes = await _client
        .from('taches')
        .select()
        .eq('colocation_id', colocationId)
        .order('prochaine_echeance', ascending: true)
        .order('titre', ascending: true);
    return lignes.map(Tache.depuisJson).toList();
  }

  @override
  Future<void> creer({
    required String colocationId,
    required String titre,
    required Frequence frequence,
    required String responsableId,
    required DateTime premiereEcheance,
  }) => _client.from('taches').insert({
    'colocation_id': colocationId,
    'titre': titre.trim(),
    'frequence': frequence.name,
    'responsable_id': responsableId,
    'prochaine_echeance': dateVersSql(premiereEcheance),
  });

  @override
  Future<Tache> terminer(String tacheId) async => Tache.depuisJson(
    await _client.rpc<Map<String, dynamic>>(
      'terminer_tache',
      params: {'p_tache_id': tacheId},
    ),
  );

  @override
  Future<void> supprimer(String tacheId) =>
      _client.from('taches').delete().eq('id', tacheId);

  @override
  Future<List<RealisationTache>> historique(String tacheId) async {
    final lignes = await _client
        .from('tache_realisations')
        .select()
        .eq('tache_id', tacheId)
        .order('fait_le', ascending: false)
        .limit(50);
    return lignes.map(RealisationTache.depuisJson).toList();
  }

  @override
  Ecoute ecouter(String colocationId, Rappels<Tache> r) =>
      EcouteSupabase<Tache>(
        _client,
        table: 'taches',
        colocationId: colocationId,
        convertir: Tache.depuisJson,
        surEvenement: r.surEvenement,
        surReconnexion: r.surReconnexion,
        surCoupure: r.surCoupure,
      );
}

// --- Courses ----------------------------------------------------------------

abstract interface class CoursesDepot {
  Future<List<ArticleCourse>> articles(String colocationId);
  Future<ArticleCourse> ajouter(
    String colocationId,
    String libelle,
    String? quantite,
  );

  /// « coché par » est rempli par la base (trigger), pas par l'application
  Future<ArticleCourse> cocher(String articleId, bool coche);
  Future<void> supprimer(List<String> articleIds);
  Ecoute ecouter(String colocationId, Rappels<ArticleCourse> rappels);
}

class CoursesDepotSupabase implements CoursesDepot {
  CoursesDepotSupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ArticleCourse>> articles(String colocationId) async {
    final lignes = await _client
        .from('articles_courses')
        .select()
        .eq('colocation_id', colocationId)
        .order('ajoute_le', ascending: true);
    return lignes.map(ArticleCourse.depuisJson).toList();
  }

  @override
  Future<ArticleCourse> ajouter(
    String colocationId,
    String libelle,
    String? quantite,
  ) async => ArticleCourse.depuisJson(
    await _client
        .from('articles_courses')
        .insert({
          'colocation_id': colocationId,
          'libelle': libelle.trim(),
          'quantite': (quantite?.trim().isEmpty ?? true)
              ? null
              : quantite!.trim(),
        })
        .select()
        .single(),
  );

  @override
  Future<ArticleCourse> cocher(String articleId, bool coche) async =>
      ArticleCourse.depuisJson(
        await _client
            .from('articles_courses')
            .update({'coche': coche})
            .eq('id', articleId)
            .select()
            .single(),
      );

  @override
  Future<void> supprimer(List<String> articleIds) =>
      _client.from('articles_courses').delete().inFilter('id', articleIds);

  @override
  Ecoute ecouter(String colocationId, Rappels<ArticleCourse> r) =>
      EcouteSupabase<ArticleCourse>(
        _client,
        table: 'articles_courses',
        colocationId: colocationId,
        convertir: ArticleCourse.depuisJson,
        surEvenement: r.surEvenement,
        surReconnexion: r.surReconnexion,
        surCoupure: r.surCoupure,
      );
}

// --- Chat -------------------------------------------------------------------

abstract interface class ChatDepot {
  /// Messages du plus récent au plus ancien. [avantId] : pagination « par clé »
  /// (on demande les messages plus anciens que le dernier affiché).
  Future<List<Message>> messages(
    String colocationId, {
    int? avantId,
    int limite = 30,
  });
  Future<Message> envoyer(String colocationId, String contenu);
  Future<void> supprimer(int messageId);

  Future<int?> dernierLu(String colocationId);
  Future<void> marquerLu(String colocationId, int messageId);
  Future<int> nombreNonLus(String colocationId);
  Ecoute ecouter(String colocationId, Rappels<Message> rappels);
}

class ChatDepotSupabase implements ChatDepot {
  ChatDepotSupabase(this._client);

  final SupabaseClient _client;

  String get _moi => _client.auth.currentUser!.id;

  @override
  Future<List<Message>> messages(
    String colocationId, {
    int? avantId,
    int limite = 30,
  }) async {
    var requete = _client
        .from('messages')
        .select()
        .eq('colocation_id', colocationId);
    if (avantId != null) requete = requete.lt('id', avantId);
    final lignes = await requete.order('id', ascending: false).limit(limite);
    return lignes.map(Message.depuisJson).toList();
  }

  @override
  Future<Message> envoyer(String colocationId, String contenu) async =>
      Message.depuisJson(
        await _client
            .from('messages')
            .insert({'colocation_id': colocationId, 'contenu': contenu.trim()})
            .select()
            .single(),
      );

  @override
  Future<void> supprimer(int messageId) =>
      _client.from('messages').delete().eq('id', messageId);

  @override
  Future<int?> dernierLu(String colocationId) async {
    final ligne = await _client
        .from('membres')
        .select('dernier_message_lu_id')
        .eq('colocation_id', colocationId)
        .eq('utilisateur_id', _moi)
        .maybeSingle();
    return (ligne?['dernier_message_lu_id'] as num?)?.toInt();
  }

  @override
  Future<void> marquerLu(String colocationId, int messageId) => _client
      .from('membres')
      .update({'dernier_message_lu_id': messageId})
      .eq('colocation_id', colocationId)
      .eq('utilisateur_id', _moi)
      // on n'efface jamais une lecture plus récente faite sur un autre appareil
      .or('dernier_message_lu_id.is.null,dernier_message_lu_id.lt.$messageId');

  @override
  Future<int> nombreNonLus(String colocationId) async {
    final dernier = await dernierLu(colocationId);
    var requete = _client
        .from('messages')
        .select('id')
        .eq('colocation_id', colocationId)
        .neq('auteur_id', _moi);
    if (dernier != null) requete = requete.gt('id', dernier);
    final reponse = await requete.limit(1).count(CountOption.exact);
    return reponse.count;
  }

  @override
  Ecoute ecouter(String colocationId, Rappels<Message> r) =>
      EcouteSupabase<Message>(
        _client,
        table: 'messages',
        colocationId: colocationId,
        convertir: Message.depuisJson,
        surEvenement: r.surEvenement,
        surReconnexion: r.surReconnexion,
        surCoupure: r.surCoupure,
      );
}
