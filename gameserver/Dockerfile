# Godot 4.6 Headless Game Server for Railway
# Build context must be the project root: docker build -f gameserver/Dockerfile .

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip ca-certificates \
    fontconfig libfontconfig1 libfreetype6 fonts-dejavu-core \
    libgl1 libxi6 libxcursor1 libxrandr2 libxinerama1 \
    && rm -rf /var/lib/apt/lists/*

# Godot download — cached in its own layer
ARG GODOT_VERSION=4.6-stable
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && cd /tmp && unzip -q godot.zip \
    && mv "Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm godot.zip

WORKDIR /game

# --- Layers ordered: least-changed → most-changed for max cache ---

# 1. Project config (rarely changes)
COPY project.godot icon.svg ./

# 2. Data + shaders (change sometimes)
COPY data/ data/
COPY shaders/ shaders/

# 3. Assets — copied in bulk, heavy visual-only files excluded via .dockerignore
COPY assets/ assets/

# 4. Scenes (change sometimes)
COPY scenes/ scenes/

# 5. Scripts (change most often — last for best cache)
COPY scripts/ scripts/

# 6. Import project — generates .godot/ with script class cache, font imports, etc.
#    Without this, class_name resolution fails and all autoloads crash.
RUN godot --headless --import || true

ENTRYPOINT ["godot", "--headless", "--path", "/game"]
