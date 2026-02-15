# Godot 4.6 Headless Game Server for Railway (root Dockerfile)

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip ca-certificates \
    fontconfig libfontconfig1 libfreetype6 fonts-dejavu-core \
    libgl1 libxi6 libxcursor1 libxrandr2 libxinerama1 \
    && rm -rf /var/lib/apt/lists/*

ARG GODOT_VERSION=4.6-stable
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && cd /tmp && unzip -q godot.zip \
    && mv "Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm godot.zip

WORKDIR /game

COPY project.godot icon.svg ./
COPY data/ data/
COPY shaders/ shaders/
COPY assets/fonts/ assets/fonts/
COPY assets/models/tie.glb assets/models/
COPY assets/models/frigate_mk1.glb assets/models/
COPY assets/models/canon_laser.glb assets/models/
COPY assets/models/tourelle.glb assets/models/
COPY scenes/ scenes/
COPY scripts/ scripts/

ENTRYPOINT ["godot", "--headless", "--path", "/game"]
