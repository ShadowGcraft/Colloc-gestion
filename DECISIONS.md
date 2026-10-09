# Décisions d'architecture

> Format : pour chaque choix important, 3 à 5 lignes (options envisagées, choix, raison).
> Schéma : [`supabase/migrations/20261009000000_schema_initial.sql`](supabase/migrations/20261009000000_schema_initial.sql). Conception : [`docs/conception.md`](docs/conception.md).
> **À relire ensemble et à savoir défendre à l'oral** : chaque choix ci-dessous peut être questionné en soutenance.

## Modèle de données

### D1 — Montants : centimes entiers
- **Options :** `float`/`double` ; `numeric(10,2)` ; `integer` en centimes.
- **Choix :** `integer` en centimes partout (base et Dart), conversion en euros seulement à l'affichage.
- **Raison :** les flottants font des erreurs d'arrondi (0,1 + 0,2 ≠ 0,3). `numeric` est exact en SQL, mais Dart n'a pas de type décimal natif : on retomberait sur des `double`. Avec des entiers, les sommes sont exactes et la somme des soldes vaut **exactement 0**.

### D2 — « Un utilisateur appartient à une coloc, avec un rôle »
- **Options :** une colonne `coloc_id` dans le profil (une seule coloc possible : contraire au cahier des charges) ; un tableau d'identifiants dans `colocations` (ni clé étrangère ni rôle) ; une table d'association.
- **Choix :** table `membres (colocation_id, utilisateur_id, role, rejoint_le, parti_le)`, avec une clé primaire composite.
- **Raison :** c'est une relation N-N qui porte un attribut (le rôle). Un index unique partiel garantit **un seul admin actif** par coloc.

### D3 — Une dépense et sa répartition : deux tables
- **Options :** une seule table avec un tableau ou du JSON des parts ; une ligne par participant qui recopie la dépense ; deux tables.
- **Choix :** `depenses` (montant, payeur, date…) + `depense_parts` (une ligne par participant avec son montant).
- **Raison :** une seule table ne suffit pas. La répartition est une relation N-N entre une dépense et des membres, avec un attribut (la part), et un tableau ne permet ni clé étrangère ni contrainte. Les parts sont **toujours stockées**, même en mode « égal », donc le calcul des soldes ne dépend jamais du mode de saisie.

### D4 — Rotation des tâches
- **Options :** une table `tache_participants (tache_id, membre, ordre)` ; un index de rotation entier ; le responsable actuel + l'ordre d'arrivée des membres.
- **Choix :** `taches.responsable_id` + l'ordre `membres.rejoint_le`. La logique est **en base**, dans la RPC `terminer_tache`.
- **Raison :** aucune table en plus. Les nouveaux membres entrent automatiquement dans la rotation et les anciens sont sautés. En base, l'historique et le passage au membre suivant se font dans une seule transaction, avec un verrou (`for update`) si deux personnes cochent en même temps. Le résultat est identique sur tous les appareils. Limite : tous les membres participent à toutes les tâches.

### D5 — Calcul des soldes : SQL ; simplification des dettes : Dart
- **Options :** tout en Dart ; tout en SQL (vue + fonction) ; soldes en SQL et simplification en Dart.
- **Choix :** une vue SQL `soldes` (`security_invoker`, donc soumise à la RLS) qui renvoie une ligne par membre. La simplification se fait en Dart, dans une fonction pure.
- **Raison :** avec 2 000 dépenses, la base renvoie 4 lignes au lieu de 2 000. La simplification est un algorithme sans accès réseau, facile à couvrir par les **tests unitaires** demandés.

### D6 — Algorithme « minimum de remboursements »
- **Options :** algorithme glouton (le plus gros débiteur paie le plus gros créancier) ; recherche exacte.
- **Choix :** recherche exacte. Nombre minimal de virements = (membres non soldés) − (nombre maximal de sous-groupes dont la somme vaut 0), calculé par programmation dynamique sur les sous-ensembles. Au-delà de 15 membres, on bascule sur le glouton.
- **Raison :** le glouton fait au plus n − 1 virements mais **n'est pas toujours minimal**. Contre-exemple : soldes +4, +3, −2, −2, −3 → le glouton fait 4 virements, alors que 3 suffisent (−3 → +3 et −2, −2 → +4). Ce cas servira de test unitaire. En 2ⁿ, l'algorithme exact reste instantané pour une coloc.

## Flutter

### D7 — Structure du dépôt
- **Options :** projet Flutter à la racine ; projet Flutter dans un sous-dossier.
- **Choix :** `app/` (Flutter), `supabase/` (projet Supabase CLI : migration, données de démo, tests SQL), `docs/` (conception), `tests_e2e/` (scénario du jalon 4), avec les lanceurs, `JOURNAL.md` et `DECISIONS.md` à la racine.
- **Raison :** chacun trouve sa partie et les fichiers de l'application ne se mélangent pas avec la doc et la base.

### D8 — Gestion d'état
- **Options :** `setState` seul ; `ChangeNotifier` + `ListenableBuilder` (inclus dans Flutter) ; `provider` ; Riverpod ; Bloc.
- **Choix :** un ViewModel `ChangeNotifier` par écran (classe de base `ModeleVue` : chargement, erreur, rechargement au retour du réseau) et une `Session` partagée (profil, coloc courante, membres), fournie par un `InheritedWidget` (`ServicesScope`).
- **Raison :** c'est l'architecture recommandée par la documentation officielle de Flutter, et elle n'ajoute **aucun package** : seuls `supabase_flutter` et `image_picker` (photo du ticket) sont utilisés. Les écrans restent simples à tester.

### D9 — Couche d'accès aux données et dossiers
- **Options :** appeler Supabase directement depuis les écrans ; une couche « dépôts » (repositories).
- **Choix :** une interface par domaine (`DepenseDepot`, `ChatDepot`…) avec son implémentation Supabase, regroupées dans `Depots`. Les écrans ne connaissent que les interfaces. Dossiers : `modeles/`, `donnees/`, `etat/`, `vues/<fonctionnalité>/`, `widgets/`, `outils/`.
- **Raison :** aucun écran n'importe Supabase. Les tests de widgets remplacent les dépôts par des faux en mémoire (`test/faux_depots.dart`), et une même logique n'est jamais écrite deux fois.

### D10 — Clés et configuration
- **Choix :** l'URL et la clé **anon** sont dans `env.json` (ignoré par Git) et sont passées par `--dart-define-from-file`. Les lanceurs le font automatiquement. La clé `service_role` n'est **jamais** utilisée : les lanceurs refusent de démarrer s'ils la détectent.
- **Raison :** la clé anon est publique par nature, et c'est la RLS qui protège les données. On la garde quand même hors du dépôt : chacun peut pointer vers son propre projet Supabase.

### D11 — Mode hors connexion
- **Options :** paquet `connectivity_plus` ; détection par les erreurs réseau des requêtes.
- **Choix :** un `EtatReseau` global. Toute erreur réseau le fait passer hors ligne (bandeau en haut de l'écran), puis il sonde le serveur toutes les 4 secondes. Au retour, chaque écran ouvert se recharge tout seul.
- **Raison :** savoir que le Wi-Fi est allumé ne prouve pas que Supabase est joignable : seule une vraie requête le prouve. Les données déjà affichées restent visibles, et la saisie d'un message ou d'un article non envoyé est conservée.

### D12 — Temps réel : resynchroniser plutôt que faire confiance
- **Choix :** chaque écran temps réel (courses, chat, tâches) charge d'abord ses données, puis applique les évènements reçus. **À chaque reconnexion du canal, il recharge tout.** Un canal est ouvert dans `initState()` et fermé dans `dispose()`.
- **Raison :** Realtime n'est pas une garantie de livraison. Pendant une coupure, les évènements sont perdus, et nous avons constaté que le tout premier abonnement après un redémarrage de Supabase peut en manquer. Le rechargement à la reconnexion rattrape tout, ce que le jalon 4 vérifie.

### D13 — Stratégie de tests
- **Choix :** quatre niveaux. Unitaires (calculs), widgets (formulaires, et tous les écrans en clair et en sombre pour détecter les débordements), intégration (dépôts contre le vrai Supabase local, temps réel compris), SQL (pgTAP : soldes et RLS). S'y ajoute une répétition automatique du jalon 4 dans un navigateur.
- **Raison :** chaque règle importante est testée là où elle vit. Les soldes sont vérifiés en SQL, puisqu'ils y sont calculés ; la simplification en Dart, pour la même raison.

### D14 — Fonctionnalité bonus
- **Options :** notifications, graphiques, export CSV, invitation par lien, cache local, tests d'intégration.
- **Choix :** **statistiques en graphiques** (écran « Statistiques » : total par mois, avancé par colocataire), dessinées avec de simples widgets ; nous avons aussi les tests d'intégration.
- **Raison :** aucun paquet supplémentaire, et cela réutilise les données déjà présentes. Un seul bonus est noté (+1) : présenter les statistiques.

## Pièges rencontrés (et leçon retenue)

- **Ordre de tri :** dans `supabase-dart`, `.order('colonne')` trie par défaut en ordre **décroissant**. Les membres s'affichaient à l'envers. Tous les tris précisent désormais `ascending:`.
- **Supprimer une coloc échouait :** les cascades vers `membres` et vers `depenses` s'exécutent dans un ordre non garanti. Les clés vers `membres` sont donc différées (`deferrable initially deferred`).
- **Contrôles différés et tests SQL :** une transaction de test annulée par `ROLLBACK` ne déclenche jamais le contrôle prévu au `COMMIT`. On le force avec `SET CONSTRAINTS ALL IMMEDIATE` *après* l'appel.
- **Accessibilité :** le bandeau « Hors connexion », dessiné avant les pages, était masqué aux lecteurs d'écran par les pages modales (`BlockSemantics`). Il est désormais dessiné après elles et déclaré comme région « vivante ».

## Points techniques du sujet (§4)

### Q1 — RLS de `membres` qui consulte `membres` (récursion)
Une policy de `membres` qui interroge `membres` déclenche de nouveau la même policy, et Postgres répond `infinite recursion detected in policy`. **Solution :** des fonctions `SECURITY DEFINER` (`prive.mes_colocations()`, `prive.est_admin()`…) lisent `membres` avec les droits du propriétaire, donc sans RLS. Elles sont placées dans le schéma `prive`, que l'API n'expose pas, avec `search_path = ''`, et ne répondent que pour `auth.uid()`.

### Q2 — Rejoindre une coloc qu'on ne peut pas lire
Aucune policy ne permet d'insérer dans `membres`. Le seul chemin est la RPC `rejoindre_colocation(code)` (`SECURITY DEFINER`) : elle cherche la coloc par son code et ajoute l'appelant **comme simple membre**. Ce qui la rend sûre :
- le code est généré par la base (10 caractères, 2⁵⁰ possibilités, aléa cryptographique) ;
- un mauvais code ne révèle rien ;
- seul l'admin peut régénérer le code, ce qui invalide l'ancien (utile après avoir retiré quelqu'un).

### Q3 — Empêcher un payeur qui n'est pas membre
Par une **contrainte**, impossible à contourner : une clé étrangère composite `(colocation_id, payeur_id) → membres (colocation_id, utilisateur_id)`. Le payeur doit donc être membre de *cette* coloc. La policy d'insertion exige en plus qu'il soit **actif**. Le même principe s'applique aux parts, aux remboursements et au responsable d'une tâche. Les parts portent aussi `colocation_id`, avec une clé `(depense_id, colocation_id) → depenses` : impossible de rattacher une part à la dépense d'une autre coloc.

### Q4 — Arrondis : 10 € entre 3 personnes
1000 centimes ÷ 3 = 333, reste 1. Le centime restant va au premier participant **dans l'ordre des identifiants**, ce qui donne 334 + 333 + 333. La règle est déterministe : tous les appareils obtiennent le même résultat. Un trigger de contrainte **différé** (vérifié au `COMMIT`) refuse toute dépense dont la somme des parts n'est pas égale au montant, quel que soit le chemin utilisé.

### Q5 — Atomicité : dépense + parts « en bloc »
PostgREST ne permet pas d'ouvrir une transaction depuis le client. On passe donc par la RPC `creer_depense` : une fonction Postgres s'exécute **dans une seule transaction**, et si une part échoue, la dépense est annulée aussi. Elle est en `SECURITY INVOKER`, donc la RLS s'applique comme pour un insert direct. En prime, un insert direct d'une dépense sans ses parts est rejeté par le trigger différé.

### Q6 — Que devient l'historique quand un membre part ?
Le membre n'est pas supprimé : on renseigne `membres.parti_le`. Ses dépenses et ses parts restent valides, il apparaît toujours dans les soldes (`a_quitte = true`) et un colocataire peut enregistrer qu'il l'a remboursé. Il perd immédiatement l'accès, car toutes les policies exigent `parti_le is null`. Ses tâches passent au membre suivant. Si l'admin part, le plus ancien membre devient admin ; si le dernier membre part, la coloc est supprimée. Les clés vers `membres` sont **différées** : sans cela, la suppression d'une coloc échouait, car Postgres ne garantit pas l'ordre des cascades.

### Q7 — Performance : 10 000 messages, 2 000 dépenses
- **Chat :** pagination « par clé » (`id < dernier_id_chargé`, `limit 30`) appuyée sur l'index `(colocation_id, id desc)`. Le coût est constant même avec 10 000 messages, alors qu'un `offset` ralentit à mesure qu'on remonte. Seuls les nouveaux messages arrivent par le temps réel.
- **Soldes :** l'agrégation se fait en SQL, avec des index sur `colocation_id`.
- **RLS :** les policies utilisent `colocation_id in (select prive.mes_colocations())`, évalué **une fois par requête** et non une fois par ligne.

### Q8 — Temps réel : filtré par la RLS ? limité à une coloc ?
Avec *Postgres Changes*, Supabase vérifie la RLS de chaque abonné pour les `INSERT` et `UPDATE` : on ne reçoit pas les lignes d'une autre coloc. En revanche, les `DELETE` ne peuvent pas être filtrés : seul l'identifiant de la ligne supprimée est envoyé, et le client ignore les identifiants qu'il ne connaît pas. Pour limiter les évènements à une seule coloc, on ajoute le filtre `colocation_id=eq.<id>` à l'abonnement (filtrage côté serveur). On ouvre un canal par écran, fermé dans `dispose()`. Les tables publiées sont `messages`, `articles_courses` et `taches`. À grande échelle, on passerait aux canaux *Broadcast* privés.
