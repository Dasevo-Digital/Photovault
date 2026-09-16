#!/usr/bin/env bash
# Räumt frühere Photo-Vault-App-Bündel aus /Applications aus Spotlight auf.
#
# Aufruf: tool/macos_spotlight_aufräumen.sh [version]
# Ohne Angabe wird die Version aus pubspec.yaml gelesen. Frühere Bündel werden
# nicht gelöscht, sondern in einen .noindex-Ordner auf dem Schreibtisch
# verschoben. Dadurch bleibt eine Rückfallebene erhalten, ohne dass Spotlight
# oder die App-Suche sie als weitere installierte Version anbieten.
set -euo pipefail

wurzel="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$wurzel/pubspec.yaml")}"
aktuell="/Applications/Photo Vault.app"
archiv="$HOME/Desktop/PhotoVault-Vorversionen.noindex"

[ -n "$version" ] || { echo "Version nicht ermittelbar." >&2; exit 1; }
[ -d "$aktuell" ] || { echo "Aktuelle App fehlt: $aktuell" >&2; exit 1; }

installierte_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$aktuell/Contents/Info.plist" 2>/dev/null || true)"
if [ "$installierte_version" != "$version" ]; then
  echo "Aktuelle App ist $installierte_version, erwartet wird $version." >&2
  exit 1
fi

mkdir -p "$archiv"

anzahl=0
while IFS= read -r -d '' app; do
  [ "$app" = "$aktuell" ] && continue
  name="$(basename "$app")"
  ziel="$archiv/$name"
  if [ -e "$ziel" ]; then
    ziel="$archiv/${name}.$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$app" "$ziel"
  echo "Archiviert: $name"
  anzahl=$((anzahl + 1))
done < <(find /Applications -maxdepth 1 -type d -name 'Photo Vault*.app*' -print0)

# Spotlight erhält Verschiebungen über FSEvents. Eine Neuindizierung des
# gesamten Startvolumes wäre dafür unverhältnismäßig und würde die Suche
# währenddessen ausbremsen; der .noindex-Ordner verhindert zudem neue Treffer.
if [ "$anzahl" -eq 0 ]; then
  echo "Keine alte Photo-Vault-Installation in /Applications gefunden."
else
  echo "$anzahl alte Installation(en) aus Spotlight archiviert."
fi
