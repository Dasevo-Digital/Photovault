#!/usr/bin/env bash
# Holt die Auslieferungen der Portierungen auf den Mac.
#
# Gebaut werden die drei Fassungen auf drei Rechnern; abgelegt gehoeren sie
# an EINEN Ort, sonst laesst sich die Pruefsummendatei nie vollstaendig
# nachrechnen und niemand weiss, welcher Stand wo liegt. Dieses Skript
# sammelt das Linux-Flatpak und das Windows-Archiv in den
# Auslieferungsordner auf dem Schreibtisch und rechnet danach ALLE
# Pruefsummen nach - auch die der eingesammelten Dateien. Genau das ist
# der Beleg, dass unterwegs nichts passiert ist.
#
# Die Gegenstellen stehen in ~/.ssh/config. Ueberschreibbar, damit im
# Skript kein Rechnername festgeschrieben ist:
#   PV_LINUX_HOST=… PV_WINDOWS_HOST=… tool/auslieferung_einsammeln.sh
#
#   tool/auslieferung_einsammeln.sh [version]
# Ohne Angabe wird die Version aus pubspec.yaml gelesen.
set -euo pipefail

linux_host="${PV_LINUX_HOST:-TestKubuntu}"
windows_host="${PV_WINDOWS_HOST:-TestWindows}"

wurzel="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$wurzel/pubspec.yaml")}"
[ -n "$version" ] || { echo "Version nicht ermittelbar." >&2; exit 1; }

ziel="$HOME/Desktop/PhotoVault-Release-v$version"
[ -d "$ziel" ] || { echo "Auslieferungsordner fehlt: $ziel" >&2; exit 1; }

echo "Auslieferung v$version -> $ziel"

# Holt eine Datei, wenn sie noch nicht da ist. Der Pfad auf der Gegenstelle
# wird ERFRAGT, nicht geraten - so steht hier kein Benutzername.
hole() {
  local host="$1" datei="$2" suchbefehl="$3"
  if [ -f "$ziel/$datei" ]; then
    echo "  $datei liegt bereits vor"
    return 0
  fi
  local pfad
  # Ohne `|| true` beendet `set -e` das Skript, sobald die Gegenstelle
  # nichts findet oder nicht antwortet - genau der Fall, den die naechste
  # Zeile behandeln soll.
  pfad="$(ssh -o ConnectTimeout=10 "$host" "$suchbefehl" 2>/dev/null | tr -d '\r' | head -1)" || true
  if [ -z "$pfad" ]; then
    echo "  $datei: auf $host nicht gefunden - uebersprungen" >&2
    return 0
  fi
  # Windows meldet den Pfad mit Rueckstrichen; scp reicht sie an die
  # Gegenstelle weiter, wo sie als Maskierung gelesen und geschluckt
  # werden. Vorwaertsstriche versteht Windows genauso, Unix-Pfade
  # enthalten keine Rueckstriche - die Umschreibung ist also gefahrlos.
  pfad="${pfad//\\//}"
  echo "  $datei <- $host"
  # Nur lokal quoten: Die Anfuehrungszeichen verbraucht diese Shell, die
  # Gegenstelle bekommt den blanken Pfad. Leerzeichen im Pfad wuerden hier
  # brechen - in den Auslieferungsnamen kommen keine vor.
  scp -q -o ConnectTimeout=10 "$host:$pfad" "$ziel/$datei"
  chmod 644 "$ziel/$datei"
}

hole "$linux_host" "PhotoVault-$version-x86_64.flatpak" \
     "ls -1 \$HOME/Desktop/PhotoVault-$version-x86_64.flatpak \$HOME/Schreibtisch/PhotoVault-$version-x86_64.flatpak 2>/dev/null"

# Windows antwortet mit cmd.exe, nicht mit einer Unix-Shell.
hole "$windows_host" "PhotoVault-$version-windows-x64.zip" \
     "for %I in (\"%USERPROFILE%\\Desktop\\PhotoVault-$version-windows-x64.zip\") do @if exist %I echo %~fI"

echo
echo "Pruefsummen nachrechnen:"
cd "$ziel"
if [ ! -f SHA256SUMS.txt ]; then
  echo "  SHA256SUMS.txt fehlt - nichts nachzurechnen." >&2
  exit 1
fi
shasum -a 256 -c SHA256SUMS.txt

# Die aktuelle macOS-App bleibt unter /Applications/Photo Vault.app. Frühere
# Test- und Sicherungskopien dort würden Spotlight als zweite Programme zeigen;
# sie werden daher nach dem vollständig geprüften Release archiviert.
"$wurzel/tool/macos_spotlight_aufräumen.sh" "$version"
