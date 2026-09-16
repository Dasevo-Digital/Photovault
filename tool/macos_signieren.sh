#!/usr/bin/env bash
#
# Signiert ein gebautes macOS-Bündel mit eingeschalteter Hardened Runtime.
#
# Aufruf:  tool/macos_signieren.sh <Pfad zur .app> [--rechte <plist>]
#                                  [--kennung <signing identity>]
#
# Warum überhaupt: Der Flutter-Bau signiert ad-hoc und OHNE Hardened
# Runtime. Ohne sie gibt es weder Library Validation noch Schutz gegen
# DYLD_INSERT_LIBRARIES – die Sandbox fängt beides nicht ab. Aufgefallen in
# Prüfrunde 12.
#
# Signiert wird von innen nach aussen. Apples `--deep` tut das zwar auch,
# wird von Apple aber ausdrücklich nicht mehr empfohlen: Es vergibt allen
# verschachtelten Teilen dieselben Rechte wie der App, was hier falsch
# wäre – die Rechte gehören nur ans äussere Bündel.
#
# WICHTIG, und der eigentliche Grund für die Prüfung am Ende: Hardened
# Runtime schaltet Library Validation ein. Ab da lädt die App nur noch
# Bibliotheken mit derselben Signatur wie sie selbst. Bei durchgehend
# ad-hoc signierten Teilen geht das auf – aber "geht auf" ist kein
# Nachweis, deshalb prüft das Skript hinterher nach und der Start gehört
# von Hand hinterher.
#
set -uo pipefail

ROT=$'\033[31m'; GRUEN=$'\033[32m'; GELB=$'\033[33m'; AUS=$'\033[0m'
titel() { printf '\n%s\n' "$1"; printf '%.0s─' $(seq 1 ${#1}); printf '\n'; }
fehler() { printf '  %s✗%s %s\n' "$ROT" "$AUS" "$1"; }
gut()    { printf '  %s✓%s %s\n' "$GRUEN" "$AUS" "$1"; }
hinweis(){ printf '  %s•%s %s\n' "$GELB" "$AUS" "$1"; }

WURZEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=""
RECHTE="$WURZEL/macos/Runner/Release.entitlements"
KENNUNG="-"   # ad-hoc; für eine Developer-ID hier deren Namen übergeben

while [ $# -gt 0 ]; do
  case "$1" in
    --rechte)  RECHTE="$2"; shift 2 ;;
    --kennung) KENNUNG="$2"; shift 2 ;;
    -*) printf '%sUnbekannte Angabe: %s%s\n' "$ROT" "$1" "$AUS"; exit 2 ;;
    *)  APP="$1"; shift ;;
  esac
done

[ -n "$APP" ] || { printf 'Aufruf: %s <Pfad zur .app> [--rechte <plist>]\n' "$0"; exit 2; }
[ -d "$APP" ] || { fehler "kein Bündel unter $APP"; exit 1; }
[ -f "$RECHTE" ] || { fehler "keine Rechtedatei unter $RECHTE"; exit 1; }

titel "Ausgangslage"
hinweis "Bündel: $APP"
hinweis "Rechte: ${RECHTE#$WURZEL/}"
hinweis "Kennung: $([ "$KENNUNG" = "-" ] && echo "ad-hoc" || echo "$KENNUNG")"

# Bei ad-hoc-Signierung MUSS Library Validation aus. Nachgemessen, zweimal
# an derselben Stelle (21.08. und in Prüfrunde 12): Die App startet sonst
# gar nicht, dyld bricht mit
#   Library not loaded: @rpath/Ass.framework/…
#   not valid for use in process: mapping process and mapped file
#   (non-platform) have different Team IDs
# ab. Der Grund ist grundsätzlich und nicht zu umgehen: Library Validation
# vergleicht Team-IDs, und eine ad-hoc-Signatur hat keine – jedes der 24
# mitgelieferten Frameworks gilt damit als fremd.
#
# Was trotzdem bleibt, ist der Grund, das hier überhaupt zu tun. Gemessen
# mit einer eingeschleusten Bibliothek: ohne Härtung läuft fremder Code im
# Prozess, mit Härtung wird DYLD_INSERT_LIBRARIES ignoriert – auch ohne
# Library Validation.
#
# Mit einer echten Developer-ID entfällt diese Ausnahme: Dann tragen alle
# Teile dieselbe Team-ID und Library Validation greift. Deshalb hängt die
# Ausnahme an --kennung und steht nicht in Release.entitlements.
if [ "$KENNUNG" = "-" ]; then
  ERWEITERT="$(mktemp -t photovault-rechte).plist"
  cp "$RECHTE" "$ERWEITERT"
  /usr/libexec/PlistBuddy -c \
    'Add :com.apple.security.cs.disable-library-validation bool true' \
    "$ERWEITERT" >/dev/null 2>&1
  RECHTE="$ERWEITERT"
  trap 'rm -f "$ERWEITERT"' EXIT
  hinweis "ad-hoc: Library Validation abgeschaltet (siehe Kommentar im Skript)"
fi

titel "Von innen nach aussen signieren"

signiere() { # pfad [zusätzliche Argumente]
  local ziel="$1"; shift
  # --timestamp=none, weil eine ad-hoc-Signatur keinen Zeitstempelserver
  # bekommt und der Versuch nur eine Minute in einen Zeitüberlauf läuft.
  if codesign --force --options runtime --timestamp=none \
       --sign "$KENNUNG" "$@" "$ziel" 2>/dev/null; then
    return 0
  fi
  fehler "$(basename "$ziel")"
  return 1
}

anzahl=0
fehlgeschlagen=0

# Zuerst alles, was lose in den Frameworks liegt (dylibs, .so), dann die
# Framework-Bündel selbst. Andersherum würde die Bündelsignatur sofort
# wieder ungültig, weil sich der Inhalt danach ändert.
while IFS= read -r datei; do
  signiere "$datei" || fehlgeschlagen=$((fehlgeschlagen + 1))
  anzahl=$((anzahl + 1))
done < <(find "$APP/Contents/Frameworks" -type f \( -name '*.dylib' -o -name '*.so' \) 2>/dev/null)

while IFS= read -r fw; do
  signiere "$fw" || fehlgeschlagen=$((fehlgeschlagen + 1))
  anzahl=$((anzahl + 1))
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name '*.framework' 2>/dev/null)

# Hilfsprogramme neben der Hauptdatei, falls es welche gibt.
while IFS= read -r helfer; do
  signiere "$helfer" || fehlgeschlagen=$((fehlgeschlagen + 1))
  anzahl=$((anzahl + 1))
done < <(find "$APP/Contents/MacOS" -type f -perm +111 2>/dev/null |
         grep -v "^$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null)$")

# Zuletzt das äussere Bündel – nur hier gehören die Rechte hin.
signiere "$APP" --entitlements "$RECHTE" || fehlgeschlagen=$((fehlgeschlagen + 1))
anzahl=$((anzahl + 1))

if [ "$fehlgeschlagen" -ne 0 ]; then
  fehler "$fehlgeschlagen von $anzahl Signaturen fehlgeschlagen"
  exit 1
fi
gut "$anzahl Teile signiert"

titel "Nachprüfen"

flags="$(codesign -dv "$APP" 2>&1 | grep '^CodeDirectory' | sed 's/.*flags=\([^ ]*\).*/\1/')"
if printf '%s' "$flags" | grep -q 'runtime'; then
  gut "Hardened Runtime aktiv ($flags)"
else
  fehler "Hardened Runtime NICHT aktiv ($flags)"
  exit 1
fi

if codesign --verify --deep --strict "$APP" 2>/dev/null; then
  gut "Signatur durchgehend gültig (--deep --strict)"
else
  fehler "Signatur nicht durchgehend gültig:"
  codesign --verify --deep --strict "$APP" 2>&1 | sed 's/^/      /'
  exit 1
fi

# --verify --deep --strict genügt hier NICHT, und das ist der Grund für
# diesen Abschnitt: Beim ersten Lauf lief die Framework-Schleife wegen
# eines Umlauts im Variablennamen gar nicht durch. Signiert war ein
# einziger Teil – und die Prüfung war trotzdem grün, weil die Frameworks
# ihre alten, gültigen Signaturen behielten. Gültig heisst eben nicht
# gehärtet. Also jedes verschachtelte Teil einzeln nachsehen.
ohne_runtime=""
while IFS= read -r teil; do
  f="$(codesign -dv "$teil" 2>&1 | grep '^CodeDirectory' | sed 's/.*flags=\([^ ]*\).*/\1/')"
  printf '%s' "$f" | grep -q 'runtime' || \
    ohne_runtime="$ohne_runtime      $(basename "$teil") ($f)"$'\n'
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name '*.framework' 2>/dev/null)

if [ -z "$ohne_runtime" ]; then
  gut "alle Frameworks tragen Hardened Runtime"
else
  fehler "diese Frameworks tragen sie NICHT:"
  printf '%s' "$ohne_runtime"
  exit 1
fi

# Die Rechte müssen nach dem Signieren noch dieselben sein. Ein
# Tippfehler im Pfad zur Rechtedatei fiele sonst erst auf, wenn die App
# den Ordner des Nutzers nicht mehr lesen kann.
titel "Rechte im fertigen Bündel"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | sed 's/^/  /'

titel "Was jetzt noch von Hand gehört"
hinweis "Starten und ausprobieren: Video abspielen, eine KI-Funktion laufen"
hinweis "lassen. Library Validation zeigt sich erst beim Laden, nicht hier."
printf '\n'
