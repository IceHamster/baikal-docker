#!/bin/sh
set -eu

PHP_PID=
NGINX_PID=

shutdown() {
    trap '' TERM INT
    echo "Stopping Nginx and PHP-FPM gracefully..."

    # Drain HTTP requests while PHP-FPM is still available to serve them.
    if [ -n "$NGINX_PID" ]; then
        kill -QUIT "$NGINX_PID" 2>/dev/null || true
        wait "$NGINX_PID" || true
    fi
    if [ -n "$PHP_PID" ]; then
        kill -QUIT "$PHP_PID" 2>/dev/null || true
        wait "$PHP_PID" || true
    fi
    exit "$1"
}
trap 'shutdown 0' TERM INT

# Keep support for empty bind mounts and data owned by a different host UID.
mkdir -p /var/www/baikal/Specific /var/www/baikal/config /run/nginx /run/php
chown -R nginx:nginx /var/www/baikal/Specific /var/www/baikal/config
chown nginx:nginx /run/nginx /run/php

echo "Starting PHP-FPM 8.5..."
php-fpm85 -F &
PHP_PID=$!

echo "Starting Nginx..."
nginx -g 'daemon off;' &
NGINX_PID=$!

# Poll the two service masters using portable shell builtins. The shell reaps
# exited children between commands. An unrequested exit is always a failure.
while kill -0 "$PHP_PID" 2>/dev/null && kill -0 "$NGINX_PID" 2>/dev/null; do
    sleep 1
done
echo "A service exited unexpectedly." >&2
shutdown 1
