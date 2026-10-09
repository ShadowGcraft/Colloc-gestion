# Lanceur Colloc' pour Windows : appelé par lancer.bat (double-clic).
#
#   lancer.bat                 menu de choix de l'appareil
#   lancer.bat -d windows      arguments transmis tels quels à « flutter run »
#
# Vérifie Flutter, le projet app\ et env.json, refuse la clé service_role,
# puis lance l'application avec --dart-define-from-file=env.json.
# Fichier enregistré en UTF-8 avec BOM : nécessaire pour les accents sous PowerShell 5.1.

$ErrorActionPreference = 'Stop'

$racine     = Split-Path -Parent $PSScriptRoot
$app        = Join-Path $racine 'app'
$envFichier = Join-Path $racine 'env.json'
$envExemple = Join-Path $racine 'env.example.json'

function Arreter([string]$message) {
    Write-Host ''
    Write-Host "Erreur : $message" -ForegroundColor Red
    exit 1
}

function Info([string]$message) {
    Write-Host "→ $message" -ForegroundColor Cyan
}

# Décode la partie centrale d'un JWT (base64url) pour lire son rôle
function Lire-PayloadJwt([string]$jwt) {
    $p = $jwt.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
    try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) }
    catch { return '' }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Arreter "Flutter est introuvable. Installez-le (https://docs.flutter.dev/get-started/install/windows), ajoutez flutter\bin au PATH, puis rouvrez la fenêtre."
}

if (-not (Test-Path -LiteralPath (Join-Path $app 'pubspec.yaml'))) {
    Arreter "Le projet Flutter n'existe pas encore dans app\. Il sera créé à l'étape 2 (voir README.md)."
}

if (-not (Test-Path -LiteralPath $envFichier)) {
    Copy-Item -LiteralPath $envExemple -Destination $envFichier
    Arreter "env.json vient d'être créé à partir du modèle. Renseignez-y l'URL et la clé anon de votre projet Supabase (Project Settings → API), puis relancez."
}

$contenu = Get-Content -LiteralPath $envFichier -Raw

if ($contenu -match 'VOTRE') {
    Arreter "env.json contient encore les valeurs d'exemple : renseignez l'URL et la clé anon de votre projet Supabase."
}

# Garde-fou : la clé service_role contourne la RLS, elle ne doit jamais être dans l'application
if ($contenu -match 'sb_secret_') {
    Arreter "env.json contient une clé secrète (sb_secret_…). Utilisez la clé anon / publishable, jamais la clé secrète."
}
foreach ($m in [regex]::Matches($contenu, 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')) {
    if ((Lire-PayloadJwt $m.Value) -match '"role"\s*:\s*"service_role"') {
        Arreter "env.json contient la clé service_role ! Remplacez-la par la clé anon (Project Settings → API)."
    }
}

if ($args.Count -gt 0) {
    $options = $args
} else {
    Write-Host ''
    Write-Host "Sur quel appareil lancer Colloc' ?"
    Write-Host '  1) Application Windows (bureau)'
    Write-Host '  2) Navigateur Chrome'
    Write-Host '  3) Choisir parmi les appareils détectés (téléphone Android, émulateur…)'
    $choix = Read-Host 'Choix [1]'
    switch ($choix) {
        { $_ -in '', '1' } { $options = @('-d', 'windows'); break }
        '2'                { $options = @('-d', 'chrome'); break }
        '3'                { $options = @(); break }
        default            { Arreter "Choix invalide : $choix" }
    }
}

Set-Location -LiteralPath $app

Info 'Récupération des dépendances (flutter pub get)…'
& flutter pub get
if ($LASTEXITCODE -ne 0) { Arreter 'flutter pub get a échoué (voir les messages ci-dessus).' }

if ($options -contains 'windows') {
    Write-Host "  Pour l'application Windows : Visual Studio 2022 avec « Développement Desktop en C++ »" -ForegroundColor DarkGray
    Write-Host '  et le mode développeur Windows activé (commande : start ms-settings:developers).' -ForegroundColor DarkGray
}

Info "Lancement de l'application…"
& flutter run "--dart-define-from-file=$envFichier" @options
exit $LASTEXITCODE
