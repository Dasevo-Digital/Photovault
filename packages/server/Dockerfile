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
# Siehe packages/server/README.md.

ARG DART_FASSUNG=3.13.5
ARG ORT_FASSUNG=1.28.3
ARG DEBIAN=trixie-slim

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

# --- Bündel für systemd ------------------------------------------------------
FROM debian:${DEBIAN} AS buendel
ARG ORT_FASSUNG
ARG TARGETARCH
COPY --from=bau /aus/bundle /pv/photo-vault-server
COPY --from=ort /libonnxruntime.so.${ORT_FASSUNG} /pv/photo-vault-server/lib/
COPY packages/server/linux /pv/photo-vault-server/systemd
COPY packages/server/README.md /pv/photo-vault-server/
RUN tar -C /pv --owner=0 --group=0 -czf "/photo-vault-server-linux-${TARGETARCH}.tar.gz" photo-vault-server

FROM scratch AS paket
COPY --from=buendel /photo-vault-server-linux-*.tar.gz /

# --- Das Bild ----------------------------------------------------------------
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
