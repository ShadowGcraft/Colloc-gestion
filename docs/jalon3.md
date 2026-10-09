# Jalon 3 — soldes prédits sur papier

Jeu de test : 4 personnes (A = Alice, B = Bob, C = Chloé, D = Dan), 5 dépenses avec des parts inégales.
Ce sont les dépenses chargées dans la base locale par [`supabase/seed.sql`](../supabase/seed.sql).
Tous les montants sont en centimes.

> Le jour du jalon, le prof impose peut-être **son** jeu de test. La méthode reste la même : remplir le tableau ci-dessous à la main, puis saisir les dépenses dans l'application et comparer avec l'écran « Soldes ».

## 1. Les dépenses et leurs parts

| # | Dépense | Payé par | Montant | Part A | Part B | Part C | Part D |
|---|---|---|---:|---:|---:|---:|---:|
| 1 | Courses Carrefour (égales entre les 4) | A | 8 460 | 2 115 | 2 115 | 2 115 | 2 115 |
| 2 | Électricité (personnalisées) | B | 12 000 | 4 000 | 4 000 | 2 000 | 2 000 |
| 3 | Pizzas (égales entre A, C, D) | C | 3 700 | **1 234** | — | 1 233 | 1 233 |
| 4 | Box internet (égales entre les 4) | D | 2 999 | 750 | 750 | 750 | **749** |
| 5 | Produits ménagers (personnalisées) | A | 1 550 | — | 1 000 | — | 550 |

Arrondis :
- 3 700 ÷ 3 = 1 233, reste 1. Le centime restant va au **premier participant dans l'ordre des identifiants**, ici A.
- 2 999 ÷ 4 = 749, reste 3. A, B et C paient 750, D paie 749.

## 2. Les soldes

Solde = ce qu'on a payé − la somme de ses parts.

| Membre | A payé | Parts dues | **Solde** | Lecture |
|---|---:|---:|---:|---|
| Alice | 8 460 + 1 550 = 10 010 | 2 115 + 4 000 + 1 234 + 750 = 8 099 | **+1 911** | on lui doit 19,11 € |
| Bob | 12 000 | 2 115 + 4 000 + 750 + 1 000 = 7 865 | **+4 135** | on lui doit 41,35 € |
| Chloé | 3 700 | 2 115 + 2 000 + 1 233 + 750 = 6 098 | **−2 398** | elle doit 23,98 € |
| Dan | 2 999 | 2 115 + 2 000 + 1 233 + 749 + 550 = 6 647 | **−3 648** | il doit 36,48 € |
| **Somme** | | | **0** | ✓ exactement zéro |

## 3. Les remboursements minimaux

Il y a 4 membres non soldés. Aucun sous-groupe ne fait 0, sauf le groupe complet : il faut donc **4 − 1 = 3 virements**, par exemple :

| Virement | Montant |
|---|---:|
| Dan → Bob | 36,48 € |
| Chloé → Alice | 19,11 € |
| Chloé → Bob | 4,87 € |

Vérification : Bob reçoit 36,48 + 4,87 = 41,35 € ✓ ; Alice reçoit 19,11 € ✓ ; Chloé verse 19,11 + 4,87 = 23,98 € ✓.

## 4. Vérifications automatiques

- `supabase test db` : la vue `soldes` renvoie exactement +1 911 / +4 135 / −2 398 / −3 648, de somme 0.
- `flutter test` : la simplification de ces soldes donne bien 3 virements qui remettent tout le monde à zéro.
