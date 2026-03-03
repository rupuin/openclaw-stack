# syntax=docker/dockerfile:1

############################
# 1) Build whisper.cpp 
############################
FROM debian:bookworm-slim AS whisper_builder

ARG WHISPER_CPP_REF=master

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates \
    build-essential cmake pkg-config \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${WHISPER_CPP_REF}" https://github.com/ggerganov/whisper.cpp.git

WORKDIR /src/whisper.cpp
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  && cmake --build build -j \
  && test -x build/bin/whisper-cli

############################
# 2) Runtime image (OpenClaw)
############################
FROM node:22-bookworm-slim

# --- OS deps (runtime) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git tini ca-certificates curl \
    gh ripgrep jq fd-find procps \
    ffmpeg \
  && rm -rf /var/lib/apt/lists/*

# Debian packages fd as `fdfind`
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd

# --- whisper-cli ---
COPY --from=whisper_builder /src/whisper.cpp/build/bin/whisper-cli /usr/local/bin/whisper-cli

# --- Whisper model (kept in image) ---
ARG WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
RUN mkdir -p /opt/whisper/models \
  && curl -L "${WHISPER_MODEL_URL}" -o /opt/whisper/models/ggml-base.en.bin

ENV WHISPER_CPP_MODEL=/opt/whisper/models/ggml-base.en.bin

# --- gogcli (Gmail/Workspace CLI) ---
ARG GOG_VERSION=0.11.0
RUN curl -L "https://github.com/steipete/gogcli/releases/latest/download/gogcli_${GOG_VERSION}_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local/bin \
  && chmod +x /usr/local/bin/gog

# --- OpenClaw ---
ARG OPENCLAW_VERSION=2026.3.1
RUN npm install -g "openclaw@${OPENCLAW_VERSION}"

ENV NODE_ENV=production \
    TINI_SUBREAPER=true \
    HOME=/home/node \
    OPENCLAW_STATE_DIR=/home/node/.openclaw

RUN mkdir -p /home/node/.openclaw/workspace \
  && chown -R node:node /home/node

USER node
WORKDIR /home/node

EXPOSE 18789 18790

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "--", "openclaw"]
