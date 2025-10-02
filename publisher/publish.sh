#!/bin/sh
set -eu

DIR="${RECORDINGS_DIR:-/recordings/mp4}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-30}"
BUCKET="${S3_BUCKET:?missing}"
PREFIX="${S3_PREFIX:?missing}"
REGION="${AWS_REGION:-us-west-2}"

echo "[publisher] one-way add/update: $DIR -> s3://$BUCKET/$PREFIX (every ${INTERVAL}s)"
while true; do
  aws s3 sync "$DIR" "s3://$BUCKET/$PREFIX" \
    --region "$REGION" \
    --size-only \
    --no-progress \
    --only-show-errors

  sleep "$INTERVAL"
done
