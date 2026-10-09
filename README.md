# Colloc'

Application mobile de gestion de colocation : dépenses partagées et soldes, tâches ménagères, liste de courses et chat en temps réel.
**Flutter + Supabase**, projet BTS SIO (sujet : [`[Projet] Colloc' gestion….pdf`](<[Projet] Colloc' gesti... _ BTS SIO D.Villars Gap.pdf>)).

## Arborescence

```
.
├── app/                  application Flutter (créée à l'étape 2)
├── supabase/schema.sql   tables, contraintes, RLS, RPC, Storage, Realtime
├── docs/conception.md    livrables du jalon 1 : schéma, matrice, navigation, tâches
├── scripts/lancer.ps1    lanceur Windows (appelé par lancer.bat)
├── lancer.bat            lanceur Windows : double-clic
├── lancer.sh             lanceur macOS / Linux
├── env.example.json      modèle de configuration (copié en env.json, ignoré par Git)
├── DECISIONS.md          décisions d'architecture
└── JOURNAL.md            journal de bord (à remplir à chaque séance)
```

## Mise en route

1. **Base de données.** Dans votre projet Supabase, ouvrez *SQL Editor*, collez tout [`supabase/schema.sql`](supabase/schema.sql) et exécutez-le, si possible avant de créer les comptes de test. Pour les tests, désactivez *Authentication → Sign In / Providers → Email → Confirm email*.
2. **Configuration.** Copiez `env.example.json` en `env.json` et renseignez l'URL et la clé **anon** (*Project Settings → API*). Le lanceur le fait pour vous au premier lancement.
   > ⚠️ La clé `service_role` (ou `sb_secret_…`) ne doit **jamais** apparaître dans le dépôt ni dans l'application. Un seul manquement entraîne un malus. Les lanceurs refusent de démarrer s'ils la trouvent.
3. **Lancement.**
   - **Windows :** double-cliquez sur `lancer.bat`, ou tapez `lancer.bat -d chrome` dans un terminal.
   - **macOS / Linux :** `./lancer.sh`, ou `./lancer.sh -d macos`.

   Le lanceur vérifie Flutter, `app/` et `env.json`, lance `flutter pub get`, propose un appareil, puis exécute `flutter run --dart-define-from-file=env.json`.

### Prérequis sous Windows
- Flutter installé, avec `flutter\bin` dans le `PATH` (`flutter doctor` doit être vert pour la cible choisie).
- Pour lancer l'application **Windows (bureau)** : Visual Studio 2022 avec la charge de travail « Développement Desktop en C++ », et le **mode développeur** activé (`start ms-settings:developers`), indispensable pour les plugins.
- Pour **Android** : Android Studio avec un émulateur démarré, ou un téléphone branché en mode débogage USB.

## Étape 2 : créer le projet Flutter (après validation du jalon 1)

```bash
flutter create --org fr.btssiogap --project-name colloc --platforms=android,ios,web,windows,macos app
cd app && flutter pub add supabase_flutter
```

Lecture de la configuration côté Dart (valeurs injectées par `--dart-define-from-file`) :

```dart
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
```

Sous VS Code, ajoutez `"toolArgs": ["--dart-define-from-file=../env.json"]` à la configuration de lancement (`.vscode/launch.json`, avec `"cwd": "app"`).

## Jalon 2 : vérifier la RLS avec `curl`

```bash
URL=https://VOTRE-PROJET.supabase.co
ANON=VOTRE_CLE_ANON

# 1. Jeton de B (compte de test)
TOKEN_B=$(curl -s "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" \
  -H "Content-Type: application/json" -d '{"email":"b@test.fr","password":"motdepasse123"}' | jq -r .access_token)

# 2. Lire les dépenses d'une coloc dont B ne fait PAS partie → doit renvoyer []
curl -s "$URL/rest/v1/depenses?colocation_id=eq.ID_DE_LA_COLOC_DE_C" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN_B"

# 3. Tenter de s'inscrire soi-même dans cette coloc → doit être refusé (403)
curl -s -X POST "$URL/rest/v1/membres" -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Type: application/json" -d '{"colocation_id":"ID_DE_LA_COLOC_DE_C","utilisateur_id":"ID_DE_B"}'
```
