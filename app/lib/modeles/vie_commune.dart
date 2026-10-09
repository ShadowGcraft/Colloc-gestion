/// Tâches ménagères, liste de courses et messages du chat.
library;

import '../outils/dates.dart';

enum Frequence {
  quotidienne('Tous les jours'),
  hebdomadaire('Toutes les semaines');

  const Frequence(this.libelle);
  final String libelle;
}

class Tache {
  const Tache({
    required this.id,
    required this.titre,
    required this.frequence,
    required this.responsableId,
    required this.prochaineEcheance,
    required this.creePar,
  });

  factory Tache.depuisJson(Map<String, dynamic> json) => Tache(
        id: json['id'] as String,
        titre: json['titre'] as String,
        frequence: Frequence.values.byName(json['frequence'] as String),
        responsableId: json['responsable_id'] as String,
        prochaineEcheance: DateTime.parse(json['prochaine_echeance'] as String),
        creePar: json['cree_par'] as String,
      );

  final String id;
  final String titre;
  final Frequence frequence;
  final String responsableId;
  final DateTime prochaineEcheance;
  final String creePar;

  bool get enRetard => prochaineEcheance.isBefore(aujourdhui());
}

class RealisationTache {
  const RealisationTache({
    required this.faitPar,
    required this.responsablePrevu,
    required this.echeance,
    required this.enRetard,
    required this.faitLe,
  });

  factory RealisationTache.depuisJson(Map<String, dynamic> json) => RealisationTache(
        faitPar: json['fait_par'] as String,
        responsablePrevu: json['responsable_prevu'] as String,
        echeance: DateTime.parse(json['echeance'] as String),
        enRetard: json['en_retard'] as bool,
        faitLe: DateTime.parse(json['fait_le'] as String),
      );

  final String faitPar;
  final String responsablePrevu;
  final DateTime echeance;
  final bool enRetard;
  final DateTime faitLe;
}

class ArticleCourse {
  const ArticleCourse({
    required this.id,
    required this.libelle,
    required this.ajoutePar,
    required this.ajouteLe,
    required this.coche,
    this.quantite,
    this.cochePar,
  });

  factory ArticleCourse.depuisJson(Map<String, dynamic> json) => ArticleCourse(
        id: json['id'] as String,
        libelle: json['libelle'] as String,
        quantite: json['quantite'] as String?,
        ajoutePar: json['ajoute_par'] as String,
        ajouteLe: DateTime.parse(json['ajoute_le'] as String),
        coche: json['coche'] as bool,
        cochePar: json['coche_par'] as String?,
      );

  final String id;
  final String libelle;
  final String? quantite;
  final String ajoutePar;
  final DateTime ajouteLe;
  final bool coche;
  final String? cochePar;

  /// Copie utilisée pour cocher immédiatement à l'écran, avant la réponse du serveur
  ArticleCourse avecCoche(bool valeur, String? par) => ArticleCourse(
        id: id,
        libelle: libelle,
        quantite: quantite,
        ajoutePar: ajoutePar,
        ajouteLe: ajouteLe,
        coche: valeur,
        cochePar: valeur ? par : null,
      );
}

class Message {
  const Message({
    required this.id,
    required this.auteurId,
    required this.contenu,
    required this.envoyeLe,
  });

  factory Message.depuisJson(Map<String, dynamic> json) => Message(
        id: (json['id'] as num).toInt(),
        auteurId: json['auteur_id'] as String,
        contenu: json['contenu'] as String,
        envoyeLe: DateTime.parse(json['envoye_le'] as String),
      );

  final int id;
  final String auteurId;
  final String contenu;
  final DateTime envoyeLe;
}
