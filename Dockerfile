FROM node:22-bookworm-slim

# Install deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    tini \
    ca-certificates \
    curl \
    gh \
    ripgrep \
 && rm -rf /var/lib/apt/lists/*

# Install Gmail CLI
ARG GOG_VERSION=0.11.0
RUN curl -L https://github.com/steipete/gogcli/releases/latest/download/gogcli_${GOG_VERSION}_linux_amd64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gog

# Install OpenClaw from npm
ARG OPENCLAW_VERSION=2026.3.1
RUN npm install -g openclaw@${OPENCLAW_VERSION}

ENV NODE_ENV=production \
    TINI_SUBREAPER=true \
    HOME=/home/node \
    OPENCLAW_STATE_DIR=/home/node/.openclaw

RUN mkdir -p /home/node/.openclaw/workspace \
 && chown -R node:node /home/node

USER node
ORKDIR /home/node

EXPOSE 18789 18790

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "--", "openclaw"]
