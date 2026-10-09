/// Simplification des dettes : à partir des soldes, trouver le MINIMUM de
/// virements qui remet tout le monde à zéro (voir DECISIONS.md, D6).
///
/// Idée : si l'on découpe les membres non soldés en k groupes dont la somme
/// vaut 0, chaque groupe de taille t se règle en t − 1 virements, soit
/// n − k virements au total. Minimiser les virements revient donc à
/// MAXIMISER le nombre de groupes à somme nulle, ce que l'on calcule par
/// programmation dynamique sur les sous-ensembles (2ⁿ états).
library;

/// Un virement à effectuer : [de] doit [montant] centimes à [vers].
class Virement {
  const Virement({required this.de, required this.vers, required this.montant});

  final String de;
  final String vers;
  final int montant;

  @override
  bool operator ==(Object other) =>
      other is Virement && other.de == de && other.vers == vers && other.montant == montant;

  @override
  int get hashCode => Object.hash(de, vers, montant);

  @override
  String toString() => '$de → $vers : $montant';
}

/// Au-delà, 2ⁿ devient trop coûteux : on bascule sur l'algorithme glouton.
const tailleMaxRechercheExacte = 15;

/// [soldes] : identifiant → solde en centimes (> 0 : on lui doit ; < 0 : il doit).
/// La somme des soldes doit valoir 0.
List<Virement> simplifierDettes(Map<String, int> soldes) {
  final somme = soldes.values.fold(0, (a, b) => a + b);
  if (somme != 0) {
    throw ArgumentError('La somme des soldes doit valoir 0 (elle vaut $somme).');
  }

  // ordre stable : le résultat ne dépend pas de l'ordre de la Map
  final ids = soldes.keys.where((id) => soldes[id] != 0).toList()..sort();
  if (ids.isEmpty) return [];

  final groupes = ids.length <= tailleMaxRechercheExacte
      ? _groupesASommeNulle(ids, soldes)
      : [ids];

  return [for (final groupe in groupes) ..._reglerGroupe(groupe, soldes)];
}

/// Découpe [ids] en un nombre maximal de groupes dont la somme vaut 0.
List<List<String>> _groupesASommeNulle(List<String> ids, Map<String, int> soldes) {
  final n = ids.length;
  final total = 1 << n;

  // somme[masque] = somme des soldes des membres présents dans le masque
  final somme = List<int>.filled(total, 0);
  for (var masque = 1; masque < total; masque++) {
    final bas = masque & -masque; // bit le plus faible
    somme[masque] = somme[masque ^ bas] + soldes[ids[bas.bitLength - 1]]!;
  }

  // meilleur[masque] = nombre max de groupes à somme nulle en retirant les
  // membres un par un ; on compte un groupe à chaque fois que le reste est nul.
  final meilleur = List<int>.filled(total, 0);
  for (var masque = 1; masque < total; masque++) {
    var max = 0;
    for (var i = 0; i < n; i++) {
      if (masque & (1 << i) != 0 && meilleur[masque ^ (1 << i)] > max) {
        max = meilleur[masque ^ (1 << i)];
      }
    }
    meilleur[masque] = max + (somme[masque] == 0 ? 1 : 0);
  }

  // Reconstruction : on refait le chemin optimal ; chaque fois que les membres
  // restants ont une somme nulle, ceux retirés depuis forment un groupe.
  final groupes = <List<String>>[];
  var courant = <String>[];
  var masque = total - 1;
  while (masque != 0) {
    final cible = meilleur[masque] - (somme[masque] == 0 ? 1 : 0);
    for (var i = 0; i < n; i++) {
      final bit = 1 << i;
      if (masque & bit != 0 && meilleur[masque ^ bit] == cible) {
        courant.add(ids[i]);
        masque ^= bit;
        break;
      }
    }
    if (somme[masque] == 0) {
      groupes.add(courant);
      courant = [];
    }
  }
  return groupes;
}

/// Règle un groupe à somme nulle en au plus (taille − 1) virements :
/// le plus gros débiteur rembourse le plus gros créancier, et on recommence.
List<Virement> _reglerGroupe(List<String> groupe, Map<String, int> soldes) {
  final restant = {for (final id in groupe) id: soldes[id]!};
  final virements = <Virement>[];

  while (true) {
    final enAttente = restant.entries.where((e) => e.value != 0).toList();
    if (enAttente.isEmpty) break;

    final debiteur = enAttente.reduce((a, b) => b.value < a.value ? b : a);
    final crediteur = enAttente.reduce((a, b) => b.value > a.value ? b : a);
    final montant = (-debiteur.value) < crediteur.value ? -debiteur.value : crediteur.value;

    virements.add(Virement(de: debiteur.key, vers: crediteur.key, montant: montant));
    restant[debiteur.key] = debiteur.value + montant;
    restant[crediteur.key] = crediteur.value - montant;
  }
  return virements;
}
