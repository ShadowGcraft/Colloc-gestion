# Lanceur Colloc' pour Windows : appelé par lancer.bat (double-clic).
#
#   lancer.bat                 application Windows (bureau) : lancer.bat transmet -d windows
#   lancer.bat menu            menu de choix de l'appareil (ce script appelé sans argument)
#   lancer.bat -d chrome       arguments transmis tels quels à « flutter run »
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

$portWeb = 8080
$urlAOuvrir = $null

# Démarre (si besoin) un émulateur Android et attend qu'il soit prêt
function Lancer-Emulateur([string[]]$emulateurs) {
    $id = ([regex]::Match((& flutter devices 2>$null | Out-String), 'emulator-\d+')).Value
    if (-not $id) {
        $emulateur = $emulateurs[0]
        if ($emulateurs.Count -gt 1) {
            Write-Host ''
            Write-Host 'Quel émulateur ?'
            for ($i = 0; $i -lt $emulateurs.Count; $i++) { Write-Host "  $($i + 1)) $($emulateurs[$i])" }
            $n = Read-Host 'Choix [1]'
            if (-not $n) { $n = '1' }
            if ($n -notmatch '^\d+$' -or [int]$n -lt 1 -or [int]$n -gt $emulateurs.Count) { Arreter "Choix invalide : $n" }
            $emulateur = $emulateurs[[int]$n - 1]
        }
        Info "Démarrage de l'émulateur $emulateur (1 à 2 minutes la première fois)…"
        & flutter emulators --launch $emulateur *> $null
        for ($t = 0; $t -lt 90 -and -not $id; $t++) {
            Start-Sleep -Seconds 2
            $id = ([regex]::Match((& flutter devices 2>$null | Out-String), 'emulator-\d+')).Value
        }
        if (-not $id) { Arreter "L'émulateur ne répond pas. Ouvrez-le depuis Android Studio puis relancez." }
    }

    # détecté ne veut pas dire prêt : on attend la fin du démarrage d'Android
    $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
    foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk")) {
        if (-not $adb -and $sdk -and (Test-Path (Join-Path $sdk 'platform-tools\adb.exe'))) { $adb = Join-Path $sdk 'platform-tools\adb.exe' }
    }
    if ($adb) {
        Info "Attente de la fin du démarrage d'Android…"
        for ($t = 0; $t -lt 90; $t++) {
            if (((& $adb -s $id shell getprop sys.boot_completed 2>$null) | Out-String).Trim() -eq '1') { break }
            Start-Sleep -Seconds 2
        }
    }
    return @('-d', $id, '--device-timeout', '60')
}

if ($args.Count -gt 0) {
    $options = $args
} else {
    Info 'Recherche des appareils disponibles…'
    $appareils = & flutter devices 2>$null | Out-String
    $emulateurs = @(& flutter emulators 2>$null | ForEach-Object {
        $colonnes = $_ -split ' • '
        if ($colonnes.Count -ge 4 -and $colonnes[3] -match 'android') { $colonnes[0].Trim() }
    })

    # Le menu ne propose que ce qui fonctionne sur cette machine
    $menu = @(@{ Libelle = 'Application Windows (bureau)'; Action = 'windows' })
    if ($emulateurs.Count -gt 0) { $menu += @{ Libelle = 'Émulateur Android (démarré automatiquement)'; Action = 'emulateur' } }
    $menu += @{ Libelle = 'Navigateur web'; Action = 'navigateur' }
    $menu += @{ Libelle = 'Choisir parmi les appareils déjà branchés ou démarrés (téléphone Android…)'; Action = 'detectes' }

    Write-Host ''
    Write-Host "Sur quel appareil lancer Colloc' ?"
    for ($i = 0; $i -lt $menu.Count; $i++) { Write-Host "  $($i + 1)) $($menu[$i].Libelle)" }
    $choix = Read-Host 'Choix [1]'
    if (-not $choix) { $choix = '1' }
    if ($choix -notmatch '^\d+$' -or [int]$choix -lt 1 -or [int]$choix -gt $menu.Count) { Arreter "Choix invalide : $choix" }

    switch ($menu[[int]$choix - 1].Action) {
        'windows'    { $options = @('-d', 'windows') }
        'emulateur'  { $options = Lancer-Emulateur $emulateurs }
        'navigateur' {
            if ($appareils -match '• chrome') { $options = @('-d', 'chrome') }
            elseif ($appareils -match '• edge') { $options = @('-d', 'edge') }
            else {
                $options = @('-d', 'web-server', '--web-hostname', '127.0.0.1', '--web-port', "$portWeb")
                $urlAOuvrir = "http://127.0.0.1:$portWeb"
            }
        }
        'detectes'   { $options = @() }
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

if ($urlAOuvrir) {
    Info "L'application s'ouvrira dans votre navigateur ($urlAOuvrir) dès qu'elle sera compilée."
    # attend que le serveur réponde, puis ouvre le navigateur par défaut
    Start-Job -ScriptBlock {
        param($url)
        for ($t = 0; $t -lt 300; $t++) {
            try { Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2 | Out-Null; Start-Process $url; return } catch { Start-Sleep -Seconds 1 }
        }
    } -ArgumentList $urlAOuvrir | Out-Null
}

Info "Lancement de l'application…"
& flutter run "--dart-define-from-file=$envFichier" @options
exit $LASTEXITCODE
