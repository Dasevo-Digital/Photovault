#!/usr/bin/env bash
#
# Baut Photo Vault als Flatpak.
#
# Aufruf:  tool/flatpak_bauen.sh [--installieren] [--pruefen] [--buendel]
#
#   --installieren  Das fertige Paket für den angemeldeten Benutzer
#                   einspielen (flatpak install --user).
#   --pruefen       Nach dem Bau im Sandkasten nachsehen, ob die
#                   mitgelieferten Werkzeuge wirklich da sind und können,
#                   was sie sollen.
#   --buendel       Die einzelne .flatpak-Datei zum Weitergeben erzeugen
#                   und auf den Schreibtisch legen.
#
# Der Flutter-Bau läuft bewusst VOR flatpak-builder: flatpak-builder
# arbeitet ohne Netzzugang, `flutter build` braucht aber die Pakete aus
# pub.dev. Deshalb entsteht das Bündel zuerst hier draussen, und der
# Bauplan nimmt es nur noch auf.
#
set -uo pipefail

ROT=$'\033[31m'; GRUEN=$'\033[32m'; GELB=$'\033[33m'; AUS=$'\033[0m'

WURZEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAUPLAN="$WURZEL/packaging/flatpak/com.example.PhotoVault.yml"
KENNUNG="com.example.PhotoVault"
LAUFZEIT="org.gnome.Platform"
LAUFZEIT_FASSUNG="49"
BAUORT="$WURZEL/build/flatpak"
LAGER="$WURZEL/build/flatpak-repo"
# Woher die Laufzeit kommt, wenn sie auf dem Zielrechner fehlt.
LAUFZEIT_QUELLE="https://dl.flathub.org/repo/flathub.flatpakrepo"

installieren=0
pruefen=0
buendel=0
for arg in "$@"; do
  case "$arg" in
    --installieren) installieren=1 ;;
    --pruefen) pruefen=1 ;;
    --buendel) buendel=1 ;;
    *) printf '%sUnbekannte Angabe: %s%s\n' "$ROT" "$arg" "$AUS"; exit 2 ;;
  esac
done

titel() { printf '\n%s\n' "$1"; printf '%.0s─' $(seq 1 ${#1}); printf '\n'; }
fehler() { printf '  %s✗%s %s\n' "$ROT" "$AUS" "$1"; }
gut()    { printf '  %s✓%s %s\n' "$GRUEN" "$AUS" "$1"; }
hinweis(){ printf '  %s•%s %s\n' "$GELB" "$AUS" "$1"; }

titel "Voraussetzungen"

mangel=0
for befehl in flatpak flatpak-builder flutter patchelf; do
  if command -v "$befehl" >/dev/null 2>&1; then
    gut "$befehl"
  else
    fehler "$befehl fehlt"
    mangel=1
  fi
done
if [ "$mangel" -ne 0 ]; then
  printf '\n  Nachzuholen:\n'
  printf '    sudo apt install flatpak flatpak-builder patchelf\n'
  printf '    flatpak remote-add --if-not-exists --user flathub \\\n'
  printf '        https://dl.flathub.org/repo/flathub.flatpakrepo\n'
  exit 1
fi

# Laufzeit und SDK. Ohne beide bricht flatpak-builder erst spät ab, mit
# einer Meldung, die nicht sagt, was zu tun ist.
for teil in "$LAUFZEIT" "${LAUFZEIT/Platform/Sdk}"; do
  if flatpak info "$teil//$LAUFZEIT_FASSUNG" >/dev/null 2>&1; then
    gut "$teil//$LAUFZEIT_FASSUNG"
  else
    fehler "$teil//$LAUFZEIT_FASSUNG fehlt"
    printf '    flatpak install --user flathub %s//%s\n' "$teil" "$LAUFZEIT_FASSUNG"
    mangel=1
  fi
done
[ "$mangel" -eq 0 ] || exit 1

titel "Flutter-Bündel bauen"
( cd "$WURZEL" && flutter build linux --release ) || exit 1
BUENDEL="$WURZEL/build/linux/x64/release/bundle"
[ -x "$BUENDEL/photo_vault" ] || { fehler "kein Bündel unter $BUENDEL"; exit 1; }

# kernel_blob.bin ist der JIT-Schnappschuss eines Debug-Baus. In einem
# Release-Bündel hat er nichts zu suchen – dort rechnet libapp.so, und
# zwar vorübersetzt. Flutter räumt flutter_assets aber nicht auf: Lag dort
# einmal ein Debug-Bau, bleibt die Datei liegen und wandert mit ins Paket.
# Gemessen: 72 MB, die das Bündel von 23 auf 40 MB aufgebläht haben, ohne
# dass sie je ausgeführt worden wären.
if [ -f "$BUENDEL/data/flutter_assets/kernel_blob.bin" ]; then
  fehler "kernel_blob.bin im Release-Bündel – Reste eines Debug-Baus."
  printf '        Erst aufräumen, dann erneut:  flutter clean\n'
  exit 1
fi
gut "$(du -sh "$BUENDEL" | cut -f1) unter build/linux/x64/release/bundle"

titel "Baupfade aus den Bibliotheken entfernen"
# Die Plugin-Bibliotheken tragen nach `flutter build linux` einen RUNPATH
# auf Verzeichnisse DIESES Rechners, etwa
# /home/…/photo_vault/linux/flutter/ephemeral. Der wandert unverändert ins
# Flatpak. Dass das Startskript LD_LIBRARY_PATH setzt, deckt es nur zu:
# Der RUNPATH bleibt ein Suchpfad vor den Systempfaden, der Sandkasten
# sieht den Heimatordner, und bei `flatpak run --command=…` ist
# LD_LIBRARY_PATH gar nicht gesetzt. Wer dort eine .so ablegt, bekommt sie
# geladen (Prüfrunde 12).
#
# Entfernt werden nur ABSOLUTE Einträge. Was mit $ORIGIN beginnt, ist
# relativ zur Datei selbst, gehört zum Bündel und muss bleiben – die
# Hauptdatei findet ihre Bibliotheken über $ORIGIN/lib.
gestrichen=0
while IFS= read -r datei; do
  alt="$(patchelf --print-rpath "$datei" 2>/dev/null)" || continue
  [ -n "$alt" ] || continue
  neu=""
  entfernt=""
  IFS=':' read -ra teile <<< "$alt"
  for teil in "${teile[@]}"; do
    [ -n "$teil" ] || continue
    case "$teil" in
      '$ORIGIN'*) neu="${neu:+$neu:}$teil" ;;
      *)          entfernt="${entfernt:+$entfernt, }$teil" ;;
    esac
  done
  [ -n "$entfernt" ] || continue
  if [ -n "$neu" ]; then
    patchelf --set-rpath "$neu" "$datei" || exit 1
  else
    patchelf --remove-rpath "$datei" || exit 1
  fi
  hinweis "$(basename "$datei"): $entfernt"
  gestrichen=$((gestrichen + 1))
done < <(find "$BUENDEL" -type f \( -name '*.so*' -o -name 'photo_vault' \))

if [ "$gestrichen" -eq 0 ]; then
  gut "keine Baupfade vorhanden"
else
  gut "$gestrichen Datei(en) bereinigt"
fi

# Gegenprobe an Ort und Stelle: Nach dem Streichen darf keine einzige
# mitgelieferte Datei mehr einen absoluten Suchpfad tragen. Ohne diese
# Zeile fiele ein Tippfehler oben erst auf einem fremden Rechner auf.
uebrig="$(while IFS= read -r datei; do
  patchelf --print-rpath "$datei" 2>/dev/null | tr ':' '\n' |
    grep -v '^\$ORIGIN' | grep -v '^$' | sed "s|^|  $(basename "$datei"): |"
done < <(find "$BUENDEL" -type f \( -name '*.so*' -o -name 'photo_vault' \)))"
if [ -n "$uebrig" ]; then
  fehler "es bleiben absolute Suchpfade übrig:"
  printf '%s\n' "$uebrig"
  exit 1
fi
gut "nur noch \$ORIGIN-relative Suchpfade"

titel "Flatpak bauen"
# --force-clean, weil ein halber Bauort aus einem abgebrochenen Lauf sonst
# stillschweigend weiterverwendet wird.
flatpak-builder --force-clean --user --repo="$LAGER" \
  --install-deps-from=flathub \
  "$BAUORT" "$BAUPLAN" || exit 1
gut "Paket gebaut"

if [ "$buendel" -eq 1 ]; then
  titel "Bündel schnüren"
  # **--runtime-repo ist der Grund, warum dieser Schritt hier steht und
  # nicht von Hand getippt wird.** Ohne die Angabe trägt die .flatpak-Datei
  # keine Quelle für ihre Laufzeit. Auf einem Rechner, der
  # org.gnome.Platform//49 schon hat, fällt das nie auf – auf jedem
  # anderen hat das Einspielen nichts, woraus es die Laufzeit holen
  # könnte. Die Bündel bis einschliesslich 1.13.0 waren so gebaut.
  fassung="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$WURZEL/pubspec.yaml")"
  ziel="${BUENDELZIEL:-$HOME/Desktop}/PhotoVault-$fassung-x86_64.flatpak"
  flatpak build-bundle --runtime-repo="$LAUFZEIT_QUELLE" \
    "$LAGER" "$ziel" "$KENNUNG" || exit 1
  gut "$(du -h "$ziel" | cut -f1)  $ziel"

  # Nachsehen, ob die Angabe wirklich in der Datei steht. Ein Schalter,
  # den man setzt und nie nachprüft, ist eine Hoffnung.
  if grep -qa 'flathub.flatpakrepo' "$ziel"; then
    gut "Laufzeitquelle im Bündel eingetragen"
  else
    fehler "keine Laufzeitquelle im Bündel – Einspielen wird anderswo scheitern"
  fi

  # **Discover kann diese Datei nicht einspielen, und das liegt nicht an
  # ihr.** Nachgestellt mit `plasma-discover --local-filename`: Die
  # Programmseite erscheint, der Knopf lässt sich drücken, und im
  # Protokoll steht `Failed to find remote ref: Remote "Lokales Paket"
  # not found`. Discover sucht einen Ursprung, den es selbst nie anlegt.
  # Aus einem richtigen Ursprung heraus findet es dasselbe Paket sofort.
  # Deshalb steht der Weg hier, statt dass ihn jeder selbst suchen muss.
  hinweis "Einspielen: flatpak install --user --bundle \"$ziel\""
  hinweis "Discover scheitert an .flatpak-Dateien (Remote „Lokales Paket\" not found)"
fi

if [ "$installieren" -eq 1 ]; then
  titel "Einspielen"
  flatpak --user remote-add --if-not-exists --no-gpg-verify photo-vault-lokal "$LAGER" || exit 1
  flatpak --user install -y --reinstall photo-vault-lokal "$KENNUNG" || exit 1
  gut "eingespielt – Start mit: flatpak run $KENNUNG"
fi

if [ "$pruefen" -eq 1 ]; then
  titel "Werkzeuge im Sandkasten"
  im_sandkasten() { flatpak-builder --run "$BAUORT" "$BAUPLAN" "$@" 2>&1; }

  # Nicht auf Vorhandensein prüfen, sondern aufrufen. Im ersten Bau lag
  # unter /app/bin/dcraw_emu das libtool-Hüllskript statt des Programms –
  # `which` war zufrieden, der Aufruf scheiterte.
  laeuft() { # name  befehl...
    local name="$1"; shift
    local aus rc
    aus="$(im_sandkasten "$@")"; rc=$?
    # Der Rückgabewert allein genügt nicht: Manche Werkzeuge melden bei
    # einem Aufruf ohne Argumente ihre Hilfe mit einem Wert ungleich null.
    # Umgekehrt genügt die Ausgabe allein auch nicht. Deshalb beides – und
    # ausdrücklich auch die Meldung von bwrap, wenn die Datei gar nicht da
    # ist. Genau die ging einmal durch, weil sie „No such file" sagt und
    # nicht „not found".
    if printf '%s' "$aus" | grep -qiE "execvp|no such file|nicht gefunden|not found|kommando nicht|command not found|nur lesbar|read-only"; then
      fehler "$name: $(printf '%s' "$aus" | head -1)"
    elif [ -z "$aus" ] && [ "$rc" -ne 0 ]; then
      fehler "$name: keine Ausgabe, Rückgabewert $rc"
    else
      gut "$name läuft"
    fi
  }
  laeuft heif-dec heif-dec --version
  laeuft dcraw_emu dcraw_emu
  # Ohne raw-identify bleiben Kamera, Objektiv und Aufnahmedatum von
  # RAW-Dateien leer, deren Format package:exif nicht kennt (CR3).
  laeuft raw-identify raw-identify
  laeuft ffmpeg ffmpeg -hide_banner -version
  laeuft ffprobe ffprobe -hide_banner -version
  laeuft zenity zenity --version

  # Das eigentliche Versprechen dieses Pakets: Vorhandensein genügt nicht,
  # libheif muss den Bildinhalt auch auspacken können. Genau daran ist der
  # erste Versuch auf echter Hardware gescheitert.
  if im_sandkasten heif-dec --list-decoders 2>&1 |
      awk '/HEIC decoders:/{gefunden=1; next} /decoders:/{gefunden=0} gefunden && NF' |
      grep -q .; then
    gut "libheif hat einen HEVC-Dekoder"
  else
    fehler "libheif ohne HEVC-Dekoder – HEIC-Fotos blieben unsichtbar"
  fi

  # Dasselbe für AVIF. Seit dem AVIF-Fix laufen .avif-Dateien über
  # libheif statt über den RAW-Entwickler – ohne dav1d im Bündel wären sie
  # danach genauso unsichtbar wie vorher, nur an anderer Stelle.
  if im_sandkasten heif-dec --list-decoders 2>&1 |
      awk '/AVIF decoders:/{gefunden=1; next} /decoders:|uncompressed/{gefunden=0} gefunden && NF' |
      grep -q .; then
    gut "libheif hat einen AVIF-Dekoder"
  else
    fehler "libheif ohne AVIF-Dekoder – AVIF-Fotos blieben unsichtbar"
  fi

  if im_sandkasten ffmpeg -hide_banner -decoders 2>/dev/null | grep -qE '^ V[.A-Z]* +hevc'; then
    gut "ffmpeg kann HEVC lesen"
  else
    fehler "ffmpeg ohne HEVC – Videovorschauen blieben leer"
  fi

  if im_sandkasten sh -c 'ls /app/lib/libmpv.so* >/dev/null 2>&1'; then
    gut "libmpv vorhanden (Videowiedergabe)"
  else
    hinweis "libmpv fehlt – alles ausser der Videowiedergabe funktioniert"
  fi

  # Der wichtigste Handgriff dieser Prüfung: OHNE den Heimatordner
  # nachsehen. Mit ihm sieht der Sandkasten das Bauverzeichnis dieses
  # Rechners – und lud daraus klaglos ONNX Runtime, das im Bündel fehlte.
  # Auf jedem anderen Rechner wären damit sämtliche KI-Funktionen
  # ausgefallen, ohne dass hier etwas aufgefallen wäre.
  titel "Wie es auf einem fremden Rechner aussieht"
  # Der Suchpfad muss derselbe sein wie im Startskript, sonst prüft man
  # etwas anderes als das, was beim Start passiert.
  fremd() { flatpak run --nofilesystem=home --nofilesystem=/media \
      --nofilesystem=/run/media --command=sh "$KENNUNG" \
      -c "export LD_LIBRARY_PATH=/app/photo_vault/lib; $1" 2>&1; }

  if flatpak info "$KENNUNG" >/dev/null 2>&1; then
    ungeloest=$(fremd 'ldd /app/photo_vault/lib/*.so 2>/dev/null | grep "not found"' | sort -u)
    if [ -z "$ungeloest" ]; then
      gut "alle Bibliotheken der App liegen im Bündel"
    else
      fehler "ausserhalb des Bündels gesucht:"
      printf '%s\n' "$ungeloest" | sed 's/^/      /'
    fi
    if fremd 'ldd /app/photo_vault/lib/libflutter_onnxruntime_plugin.so' |
        grep -q "libonnxruntime.so.1 => /app/"; then
      gut "ONNX Runtime kommt aus dem Bündel (alle KI-Funktionen)"
    else
      fehler "ONNX Runtime nicht aus dem Bündel – KI-Funktionen fielen aus"
    fi

    # Am EINGESPIELTEN Paket nachsehen, nicht am Bündel davor: Geprüft
    # gehört, was ausgeliefert wird. Ein Bauschritt, der stillschweigend
    # übersprungen wurde, fiele oben nicht auf.
    ORT="$(flatpak info --show-location "$KENNUNG" 2>/dev/null)/files/photo_vault"
    if [ -d "$ORT" ]; then
      rest="$(while IFS= read -r datei; do
        patchelf --print-rpath "$datei" 2>/dev/null | tr ':' '\n' |
          grep -v '^\$ORIGIN' | grep -v '^$' | sed "s|^|      $(basename "$datei"): |"
      done < <(find "$ORT" -type f \( -name '*.so*' -o -name 'photo_vault' \)))"
      if [ -z "$rest" ]; then
        gut "kein Baupfad im ausgelieferten Paket"
      else
        fehler "Baupfade im ausgelieferten Paket:"
        printf '%s\n' "$rest"
      fi
    fi
  else
    hinweis "nicht eingespielt – mit --installieren wiederholen"
  fi
fi

printf '\n'
