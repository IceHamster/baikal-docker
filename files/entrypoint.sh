#!/bin/sh
set -e

# --- 1. Permission Fixes ---
# Ensure Nginx can write to the data directories (crucial for mounted volumes)
if [ -d "/var/www/baikal/Specific" ]; then
    chown -R nginx:nginx /var/www/baikal/Specific
fi

if [ -d "/var/www/baikal/config" ]; then
    chown -R nginx:nginx /var/www/baikal/config
fi

# --- 2. Start Services ---

# Start PHP-FPM in the background
# -F forces it to stay in foreground (so we can see logs), but we use & to background it in the shell
echo "Starting PHP-FPM 8.5..."
php-fpm85 -F &
PHP_PID=$!

# Start Nginx in the background
echo "Starting Nginx..."
nginx -g "daemon off;" &
NGINX_PID=$!

# --- 3. Process Management Loop ---

# Define cleanup function to kill processes if container stops
cleanup() {
    echo "Container stopped, killing processes..."
    kill -TERM "$PHP_PID" "$NGINX_PID" 2>/dev/null
    exit 0
}

# Trap system signals (SIGTERM/SIGINT) to run the cleanup function
trap cleanup TERM INT

# Wait loop: Check if processes are alive every 2 seconds
# If one crashes, we kill the container so Docker knows something went wrong.
while kill -0 "$PHP_PID" 2>/dev/null && kill -0 "$NGINX_PID" 2>/dev/null; do
    sleep 2
done

# If we reach here, one process has crashed
echo "One of the processes exited unexpectedly."
cleanup
exit 1