import 'package:colloc/donnees/depense_depot.dart';
import 'package:colloc/modeles/argent.dart';
import 'package:colloc/modeles/coloc.dart';
import 'package:colloc/vues/depenses/nouvelle_depense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faux dépôt : enregistre ce que le formulaire lui envoie, sans réseau.
class FauxDepenseDepot implements DepenseDepot {
  final recues = <NouvelleDepense>[];

  @override
  Future<String> creer(NouvelleDepense depense) async {
    recues.add(depense);
    return 'nouvelle-depense';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Membre membre(String id, String pseudo) => Membre(
  utilisateurId: id,
  pseudo: pseudo,
  role: Role.membre,
  rejointLe: DateTime(2026),
);

void main() {
  late FauxDepenseDepot depot;

  Future<void> ouvrirFormulaire(WidgetTester tester) async {
    depot = FauxDepenseDepot();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: NouvelleDepensePage(
          depot: depot,
          colocationId: 'coloc',
          moi: 'a',
          membres: [
            membre('a', 'Alice'),
            membre('b', 'Bob'),
            membre('c', 'Chloé'),
          ],
        ),
      ),
    );
  }

  Future<void> enregistrer(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('enregistrer')));
    await tester.tap(find.byKey(const Key('enregistrer')));
    await tester.pumpAndSettle();
  }

  testWidgets('formulaire vide : erreurs affichées et rien n\'est envoyé', (
    tester,
  ) async {
    await ouvrirFormulaire(tester);
    await enregistrer(tester);

    expect(find.text('Montant invalide (ex. 12,50)'), findsOneWidget);
    expect(find.text('Décrivez la dépense'), findsOneWidget);
    expect(depot.recues, isEmpty);
  });

  testWidgets(
    'parts égales : 10 € entre 3 affiche 3,34 € / 3,33 € / 3,33 € et envoie la dépense',
    (tester) async {
      await ouvrirFormulaire(tester);
      await tester.enterText(find.byKey(const Key('montant')), '10');
      await tester.enterText(find.byKey(const Key('description')), 'Pizza');
      await tester.pump();

      expect(find.text('3,34 €'), findsOneWidget);
      expect(find.text('3,33 €'), findsNWidgets(2));

      await enregistrer(tester);
      expect(depot.recues, hasLength(1));
      final envoyee = depot.recues.single;
      expect(envoyee.montantCentimes, 1000);
      expect(envoyee.payeurId, 'a');
      expect(envoyee.participants, ['a', 'b', 'c']);
      expect(
        envoyee.montantsPersonnalises,
        isNull,
        reason: 'la base calcule les parts égales',
      );
    },
  );

  testWidgets(
    'parts personnalisées : refusées tant que la somme ne fait pas le total',
    (tester) async {
      await ouvrirFormulaire(tester);
      await tester.enterText(find.byKey(const Key('montant')), '30');
      await tester.enterText(find.byKey(const Key('description')), 'Courses');
      await tester.tap(find.byKey(const Key('mode_personnalise')));
      await tester.pump();

      // Chloé ne participe pas
      await tester.tap(find.byKey(const Key('participant_c')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('part_a')), '10');
      await tester.enterText(find.byKey(const Key('part_b')), '15');
      await tester.pump();
      expect(find.text('Reste à répartir : 5,00 €'), findsOneWidget);

      await enregistrer(tester);
      expect(find.byKey(const Key('erreur_repartition')), findsOneWidget);
      expect(depot.recues, isEmpty);

      await tester.enterText(find.byKey(const Key('part_b')), '20');
      await enregistrer(tester);
      expect(depot.recues, hasLength(1));
      expect(depot.recues.single.participants, ['a', 'b']);
      expect(depot.recues.single.montantsPersonnalises, [1000, 2000]);
    },
  );

  testWidgets('aucun participant : la dépense est refusée', (tester) async {
    await ouvrirFormulaire(tester);
    await tester.enterText(find.byKey(const Key('montant')), '12');
    await tester.enterText(find.byKey(const Key('description')), 'Test');
    for (final id in ['a', 'b', 'c']) {
      await tester.tap(find.byKey(Key('participant_$id')));
    }
    await enregistrer(tester);

    expect(find.text('Choisissez au moins un participant.'), findsOneWidget);
    expect(depot.recues, isEmpty);
  });
}
