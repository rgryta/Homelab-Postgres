# Versions managed in .versions file - these are fallback defaults for local builds
ARG PG_VERSION=18

# =============================================================================
# Base builder: common dependencies
# =============================================================================
FROM postgres:${PG_VERSION}-alpine AS builder-base

RUN apk add --no-cache \
    git \
    build-base \
    clang19 \
    clang-dev \
    llvm19 \
    cargo \
    rust \
    rustfmt \
    openssl-dev

# =============================================================================
# Stage: Build pgvector (parallel)
# =============================================================================
FROM builder-base AS pgvector-builder

ARG PGVECTOR_VERSION=0.8.1

RUN git clone --branch v${PGVECTOR_VERSION} --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector \
    && cd /tmp/pgvector \
    && make OPTFLAGS="" \
    && make install

# =============================================================================
# Stage: Build VectorChord (parallel)
# =============================================================================
FROM builder-base AS vchord-builder

ARG VECTORCHORD_VERSION=1.0.0

RUN PG_MAJOR=$(pg_config --version | sed 's/PostgreSQL //' | cut -d. -f1) \
    && cargo install cargo-pgrx --version 0.16.1 --locked \
    && cargo pgrx init --pg${PG_MAJOR} $(which pg_config) \
    && git clone --branch ${VECTORCHORD_VERSION} --depth 1 https://github.com/tensorchord/VectorChord.git /tmp/vchord \
    && cd /tmp/vchord \
    && cargo pgrx install --release --pg-config $(which pg_config)

# =============================================================================
# Final stage: clean Alpine with extensions
# =============================================================================
FROM postgres:${PG_VERSION}-alpine

ARG PGVECTOR_VERSION=0.8.1
ARG VECTORCHORD_VERSION=1.0.0

# Copy pgvector extension
COPY --from=pgvector-builder /usr/local/lib/postgresql/vector.so /usr/local/lib/postgresql/
COPY --from=pgvector-builder /usr/local/share/postgresql/extension/vector* /usr/local/share/postgresql/extension/

# Copy VectorChord extension
COPY --from=vchord-builder /usr/local/lib/postgresql/vchord.so /usr/local/lib/postgresql/
COPY --from=vchord-builder /usr/local/share/postgresql/extension/vchord* /usr/local/share/postgresql/extension/

# Create tablespace directories with correct permissions
RUN mkdir -p /mnt/tablespaces/nvme /mnt/tablespaces/archive \
    && chown postgres:postgres /mnt/tablespaces/nvme /mnt/tablespaces/archive \
    && chmod 700 /mnt/tablespaces/nvme /mnt/tablespaces/archive

# Add VectorChord to shared_preload_libraries
RUN echo "shared_preload_libraries = 'vchord.so'" >> /usr/local/share/postgresql/postgresql.conf.sample

# Labels for version tracking
LABEL org.opencontainers.image.title="Homelab PostgreSQL"
LABEL org.opencontainers.image.description="PostgreSQL with pgvector and VectorChord extensions"
LABEL org.opencontainers.image.source="https://github.com/rgryta/Homelab-Postgres"
LABEL pgvector.version="${PGVECTOR_VERSION}"
LABEL vectorchord.version="${VECTORCHORD_VERSION}"
