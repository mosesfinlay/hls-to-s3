#!/bin/sh
set -eu

: "${AWS_REGION:?AWS_REGION missing}"
: "${S3_BUCKET:?S3_BUCKET missing}"
: "${S3_PREFIX:=recordings}"
: "${PUBLIC_ACL:=true}"
: "${SYNC_INTERVAL_SECONDS:=30}"
: "${MP4_MAXAGE:=86400}"
: "${RECORDINGS_DIR:=/recordings}"

DEST="s3://${S3_BUCKET}/${S3_PREFIX}"
ACL_ARGS=""
if [ "${PUBLIC_ACL}" = "true" ]; then
  ACL_ARGS="--acl public-read"
fi

echo "Starting MP4 recorder publisher -> ${DEST} (interval ${SYNC_INTERVAL_SECONDS}s)"
echo "ACL public? ${PUBLIC_ACL}, region=${AWS_REGION}"

# Wait for the recordings dir to exist
while [ ! -d "${RECORDINGS_DIR}" ]; do
  echo "Waiting for ${RECORDINGS_DIR}..."
  sleep 1
done

# Sync MP4 recordings to S3
while true; do
  # Upload MP4 files
  aws s3 sync "${RECORDINGS_DIR}" "${DEST}" \
    --size-only \
    ${ACL_ARGS} \
    --exclude "*" --include "*.mp4" \
    --cache-control "max-age=${MP4_MAXAGE}, s-maxage=${MP4_MAXAGE}"

  sleep "${SYNC_INTERVAL_SECONDS}"
done
