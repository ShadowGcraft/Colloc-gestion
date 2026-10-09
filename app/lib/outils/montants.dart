/// Conversion entre centimes (entiers, utilisés partout dans l'app et en base)
/// et texte en euros (uniquement pour l'affichage et la saisie).
library;

/// 123456 → « 1 234,56 € » ; -500 → « -5,00 € ».
String formaterEuros(int centimes, {bool signe = false}) {
  final negatif = centimes < 0;
  final absolu = centimes.abs();
  final euros = (absolu ~/ 100).toString();
  final reste = (absolu % 100).toString().padLeft(2, '0');

  // séparateur de milliers : espace fine insécable, comme en français
  final groupes = StringBuffer();
  for (var i = 0; i < euros.length; i++) {
    if (i > 0 && (euros.length - i) % 3 == 0) groupes.write(' ');
    groupes.write(euros[i]);
  }

  final prefixe = negatif ? '-' : (signe && centimes > 0 ? '+' : '');
  return '$prefixe$groupes,$reste €';
}

/// Lit une saisie utilisateur (« 12 », « 12,5 », « 12.50 », « 1 234,56 ») en centimes.
/// Renvoie null si la saisie n'est pas un montant valide (plus de 2 décimales, lettres…).
int? lireMontant(String saisie) {
  final texte = saisie.replaceAll(RegExp(r'[\s  €]'), '').replaceAll(',', '.');
  final correspondance = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$').firstMatch(texte);
  if (correspondance == null) return null;

  final euros = int.parse(correspondance.group(1)!);
  final decimales = (correspondance.group(2) ?? '').padRight(2, '0');
  return euros * 100 + int.parse(decimales);
}

/// Affiche des centimes sous une forme modifiable dans un champ (« 12,50 »).
String centimesVersSaisie(int centimes) =>
    '${centimes ~/ 100},${(centimes % 100).toString().padLeft(2, '0')}';
