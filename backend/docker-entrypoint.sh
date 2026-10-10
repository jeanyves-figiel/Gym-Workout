#!/bin/sh
# Hosts (e.g. Fly volumes) may mount /data root-owned: fix ownership, then drop to `node`.
set -e
if [ "$(id -u)" = "0" ]; then
  mkdir -p "$(dirname "${DB_PATH:-/data/app.db}")"
  chown -R node:node "$(dirname "${DB_PATH:-/data/app.db}")"
  exec su -p -s /bin/sh node -c 'exec "$0" "$@"' -- "$@"
fi
exec "$@"
