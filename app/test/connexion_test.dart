import 'package:colloc/donnees/auth_depot.dart';
import 'package:colloc/vues/auth/connexion_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException;

class FauxAuthDepot implements AuthDepot {
  final connexions = <String>[];
  bool refuser = false;

  @override
  Future<void> connecter({
    required String email,
    required String motDePasse,
  }) async {
    connexions.add(email);
    if (refuser) {
      throw AuthApiException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late FauxAuthDepot auth;

  Future<void> ouvrir(WidgetTester tester) async {
    auth = FauxAuthDepot();
    await tester.pumpWidget(MaterialApp(home: ConnexionPage(auth: auth)));
  }

  testWidgets(
    'e-mail et mot de passe invalides : pas de tentative de connexion',
    (tester) async {
      await ouvrir(tester);
      await tester.enterText(find.byKey(const Key('email')), 'pas-un-email');
      await tester.enterText(find.byKey(const Key('mot_de_passe')), '123');
      await tester.tap(find.byKey(const Key('valider')));
      await tester.pump();

      expect(find.text('Adresse e-mail invalide'), findsOneWidget);
      expect(find.text('Au moins 6 caractères'), findsOneWidget);
      expect(auth.connexions, isEmpty);
    },
  );

  testWidgets('identifiants refusés par le serveur : message en français', (
    tester,
  ) async {
    await ouvrir(tester);
    auth.refuser = true;
    await tester.enterText(find.byKey(const Key('email')), 'alice@colloc.test');
    await tester.enterText(
      find.byKey(const Key('mot_de_passe')),
      'mauvais-mdp',
    );
    await tester.tap(find.byKey(const Key('valider')));
    await tester.pumpAndSettle();

    expect(auth.connexions, ['alice@colloc.test']);
    expect(find.text('E-mail ou mot de passe incorrect.'), findsOneWidget);
  });

  testWidgets("l'inscription demande en plus un pseudo", (tester) async {
    await ouvrir(tester);
    expect(find.byKey(const Key('pseudo')), findsNothing);
    await tester.tap(find.text('Inscription'));
    await tester.pump();
    expect(find.byKey(const Key('pseudo')), findsOneWidget);
  });
}
