# Godot 4.6 Headless Game Server for Railway
# Build context must be the project root: docker build -f gameserver/Dockerfile .

FROM ubuntu:22.04 AS base

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download Godot 4.6 headless (Linux x86_64)
ARG GODOT_VERSION=4.6-stable
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && unzip -q "Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && mv "Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm *.zip

WORKDIR /game

# Copy only what the server needs (no build artifacts, no backend)
COPY project.godot .
COPY icon.svg .
COPY scripts/ scripts/
COPY scenes/ scenes/
COPY shaders/ shaders/
COPY data/ data/
COPY assets/ assets/

# Pre-import resources so first startup is fast
RUN godot --headless --import || true

# Railway sets PORT env var dynamically; our NetworkManager reads it
EXPOSE 7777

# Run as headless dedicated server
# NetworkManager._check_dedicated_server() detects headless → is_dedicated_server = true
# → calls start_dedicated_server() which reads PORT from env
ENTRYPOINT ["godot", "--headless", "--path", "/game"]
