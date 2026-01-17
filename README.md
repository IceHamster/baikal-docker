# Dockerized Baikal Server

A lightweight, optimized Docker container for [Baikal](https://sabre.io/baikal/), a free CalDAV and CardDAV server.

## Features

- **Base:** Alpine Linux (Lightweight)
- **Web Server:** Nginx (Optimized configuration)
- **PHP:** PHP 8.5 via PHP-FPM
- **Architecture:** Managed via Supervisord for robustness
- **Security:** Hardened Nginx headers, non-root application execution

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
    ports:
      - "8080:80"
    volumes:
      - ./data/config:/var/www/baikal/config
      - ./data/specific:/var/www/baikal/Specific

```

Run it:

```bash
docker-compose up -d

```

### 3. Run with Docker CLI

```bash
docker run -d \
  --name baikal \
  -p 8080:80 \
  -v $(pwd)/data/config:/var/www/baikal/config \
  -v $(pwd)/data/specific:/var/www/baikal/Specific \
  my-baikal

```

### Initial Setup

1. Open your browser and navigate to `http://localhost:8080`.
2. Follow the Baikal installation wizard.
3. **Note:** Since this image uses SQLite, no external database setup is required.

## Configuration

| Path | Description |
| --- | --- |
| `/var/www/baikal/config` | Contains `baikal.yaml` and system config. |
| `/var/www/baikal/Specific` | Contains the SQLite database and event data. |

## Troubleshooting

**Permission Issues:**
The container includes an entrypoint script that automatically fixes permissions on the `/var/www/baikal/Specific` directory on startup. If you still face issues, ensure your host user has read/write access to the mounted folders.
