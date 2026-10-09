/// Traduction des erreurs techniques en messages compréhensibles.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Vrai si l'erreur vient d'une absence de réseau (et non d'un refus du serveur).
bool estErreurReseau(Object erreur) {
  if (erreur is AuthRetryableFetchException || erreur is TimeoutException) return true;
  if (erreur is PostgrestException || erreur is AuthException || erreur is StorageException) {
    return _ressembleReseau(erreur.toString()) && !_aUnCodeHttp(erreur);
  }
  // SocketException (mobile / bureau), ClientException (web)… sans importer dart:io
  return _ressembleReseau(erreur.toString());
}

bool _aUnCodeHttp(Object erreur) => switch (erreur) {
      PostgrestException(:final code) => code != null,
      AuthException(:final statusCode) => statusCode != null,
      StorageException(:final statusCode) => statusCode != null,
      _ => false,
    };

bool _ressembleReseau(String texte) => RegExp(
      r'SocketException|ClientException|Failed host lookup|Connection (refused|closed|reset|failed)'
      r'|Network is unreachable|XMLHttpRequest|Failed to fetch|HandshakeException|timed out',
      caseSensitive: false,
    ).hasMatch(texte);

/// Message à afficher à l'utilisateur pour [erreur].
String messageErreur(Object erreur) {
  if (estErreurReseau(erreur)) {
    return 'Pas de connexion internet. Réessayez quand le réseau sera revenu.';
  }

  return switch (erreur) {
    AuthException() => _messageAuth(erreur),
    PostgrestException() => _messagePostgrest(erreur),
    StorageException(:final message) when message.contains('size') || message.contains('large') =>
      'Image trop lourde (5 Mo maximum).',
    StorageException(:final message) when message.contains('mime') =>
      "Format d'image non accepté (JPEG, PNG ou WebP).",
    StorageException() => "L'envoi de l'image a échoué.",
    _ => 'Une erreur inattendue est survenue.',
  };
}

String _messageAuth(AuthException e) => switch (e.code) {
      'invalid_credentials' => 'E-mail ou mot de passe incorrect.',
      'user_already_exists' || 'email_exists' => 'Un compte existe déjà avec cet e-mail.',
      'weak_password' => 'Mot de passe trop faible (6 caractères minimum).',
      'email_not_confirmed' => "Confirmez d'abord votre adresse e-mail (lien reçu par mail).",
      'over_email_send_rate_limit' || 'over_request_rate_limit' =>
        'Trop de tentatives. Patientez quelques minutes.',
      'validation_failed' || 'email_address_invalid' => 'Adresse e-mail invalide.',
      _ => 'Authentification impossible : ${e.message}',
    };

String _messagePostgrest(PostgrestException e) {
  // Nos fonctions SQL lèvent des messages déjà rédigés en français : on les affiche tels quels.
  final technique = e.message.startsWith('new row') ||
      e.message.startsWith('permission denied') ||
      e.message.contains('violates');
  if (!technique && const {'42501', 'P0002', '22023', '23514'}.contains(e.code)) return e.message;

  return switch (e.code) {
    '42501' => "Action non autorisée : vous n'avez pas les droits nécessaires.",
    '23514' => 'Valeur refusée par la base (montant ou texte invalide).',
    '23505' => 'Cet élément existe déjà.',
    '23503' => "Cet élément est lié à d'autres données et ne peut pas être modifié.",
    'PGRST116' => 'Élément introuvable (il a peut-être été supprimé).',
    _ => 'Le serveur a refusé la demande.',
  };
}
