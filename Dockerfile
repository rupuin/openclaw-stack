# syntax=docker/dockerfile:1
############################
# Build args (global – available in all stages)
############################
ARG WHISPER_CPP_REF=master
ARG WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
ARG GOG_VERSION=0.12.0
ARG OPENCLAW_VERSION=2026.4.2

############################
# 1) Build whisper.cpp (whisper-cli)
############################
FROM debian:bookworm-slim AS whisper_builder

# Re-declare ARG so the global value flows into this stage
ARG WHISPER_CPP_REF

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates \
      build-essential cmake pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone \
      --depth 1 \
      --single-branch \
      --branch "${WHISPER_CPP_REF}" \
      https://github.com/ggerganov/whisper.cpp.git

WORKDIR /src/whisper.cpp

#  fully static binary; no .so copying headaches
RUN cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
    && cmake --build build -j"$(nproc)" \
    && test -x build/bin/whisper-cli

# Verify: should print "not a dynamic executable" (or minimal system libs only)
RUN ldd build/bin/whisper-cli || true

############################
# 2) Runtime image (OpenClaw)
############################
FROM node:25-bookworm-slim

# Re-declare ARGs needed in this stage
ARG WHISPER_MODEL_URL
ARG GOG_VERSION
ARG OPENCLAW_VERSION

# ---- OS runtime deps ----
RUN apt-get update && apt-get install -y --no-install-recommends \
      git tini ca-certificates curl \
      gh ripgrep jq fd-find procps \
      ffmpeg \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# ---- whisper-cli (statically linked → no ldconfig needed) ----
COPY --from=whisper_builder --chmod=755 \
     /src/whisper.cpp/build/bin/whisper-cli /usr/local/bin/whisper-cli

# Smoke-test at build time so a broken binary fails the build immediately
RUN whisper-cli --help >/dev/null

# ---- Whisper model ----
# Cache the downloaded model across builds with BuildKit cache mount
RUN --mount=type=cache,target=/opt/whisper/model-cache \
    mkdir -p /opt/whisper/models \
    && if [ ! -f /opt/whisper/model-cache/ggml-base.en.bin ]; then \
         curl -fsSL "${WHISPER_MODEL_URL}" \
              -o /opt/whisper/model-cache/ggml-base.en.bin; \
       fi \
    && cp /opt/whisper/model-cache/ggml-base.en.bin /opt/whisper/models/ggml-base.en.bin

ENV WHISPER_CPP_MODEL=/opt/whisper/models/ggml-base.en.bin

# ---- gogcli ----
RUN curl -fsSL \
      "https://github.com/steipete/gogcli/releases/download/v${GOG_VERSION}/gogcli_${GOG_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/gog \
    && gog --version

# ---- OpenClaw ----
ARG OPENCLAW_VERSION
RUN npm install -g "openclaw@${OPENCLAW_VERSION}"

# ---- Runtime environment ----
ENV NODE_ENV=production \
    TINI_SUBREAPER=true \
    HOME=/home/node \
    OPENCLAW_STATE_DIR=/home/node/.openclaw

RUN mkdir -p /home/node/.openclaw/workspace \
    && chown -R node:node /home/node /opt/whisper

USER node
WORKDIR /home/node

EXPOSE 18789 18790

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
    CMD node -e "fetch('http://127.0.0.1:18789/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "--", "openclaw"]
