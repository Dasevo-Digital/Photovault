#!/usr/bin/env bash
#
# Prüft eine Linux-Maschine auf alles, was Photo Vault zum Bauen und Laufen
# braucht – und nennt für jedes fehlende Stück den Installationsbefehl.
#
# Aufruf:  tool/linux_setup_check.sh
# Ergebnis: Exit-Code 0, wenn alles zum BAUEN vorhanden ist. Fehlende
#           Laufzeit-Werkzeuge senken den Funktionsumfang, verhindern den
#           Build aber nicht.
#
set -uo pipefail

ROT=$'\033[31m'; GRUEN=$'\033[32m'; GELB=$'\033[33m'; AUS=$'\033[0m'
fehlt_build=0
fehlt_laufzeit=0

titel() { printf '\n%s\n' "$1"; printf '%.0s─' $(seq 1 ${#1}); printf '\n'; }

pruefe() { # name  befehl  paket  kategorie(build|laufzeit)  zweck
  local name="$1" befehl="$2" paket="$3" kategorie="$4" zweck="$5"
  if command -v "$befehl" >/dev/null 2>&1; then
    printf '  %s✓%s %-16s %s\n' "$GRUEN" "$AUS" "$name" "$zweck"
  else
    if [ "$kategorie" = build ]; then
      printf '  %s✗%s %-16s %s\n' "$ROT" "$AUS" "$name" "$zweck"
      printf '      → %s\n' "$paket"
      fehlt_build=$((fehlt_build+1))
    else
      printf '  %s!%s %-16s %s\n' "$GELB" "$AUS" "$name" "$zweck"
      printf '      → %s\n' "$paket"
      fehlt_laufzeit=$((fehlt_laufzeit+1))
    fi
  fi
}

# Vorhandenes heif-dec heisst NICHT, dass HEIC gelesen werden kann.
#
# Beim ersten Lauf auf Ubuntu 26.04 war libheif-examples installiert, und
# trotzdem scheiterte jede Umwandlung mit „Decoder plugin generated an
# error: Unspecified". Der Grund: libheif liefert die Codecs seit 1.20 als
# eigene Plugin-Pakete, und Ubuntu installiert von Haus aus nur die
# AV1-Plugins – für HEVC, also genau das, was in jeder iPhone-Datei steckt,
# ist keines dabei. „heif-dec ist da" hätte hier grün gemeldet und jedes
# iPhone-Foto wäre unsichtbar geblieben.
#
# Deshalb wird nicht das Programm geprüft, sondern seine Fähigkeit.
pruefe_heic_dekoder() {
  if heif-dec --list-decoders 2>/dev/null |
       awk '/^HEIC decoders:/{gefunden=1; next} /decoders:|uncompressed/{gefunden=0} gefunden && NF' |
       grep -q .; then
    printf '  %s✓%s %-16s %s\n' "$GRUEN" "$AUS" 'HEVC-Dekoder' 'entschlüsselt den Inhalt von HEIC'
  else
    printf '  %s!%s %-16s %s\n' "$GELB" "$AUS" 'HEVC-Dekoder' 'entschlüsselt den Inhalt von HEIC'
    printf '      → sudo apt install libheif-plugin-libde265\n'
    printf '        (ohne ihn scheitert JEDE HEIC-Datei, obwohl heif-dec da ist)\n'
    fehlt_laufzeit=$((fehlt_laufzeit+1))
  fi
}

pruefe_lib() { # name  pkg-config-name  paket  zweck
  local name="$1" pc="$2" paket="$3" zweck="$4"
  if pkg-config --exists "$pc" 2>/dev/null; then
    printf '  %s✓%s %-16s %s\n' "$GRUEN" "$AUS" "$name" "$zweck"
  else
    printf '  %s✗%s %-16s %s\n' "$ROT" "$AUS" "$name" "$zweck"
    printf '      → %s\n' "$paket"
    fehlt_build=$((fehlt_build+1))
  fi
}

printf 'Photo Vault – Linux-Bereitschaftsprüfung\n'
printf 'System: %s\n' "$(uname -sr)"
[ -f /etc/os-release ] && printf 'Distribution: %s\n' "$(. /etc/os-release; echo "$PRETTY_NAME")"

titel 'Zum Bauen nötig'
pruefe 'Flutter SDK'  flutter     'https://docs.flutter.dev/get-started/install/linux' build 'Compiler und Werkzeuge'
# Ohne git bricht das flutter-Kommando SOFORT ab ("Unable to find git in your
# PATH") – noch bevor irgendetwas übersetzt wird. Auf einer frisch
# aufgesetzten Ubuntu-Maschine ist git nicht dabei; beim ersten echten Lauf
# war das prompt der erste Stolperstein, und die Prüfung hat ihn nicht
# genannt, weil sie git für selbstverständlich hielt.
pruefe 'git'          git         'sudo apt install git'                              build 'wird vom Flutter-Werkzeug vorausgesetzt'
pruefe 'clang'        clang       'sudo apt install clang'                            build 'C++-Compiler für den Linux-Build'
pruefe 'cmake'        cmake       'sudo apt install cmake'                            build 'Build-System'
pruefe 'ninja'        ninja       'sudo apt install ninja-build'                      build 'Build-System'
pruefe 'pkg-config'   pkg-config  'sudo apt install pkg-config'                       build 'Bibliothekssuche'
pruefe_lib 'GTK 3'    gtk+-3.0    'sudo apt install libgtk-3-dev'                            'Fensterrahmen der App'
# Dasselbe Muster wie bei git darüber, nur eine Stufe subtiler: Bis
# Prüfrunde 12 stand libmpv unten bei „zur Laufzeit", und geprüft wurde das
# PROGRAMM mpv. Beides falsch. media_kit_video sucht beim Bauen über
# pkg-config nach der Bibliothek; fehlen die Entwicklungsdateien, bricht
# CMake ab („Target links to PkgConfig::mpv but the target was not found"),
# und zwar bevor irgendetwas übersetzt wird. Eine Maschine mit dem
# mpv-Programm, aber ohne libmpv-dev, kam durch die Prüfung und scheiterte
# dann am Bau.
pruefe_lib 'libmpv'   mpv         'sudo apt install libmpv-dev'                              'Videowiedergabe (media_kit) – auch zum BAUEN nötig'

titel 'Zur Laufzeit – ohne diese fehlen einzelne Funktionen'
pruefe 'ffmpeg'       ffmpeg      'sudo apt install ffmpeg'                        laufzeit 'Video-Vorschaubild und -Zuschnitt'
pruefe 'ffprobe'      ffprobe     'sudo apt install ffmpeg'                        laufzeit 'Videolänge ermitteln'
pruefe 'heif-dec'     heif-dec    'sudo apt install libheif-examples'              laufzeit 'HEIC/HEIF-Fotos (iPhone)'
pruefe_heic_dekoder
pruefe 'dcraw_emu'    dcraw_emu   'sudo apt install libraw-bin'                    laufzeit 'RAW-Fotos'
pruefe 'raw-identify' raw-identify 'sudo apt install libraw-bin'                   laufzeit 'Kamera/Objektiv aus RAW'

titel 'Nur für die Fernprüfung (optional)'
pruefe 'xvfb-run'     xvfb-run    'sudo apt install xvfb'                          laufzeit 'App ohne Bildschirm starten (SSH)'

# Hier stand bis zuletzt „Noch nicht umgesetzt: Entwickeln, Texterkennung",
# mit Verweis auf die Phasen 2, 3 und 5 des Linux-Plans. Alle drei sind
# seit Langem fertig – der Hinweis war das Erste, was ein Linux-Nutzer beim
# Aufsetzen zu lesen bekam, und er war schlicht falsch.
titel 'Was ohne diese Werkzeuge fehlt'
printf '  Ohne heif-dec:   iPhone-Fotos (HEIC) bleiben ohne Vorschau\n'
printf '  Ohne dcraw_emu:  dasselbe für RAW-Dateien aller Hersteller\n'
printf '  Ohne raw-identify: RAW-Fotos ohne Kamera, Objektiv und Aufnahmedatum\n'
printf '                   (betrifft vor allem CR3 – dort liest die übliche\n'
printf '                   EXIF-Bibliothek gar nichts)\n'
printf '  Ohne ffmpeg:     keine Videovorschau, kein Videoschnitt\n'
printf '  Ohne ffprobe:    keine Videolänge in den Angaben\n'
printf '  Alles andere – Entwickeln, Texterkennung, Gesichter – arbeitet\n'
printf '  auch ohne sie.\n'

titel 'Ergebnis'
if [ "$fehlt_build" -gt 0 ]; then
  printf '  %s%d Bau-Voraussetzung(en) fehlen%s – bitte oben genannte Pakete installieren.\n' "$ROT" "$fehlt_build" "$AUS"
else
  printf '  %sBauen möglich.%s Nächster Schritt:\n' "$GRUEN" "$AUS"
  printf '      flutter pub get && dart run build_runner build --delete-conflicting-outputs\n'
  printf '      flutter build linux    # oder: flutter run -d linux\n'
fi
if [ "$fehlt_laufzeit" -gt 0 ]; then
  printf '  %s%d Laufzeit-Werkzeug(e) fehlen%s – die App startet trotzdem, einzelne Funktionen bleiben aus.\n' "$GELB" "$fehlt_laufzeit" "$AUS"
fi

[ "$fehlt_build" -eq 0 ]
