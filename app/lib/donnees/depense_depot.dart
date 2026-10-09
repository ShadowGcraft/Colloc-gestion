import 'package:supabase_flutter/supabase_flutter.dart';

import '../modeles/argent.dart';
import '../outils/dates.dart';
import '../outils/simplification.dart';
import 'fichiers.dart';

abstract interface class DepenseDepot {
  /// Dépenses de la plus récente à la plus ancienne, par pages
  Future<List<Depense>> depenses(String colocationId, {int debut = 0, int taille = 30});

  /// Crée la dépense et ses parts en une seule transaction (RPC creer_depense)
  Future<String> creer(NouvelleDepense depense);
  Future<void> supprimer(Depense depense);
  Future<String> urlTicket(String chemin);

  Future<List<Solde>> soldes(String colocationId);
  Future<List<Remboursement>> remboursements(String colocationId);
  Future<void> rembourser(String colocationId, Virement virement);
  Future<void> annulerRemboursement(String remboursementId);

  /// Montants, dates et payeurs de toutes les dépenses (écran Statistiques)
  Future<List<Depense>> resumePourStatistiques(String colocationId);
}

class DepenseDepotSupabase implements DepenseDepot {
  DepenseDepotSupabase(this._client, this._urls);

  final SupabaseClient _client;
  final UrlsSignees _urls;

  @override
  Future<List<Depense>> depenses(String colocationId, {int debut = 0, int taille = 30}) async {
    final lignes = await _client
        .from('depenses')
        .select('*, parts:depense_parts(utilisateur_id, montant_centimes)')
        .eq('colocation_id', colocationId)
        .order('date_depense', ascending: false)
        .order('cree_le', ascending: false)
        .range(debut, debut + taille - 1);
    return lignes.map(Depense.depuisJson).toList();
  }

  @override
  Future<String> creer(NouvelleDepense d) async {
    // 1. la photo d'abord (si l'enregistrement échoue ensuite, on la supprime)
    String? chemin;
    final ticket = d.ticket;
    if (ticket != null) {
      chemin = await envoyerImage(
        _client,
        bucket: 'tickets',
        dossier: d.colocationId,
        octets: ticket.octets,
        typeMime: ticket.typeMime,
      );
    }

    // 2. la dépense et ses parts, en bloc
    try {
      return await _client.rpc<String>('creer_depense', params: {
        'p_colocation_id': d.colocationId,
        'p_payeur_id': d.payeurId,
        'p_montant_centimes': d.montantCentimes,
        'p_description': d.description.trim(),
        'p_date': dateVersSql(d.date),
        'p_participants': d.participants,
        'p_montants': d.montantsPersonnalises,
        'p_ticket_chemin': chemin,
      });
    } catch (_) {
      if (chemin != null) await supprimerSansErreur(_client, 'tickets', chemin);
      rethrow;
    }
  }

  @override
  Future<void> supprimer(Depense depense) async {
    await _client.from('depenses').delete().eq('id', depense.id);
    final chemin = depense.ticketChemin;
    if (chemin != null) await supprimerSansErreur(_client, 'tickets', chemin);
  }

  @override
  Future<String> urlTicket(String chemin) => _urls.pour('tickets', chemin);

  @override
  Future<List<Solde>> soldes(String colocationId) async {
    final lignes = await _client.from('soldes').select().eq('colocation_id', colocationId);
    return lignes.map(Solde.depuisJson).toList();
  }

  @override
  Future<List<Remboursement>> remboursements(String colocationId) async {
    final lignes = await _client
        .from('remboursements')
        .select()
        .eq('colocation_id', colocationId)
        .order('cree_le', ascending: false)
        .limit(30);
    return lignes.map(Remboursement.depuisJson).toList();
  }

  @override
  Future<void> rembourser(String colocationId, Virement virement) =>
      _client.from('remboursements').insert({
        'colocation_id': colocationId,
        'debiteur_id': virement.de,
        'crediteur_id': virement.vers,
        'montant_centimes': virement.montant,
      });

  @override
  Future<void> annulerRemboursement(String remboursementId) =>
      _client.from('remboursements').delete().eq('id', remboursementId);

  @override
  Future<List<Depense>> resumePourStatistiques(String colocationId) async {
    final lignes = await _client
        .from('depenses')
        .select('id, payeur_id, montant_centimes, description, date_depense, cree_par')
        .eq('colocation_id', colocationId)
        .order('date_depense')
        .limit(5000);
    return lignes.map(Depense.depuisJson).toList();
  }
}
