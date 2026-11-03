#!/bin/bash
#
# Baut djxl (libjxl) für Windows – nur das Auspackprogramm (#276).
#
# Aufruf aus einer MSYS2-Shell:  bash tool/windows_jxl.sh <Zielordner>
#
# Warum selbst bauen statt das fertige MSYS2-Paket zu nehmen: Dessen
# djxl.exe hängt an OpenEXR samt Imath und an den Kodierern, gebraucht
# wird davon zum Lesen nichts. libjxl selbst wird fest hineingebunden;
# was bleibt, sind highway, brotli, lcms2 und libpng als DLLs. Dieselben
# Schalter stehen im Flatpak-Bauplan.
#
# Weder set -e noch set -u vor dem Profil, siehe windows_libheif.sh.
export MSYSTEM=MINGW64
source /etc/profile
set -e

FASSUNG="v0.11.2"
# Der Commit hinter dem Tag, siehe windows_libheif.sh.
COMMIT="332feb17d17311c748445f7ee75c4fb55cc38530"
ZIEL="${1:?Zielordner angeben}"
ARBEIT="$(mktemp -d)"
trap 'rm -rf "$ARBEIT"' EXIT

echo "== Bauwerkzeuge und Bibliotheken =="
pacman -S --noconfirm --needed \
  mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja \
  mingw-w64-x86_64-highway mingw-w64-x86_64-brotli mingw-w64-x86_64-lcms2 \
  mingw-w64-x86_64-libpng git

echo "== libjxl $FASSUNG holen =="
# Ohne die Untermodule: Alles, was sie brächten, kommt aus MSYS2.
git clone --depth 1 --branch "$FASSUNG" \
  https://github.com/libjxl/libjxl.git "$ARBEIT/quelle"
IST="$(git -C "$ARBEIT/quelle" rev-parse HEAD)"
if [ "$IST" != "$COMMIT" ]; then
  echo "libjxl $FASSUNG zeigt auf $IST statt auf $COMMIT – abgebrochen" >&2
  exit 1
fi

echo "== Übersetzen =="
cmake -G Ninja -S "$ARBEIT/quelle" -B "$ARBEIT/bau" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
  -DJPEGXL_ENABLE_TOOLS=ON -DJPEGXL_ENABLE_BENCHMARK=OFF \
  -DJPEGXL_ENABLE_EXAMPLES=OFF -DJPEGXL_ENABLE_MANPAGES=OFF \
  -DJPEGXL_ENABLE_DOXYGEN=OFF -DJPEGXL_ENABLE_JNI=OFF \
  -DJPEGXL_ENABLE_PLUGINS=OFF -DJPEGXL_ENABLE_VIEWERS=OFF \
  -DJPEGXL_ENABLE_OPENEXR=OFF -DJPEGXL_ENABLE_SJPEG=OFF \
  -DJPEGXL_ENABLE_JPEGLI=OFF -DJPEGXL_ENABLE_SKCMS=OFF \
  -DJPEGXL_FORCE_SYSTEM_BROTLI=ON -DJPEGXL_FORCE_SYSTEM_HWY=ON \
  -DJPEGXL_FORCE_SYSTEM_LCMS2=ON
cmake --build "$ARBEIT/bau" --parallel --target djxl

echo "== Einsammeln nach $ZIEL =="
mkdir -p "$ZIEL"
cp "$ARBEIT/bau/tools/djxl.exe" "$ZIEL/"

# Die DLL-Hülle in Runden und mit Schlussprüfung, siehe windows_libheif.sh.
huelle_ziehen() {
  cd "$ZIEL"
  ldd djxl.exe 2>/dev/null | grep -i '/mingw64/' |
    sed 's/.*=> //; s/ (0x.*//' | sort -u |
    while read -r dll; do [ -f "$dll" ] && cp -f "$dll" "$ZIEL/"; done
  ldd djxl.exe 2>/dev/null | grep -i 'not found' |
    sed 's/[[:space:]]*//; s/ =>.*//' | sort -u |
    while read -r name; do
      [ -f "/mingw64/bin/$name" ] && cp -f "/mingw64/bin/$name" "$ZIEL/"
    done
}

for _ in 1 2 3 4 5; do
  vorher=$(ls "$ZIEL" | wc -l)
  huelle_ziehen
  [ "$(ls "$ZIEL" | wc -l)" = "$vorher" ] && break
done

echo "== Huelle pruefen =="
cd "$ZIEL"
if ldd djxl.exe 2>/dev/null | grep -i 'not found'; then
  echo "FEHLER: djxl.exe fehlen DLLs (siehe oben)." >&2
  exit 1
fi
echo "vollstaendig"
