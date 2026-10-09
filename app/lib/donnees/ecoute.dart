/// Abonnements temps réel (Supabase Realtime), limités à une colocation.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Évènement reçu sur une table suivie en temps réel.
sealed class Evenement<T> {
  const Evenement();
}

class Ajout<T> extends Evenement<T> {
  const Ajout(this.element);
  final T element;
}

class Modification<T> extends Evenement<T> {
  const Modification(this.element);
  final T element;
}

class Suppression<T> extends Evenement<T> {
  const Suppression(this.id);
  final Object id;
}

/// Un abonnement en cours, à fermer quand l'écran se ferme.
abstract interface class Ecoute {
  Future<void> fermer();
}

/// Suit les changements d'une table pour UNE colocation.
///
/// - INSERT et UPDATE : filtrés côté serveur par `colocation_id` ET par la RLS.
/// - DELETE : Supabase ne sait pas les filtrer (la ligne n'existe plus) ; on ne
///   reçoit que l'identifiant et l'écran ignore ceux qu'il ne connaît pas.
/// - Après une coupure, le client se réabonne tout seul : [surReconnexion]
///   permet alors de recharger ce qui a été manqué pendant la coupure.
class EcouteSupabase<T> implements Ecoute {
  EcouteSupabase(
    this._client, {
    required String table,
    required String colocationId,
    required T Function(Map<String, dynamic>) convertir,
    required void Function(Evenement<T>) surEvenement,
    void Function()? surReconnexion,
    void Function()? surCoupure,
  }) {
    final filtre = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'colocation_id',
      value: colocationId,
    );
    _canal = _client
        .channel('$table:$colocationId:${_numero++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: table,
          filter: filtre,
          callback: (p) => surEvenement(Ajout(convertir(p.newRecord))),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: table,
          filter: filtre,
          callback: (p) => surEvenement(Modification(convertir(p.newRecord))),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: table,
          callback: (p) {
            final id = p.oldRecord['id'];
            if (id != null) surEvenement(Suppression(id as Object));
          },
        )
        .subscribe((statut, _) {
          switch (statut) {
            case RealtimeSubscribeStatus.subscribed:
              if (_dejaConnecte) surReconnexion?.call();
              _dejaConnecte = true;
              if (!_pret.isCompleted) _pret.complete();
            case RealtimeSubscribeStatus.channelError ||
                RealtimeSubscribeStatus.timedOut:
              surCoupure?.call();
            case RealtimeSubscribeStatus.closed:
              break;
          }
        });
  }

  static var _numero = 0;

  final SupabaseClient _client;
  late final RealtimeChannel _canal;
  var _dejaConnecte = false;
  final _pret = Completer<void>();

  /// Se termine quand le serveur a confirmé l'abonnement
  Future<void> get pret => _pret.future;

  @override
  Future<void> fermer() => _client.removeChannel(_canal);
}
