#!/bin/sh
set -e

envsubst '${CHUNK_DURATION_MINUTES}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'

