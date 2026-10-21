#!/bin/sh
set -eu

# Exercise Nginx and its PHP-FPM socket, including an expected response body.
wget -q -T 3 -O - http://127.0.0.1/health | grep -qx pong
