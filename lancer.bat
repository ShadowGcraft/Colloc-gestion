@echo off
rem Lanceur Colloc pour Windows : double-cliquer sur ce fichier.
rem Tout le travail est fait par scripts\lancer.ps1 (les arguments lui sont transmis).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\lancer.ps1" %*
if errorlevel 1 pause
