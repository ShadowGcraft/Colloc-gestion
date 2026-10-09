/// Dépenses, parts, soldes et remboursements. Tous les montants sont en centimes.
library;

class Depense {
  const Depense({
    required this.id,
    required this.payeurId,
    required this.montantCentimes,
    required this.description,
    required this.date,
    required this.creePar,
    required this.parts,
    this.ticketChemin,
  });

  /// Ligne de `depenses` avec les parts embarquées : `*, parts:depense_parts(...)`
  factory Depense.depuisJson(Map<String, dynamic> json) => Depense(
        id: json['id'] as String,
        payeurId: json['payeur_id'] as String,
        montantCentimes: (json['montant_centimes'] as num).toInt(),
        description: json['description'] as String,
        date: DateTime.parse(json['date_depense'] as String),
        creePar: json['cree_par'] as String,
        ticketChemin: json['ticket_chemin'] as String?,
        parts: {
          for (final p in (json['parts'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
            p['utilisateur_id'] as String: (p['montant_centimes'] as num).toInt(),
        },
      );

  final String id;
  final String payeurId;
  final int montantCentimes;
  final String description;
  final DateTime date;
  final String creePar;
  final String? ticketChemin;

  /// identifiant du participant → sa part en centimes
  final Map<String, int> parts;
}

/// Ce qu'on envoie pour créer une dépense (la base calcule les parts égales).
class NouvelleDepense {
  const NouvelleDepense({
    required this.colocationId,
    required this.payeurId,
    required this.montantCentimes,
    required this.description,
    required this.date,
    required this.participants,
    this.montantsPersonnalises,
    this.ticket,
  });

  final String colocationId;
  final String payeurId;
  final int montantCentimes;
  final String description;
  final DateTime date;
  final List<String> participants;

  /// null = parts égales ; sinon un montant par participant, dans le même ordre
  final List<int>? montantsPersonnalises;
  final PhotoTicket? ticket;
}

class PhotoTicket {
  const PhotoTicket({required this.octets, required this.typeMime});

  final List<int> octets;
  final String typeMime;
}

class Solde {
  const Solde({required this.utilisateurId, required this.centimes, required this.aQuitte});

  factory Solde.depuisJson(Map<String, dynamic> json) => Solde(
        utilisateurId: json['utilisateur_id'] as String,
        centimes: (json['solde_centimes'] as num).toInt(),
        aQuitte: json['a_quitte'] as bool,
      );

  final String utilisateurId;

  /// > 0 : on lui doit de l'argent ; < 0 : il en doit
  final int centimes;
  final bool aQuitte;
}

class Remboursement {
  const Remboursement({
    required this.id,
    required this.debiteurId,
    required this.crediteurId,
    required this.montantCentimes,
    required this.creePar,
    required this.creeLe,
  });

  factory Remboursement.depuisJson(Map<String, dynamic> json) => Remboursement(
        id: json['id'] as String,
        debiteurId: json['debiteur_id'] as String,
        crediteurId: json['crediteur_id'] as String,
        montantCentimes: (json['montant_centimes'] as num).toInt(),
        creePar: json['cree_par'] as String,
        creeLe: DateTime.parse(json['cree_le'] as String),
      );

  final String id;
  final String debiteurId;
  final String crediteurId;
  final int montantCentimes;
  final String creePar;
  final DateTime creeLe;
}
