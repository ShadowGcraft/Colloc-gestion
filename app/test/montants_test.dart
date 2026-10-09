import 'package:colloc/outils/montants.dart';
import 'package:colloc/outils/repartition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Saisie des montants', () {
    test('accepte virgule, point, espaces et symbole euro', () {
      expect(lireMontant('12'), 1200);
      expect(lireMontant('12,5'), 1250);
      expect(lireMontant('12.50'), 1250);
      expect(lireMontant(' 1 234,56 € '), 123456);
      expect(lireMontant('0,07'), 7);
    });

    test('refuse les saisies invalides', () {
      expect(lireMontant(''), isNull);
      expect(lireMontant('abc'), isNull);
      expect(lireMontant('12,345'), isNull, reason: 'pas plus de 2 décimales');
      expect(lireMontant('-5'), isNull);
      expect(lireMontant('1,2,3'), isNull);
    });
  });

  group('Affichage des montants', () {
    test('format français avec séparateur de milliers', () {
      expect(formaterEuros(123456), '1 234,56 €');
      expect(formaterEuros(5), '0,05 €');
      expect(formaterEuros(-2398), '-23,98 €');
      expect(formaterEuros(1911, signe: true), '+19,11 €');
    });

    test('aller-retour saisie → centimes → saisie', () {
      expect(lireMontant(centimesVersSaisie(8460)), 8460);
    });
  });

  group('Répartition en parts égales (identique à la RPC creer_depense)', () {
    test(
      '10 € entre 3 : le centime restant va au premier identifiant trié',
      () {
        final parts = repartirEgalement(1000, ['c', 'a', 'b']);
        expect(parts, {'a': 334, 'b': 333, 'c': 333});
      },
    );

    test('la somme des parts vaut toujours exactement le total', () {
      for (final total in [1, 99, 1000, 2999, 8460, 123457]) {
        for (var n = 1; n <= 7; n++) {
          final parts = repartirEgalement(total, [
            for (var i = 0; i < n; i++) 'p$i',
          ]);
          expect(
            parts.values.fold(0, (a, b) => a + b),
            total,
            reason: '$total entre $n',
          );
        }
      }
    });

    test('jeu de test du jalon 3 : 29,99 € entre 4 → 750, 750, 750, 749', () {
      expect(repartirEgalement(2999, ['a', 'b', 'c', 'd']).values.toList(), [
        750,
        750,
        750,
        749,
      ]);
    });
  });
}
