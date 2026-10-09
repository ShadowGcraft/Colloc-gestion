#!/usr/bin/env bash
# Lanceur Colloc' pour macOS / Linux (équivalent de lancer.bat sous Windows).
#
#   ./lancer.sh              menu de choix de l'appareil
#   ./lancer.sh -d chrome    arguments transmis tels quels à « flutter run »
#
# Vérifie Flutter, le projet app/ et env.json, refuse la clé service_role,
# puis lance l'application avec --dart-define-from-file=env.json.
set -eo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$RACINE/app"
ENV_FICHIER="$RACINE/env.json"
ENV_EXEMPLE="$RACINE/env.example.json"

erreur() { printf '\n\033[31mErreur : %s\033[0m\n' "$*" >&2; exit 1; }
info()   { printf '\033[36m→ %s\033[0m\n' "$*"; }

# Décode la partie centrale d'un JWT (base64url) pour lire son rôle
payload_jwt() {
  local p
  p="$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')"
  while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done
  printf '%s' "$p" | base64 --decode 2>/dev/null || true
}

command -v flutter >/dev/null 2>&1 \
  || erreur "Flutter est introuvable. Installez-le (https://docs.flutter.dev/get-started/install) puis rouvrez le terminal."

[ -f "$APP/pubspec.yaml" ] \
  || erreur "Le projet Flutter n'existe pas encore dans app/. Il sera créé à l'étape 2 (voir README.md)."

if [ ! -f "$ENV_FICHIER" ]; then
  cp "$ENV_EXEMPLE" "$ENV_FICHIER"
  erreur "env.json vient d'être créé à partir du modèle. Renseignez-y l'URL et la clé anon de votre projet Supabase (Project Settings → API), puis relancez."
fi

grep -q 'VOTRE' "$ENV_FICHIER" \
  && erreur "env.json contient encore les valeurs d'exemple : renseignez l'URL et la clé anon de votre projet Supabase."

# Garde-fou : la clé service_role contourne la RLS, elle ne doit jamais être dans l'application
grep -q 'sb_secret_' "$ENV_FICHIER" \
  && erreur "env.json contient une clé secrète (sb_secret_…). Utilisez la clé anon / publishable, jamais la clé secrète."
for jwt in $(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$ENV_FICHIER" || true); do
  if payload_jwt "$jwt" | grep -q '"role" *: *"service_role"'; then
    erreur "env.json contient la clé service_role ! Remplacez-la par la clé anon (Project Settings → API)."
  fi
done

if [ $# -gt 0 ]; then
  ARGS=("$@")
else
  echo
  echo "Sur quel appareil lancer Colloc' ?"
  echo "  1) Choisir parmi les appareils détectés (téléphone, émulateur, simulateur…)"
  echo "  2) Navigateur Chrome"
  if [ "$(uname)" = "Darwin" ]; then echo "  3) Application macOS"; else echo "  3) Application Linux"; fi
  read -r -p "Choix [1] : " choix
  case "${choix:-1}" in
    1) ARGS=() ;;
    2) ARGS=(-d chrome) ;;
    3) if [ "$(uname)" = "Darwin" ]; then ARGS=(-d macos); else ARGS=(-d linux); fi ;;
    *) erreur "Choix invalide : $choix" ;;
  esac
fi

cd "$APP"
info "Récupération des dépendances (flutter pub get)…"
flutter pub get
info "Lancement de l'application…"
exec flutter run --dart-define-from-file="$ENV_FICHIER" ${ARGS[@]+"${ARGS[@]}"}
