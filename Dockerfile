FROM alpine:3.23@sha256:865b95f46d98cf867a156fe4a135ad3fe50d2056aa3f25ed31662dff6da4eb62 AS builder

# renovate: datasource=github-releases packageName=sabre-io/Baikal
ENV BAIKAL_VERSION=0.11.1
WORKDIR /app
RUN apk add --no-cache unzip curl \
    && curl -L -o baikal.zip https://github.com/sabre-io/Baikal/releases/download/$BAIKAL_VERSION/baikal-$BAIKAL_VERSION.zip \
    && unzip -q baikal.zip \
    && rm baikal.zip

FROM alpine:3.23@sha256:865b95f46d98cf867a156fe4a135ad3fe50d2056aa3f25ed31662dff6da4eb62

# Install Nginx and PHP (Removed Supervisor)
RUN apk add --no-cache \
    nginx \
    php85 \
    php85-fpm \
    php85-common \
    php85-openssl \
    php85-curl \
    php85-mbstring \
    php85-ctype \
    php85-dom \
    php85-xml \
    php85-xmlwriter \
    php85-simplexml \
    php85-tokenizer \
    php85-session \
    php85-pdo \
    php85-pdo_pgsql \
    php85-pgsql \
    php85-zlib

# Create Directories & User Setup
RUN mkdir -p /var/www/baikal/Specific /var/www/baikal/config /run/nginx /run/php \
    && chown -R nginx:nginx /var/www/baikal /var/log/nginx /run/nginx /run/php

# Configure PHP-FPM (Socket Mode)
RUN sed -i 's/listen = 127.0.0.1:9000/listen = \/run\/php\/php-fpm.sock/g' /etc/php85/php-fpm.d/www.conf \
    && sed -i 's/^user = nobody/user = nginx/g' /etc/php85/php-fpm.d/www.conf \
    && sed -i 's/^group = nobody/group = nginx/g' /etc/php85/php-fpm.d/www.conf \
    && sed -i 's/;listen.owner = nobody/listen.owner = nginx/g' /etc/php85/php-fpm.d/www.conf \
    && sed -i 's/;listen.group = nobody/listen.group = nginx/g' /etc/php85/php-fpm.d/www.conf \
    && sed -i 's/;listen.mode = 0660/listen.mode = 0660/g' /etc/php85/php-fpm.d/www.conf \
    && sed -i 's/^error_log = .*/error_log = \/dev\/stderr/' /etc/php85/php-fpm.conf

# Copy Application Code
COPY --from=builder --chown=nginx:nginx /app/baikal /var/www/baikal

# Copy Configurations
COPY files/nginx.conf /etc/nginx/http.d/default.conf
COPY files/entrypoint.sh /usr/local/bin/entrypoint.sh

# Make entrypoint executable
RUN chmod +x /usr/local/bin/entrypoint.sh

# Persist Data
VOLUME ["/var/www/baikal/Specific", "/var/www/baikal/config"]

EXPOSE 80

# The script now acts as the process manager
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]