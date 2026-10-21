# Dockerized Baikal Server

A lightweight, optimized Docker container for [Baikal](https://sabre.io/baikal/), a free CalDAV and CardDAV server.

## Features

- **Base:** Alpine Linux (Lightweight)
- **Web Server:** Nginx (Optimized configuration)
- **PHP:** PHP 8.5 via PHP-FPM
- **Database:** External PostgreSQL via PDO
- **Processes:** Tini and a shell wrapper manage Nginx and PHP-FPM, drain requests on shutdown, and exit on service failure
- **Security:** Root-owned application code and unprivileged web workers; only application data and runtime directories are writable by workers
- **Monitoring:** Nginx/PHP-FPM health check and logs on stdout/stderr
- **Updates:** Verified release ZIP checksum, with Renovate updating the version and SHA-256 together

## Usage

### 1. Build the image
```bash
docker build -t my-baikal .
```

### 2. Run with Docker Compose (Recommended)

Create a `docker-compose.yml` file:

```yaml
services:
  baikal:
    build: .
    image: my-baikal:latest
    container_name: baikal
    restart: unless-stopped
    stop_grace_period: 30s
    ports:
      - "8080:80"
    volumes:
      - ./data/config:/var/www/baikal/config
      - ./data/specific:/var/www/baikal/Specific
```

Run it:

```bash
docker compose up -d
```

### 3. Run with Docker CLI

```bash
docker run -d \
  --name baikal \
  --stop-timeout 30 \
  -p 8080:80 \
  -v "$(pwd)/data/config:/var/www/baikal/config" \
  -v "$(pwd)/data/specific:/var/www/baikal/Specific" \
  my-baikal
```

### Initial Setup

1. Open your browser and navigate to `http://localhost:8080`.
2. Follow the Baikal installation wizard and select PostgreSQL.
3. Supply the hostname, database name, username, and password for your PostgreSQL server. The server must be reachable from the container; `localhost` refers to the Baikal container itself. If PostgreSQL runs in another container, attach both services to the same Docker network and use its service name.

Create the PostgreSQL database and its user before running the wizard. This image installs the PostgreSQL driver; it does not include a database server or SQLite/MySQL drivers.

## Configuration

| Path | Description |
| --- | --- |
| `/var/www/baikal/config` | Contains `baikal.yaml` and system config. |
| `/var/www/baikal/Specific` | Baikal's persistent application-specific files. Calendar/contact records reside in PostgreSQL. |

The entrypoint and service master processes run as root to prepare mounted directories and start the services. Nginx and PHP request workers run as `nginx`. Application code is not writable by those workers.

The health check requests the container-local `/health` endpoint through Nginx and PHP-FPM. It checks those services independently of installation state; it does not verify the PostgreSQL connection. Inspect health using `docker inspect baikal` and logs using `docker logs baikal`. Docker restart policies react to process exit, not an `unhealthy` status alone.

## Updates and validation

`BAIKAL_VERSION` and `BAIKAL_SHA256` in the Dockerfile are one Renovate dependency using the `github-release-attachments` datasource. Renovate identifies the release ZIP by its existing SHA-256 and computes the corresponding new release's checksum. Keep both values together when updating manually. The build verifies the checksum before unpacking and fails if the archive does not match.

CI builds and smoke-tests the ARM64 image before publishing. Weekly and manually triggered builds bypass the build cache to refresh Alpine packages, even when the base-image digest has not changed. Workflow changes also run CI.

Builds from `main` publish both the Baikal version tag and `latest`. The separate **Clean up old container images** workflow runs weekly and removes untagged images older than 30 days. It preserves tagged releases and the platform manifests and attestations they reference. Publishing and cleanup share a concurrency lock to prevent overlapping registry changes.

For a cleanup preview, run that workflow manually with `dry_run` enabled (the default). Disable it to perform the cleanup. Scheduled runs perform the cleanup automatically. Images pinned only by an old, untagged digest are subject to this 30-day retention policy.

To run the same smoke tests locally (Docker and Python 3 required):

```bash
docker build -t baikal:test .
python3 tests/smoke.py baikal:test
```

Tests create disposable containers without publishing ports or using existing data. They cover startup, PostgreSQL driver availability, code/data permissions, logging, health checks, graceful shutdown, and service failures.

## Troubleshooting

**Permission Issues:**
The entrypoint fixes ownership of both `/var/www/baikal/Specific` and `/var/www/baikal/config` on startup, including bind mounts. Ensure those mounts allow ownership changes and are writable. Back up both directories and your PostgreSQL database before upgrades.
