// Tests d'intégration de la couche de données contre un VRAI Supabase local
// (données de supabase/seed.sql). Ils ne font pas partie de `flutter test`.
//
//   supabase db reset            # à la racine du dépôt : base remise à zéro + données de démo
//   cd app && flutter test test_integration --dart-define-from-file=../env.json
@TestOn('vm')
library;

import 'package:colloc/donnees/depots.dart';
import 'package:colloc/modeles/argent.dart';
import 'package:colloc/modeles/vie_commune.dart';
import 'package:colloc/outils/simplification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

const _url = String.fromEnvironment('SUPABASE_URL');
const _cle = String.fromEnvironment('SUPABASE_ANON_KEY');
const _alpes = '11111111-0000-4000-8000-000000000001';
const _alice = 'aaaaaaaa-0000-4000-8000-000000000001';
const _bob = 'bbbbbbbb-0000-4000-8000-000000000002';
const _chloe = 'cccccccc-0000-4000-8000-000000000003';
const _dan = 'dddddddd-0000-4000-8000-000000000004';

/// Un client indépendant par utilisateur, comme deux téléphones différents.
Future<(SupabaseClient, Depots)> connecter(String email) async {
  final client = SupabaseClient(
    _url,
    _cle,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final depots = Depots.supabase(client);
  await depots.auth.connecter(email: email, motDePasse: 'motdepasse123');
  return (client, depots);
}

void main() {
  if (_url.isEmpty || !_url.contains('127.0.0.1')) {
    test(
      'configuration',
      () => fail(
        'Lancez avec --dart-define-from-file=../env.json pointant vers le Supabase LOCAL',
      ),
    );
    return;
  }

  late SupabaseClient clientAlice;
  late Depots alice;
  late Depots bob;
  late Depots eve;

  setUpAll(() async {
    (clientAlice, alice) = await connecter('alice@colloc.test');
    (_, bob) = await connecter('bob@colloc.test');
    (_, eve) = await connecter('eve@colloc.test');
  });

  test('colocations et membres (avec profils embarqués)', () async {
    final colocs = await alice.colocs.mesColocations();
    expect(colocs.map((c) => c.nom), ['Coloc des Alpes']);
    expect(colocs.single.suisAdmin, isTrue);

    final membres = await alice.colocs.membres(_alpes);
    expect(membres.map((m) => m.pseudo), ['Alice', 'Bob', 'Chloé', 'Dan']);
  });

  test('jalon 2 : Ève ne voit rien de la coloc des Alpes', () async {
    expect(await eve.depenses.depenses(_alpes), isEmpty);
    expect(await eve.colocs.membres(_alpes), isEmpty);
    expect(await eve.depenses.soldes(_alpes), isEmpty);
    expect(await eve.chat.messages(_alpes), isEmpty);
    await expectLater(
      eve.colocs.rejoindre('MAUVAISCOD'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('jalon 3 : soldes du jeu de test et virements minimaux', () async {
    final depenses = await alice.depenses.depenses(_alpes);
    expect(depenses, hasLength(5));
    expect(depenses.firstWhere((d) => d.description == 'Pizzas').parts, {
      _alice: 1234,
      _chloe: 1233,
      _dan: 1233,
    });

    final soldes = {
      for (final s in await alice.depenses.soldes(_alpes))
        s.utilisateurId: s.centimes,
    };
    expect(soldes, {_alice: 1911, _bob: 4135, _chloe: -2398, _dan: -3648});
    expect(simplifierDettes(soldes), hasLength(3));
  });

  test('dépense avec photo du ticket, puis remboursement', () async {
    final id = await alice.depenses.creer(
      NouvelleDepense(
        colocationId: _alpes,
        payeurId: _alice,
        montantCentimes: 1000,
        description: 'Test intégration',
        date: DateTime.now(),
        participants: [_alice, _bob],
        ticket: const PhotoTicket(
          octets: [0xFF, 0xD8, 0xFF, 0xD9],
          typeMime: 'image/jpeg',
        ),
      ),
    );
    final creee = (await alice.depenses.depenses(_alpes))
        .firstWhere((d) => d.id == id);
    expect(creee.parts, {_alice: 500, _bob: 500});
    expect(creee.ticketChemin, startsWith('$_alpes/'));
    expect(
      await bob.depenses.urlTicket(creee.ticketChemin!),
      contains('/storage/v1/object/sign/tickets/'),
    );
    await expectLater(
      eve.depenses.urlTicket(creee.ticketChemin!),
      throwsA(isA<StorageException>()),
    );

    await bob.depenses.rembourser(
      _alpes,
      const Virement(de: _bob, vers: _alice, montant: 500),
    );
    final remboursements = await alice.depenses.remboursements(_alpes);
    expect(remboursements.first.montantCentimes, 500);

    // nettoyage : la base revient à l'état du jeu de test
    await bob.depenses.annulerRemboursement(remboursements.first.id);
    await alice.depenses.supprimer(creee);
    final soldes = {
      for (final s in await alice.depenses.soldes(_alpes))
        s.utilisateurId: s.centimes,
    };
    expect(soldes[_alice], 1911);
  });

  test('temps réel : Alice voit en direct l\'article ajouté, coché puis supprimé par Bob', () async {
    final recus = <Evenement<ArticleCourse>>[];
    final ecoute = EcouteSupabase<ArticleCourse>(
      clientAlice,
      table: 'articles_courses',
      colocationId: _alpes,
      convertir: ArticleCourse.depuisJson,
      surEvenement: recus.add,
    );
    await ecoute.pret.timeout(const Duration(seconds: 15));

    /// Attend qu'un évènement vérifiant [critere] soit reçu (false au bout de [delai]).
    Future<bool> attendre(
      bool Function(Evenement<ArticleCourse>) critere, {
      int delai = 10,
    }) async {
      for (var i = 0; i < delai * 10; i++) {
        if (recus.any(critere)) return true;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return false;
    }

    // Juste après `supabase db reset`, Realtime démarre « à froid » et peut manquer
    // les tout premiers changements : on envoie une sonde jusqu'à la recevoir.
    for (var essai = 1; ; essai++) {
      final sonde = await bob.courses.ajouter(_alpes, 'sonde $essai', null);
      final recu = await attendre(
        (e) => e is Ajout<ArticleCourse> && e.element.id == sonde.id,
        delai: 3,
      );
      await bob.courses.supprimer([sonde.id]);
      if (recu) break;
      if (essai == 10) fail('Realtime ne délivre aucun évènement');
    }

    final article = await bob.courses.ajouter(
      _alpes,
      'Café (test temps réel)',
      null,
    );
    expect(
      await attendre(
        (e) => e is Ajout<ArticleCourse> && e.element.id == article.id,
      ),
      isTrue,
    );

    await bob.courses.cocher(article.id, true);
    expect(
      await attendre(
        (e) => e is Modification<ArticleCourse> && e.element.id == article.id,
      ),
      isTrue,
    );
    final coche = recus.whereType<Modification<ArticleCourse>>().last.element;
    expect(coche.coche, isTrue);
    expect(
      coche.cochePar,
      _bob,
      reason: 'rempli par le trigger, pas par le client',
    );

    await bob.courses.supprimer([article.id]);
    expect(
      await attendre(
        (e) => e is Suppression<ArticleCourse> && e.id == article.id,
      ),
      isTrue,
    );

    await ecoute.fermer();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('chat : pagination par clé et messages non lus', () async {
    final page1 = await alice.chat.messages(_alpes, limite: 30);
    final page2 = await alice.chat.messages(
      _alpes,
      avantId: page1.last.id,
      limite: 30,
    );
    expect(page1, hasLength(30));
    expect(page2.first.id, lessThan(page1.last.id));
    expect({
      ...page1.map((m) => m.id),
      ...page2.map((m) => m.id),
    }, hasLength(60));

    await alice.chat.marquerLu(_alpes, page1.first.id);
    expect(await alice.chat.nombreNonLus(_alpes), 0);
    final message = await bob.chat.envoyer(_alpes, 'Coucou (test)');
    expect(await alice.chat.nombreNonLus(_alpes), 1);
    await bob.chat.supprimer(message.id);
  });

  test(
    'tâches : « fait » avance la rotation et remplit l\'historique',
    () async {
      final tache = (await alice.taches.taches(_alpes))
          .firstWhere((t) => t.titre == 'Vaisselle');
      final suivante = await alice.taches.terminer(tache.id);
      expect(suivante.responsableId, isNot(tache.responsableId));
      expect(
        suivante.prochaineEcheance.isAfter(tache.prochaineEcheance),
        isTrue,
      );
      final historique = await alice.taches.historique(tache.id);
      expect(historique.first.faitPar, _alice);
      expect(historique.first.responsablePrevu, tache.responsableId);
      expect(tache.frequence, Frequence.quotidienne);
    },
  );
}
