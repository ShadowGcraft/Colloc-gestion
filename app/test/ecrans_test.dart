// Parcourt tous les écrans de l'application avec de fausses données, au format
// téléphone, en thème clair puis sombre : le test échoue au moindre débordement
// d'affichage ou à la moindre exception.
//
// Captures d'écran (pour la soutenance) :
//   flutter test test/ecrans_test.dart --update-goldens --dart-define=CAPTURES=true
// → images dans test/captures/
import 'dart:io';

import 'package:colloc/app.dart';
import 'package:colloc/etat/reseau.dart';
import 'package:colloc/etat/services.dart';
import 'package:colloc/etat/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'faux_depots.dart';

const _captures = bool.fromEnvironment('CAPTURES');

Future<void> _chargerPolices() async {
  final racine =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dossier = '$racine/bin/cache/artifacts/material_fonts';
  Future<void> charger(String famille, List<String> fichiers) async {
    final chargeur = FontLoader(famille);
    for (final f in fichiers) {
      chargeur.addFont(
        File('$dossier/$f').readAsBytes().then((o) => ByteData.view(o.buffer)),
      );
    }
    await chargeur.load();
  }

  await charger('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await charger('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  setUpAll(() async {
    if (_captures) await _chargerPolices();
  });

  for (final luminosite in Brightness.values) {
    final theme = luminosite == Brightness.dark ? 'sombre' : 'clair';

    testWidgets('tous les écrans s\'affichent sans erreur (thème $theme)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(
        1170,
        2532,
      ); // iPhone 14 : 390 × 844 points
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue = luminosite;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final depots = fauxDepots();
      final reseau = EtatReseau(sonde: () async {});
      final services = Services(
        depots: depots,
        session: Session(depots, reseau),
        reseau: reseau,
      );
      await tester.pumpWidget(ColocApp(services: services));
      await tester.pumpAndSettle();

      Future<void> capture(String nom) async {
        if (_captures) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('captures/$theme-$nom.png'),
          );
        }
      }

      Future<void> ouvrir(Finder cible) async {
        await tester.tap(cible);
        await tester.pumpAndSettle();
      }

      // (tester.pageBack() cherche l'info-bulle anglaise « Back » ; l'app est en français)
      Future<void> retour() => ouvrir(find.byTooltip('Retour'));

      Future<void> menu(String entree) async {
        await ouvrir(find.byTooltip('Menu'));
        await ouvrir(find.text(entree));
      }

      // Dépenses
      expect(find.text('Coloc des Alpes'), findsOneWidget);
      expect(find.text('Courses Carrefour'), findsOneWidget);
      await capture('1-depenses');

      await ouvrir(find.text('Courses Carrefour'));
      expect(find.text('Répartition'), findsOneWidget);
      await capture('2-detail-depense');
      await retour();

      await ouvrir(find.text('Soldes et remboursements'));
      expect(
        find.text('3 virements suffisent pour que tout le monde soit quitte.'),
        findsOneWidget,
      );
      await capture('3-soldes');
      await retour();

      await ouvrir(find.text('Dépense'));
      expect(find.text('Nouvelle dépense'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('montant')), '84,60');
      await tester.pumpAndSettle();
      await capture('4-nouvelle-depense');
      await retour();

      // Onglets
      await ouvrir(find.text('Tâches'));
      expect(find.text('En retard de 2 jours'), findsOneWidget);
      expect(find.text("C'est votre tour !"), findsOneWidget);
      await capture('5-taches');

      await ouvrir(find.byTooltip('Plus').first);
      await ouvrir(find.text('Historique'));
      expect(find.text('Faite par Chloé'), findsOneWidget);
      await retour();

      await ouvrir(find.text('Courses'));
      expect(find.text('Coché par Chloé'), findsOneWidget);
      await capture('6-courses');

      await ouvrir(find.text('Chat'));
      expect(find.text('Nouveaux messages'), findsOneWidget);
      await capture('7-chat');

      // Menu
      await menu('Paramètres de la coloc');
      expect(find.text('GAPDE-MXV27'), findsOneWidget);
      expect(find.text('Anciens membres'), findsOneWidget);
      await capture('8-parametres');
      await retour();

      await menu('Statistiques');
      expect(find.text('Dépenses par mois'), findsOneWidget);
      await capture('9-statistiques');
      await retour();

      await menu('Changer de colocation');
      expect(find.text('Appart de Gap'), findsOneWidget);
      await retour();

      await menu('Mon profil');
      expect(find.text('Se déconnecter'), findsOneWidget);
      await retour();

      // Mode hors connexion : le bandeau apparaît
      reseau.signalerErreur(Exception('SocketException: Failed host lookup'));
      await tester.pump();
      expect(find.textContaining('Hors connexion'), findsOneWidget);
      // annoncé aux lecteurs d'écran (région « vivante »)
      final semantique = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp('Hors connexion')),
        findsOneWidget,
      );
      semantique.dispose();
      await capture('10-hors-connexion');
      reseau.dispose();
    });
  }
}
