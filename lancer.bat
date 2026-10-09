@echo off
rem Lanceur Colloc pour Windows : double-cliquer sur ce fichier lance l'application de bureau Windows.
rem   lancer.bat              application Windows (bureau)
rem   lancer.bat menu         menu de choix de l'appareil (emulateur Android, navigateur...)
rem   lancer.bat -d chrome    arguments transmis tels quels a "flutter run"
rem Tout le travail est fait par scripts\lancer.ps1.
setlocal
set "ARGS=%*"
if "%~1"=="" set "ARGS=-d windows"
if /i "%~1"=="menu" set "ARGS="
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\lancer.ps1" %ARGS%
if errorlevel 1 pause
