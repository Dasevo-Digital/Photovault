# syntax=docker/dockerfile:1
#
# Der Photo Vault Server als Docker-Bild – und dasselbe Programm als Bündel
# für systemd. Gebaut wird vom Wurzelordner des Repos aus, weil der Server
# den Kern (packages/kern) und die ONNX-API (third_party/onnxruntime_api)
# als Pfadabhängigkeiten mitbringt:
#
#   docker buildx build -f packages/server/Dockerfile \
#     --platform linux/amd64,linux/arm64 -t photo-vault-server .
#
# Das Bündel für systemd (bin/, lib/, systemd/) als tar.gz je Plattform:
#
#   docker buildx build -f packages/server/Dockerfile --target paket \
#     --platform linux/amd64,linux/arm64 --output type=local,dest=aus .
#
# Das Bild für Intel-Grafik (OpenVINO, nur amd64; Issue #104):
#
#   docker buildx build -f packages/server/Dockerfile --target openvino \
#     --platform linux/amd64 -t photo-vault-server:openvino .
#
# … und als Bündel für systemd:
#
#   docker buildx build -f packages/server/Dockerfile --target paket-openvino \
#     --platform linux/amd64 --output type=local,dest=aus .
#
# Siehe packages/server/README.md.

ARG DART_FASSUNG=3.13.5
ARG ORT_FASSUNG=1.28.3
ARG DEBIAN=trixie-slim
ARG UBUNTU=26.04

# --- Übersetzen ------------------------------------------------------------
# `dart build cli` statt `dart compile exe`: sqlite3 bringt seine Bibliothek
# über einen Bau-Hook mit, und den kennt nur `dart build`. Heraus kommt ein
# Bündel aus bin/photo_vault_server und lib/libsqlite3.so.
FROM dart:${DART_FASSUNG} AS bau
WORKDIR /quelle
COPY third_party/onnxruntime_api third_party/onnxruntime_api
COPY packages/kern packages/kern
COPY packages/server packages/server
WORKDIR /quelle/packages/server
RUN dart pub get --enforce-lockfile
# Die Fassung ins Programm schreiben (siehe lib/src/fassung.dart).
ARG PV_FASSUNG=Entwicklung
ARG PV_COMMIT=
RUN printf "const serverFassung = '%s';\nconst serverCommit = '%s';\n" "$PV_FASSUNG" "$PV_COMMIT" > lib/src/fassung.dart
RUN dart build cli -o /aus

# --- ONNX Runtime ------------------------------------------------------------
# Das offizielle Paket von Microsoft in genau der Fassung, mit der auch die
# App rechnet (third_party/flutter_onnxruntime) – sonst wären die Ergebnisse
# nicht dieselben. Die Prüfsummen stehen in der Freigabe auf GitHub.
FROM debian:${DEBIAN} AS ort
ARG ORT_FASSUNG
ARG TARGETARCH
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) arch=x64; summe=db14e4863bd37893fc59729d986ab2a0d043d10b7d44da1913c4982b7e3d009c ;; \
      arm64) arch=aarch64; summe=6c6b1ae96d7b0be9f555092857c6a4f2b0b5587a5298d732d9e52e8253038ce7 ;; \
      *) echo "keine ONNX Runtime für $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/ort.tgz \
      "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_FASSUNG}/onnxruntime-linux-${arch}-${ORT_FASSUNG}.tgz"; \
    echo "$summe  /tmp/ort.tgz" | sha256sum -c -; \
    mkdir /ort; \
    tar -xzf /tmp/ort.tgz -C /ort --strip-components=1; \
    cp "/ort/lib/libonnxruntime.so.${ORT_FASSUNG}" /libonnxruntime.so.${ORT_FASSUNG}; \
    rm -rf /tmp/ort.tgz /ort

# --- ONNX Runtime mit OpenVINO (nur amd64) -----------------------------------
# Intels Bau aus dem Python-Paket onnxruntime-openvino 1.24.1: libonnxruntime
# mit dem Anbieter für OpenVINO 2025.4 und dessen Plugins (CPU, Grafik, NPU).
# Neuer gibt es ihn nicht fertig – der Server lädt die ältere Fassung und
# sagt beim Start, dass sie nicht die der App ist (siehe geprueftFassung).
# Was auf der Grafik rechnet, besteht vorher die Gegenprobe gegen die CPU.
FROM debian:${DEBIAN} AS ort-openvino
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl python3 \
 && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    curl -fsSL -o /tmp/ov.whl \
      "https://files.pythonhosted.org/packages/50/cf/17ba72de2df0fcba349937d2788f154397bbc2d1a2d67772a97e26f6bc5f/onnxruntime_openvino-1.24.1-cp312-cp312-manylinux_2_28_x86_64.whl"; \
    echo "d617fac2f59a6ab5ea59a788c3e1592240a129642519aaeaa774761dfe35150e  /tmp/ov.whl" | sha256sum -c -; \
    python3 -m zipfile -e /tmp/ov.whl /tmp/ov; \
    mkdir /ov; \
    cp -a /tmp/ov/onnxruntime/capi/*.so* /ov/; \
    rm -f /ov/onnxruntime_pybind11_state*; \
    rm -rf /tmp/ov /tmp/ov.whl

# --- Bündel für systemd ------------------------------------------------------
FROM debian:${DEBIAN} AS buendel
ARG ORT_FASSUNG
ARG TARGETARCH
COPY --from=bau /aus/bundle /pv/photo-vault-server
COPY --from=ort /libonnxruntime.so.${ORT_FASSUNG} /pv/photo-vault-server/lib/
COPY packages/server/linux /pv/photo-vault-server/systemd
COPY packages/server/README.md /pv/photo-vault-server/
COPY packages/server/web /pv/photo-vault-server/web
COPY assets/lebensbaum /pv/photo-vault-server/web/lebensbaum
COPY assets/fonts/EBGaramond-Variable.ttf /pv/photo-vault-server/web/schrift/ebgaramond.ttf
COPY assets/fonts/GreatVibes-Regular.ttf /pv/photo-vault-server/web/schrift/greatvibes.ttf
COPY assets/fonts/OFL-EBGaramond.txt assets/fonts/OFL-GreatVibes.txt /pv/photo-vault-server/web/schrift/
RUN tar -C /pv --owner=0 --group=0 -czf "/photo-vault-server-linux-${TARGETARCH}.tar.gz" photo-vault-server

FROM scratch AS paket
COPY --from=buendel /photo-vault-server-linux-*.tar.gz /

# Dasselbe Bündel mit Intels ONNX Runtime unter lib/openvino (nur amd64;
# siehe README, „Intel-Grafik mit systemd“).
FROM buendel AS buendel-openvino
COPY --from=ort-openvino /ov /pv/photo-vault-server/lib/openvino
RUN tar -C /pv --owner=0 --group=0 \
      -czf /photo-vault-server-linux-amd64-openvino.tar.gz photo-vault-server

FROM scratch AS paket-openvino
COPY --from=buendel-openvino /photo-vault-server-linux-amd64-openvino.tar.gz /

# --- Das Bild für Intel-Grafik -------------------------------------------------
# Ubuntu statt Debian: Den Treiber für Rechnen auf der Intel-Grafik
# (intel-opencl-icd, Level Zero) hat Debian trixie nicht. Die Grafik kommt
# mit `--device /dev/dri` in den Container; der Nutzer braucht die Gruppe,
# der /dev/dri/renderD128 auf dem Wirt gehört (`--group-add …`, siehe
# README).
FROM ubuntu:${UBUNTU} AS openvino
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ffmpeg \
      libheif-examples libheif-plugin-libde265 libheif-plugin-dav1d \
      libraw-bin \
      tzdata \
      intel-opencl-icd libze-intel-gpu1 libze1 \
 && rm -rf /var/lib/apt/lists/*
RUN groupadd --system --gid 8790 photovault \
 && useradd --system --uid 8790 --gid 8790 --home-dir /daten --no-create-home photovault \
 && mkdir /daten && chown photovault:photovault /daten
COPY --from=bau /aus/bundle /opt/photo-vault-server
COPY packages/server/web /opt/photo-vault-server/web
COPY assets/lebensbaum /opt/photo-vault-server/web/lebensbaum
COPY assets/fonts/EBGaramond-Variable.ttf /opt/photo-vault-server/web/schrift/ebgaramond.ttf
COPY assets/fonts/GreatVibes-Regular.ttf /opt/photo-vault-server/web/schrift/greatvibes.ttf
COPY assets/fonts/OFL-EBGaramond.txt assets/fonts/OFL-GreatVibes.txt /opt/photo-vault-server/web/schrift/
COPY --from=ort-openvino /ov /opt/photo-vault-server/lib/openvino
RUN printf '#!/bin/sh\nexec /opt/photo-vault-server/bin/photo_vault_server "$@"\n' \
      > /usr/local/bin/photo_vault_server \
 && chmod 755 /usr/local/bin/photo_vault_server
ENV PV_DATEN=/daten \
    PV_ADRESSE=0.0.0.0 \
    PV_PORT=8790 \
    PV_ONNXRUNTIME=/opt/photo-vault-server/lib/openvino/libonnxruntime.so.1.24.1 \
    PV_BESCHLEUNIGER=openvino
USER photovault
VOLUME /daten
EXPOSE 8790
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s \
  CMD ["/opt/photo-vault-server/bin/photo_vault_server", "--lebenszeichen"]
ENTRYPOINT ["/opt/photo-vault-server/bin/photo_vault_server"]

# --- Das Bild ----------------------------------------------------------------
# Zuletzt, damit es bleibt, was ohne `--target` entsteht.
FROM debian:${DEBIAN}
ARG ORT_FASSUNG
# Dieselben Werkzeuge wie die App unter Linux: ffmpeg für Videos, libheif
# für HEIC/AVIF (die Dekoder sind eigene Pakete und fehlen ohne sie still),
# LibRaw für RAW.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ffmpeg \
      libheif-examples libheif-plugin-libde265 libheif-plugin-dav1d \
      libraw-bin \
      tzdata \
 && rm -rf /var/lib/apt/lists/*
RUN groupadd --system --gid 8790 photovault \
 && useradd --system --uid 8790 --gid 8790 --home-dir /daten --no-create-home photovault \
 && mkdir /daten && chown photovault:photovault /daten
COPY --from=bau /aus/bundle /opt/photo-vault-server
COPY packages/server/web /opt/photo-vault-server/web
COPY assets/lebensbaum /opt/photo-vault-server/web/lebensbaum
COPY assets/fonts/EBGaramond-Variable.ttf /opt/photo-vault-server/web/schrift/ebgaramond.ttf
COPY assets/fonts/GreatVibes-Regular.ttf /opt/photo-vault-server/web/schrift/greatvibes.ttf
COPY assets/fonts/OFL-EBGaramond.txt assets/fonts/OFL-GreatVibes.txt /opt/photo-vault-server/web/schrift/
COPY --from=ort /libonnxruntime.so.${ORT_FASSUNG} /opt/photo-vault-server/lib/
# Für die Verwaltung: docker exec -it … photo_vault_server konto anlegen NAME.
# Ein Startskript statt eines Symlinks: Die Bibliotheken liegen relativ zum
# Programm, und das soll unter seinem eigenen Pfad laufen.
RUN printf '#!/bin/sh\nexec /opt/photo-vault-server/bin/photo_vault_server "$@"\n' \
      > /usr/local/bin/photo_vault_server \
 && chmod 755 /usr/local/bin/photo_vault_server
# Im Bild auf allen Adressen: Erreichbar ist der Server trotzdem nur über
# das, was der Container nach aussen gibt – hinter dem Reverse Proxy.
ENV PV_DATEN=/daten \
    PV_ADRESSE=0.0.0.0 \
    PV_PORT=8790
USER photovault
VOLUME /daten
EXPOSE 8790
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s \
  CMD ["/opt/photo-vault-server/bin/photo_vault_server", "--lebenszeichen"]
ENTRYPOINT ["/opt/photo-vault-server/bin/photo_vault_server"]
