FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS builder

WORKDIR /app
RUN apk add --no-cache curl unzip

# Renovate updates the release version and archive checksum as one dependency.
# renovate: datasource=github-release-attachments packageName=sabre-io/Baikal
ARG BAIKAL_VERSION=0.13.0
ARG BAIKAL_SHA256=81e74df123230e863f608d228fdd7b9a1a788f60b04d37e6973c302192e83f32
RUN curl --fail --silent --show-error --location --retry 3 --max-time 120 \
        --output baikal.zip "https://github.com/sabre-io/Baikal/releases/download/${BAIKAL_VERSION}/baikal-${BAIKAL_VERSION}.zip" \
    && printf '%s  %s\n' "$BAIKAL_SHA256" baikal.zip | sha256sum -c - \
    && unzip -q baikal.zip \
    && rm baikal.zip

FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS runtime

RUN apk add --no-cache \
    nginx \
    php85 \
    php85-common \
    php85-ctype \
    php85-curl \
    php85-dom \
    php85-fpm \
    php85-mbstring \
    php85-openssl \
    php85-pdo \
    php85-pdo_pgsql \
    php85-pgsql \
    php85-session \
    php85-simplexml \
    php85-tokenizer \
    php85-xml \
    php85-xmlreader \
    php85-xmlwriter \
    php85-zlib \
    tini

# Application code stays owned by root. Only data and runtime paths are writable
# by the web workers; mounted data directories are also prepared at startup.
COPY --from=builder --chown=root:root /app/baikal /var/www/baikal
RUN mkdir -p /var/www/baikal/Specific /var/www/baikal/config /run/nginx /run/php \
    && chown -R nginx:nginx /var/www/baikal/Specific /var/www/baikal/config \
        /var/log/nginx /run/nginx /run/php

COPY files/nginx.conf /etc/nginx/http.d/default.conf
COPY files/php-fpm.conf /etc/php85/php-fpm.d/zz-docker.conf
COPY --chmod=0755 files/entrypoint.sh files/healthcheck.sh /usr/local/bin/

VOLUME ["/var/www/baikal/Specific", "/var/www/baikal/config"]
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

# Tini forwards signals to the wrapper and reaps orphaned service workers.
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
