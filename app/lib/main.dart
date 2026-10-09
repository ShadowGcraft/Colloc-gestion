import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import 'app.dart';
import 'config.dart';
import 'donnees/depots.dart';
import 'etat/reseau.dart';
import 'etat/services.dart';
import 'etat/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Config.estComplete) {
    runApp(const ConfigurationManquante());
    return;
  }

  await Supabase.initialize(
    url: Config.url,
    publishableKey: Config.clePublique,
  );
  final client = Supabase.instance.client;

  final depots = Depots.supabase(client);
  final reseau = EtatReseau(
    sonde: () => client.from('profils').select('id').limit(1),
  );

  runApp(
    ColocApp(
      services: Services(
        depots: depots,
        session: Session(depots, reseau),
        reseau: reseau,
      ),
    ),
  );
}
