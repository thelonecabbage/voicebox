# ============================================================
# Voicebox — Local TTS Server with Web UI (CPU)
# 3-stage build: Frontend → Python deps → Runtime
# ============================================================

# === Stage 1: Build frontend ===
FROM oven/bun:1 AS frontend

WORKDIR /build

# Copy workspace config and frontend source
COPY package.json bun.lock CHANGELOG.md ./
COPY app/ ./app/
COPY web/ ./web/

# Strip workspaces not needed for web build, and fix trailing comma
RUN sed -i '/"tauri"/d; /"landing"/d' package.json && \
    sed -i -z 's/,\n  ]/\n  ]/' package.json
RUN bun install --no-save
# Build frontend (skip tsc — upstream has pre-existing type errors)
RUN cd web && bunx --bun vite build


# === Stage 2: Build Python dependencies ===
FROM python:3.11-slim-bookworm AS backend-builder

WORKDIR /build

RUN set -eux; \
    printf 'Acquire::Retries "5";\nAcquire::ForceIPv4 "true";\n' \
        > /etc/apt/apt.conf.d/80-network-workarounds; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        build-essential; \
    rm -rf /var/lib/apt/lists/*
    
RUN pip install --no-cache-dir --upgrade pip

COPY backend/requirements.txt .

# Keep the Docker image CPU-only. Without these constraints pip resolves the
# newest PyPI torch build, which pulls the full CUDA dependency stack.
RUN printf '%s\n' \
    'torch==2.7.1+cpu' \
    'torchaudio==2.7.1+cpu' \
    > docker-constraints.txt
RUN pip install --no-cache-dir --prefix=/install \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    -c docker-constraints.txt \
    -r requirements.txt
RUN pip install --no-cache-dir --prefix=/install --no-deps chatterbox-tts
RUN pip install --no-cache-dir --prefix=/install --no-deps hume-tada
RUN pip install --no-cache-dir --prefix=/install --no-deps \
    git+https://github.com/QwenLM/Qwen3-TTS.git


# === Stage 3: Runtime ===
FROM python:3.11-slim-bookworm

# Create non-root user for security
RUN groupadd -r voicebox && \
    useradd -r -g voicebox -m -s /bin/bash voicebox

WORKDIR /app

# Install only runtime system dependencies
RUN set -eux; \
    printf 'Acquire::Retries "5";\nAcquire::ForceIPv4 "true";\n' \
        > /etc/apt/apt.conf.d/80-network-workarounds; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        ffmpeg \
        curl \
        libatomic1; \
    rm -rf /var/lib/apt/lists/*

ARG VOICEBOX_UID=1000
ARG VOICEBOX_GID=1000
RUN groupmod --gid "${VOICEBOX_GID}" voicebox && \
    usermod --uid "${VOICEBOX_UID}" --gid voicebox voicebox && \
    chown -R voicebox:voicebox /home/voicebox
    
# Copy installed Python packages from builder stage
COPY --from=backend-builder /install /usr/local

# Copy backend application code
COPY --chown=voicebox:voicebox backend/ /app/backend/

# Copy built frontend from frontend stage
COPY --from=frontend --chown=voicebox:voicebox /build/web/dist /app/frontend/

# Create data directories owned by non-root user
RUN mkdir -p /app/data/generations /app/data/profiles /app/data/cache \
    && chown -R voicebox:voicebox /app/data

COPY docker-entrypoint.sh /usr/local/bin/voicebox-entrypoint
RUN chmod +x /usr/local/bin/voicebox-entrypoint

# Expose the API port
EXPOSE 17493

# Health check — auto-restart if the server hangs
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -f http://localhost:17493/health || exit 1

# Start the FastAPI server
ENTRYPOINT ["voicebox-entrypoint"]
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "17493"]
