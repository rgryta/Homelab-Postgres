ARG PG_VERSION=18
FROM postgres:${PG_VERSION}-alpine

ARG PGVECTOR_VERSION=0.8.1
ARG VECTORCHORD_VERSION=1.0.0

# Install build dependencies
RUN apk add --no-cache --virtual .build-deps \
    git \
    build-base \
    clang19 \
    llvm19 \
    cargo \
    rust

# Install pgvector
RUN git clone --branch v${PGVECTOR_VERSION} --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector \
    && cd /tmp/pgvector \
    && make OPTFLAGS="" \
    && make install \
    && rm -rf /tmp/pgvector

# Install VectorChord
# VectorChord requires pgrx - using pre-built releases instead
RUN set -e; \
    ARCH=$(uname -m); \
    case "$ARCH" in \
        x86_64) RUST_ARCH="x86_64-unknown-linux-musl" ;; \
        aarch64) RUST_ARCH="aarch64-unknown-linux-musl" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac; \
    PG_MAJOR=$(pg_config --version | sed 's/PostgreSQL //' | cut -d. -f1); \
    # Download pre-built VectorChord release
    wget -q "https://github.com/tensorchord/VectorChord/releases/download/${VECTORCHORD_VERSION}/vchord-pg${PG_MAJOR}-${RUST_ARCH}.tar.gz" -O /tmp/vchord.tar.gz || \
    # Fallback: build from source if pre-built not available
    (cd /tmp && \
     git clone --branch v${VECTORCHORD_VERSION} --depth 1 https://github.com/tensorchord/VectorChord.git && \
     cd VectorChord && \
     cargo install cargo-pgrx --version 0.12.9 --locked && \
     cargo pgrx init --pg${PG_MAJOR} $(which pg_config) && \
     cargo pgrx install --release --pg-config $(which pg_config) && \
     cd / && rm -rf /tmp/VectorChord); \
    # If tar exists, extract it
    if [ -f /tmp/vchord.tar.gz ]; then \
        mkdir -p /tmp/vchord && \
        tar -xzf /tmp/vchord.tar.gz -C /tmp/vchord && \
        cp -r /tmp/vchord/usr/lib/postgresql/${PG_MAJOR}/lib/* $(pg_config --pkglibdir)/ 2>/dev/null || true && \
        cp -r /tmp/vchord/usr/share/postgresql/${PG_MAJOR}/extension/* $(pg_config --sharedir)/extension/ 2>/dev/null || true && \
        rm -rf /tmp/vchord /tmp/vchord.tar.gz; \
    fi

# Cleanup build dependencies
RUN apk del .build-deps \
    && rm -rf /root/.cargo /root/.rustup /tmp/*

# Create tablespace directories with correct permissions
# These will be mounted as volumes at runtime
RUN mkdir -p /mnt/tablespaces/nvme /mnt/tablespaces/archive \
    && chown postgres:postgres /mnt/tablespaces/nvme /mnt/tablespaces/archive \
    && chmod 700 /mnt/tablespaces/nvme /mnt/tablespaces/archive

# Add VectorChord to shared_preload_libraries via custom config
RUN echo "shared_preload_libraries = 'vchord.so'" >> /usr/local/share/postgresql/postgresql.conf.sample

# Labels for version tracking
LABEL org.opencontainers.image.title="Homelab PostgreSQL"
LABEL org.opencontainers.image.description="PostgreSQL with pgvector and VectorChord extensions"
LABEL org.opencontainers.image.source="https://github.com/rgryta/Homelab-Postgres"
LABEL pgvector.version="${PGVECTOR_VERSION}"
LABEL vectorchord.version="${VECTORCHORD_VERSION}"
