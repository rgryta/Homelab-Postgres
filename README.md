## Homelab PostgreSQL

Custom PostgreSQL image with vector extensions for homelab services.

### Features

- **PostgreSQL 18** (Alpine-based)
- **pgvector** - Vector similarity search
- **VectorChord** - High-performance vector indexing (successor to pgvecto.rs)
- **Tablespace support** - Pre-configured directories for storage tiering
- **Multi-arch** - Supports amd64 and arm64

### Image Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest build from main branch |
| `pg18` | PostgreSQL 18 with default extension versions |
| `pg18-pgvector0.8.1-vchord1.0.0` | Fully versioned tag |

### Docker Compose

```yaml
services:
  postgres:
    image: ghcr.io/rgryta/homelab-postgres:latest
    container_name: homelab-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--data-checksums"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - nvme_indexes:/mnt/tablespaces/nvme
      - archive_data:/mnt/tablespaces/archive
      - ./init-scripts:/docker-entrypoint-initdb.d:ro
    networks:
      homelab-network:
        ipv4_address: 172.20.0.30
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 256M
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  postgres_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/quick/apps/volumes/databases/postgres/data
  nvme_indexes:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/quick/apps/volumes/databases/postgres/tablespaces/nvme_indexes
  archive_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/archive/apps/volumes/databases/postgres/tablespaces/archive_data

networks:
  homelab-network:
    external: true
```

### Extensions Setup

Create an init script to enable extensions in your databases:

**init-scripts/01-setup.sql:**
```sql
-- Create tablespaces (directories pre-created in image)
CREATE TABLESPACE nvme_ts LOCATION '/mnt/tablespaces/nvme';
CREATE TABLESPACE archive_ts LOCATION '/mnt/tablespaces/archive';

-- Create database with vector support
CREATE DATABASE myapp;
\c myapp
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS vchord;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Verify extensions
SELECT extname, extversion FROM pg_extension;
```

### Storage Tiering

The image includes pre-configured tablespace directories:

| Mount Point | Purpose |
|-------------|---------|
| `/mnt/tablespaces/nvme` | Fast storage (indexes, hot data) |
| `/mnt/tablespaces/archive` | Bulk storage (cold data) |

Example: Store large tables on archive, indexes on NVMe:
```sql
CREATE DATABASE mydb TABLESPACE archive_ts;
\c mydb
-- After importing data, move indexes to fast storage:
ALTER INDEX my_index SET TABLESPACE nvme_ts;
```

### Building Locally

```bash
docker build -t homelab-postgres:local \
  --build-arg PG_VERSION=18 \
  --build-arg PGVECTOR_VERSION=0.8.1 \
  --build-arg VECTORCHORD_VERSION=1.0.0 \
  .
```

### Default Versions

| Component | Default |
|-----------|---------|
| PostgreSQL | 18 |
| pgvector | 0.8.1 |
| VectorChord | 1.0.0 |

### Credits

- PostgreSQL: https://www.postgresql.org/
- pgvector: https://github.com/pgvector/pgvector
- VectorChord: https://github.com/tensorchord/VectorChord
