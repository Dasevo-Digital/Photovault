#!/bin/bash
#
# Baut ffmpeg für Windows – nur mit dem, was Photo Vault aufruft.
#
# Aufruf aus einer MSYS2-Shell:  bash tool/windows_ffmpeg.sh <Zielordner>
#
# Warum selbst bauen statt den fertigen LGPL-Bau von BtbN zu nehmen: Der
# bringt jeden Codec, jedes Format und jeden Filter mit – 124 MB DLLs,
# fast die Hälfte des ganzen Windows-Pakets (Issue #3). Photo Vault ruft
# ffmpeg für genau fünf Dinge auf:
#
#   - Vorschaubild eines Videos  (lesen, scale, JPEG schreiben)
#   - Videolänge                 (ffprobe)
#   - verlustfreier Zuschnitt    (-c copy in denselben Container)
#   - Kameraflug, Diashow        (Rohbilder über die Pipe, H.264, MP4)
#   - Musik unterlegen           (Audio lesen, AAC, afade)
#
# Gelesen wird dabei weiter alles, was Telefone und Kameras schreiben;
# weggelassen sind Encoder, Netzwerk, Geräte und die Filterbibliothek bis
# auf das, was diese Aufrufe brauchen.
#
# **H.264 kommt von Windows** (h264_mf, Media Foundation; braucht seit
# ffmpeg 9 die D3D11-Schnittstelle zum Bauen), nicht aus
# libopenh264 wie bei BtbN: OpenH264 ist nur als Ciscos eigene Binärdatei
# durch dessen Patentlizenz gedeckt, ein selbst gebautes nicht. Fehlt der
# Windows-Encoder (N-Editionen ohne Media Feature Pack), weicht die App auf
# mpeg4 aus (flugvideo.dart, h264Schalter).
#
# Lizenz: LGPL (kein --enable-gpl, kein --enable-nonfree).
#
# Weder set -e noch set -u vor dem Profil: MSYS2s /etc/profile greift auf
# nicht gesetzte Variablen zu (siehe windows_libheif.sh).
export MSYSTEM=MINGW64
source /etc/profile
set -e

FASSUNG="n9.0.1"
# Der Commit hinter dem Tag. Ein Tag lässt sich auf dem Server verschieben,
# ein Commit-Hash nicht: Zeigt der Tag woanders hin, wird nicht gebaut.
COMMIT="bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa"

ZIEL="${1:?Zielordner angeben}"
ARBEIT="$(mktemp -d)"
trap 'rm -rf "$ARBEIT"' EXIT

echo "== Bauwerkzeuge =="
pacman -S --noconfirm --needed \
  mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-pkgconf \
  mingw-w64-x86_64-dav1d mingw-w64-x86_64-zlib make git

echo "== ffmpeg $FASSUNG holen =="
git clone --depth 1 --branch "$FASSUNG" \
  https://github.com/FFmpeg/FFmpeg.git "$ARBEIT/quelle"
IST="$(git -C "$ARBEIT/quelle" rev-parse HEAD)"
if [ "$IST" != "$COMMIT" ]; then
  echo "ffmpeg $FASSUNG zeigt auf $IST statt auf $COMMIT – abgebrochen" >&2
  exit 1
fi

# Was gelesen wird: die Videoformate von Telefonen, Kameras und älteren
# Digitalkameras (AVI/MJPEG, DV, WMV, 3GP) und die Tonformate, die sich
# als Musik unterlegen lassen (tonspur.dart).
VIDEO_DECODER="h264,hevc,mpeg4,msmpeg4v1,msmpeg4v2,msmpeg4v3,h263,h263p,\
mjpeg,mjpegb,prores,vp8,vp9,libdav1d,mpeg1video,mpeg2video,dvvideo,vc1,\
wmv1,wmv2,wmv3,theora,dnxhd,png,rawvideo,qtrle,flv"
AUDIO_DECODER="aac,aac_latm,mp3,mp3float,mp2,mp2float,ac3,eac3,alac,flac,\
opus,vorbis,amrnb,amrwb,wmav1,wmav2,adpcm_ima_qt,adpcm_ms,adpcm_ima_wav,\
pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,\
pcm_f32be,pcm_u8,pcm_s8,pcm_mulaw,pcm_alaw"
DEMUXER="mov,matroska,avi,mpegts,mpegps,mpegvideo,m4v,h264,hevc,mp3,aac,\
wav,w64,flac,ogg,aiff,caf,amr,asf,flv,dv,rawvideo,mjpeg"
# Was geschrieben wird: JPEG-Vorschaubilder, H.264 und MPEG-4 für
# Kameraflug und Diashow, AAC für die Musik.
ENCODER="mjpeg,h264_mf,mpeg4,aac"
# Der Zuschnitt schreibt in den Container, aus dem er liest. Die Namen
# sind die von configure, nicht die Endungen: .3gp heisst tgp, .mpg
# mpeg1system, .wmv asf.
MUXER="image2,mp4,mov,ipod,tgp,tg2,matroska,webm,avi,mpegts,mpeg1system,\
mpeg2vob,ogg,ogv,asf,flv,dv,null"
# Was die Aufrufe brauchen und was ffmpeg selbst einsetzt: Formatwandlung,
# Drehen nach den Metadaten eines Telefonvideos, Abtastraten.
FILTER="buffer,buffersink,abuffer,abuffersink,format,aformat,scale,\
aresample,null,anull,copy,acopy,transpose,hflip,vflip,rotate,afade,setsar,\
setpts,asetpts,trim,atrim,fps,settb,asettb,crop,pad,split,asplit"
# Kameraflug und Diashow schicken ihre Bilder über `-i -`; das liest
# ffmpeg 9 über das Protokoll fd, nicht mehr über pipe.
PROTOKOLLE="file,pipe,fd"

echo "== Konfigurieren =="
cd "$ARBEIT/quelle"
./configure \
  --prefix="$ARBEIT/fertig" \
  --target-os=mingw32 --arch=x86_64 \
  --enable-shared --disable-static \
  --disable-everything --disable-autodetect \
  --disable-doc --disable-debug --disable-network \
  --disable-avdevice --disable-ffplay \
  --enable-w32threads --enable-mediafoundation --enable-d3d11va \
  --enable-zlib --enable-libdav1d \
  --enable-decoder="$VIDEO_DECODER,$AUDIO_DECODER" \
  --enable-demuxer="$DEMUXER" \
  --enable-encoder="$ENCODER" \
  --enable-muxer="$MUXER" \
  --enable-filter="$FILTER" \
  --enable-parsers --enable-bsfs \
  --enable-protocol="$PROTOKOLLE" \
  --enable-swscale --enable-swresample \
  --extra-ldflags="-static-libgcc"

echo "== Übersetzen =="
make -j"$(nproc)"
make install

echo "== Einsammeln nach $ZIEL =="
mkdir -p "$ZIEL"
cp "$ARBEIT/fertig/bin/ffmpeg.exe" "$ARBEIT/fertig/bin/ffprobe.exe" "$ZIEL/"
cp "$ARBEIT/fertig/bin/"*.dll "$ZIEL/"

# Die LGPL verlangt, dass der Lizenztext mitgeht und klar ist, woraus
# gebaut wurde. Der Quelltext ist ffmpeg $FASSUNG unverändert; die
# Schalter stehen hier und in ffmpeg -buildconf.
cp "$ARBEIT/quelle/COPYING.LGPLv2.1" "$ZIEL/ffmpeg-LIZENZ.txt"
{
  echo "ffmpeg $FASSUNG (Commit $COMMIT), unveraendert,"
  echo "Quelle: https://github.com/FFmpeg/FFmpeg/tree/$FASSUNG"
  echo "Lizenz: LGPL 2.1 oder spaeter, siehe ffmpeg-LIZENZ.txt"
  echo "Gebaut mit tool/windows_ffmpeg.sh aus dem Photo-Vault-Quelltext:"
  "$ARBEIT/fertig/bin/ffmpeg.exe" -hide_banner -buildconf
} | sed 's/$/\r/' > "$ZIEL/ffmpeg-QUELLE.txt"

# Die DLL-Hülle wie bei libheif: in Runden nachlegen, am Ende belegen.
suchorte="$ARBEIT/fertig/bin /mingw64/bin"
huelle_ziehen() {
  cd "$ZIEL"
  for exe in ffmpeg.exe ffprobe.exe; do
    ldd "$exe" 2>/dev/null | grep -iE '/mingw64/|/fertig/' |
      sed 's/.*=> //; s/ (0x.*//' | sort -u |
      while read -r dll; do [ -f "$dll" ] && cp -f "$dll" "$ZIEL/"; done
    ldd "$exe" 2>/dev/null | grep -i 'not found' |
      sed 's/[[:space:]]*//; s/ =>.*//' | sort -u |
      while read -r name; do
        for ort in $suchorte; do
          if [ -f "$ort/$name" ]; then cp -f "$ort/$name" "$ZIEL/"; break; fi
        done
      done
  done
}
for _ in 1 2 3 4 5; do
  vorher=$(ls "$ZIEL" | wc -l)
  huelle_ziehen
  [ "$(ls "$ZIEL" | wc -l)" = "$vorher" ] && break
done

echo "== Huelle pruefen =="
cd "$ZIEL"
for exe in ffmpeg.exe ffprobe.exe; do
  if ldd "$exe" 2>/dev/null | grep -i 'not found'; then
    echo "FEHLER: $exe fehlen DLLs (siehe oben)." >&2
    exit 1
  fi
done
./ffmpeg.exe -hide_banner -version | head -1
echo "vollstaendig"
