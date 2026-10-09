import 'package:colloc/outils/simplification.dart';
import 'package:flutter_test/flutter_test.dart';

/// Applique les virements aux soldes : tout le monde doit finir à 0.
Map<String, int> appliquer(Map<String, int> soldes, List<Virement> virements) {
  final resultat = Map.of(soldes);
  for (final v in virements) {
    resultat[v.de] = resultat[v.de]! + v.montant;
    resultat[v.vers] = resultat[v.vers]! - v.montant;
  }
  return resultat;
}

void main() {
  group('Simplification des dettes', () {
    test(
      'jeu de test du jalon 3 : 3 virements suffisent et soldent tout le monde',
      () {
        // soldes calculés à la main dans docs/jalon3.md (et vérifiés en SQL par pgTAP)
        const soldes = {
          'Alice': 1911,
          'Bob': 4135,
          'Chloé': -2398,
          'Dan': -3648,
        };
        final virements = simplifierDettes(soldes);

        expect(virements, hasLength(3));
        expect(appliquer(soldes, virements).values, everyElement(0));
        expect(virements.every((v) => v.montant > 0), isTrue);
      },
    );

    test("bat l'algorithme glouton : +4 +3 −2 −2 −3 se règle en 3 virements, pas 4", () {
      const soldes = {'A': 400, 'B': 300, 'C': -200, 'D': -200, 'E': -300};
      final virements = simplifierDettes(soldes);

      expect(virements, hasLength(3));
      expect(appliquer(soldes, virements).values, everyElement(0));
      // E (−3) rembourse directement B (+3) : un groupe à somme nulle isolé
      expect(
        virements,
        contains(const Virement(de: 'E', vers: 'B', montant: 300)),
      );
    });

    test('tout le monde à zéro : aucun virement', () {
      expect(simplifierDettes({'A': 0, 'B': 0}), isEmpty);
      expect(simplifierDettes({}), isEmpty);
    });

    test(
      'une seule dette : un seul virement du débiteur vers le créancier',
      () {
        expect(simplifierDettes({'A': -1250, 'B': 1250}), [
          const Virement(de: 'A', vers: 'B', montant: 1250),
        ]);
      },
    );

    test('refuse des soldes dont la somme ne vaut pas 0', () {
      expect(() => simplifierDettes({'A': 100, 'B': -99}), throwsArgumentError);
    });

    test('au-delà de 15 membres (algorithme glouton) : toujours au plus n − 1 virements', () {
      final soldes = {
        for (var i = 0; i < 20; i++) 'M$i': (i.isEven ? 1 : -1) * (100 + i * 7),
      };
      final ecart = soldes.values.fold(0, (a, b) => a + b);
      soldes['M0'] = soldes['M0']! - ecart; // somme ramenée à 0

      final virements = simplifierDettes(soldes);
      expect(virements.length, lessThanOrEqualTo(19));
      expect(appliquer(soldes, virements).values, everyElement(0));
    });
  });
}
