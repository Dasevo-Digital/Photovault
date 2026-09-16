#!/bin/sh
# Der Flutter-Bau erwartet seinen data-Ordner neben der ausführbaren Datei,
# deshalb liegt das ganze Bündel unter /app/photo_vault und nicht in
# /app/bin.
# Die Plugin-Bibliotheken tragen eine RUNPATH aus dem Baurechner. Der
# Suchpfad wird VOR der RUNPATH ausgewertet, also gewinnt hier immer die
# Fassung aus dem Bündel – auch auf dem Rechner, auf dem gebaut wurde.
# Ohne diese Zeile lud die App ONNX Runtime aus dem Bauverzeichnis, was
# nur dort existiert.
export LD_LIBRARY_PATH="/app/photo_vault/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec /app/photo_vault/photo_vault "$@"
