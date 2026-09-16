@echo off
rem  Legt eine Verknuepfung zu Photo Vault im Startmenue an.
rem
rem  Das Paket ist bewusst ein Ordner zum Auspacken und kein Installations-
rem  paket - deshalb taucht die App von sich aus nicht unter "Programme" auf.
rem  Diese Datei holt das nach, ohne sonst etwas am System zu aendern: Sie
rem  legt eine einzige .lnk an, die auf die photo_vault.exe in DIESEM Ordner
rem  zeigt. Wird der Ordner verschoben oder geloescht, zeigt sie ins Leere -
rem  dann diese Datei am neuen Ort erneut ausfuehren.

setlocal
set "ZIEL=%~dp0photo_vault.exe"

if not exist "%ZIEL%" (
  echo FEHLER: photo_vault.exe liegt nicht neben dieser Datei.
  echo Diese Datei gehoert in denselben Ordner wie das Programm.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ordner = [Environment]::GetFolderPath('Programs');" ^
  "$pfad = Join-Path $ordner 'Photo Vault.lnk';" ^
  "$w = New-Object -ComObject WScript.Shell;" ^
  "$v = $w.CreateShortcut($pfad);" ^
  "$v.TargetPath = '%ZIEL%';" ^
  "$v.WorkingDirectory = '%~dp0';" ^
  "$v.Description = 'Photo Vault - Fotos lokal verwalten';" ^
  "$v.Save();" ^
  "Write-Output ('Angelegt: ' + $pfad)"

if errorlevel 1 (
  echo FEHLER: Die Verknuepfung konnte nicht angelegt werden.
  pause
  exit /b 1
)

echo.
echo Photo Vault steht jetzt im Startmenue unter "Programme".
echo.
echo Zum Entfernen die Verknuepfung dort loeschen - am Programm
echo selbst aendert das nichts.
echo.
pause
