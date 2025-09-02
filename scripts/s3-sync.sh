#!/usr/bin/env bash
set -euo pipefail
# Reads BUCKET, PREFIX, SYNC_INTERVAL_SECONDS from /etc/hls-to-s3.env (via systemd)
: "${BUCKET:?BUCKET env var required}"
: "${PREFIX:?PREFIX env var required}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-5}"

SRC="/opt/hls-to-s3/hls"
DST="s3://${BUCKET}/${PREFIX}"

echo "[s3-sync] syncing ${SRC} -> ${DST} every ${INTERVAL}s"
# Ensure source exists
mkdir -p "${SRC}"

while true; do
  /usr/bin/aws s3 sync "${SRC}" "${DST}" --size-only --no-progress
  sleep "${INTERVAL}"
done
