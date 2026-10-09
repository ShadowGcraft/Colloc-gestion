// Faux dépôts en mémoire : permettent d'afficher tous les écrans dans les tests,
// sans réseau ni Supabase.
import 'package:colloc/donnees/depots.dart';
import 'package:colloc/modeles/argent.dart';
import 'package:colloc/modeles/coloc.dart';
import 'package:colloc/modeles/vie_commune.dart';
import 'package:colloc/outils/dates.dart';
import 'package:colloc/outils/simplification.dart';

const alice = 'a', bob = 'b', chloe = 'c', dan = 'd';
const colocId = 'coloc-alpes';

class _Ecoute implements Ecoute {
  @override
  Future<void> fermer() async {}
}

class FauxAuth implements AuthDepot {
  @override
  String? get utilisateurId => alice;
  @override
  Stream<bool> get changements => const Stream.empty();
  @override
  Future<void> connecter({
    required String email,
    required String motDePasse,
  }) async {}
  @override
  Future<bool> inscrire({
    required String email,
    required String motDePasse,
    required String pseudo,
  }) async => true;
  @override
  Future<void> deconnecter() async {}
}

class FauxColocs implements ColocDepot {
  final _membres = [
    Membre(
      utilisateurId: alice,
      pseudo: 'Alice',
      role: Role.admin,
      rejointLe: DateTime(2026, 9),
    ),
    Membre(
      utilisateurId: bob,
      pseudo: 'Bob',
      role: Role.membre,
      rejointLe: DateTime(2026, 9, 2),
    ),
    Membre(
      utilisateurId: chloe,
      pseudo: 'Chloé',
      role: Role.membre,
      rejointLe: DateTime(2026, 9, 3),
    ),
    Membre(
      utilisateurId: dan,
      pseudo: 'Dan',
      role: Role.membre,
      rejointLe: DateTime(2026, 9, 4),
    ),
    Membre(
      utilisateurId: 'e',
      pseudo: 'Ève',
      role: Role.membre,
      rejointLe: DateTime(2026, 9, 5),
      partiLe: DateTime(2026, 10, 1),
    ),
  ];

  @override
  Future<Profil> monProfil() async => const Profil(id: alice, pseudo: 'Alice');
  @override
  Future<List<Colocation>> mesColocations() async => const [
    Colocation(
      id: colocId,
      nom: 'Coloc des Alpes',
      codeInvitation: 'GAPDEMXV27',
      monRole: Role.admin,
    ),
    Colocation(
      id: 'autre',
      nom: 'Appart de Gap',
      codeInvitation: 'HJKLMN2345',
      monRole: Role.membre,
    ),
  ];
  @override
  Future<List<Membre>> membres(String colocationId) async => _membres;
  @override
  Future<String> urlAvatar(String chemin) async => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class FauxDepenses implements DepenseDepot {
  @override
  Future<List<Depense>> depenses(
    String colocationId, {
    int debut = 0,
    int taille = 30,
  }) async => [
    Depense(
      id: '1',
      payeurId: alice,
      montantCentimes: 8460,
      description: 'Courses Carrefour',
      date: aujourdhui(),
      creePar: alice,
      ticketChemin: '$colocId/ticket.jpg',
      parts: const {alice: 2115, bob: 2115, chloe: 2115, dan: 2115},
    ),
    Depense(
      id: '2',
      payeurId: bob,
      montantCentimes: 12000,
      description: 'Électricité — facture de septembre (très longue description pour tester)',
      date: aujourdhui().subtract(const Duration(days: 9)),
      creePar: bob,
      parts: const {alice: 4000, bob: 4000, chloe: 2000, dan: 2000},
    ),
  ];
  @override
  Future<List<Solde>> soldes(String colocationId) async => const [
    Solde(utilisateurId: alice, centimes: 1911, aQuitte: false),
    Solde(utilisateurId: bob, centimes: 4135, aQuitte: false),
    Solde(utilisateurId: chloe, centimes: -2398, aQuitte: false),
    Solde(utilisateurId: dan, centimes: -3648, aQuitte: false),
  ];
  @override
  Future<List<Remboursement>> remboursements(String colocationId) async => [
    Remboursement(
      id: 'r1',
      debiteurId: dan,
      crediteurId: alice,
      montantCentimes: 1500,
      creePar: alice,
      creeLe: DateTime.now(),
    ),
  ];
  @override
  Future<List<Depense>> resumePourStatistiques(String colocationId) async => [
    for (var i = 0; i < 12; i++)
      Depense(
        id: 's$i',
        payeurId: [alice, bob, chloe, dan][i % 4],
        montantCentimes: 1500 + i * 1700,
        description: 'Dépense $i',
        date: DateTime(DateTime.now().year, DateTime.now().month - (i % 6), 5),
        creePar: alice,
        parts: const {},
      ),
  ];
  @override
  Future<String> urlTicket(String chemin) => Future.error('hors ligne');
  @override
  Future<void> rembourser(String colocationId, Virement virement) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class FauxTaches implements TacheDepot {
  @override
  Future<List<Tache>> taches(String colocationId) async => [
    Tache(
      id: 't1',
      titre: 'Sortir les poubelles',
      frequence: Frequence.hebdomadaire,
      responsableId: bob,
      prochaineEcheance: aujourdhui().subtract(const Duration(days: 2)),
      creePar: alice,
    ),
    Tache(
      id: 't2',
      titre: 'Vaisselle',
      frequence: Frequence.quotidienne,
      responsableId: alice,
      prochaineEcheance: aujourdhui(),
      creePar: alice,
    ),
  ];
  @override
  Future<List<RealisationTache>> historique(String tacheId) async => [
    RealisationTache(
      faitPar: chloe,
      responsablePrevu: bob,
      echeance: aujourdhui().subtract(const Duration(days: 9)),
      enRetard: true,
      faitLe: DateTime.now().subtract(const Duration(days: 7)),
    ),
  ];
  @override
  Ecoute ecouter(String colocationId, Rappels<Tache> rappels) => _Ecoute();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class FauxCourses implements CoursesDepot {
  @override
  Future<List<ArticleCourse>> articles(String colocationId) async => [
    ArticleCourse(
      id: 'c1',
      libelle: 'Lait',
      quantite: '2 L',
      ajoutePar: alice,
      ajouteLe: DateTime(2026),
      coche: false,
    ),
    ArticleCourse(
      id: 'c2',
      libelle: 'Pâtes',
      ajoutePar: bob,
      ajouteLe: DateTime(2026),
      coche: false,
    ),
    ArticleCourse(
      id: 'c3',
      libelle: 'Café',
      ajoutePar: dan,
      ajouteLe: DateTime(2026),
      coche: true,
      cochePar: chloe,
    ),
  ];
  @override
  Ecoute ecouter(String colocationId, Rappels<ArticleCourse> rappels) =>
      _Ecoute();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class FauxChat implements ChatDepot {
  @override
  Future<List<Message>> messages(
    String colocationId, {
    int? avantId,
    int limite = 30,
  }) async => [
    for (var i = 12; i >= 1; i--)
      Message(
        id: i,
        auteurId: [alice, bob, chloe, dan][i % 4],
        contenu: i == 12
            ? 'Qui a fini le café ??? Il en faut pour demain matin, merci !'
            : 'Message n° $i',
        envoyeLe: DateTime.now().subtract(Duration(minutes: 13 - i)),
      ),
  ];
  @override
  Future<int?> dernierLu(String colocationId) async => 9;
  @override
  Future<int> nombreNonLus(String colocationId) async => 3;
  @override
  Ecoute ecouter(String colocationId, Rappels<Message> rappels) => _Ecoute();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

Depots fauxDepots() => Depots(
  auth: FauxAuth(),
  colocs: FauxColocs(),
  depenses: FauxDepenses(),
  taches: FauxTaches(),
  courses: FauxCourses(),
  chat: FauxChat(),
);
