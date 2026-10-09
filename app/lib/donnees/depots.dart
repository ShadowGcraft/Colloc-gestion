import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_depot.dart';
import 'coloc_depot.dart';
import 'depense_depot.dart';
import 'fichiers.dart';
import 'vie_commune_depot.dart';

export 'auth_depot.dart';
export 'coloc_depot.dart';
export 'depense_depot.dart';
export 'ecoute.dart';
export 'vie_commune_depot.dart';

/// Tous les points d'accès aux données. L'interface ne connaît que ces
/// interfaces : jamais Supabase directement (ce qui permet de la tester avec
/// de faux dépôts).
class Depots {
  const Depots({
    required this.auth,
    required this.colocs,
    required this.depenses,
    required this.taches,
    required this.courses,
    required this.chat,
  });

  factory Depots.supabase(SupabaseClient client) {
    final urls = UrlsSignees(client);
    return Depots(
      auth: AuthDepotSupabase(client),
      colocs: ColocDepotSupabase(client, urls),
      depenses: DepenseDepotSupabase(client, urls),
      taches: TacheDepotSupabase(client),
      courses: CoursesDepotSupabase(client),
      chat: ChatDepotSupabase(client),
    );
  }

  final AuthDepot auth;
  final ColocDepot colocs;
  final DepenseDepot depenses;
  final TacheDepot taches;
  final CoursesDepot courses;
  final ChatDepot chat;
}
