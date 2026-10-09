import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthDepot {
  /// Identifiant de l'utilisateur connecté, null si personne n'est connecté
  String? get utilisateurId;

  /// Émet true à la connexion, false à la déconnexion
  Stream<bool> get changements;

  Future<void> connecter({required String email, required String motDePasse});

  /// Renvoie false si le compte doit encore être confirmé par e-mail.
  Future<bool> inscrire({required String email, required String motDePasse, required String pseudo});

  Future<void> deconnecter();
}

class AuthDepotSupabase implements AuthDepot {
  AuthDepotSupabase(this._client);

  final SupabaseClient _client;

  @override
  String? get utilisateurId => _client.auth.currentUser?.id;

  @override
  Stream<bool> get changements =>
      _client.auth.onAuthStateChange.map((etat) => etat.session != null).distinct();

  @override
  Future<void> connecter({required String email, required String motDePasse}) =>
      _client.auth.signInWithPassword(email: email.trim(), password: motDePasse);

  @override
  Future<bool> inscrire({
    required String email,
    required String motDePasse,
    required String pseudo,
  }) async {
    // le pseudo est lu par le trigger SQL qui crée le profil
    final reponse = await _client.auth.signUp(
      email: email.trim(),
      password: motDePasse,
      data: {'pseudo': pseudo.trim()},
    );
    return reponse.session != null;
  }

  @override
  Future<void> deconnecter() => _client.auth.signOut();
}
