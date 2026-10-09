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

PORT_WEB=8080
URL_A_OUVRIR=""

# Démarre (si besoin) un émulateur Android et attend qu'il soit prêt
lancer_emulateur() {
  local id
  id="$(flutter devices </dev/null 2>/dev/null | grep -o 'emulator-[0-9]*' | head -1 || true)"
  if [ -z "$id" ]; then
    local emulateur="$EMULATEURS"
    if [ "$(printf '%s\n' "$EMULATEURS" | wc -l | tr -d ' ')" -gt 1 ]; then
      echo
      echo "Quel émulateur ?"
      local i=1 e
      while IFS= read -r e; do echo "  $i) $e"; i=$((i + 1)); done <<< "$EMULATEURS"
      read -r -p "Choix [1] : " n || n=""
      emulateur="$(printf '%s\n' "$EMULATEURS" | sed -n "${n:-1}p")"
      [ -n "$emulateur" ] || erreur "Choix invalide : $n"
    fi
    info "Démarrage de l'émulateur $emulateur (1 à 2 minutes la première fois)…"
    flutter emulators --launch "$emulateur" </dev/null >/dev/null 2>&1 || erreur "Impossible de démarrer l'émulateur $emulateur."
    for _ in $(seq 1 90); do
      id="$(flutter devices </dev/null 2>/dev/null | grep -o 'emulator-[0-9]*' | head -1 || true)"
      [ -n "$id" ] && break
      sleep 2
    done
    [ -n "$id" ] || erreur "L'émulateur ne répond pas. Ouvrez-le depuis Android Studio puis relancez."
  fi

  # détecté ne veut pas dire prêt : on attend la fin du démarrage d'Android
  local adb
  adb="$(command -v adb || true)"
  for chemin in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -z "$adb" ] && [ -n "$chemin" ] && [ -x "$chemin/platform-tools/adb" ] && adb="$chemin/platform-tools/adb"
  done
  if [ -n "$adb" ]; then
    info "Attente de la fin du démarrage d'Android…"
    for _ in $(seq 1 90); do
      [ "$("$adb" -s "$id" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
      sleep 2
    done
  fi
  ARGS=(-d "$id" --device-timeout 60)
}

# Navigateur : Chrome si Flutter le trouve, sinon serveur web + navigateur par défaut (Safari, Firefox…)
lancer_navigateur() {
  if printf '%s' "$APPAREILS" | grep -qi '• chrome'; then
    ARGS=(-d chrome)
  else
    ARGS=(-d web-server --web-hostname 127.0.0.1 --web-port "$PORT_WEB")
    URL_A_OUVRIR="http://127.0.0.1:$PORT_WEB"
  fi
}

if [ $# -gt 0 ]; then
  ARGS=("$@")
else
  info "Recherche des appareils disponibles…"
  APPAREILS="$(flutter devices </dev/null 2>/dev/null || true)"
  EMULATEURS="$(flutter emulators </dev/null 2>/dev/null | awk -F' • ' '$4 ~ /android/ {sub(/ +$/, "", $1); print $1}')"

  # Le menu ne propose que ce qui fonctionne sur cette machine
  LIBELLES=(); ACTIONS=()
  if [ -n "$EMULATEURS" ]; then LIBELLES+=("Émulateur Android (démarré automatiquement)"); ACTIONS+=(emulateur); fi
  LIBELLES+=("Navigateur web"); ACTIONS+=(navigateur)
  if [ "$(uname)" = "Darwin" ]; then
    if xcodebuild -version >/dev/null 2>&1; then LIBELLES+=("Application macOS"); ACTIONS+=(macos); fi
  else
    LIBELLES+=("Application Linux"); ACTIONS+=(linux)
  fi
  LIBELLES+=("Choisir parmi les appareils déjà branchés ou démarrés"); ACTIONS+=(detectes)

  echo
  echo "Sur quel appareil lancer Colloc' ?"
  for i in "${!LIBELLES[@]}"; do echo "  $((i + 1))) ${LIBELLES[$i]}"; done
  if [ "$(uname)" = "Darwin" ] && ! xcodebuild -version >/dev/null 2>&1; then
    echo "  (application macOS / iOS indisponible : Xcode n'est pas installé)"
  fi
  read -r -p "Choix [1] : " choix || choix=""
  choix="${choix:-1}"
  case "$choix" in *[!0-9]* | '') erreur "Choix invalide : $choix" ;; esac
  [ "$choix" -ge 1 ] && [ "$choix" -le "${#ACTIONS[@]}" ] || erreur "Choix invalide : $choix"

  case "${ACTIONS[$((choix - 1))]}" in
    emulateur) lancer_emulateur ;;
    navigateur) lancer_navigateur ;;
    macos) ARGS=(-d macos) ;;
    linux) ARGS=(-d linux) ;;
    detectes) ARGS=() ;;
  esac
fi

cd "$APP"
info "Récupération des dépendances (flutter pub get)…"
flutter pub get

if [ -n "$URL_A_OUVRIR" ]; then
  info "L'application s'ouvrira dans votre navigateur ($URL_A_OUVRIR) dès qu'elle sera compilée."
  # attend que le serveur réponde, puis ouvre le navigateur par défaut
  (
    for _ in $(seq 1 300); do
      if curl -fs -o /dev/null "$URL_A_OUVRIR"; then
        open "$URL_A_OUVRIR" 2>/dev/null || xdg-open "$URL_A_OUVRIR" >/dev/null 2>&1
        exit 0
      fi
      sleep 1
    done
  ) &
fi

info "Lancement de l'application…"
exec flutter run --dart-define-from-file="$ENV_FICHIER" ${ARGS[@]+"${ARGS[@]}"}
