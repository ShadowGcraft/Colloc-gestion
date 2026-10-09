# Audit de sécurité croisé — mode d'emploi

Chaque étudiant attaque la base d'un **autre** groupe avec sa clé anon publique et un compte de test, puis rédige un rapport d'une demi-page.
Ce document contient (1) les attaques à tenter et (2) un modèle de rapport. **Le rapport lui-même est à rédiger par chacun de vous.**

## 1. Préparation

```bash
URL=https://PROJET-DU-GROUPE-AUDITE.supabase.co
ANON=CLE_ANON_DU_GROUPE_AUDITE
# créer son compte de test sur leur projet, puis récupérer son jeton :
TOKEN=$(curl -s "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" \
  -H "Content-Type: application/json" -d '{"email":"moi@test.fr","password":"..."}' | jq -r .access_token)
H=(-H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")
```

Adaptez les noms de tables et de colonnes au schéma du groupe audité (leur `DECISIONS.md` ou `GET $URL/rest/v1/` les liste).

## 2. Attaques à tenter

| # | Attaque | Commande type | Résultat attendu si c'est sûr |
|---|---|---|---|
| 1 | Lire sans être connecté | `curl "$URL/rest/v1/depenses" -H "apikey: $ANON"` | `[]` ou 401 |
| 2 | Lire les données d'une coloc dont on n'est pas membre | `curl "$URL/rest/v1/depenses?select=*" "${H[@]}"` | seulement ses propres colocs |
| 3 | S'ajouter soi-même dans une coloc | `POST /rest/v1/membres {colocation_id, user_id}` | refusé (403) |
| 4 | Se donner le rôle admin | `PATCH /rest/v1/membres?user_id=eq.MOI {"role":"admin"}` | refusé ou 0 ligne |
| 5 | Lire les codes d'invitation des autres colocs | `GET /rest/v1/colocations?select=code_invitation` | uniquement ses colocs |
| 6 | Deviner un code d'invitation | appeler la RPC « rejoindre » avec des codes au hasard | refus, code assez long (≥ 8 caractères aléatoires) |
| 7 | Écrire au nom d'un autre | `POST /rest/v1/messages {"auteur_id":"AUTRE", ...}` | refusé |
| 8 | Dépense dont le payeur n'est pas membre | `POST` d'une dépense avec un payeur étranger | refusé |
| 9 | Dépense mal répartie (parts ≠ total) | insérer une dépense sans parts, ou avec des parts fausses | refusé |
| 10 | Modifier / supprimer la dépense d'un autre | `PATCH` / `DELETE` sur une dépense dont on n'est pas l'auteur | 0 ligne |
| 11 | Lire les fichiers d'une autre coloc | `GET $URL/storage/v1/object/authenticated/tickets/AUTRE_COLOC/x.jpg` | 400 / 403 |
| 12 | Appeler une fonction interne | `POST $URL/rest/v1/rpc/nom_de_fonction_interne` | 404 ou refus |
| 13 | Clé `service_role` dans leur dépôt | chercher `service_role`, `sb_secret_`, ou un JWT contenant `"role":"service_role"` | rien |
| 14 | Temps réel | s'abonner à leur table de messages sans filtre | ne reçoit que ses colocs |

Notez pour chaque essai : la commande, la réponse obtenue, et si c'est une faille.

## 3. Modèle de rapport (½ page)

> **Audit de sécurité — groupe audité : …… — auditeur : ……… — date : ……**
>
> **Périmètre :** clé anon + un compte de test, API REST, Storage et Realtime.
>
> **Résultats :** X attaques tentées, Y réussies.
>
> **Failles trouvées** (pour chacune : description, commande, gravité, correction proposée) :
> 1. …
>
> **Points solides :** …
>
> **Conclusion :** …

## 4. Ce que notre propre base doit refuser

Nos tests automatiques couvrent déjà les attaques 1 à 12 et 14 sur notre base : `supabase test db` et `app/test_integration/`. Avant l'audit, rejouez-les sur le projet en ligne avec les commandes du [README](../README.md#jalon-2--vérifier-la-rls-avec-curl).
