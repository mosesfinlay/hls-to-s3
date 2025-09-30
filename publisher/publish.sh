#!/bin/sh
set -eu

: "${AWS_REGION:?AWS_REGION missing}"
: "${S3_BUCKET:?S3_BUCKET missing}"
: "${S3_PREFIX:=hls}"
: "${PUBLIC_ACL:=true}"
: "${SYNC_INTERVAL_SECONDS:=1}"
: "${PLAYLIST_MAXAGE:=1}"
: "${SEGMENT_MAXAGE:=3}"
: "${HLS_DIR:=/hls}"

DEST="s3://${S3_BUCKET}/${S3_PREFIX}"
ACL_ARGS=""
if [ "${PUBLIC_ACL}" = "true" ]; then
  ACL_ARGS="--acl public-read"
fi

echo "Starting HLS publisher -> ${DEST} (interval ${SYNC_INTERVAL_SECONDS}s)"
echo "ACL public? ${PUBLIC_ACL}, region=${AWS_REGION}"

# Wait for the HLS dir to exist
while [ ! -d "${HLS_DIR}" ]; do
  echo "Waiting for ${HLS_DIR}..."
  sleep 1
done

# Two-pass sync: TS first (slightly longer cache), then M3U8 (short cache)
while true; do
  # Upload segments
  aws s3 sync "${HLS_DIR}" "${DEST}" \
    --size-only \
    ${ACL_ARGS} \
    --exclude "*" --include "*.ts" \
    --cache-control "max-age=${SEGMENT_MAXAGE}, s-maxage=${SEGMENT_MAXAGE}, stale-while-revalidate=${SEGMENT_MAXAGE}"

  # Upload playlists
  aws s3 sync "${HLS_DIR}" "${DEST}" \
    --size-only \
    ${ACL_ARGS} \
    --exclude "*" --include "*.m3u8" \
    --cache-control "max-age=${PLAYLIST_MAXAGE}, s-maxage=${PLAYLIST_MAXAGE}, stale-while-revalidate=${PLAYLIST_MAXAGE}"

  sleep "${SYNC_INTERVAL_SECONDS}"
done
