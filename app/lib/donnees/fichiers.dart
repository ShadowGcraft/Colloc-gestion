import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Les buckets sont privés : on affiche les images par URL signée (valable 1 h),
/// mises en cache pour ne pas en redemander une à chaque affichage.
class UrlsSignees {
  UrlsSignees(this._client);

  final SupabaseClient _client;
  final _cache = <String, (String, DateTime)>{};

  static const _duree = Duration(hours: 1);

  Future<String> pour(String bucket, String chemin) async {
    final cle = '$bucket/$chemin';
    final enCache = _cache[cle];
    if (enCache != null &&
        enCache.$2.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return enCache.$1;
    }
    final url = await _client.storage
        .from(bucket)
        .createSignedUrl(chemin, _duree.inSeconds);
    _cache[cle] = (url, DateTime.now().add(_duree));
    return url;
  }
}

Future<String> envoyerImage(
  SupabaseClient client, {
  required String bucket,
  required String dossier,
  required List<int> octets,
  required String typeMime,
}) async {
  final extension = switch (typeMime) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => 'jpg',
  };
  final chemin = '$dossier/${nouvelIdentifiant()}.$extension';
  await client.storage
      .from(bucket)
      .uploadBinary(
        chemin,
        Uint8List.fromList(octets),
        fileOptions: FileOptions(contentType: typeMime),
      );
  return chemin;
}

/// Supprime un fichier sans faire échouer l'action principale (simple ménage).
Future<void> supprimerSansErreur(
  SupabaseClient client,
  String bucket,
  String chemin,
) async {
  try {
    await client.storage.from(bucket).remove([chemin]);
  } catch (_) {
    // fichier orphelin au pire : sans conséquence pour l'utilisateur
  }
}

/// UUID v4 aléatoire (source cryptographique), pour nommer les fichiers.
String nouvelIdentifiant() {
  final aleatoire = Random.secure();
  final octets = List<int>.generate(16, (_) => aleatoire.nextInt(256));
  octets[6] = (octets[6] & 0x0f) | 0x40;
  octets[8] = (octets[8] & 0x3f) | 0x80;
  final hex = octets.map((o) => o.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
