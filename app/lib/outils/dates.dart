/// Formatage des dates en français, sans dépendance externe.
library;

const _jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _mois = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

DateTime jourSeul(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime aujourdhui() => jourSeul(DateTime.now());

/// « lun. 12 oct. » (l'année n'est affichée que si ce n'est pas l'année en cours)
String formaterDate(DateTime d) {
  final annee = d.year == DateTime.now().year ? '' : ' ${d.year}';
  return '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]}$annee';
}

/// « aujourd'hui », « demain », « hier », « dans 3 jours », « il y a 5 jours »
String formaterEcheance(DateTime echeance) {
  final ecart = jourSeul(echeance).difference(aujourdhui()).inDays;
  return switch (ecart) {
    0 => "aujourd'hui",
    1 => 'demain',
    -1 => 'hier',
    > 1 => 'dans $ecart jours',
    _ => 'il y a ${-ecart} jours',
  };
}

/// « 14:05 » pour aujourd'hui, sinon « lun. 12 oct., 14:05 »
String formaterHorodatage(DateTime d) {
  final local = d.toLocal();
  final heure = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return jourSeul(local) == aujourdhui() ? heure : '${formaterDate(local)}, $heure';
}

String nomDuMois(int mois) => _mois[mois - 1];

/// Format attendu par Postgres pour une colonne `date` : « 2026-10-09 »
String dateVersSql(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
