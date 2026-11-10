# Servidor de Mega Tic Toe: Godot en modo headless.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/godot.zip \
       "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY project.godot ./
COPY scripts ./scripts
COPY scenes ./scenes
COPY server ./server

# El puerto lo da la plataforma por la variable PORT (por defecto 9080).
CMD ["godot", "--headless", "-s", "server/server_main.gd"]
