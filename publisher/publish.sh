#!/bin/sh
set -eu

: "${AWS_REGION:?AWS_REGION missing}"
: "${S3_BUCKET:?S3_BUCKET missing}"
: "${S3_PREFIX:=mp4}"
: "${PUBLIC_ACL:=true}"
: "${SYNC_INTERVAL_SECONDS:=1}"
: "${PLAYLIST_MAXAGE:=1}"
: "${SEGMENT_MAXAGE:=3}"
: "${MP4_DIR:=/hls}"
: "${RECORD_DURATION:=300s}"

DEST="s3://${S3_BUCKET}/${S3_PREFIX}"
ACL_ARGS=""
if [ "${PUBLIC_ACL}" = "true" ]; then
  ACL_ARGS="--acl public-read"
fi

echo "Starting MP4 publisher -> ${DEST} (interval ${SYNC_INTERVAL_SECONDS}s)"
echo "ACL public? ${PUBLIC_ACL}, region=${AWS_REGION}, record duration=${RECORD_DURATION}"

# Wait for the MP4 dir to exist
while [ ! -d "${MP4_DIR}" ]; do
  echo "Waiting for ${MP4_DIR}..."
  sleep 1
done

# Sync MP4 files to S3
while true; do
  # Upload MP4 files
  aws s3 sync "${MP4_DIR}" "${DEST}" \
    --size-only \
    ${ACL_ARGS} \
    --exclude "*" --include "*.mp4" \
    --cache-control "public, max-age=3600"

  sleep "${SYNC_INTERVAL_SECONDS}"
done
