/// Profils, colocations et membres : qui fait partie de quoi.
library;

class Profil {
  const Profil({required this.id, required this.pseudo, this.avatarChemin});

  factory Profil.depuisJson(Map<String, dynamic> json) => Profil(
        id: json['id'] as String,
        pseudo: json['pseudo'] as String,
        avatarChemin: json['avatar_chemin'] as String?,
      );

  final String id;
  final String pseudo;
  final String? avatarChemin;
}

enum Role { admin, membre }

class Colocation {
  const Colocation({
    required this.id,
    required this.nom,
    required this.codeInvitation,
    required this.monRole,
  });

  /// Ligne de `membres` avec la coloc embarquée : `role, colocation:colocations(*)`
  factory Colocation.depuisAppartenance(Map<String, dynamic> json) {
    final coloc = json['colocation'] as Map<String, dynamic>;
    return Colocation(
      id: coloc['id'] as String,
      nom: coloc['nom'] as String,
      codeInvitation: coloc['code_invitation'] as String,
      monRole: Role.values.byName(json['role'] as String),
    );
  }

  final String id;
  final String nom;
  final String codeInvitation;
  final Role monRole;

  bool get suisAdmin => monRole == Role.admin;

  /// « GAPDE-MXV27 » : plus facile à dicter (la base accepte avec ou sans tiret)
  String get codeLisible => '${codeInvitation.substring(0, 5)}-${codeInvitation.substring(5)}';
}

class Membre {
  const Membre({
    required this.utilisateurId,
    required this.pseudo,
    required this.role,
    required this.rejointLe,
    this.avatarChemin,
    this.partiLe,
    this.dernierMessageLuId,
  });

  /// Ligne de `membres` avec le profil embarqué : `*, profil:profils(pseudo, avatar_chemin)`
  factory Membre.depuisJson(Map<String, dynamic> json) {
    final profil = json['profil'] as Map<String, dynamic>?;
    return Membre(
      utilisateurId: json['utilisateur_id'] as String,
      pseudo: profil?['pseudo'] as String? ?? 'Ancien membre',
      avatarChemin: profil?['avatar_chemin'] as String?,
      role: Role.values.byName(json['role'] as String),
      rejointLe: DateTime.parse(json['rejoint_le'] as String),
      partiLe: json['parti_le'] == null ? null : DateTime.parse(json['parti_le'] as String),
      dernierMessageLuId: (json['dernier_message_lu_id'] as num?)?.toInt(),
    );
  }

  final String utilisateurId;
  final String pseudo;
  final String? avatarChemin;
  final Role role;
  final DateTime rejointLe;
  final DateTime? partiLe;
  final int? dernierMessageLuId;

  bool get estActif => partiLe == null;
  bool get estAdmin => role == Role.admin;
}
