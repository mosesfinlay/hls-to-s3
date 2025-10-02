#!/bin/sh
set -eu

DIR="${RECORDINGS_DIR:-/recordings/mp4}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-10}"
BUCKET="${S3_BUCKET:?missing}"
PREFIX="${S3_PREFIX:?missing}"
REGION="${AWS_REGION:-us-west-2}"

echo "[publisher] syncing $DIR -> s3://$BUCKET/$PREFIX (every ${INTERVAL}s)"
while true; do
  aws s3 sync "$DIR" "s3://$BUCKET/$PREFIX" \
    --region "$REGION" --delete --size-only --no-progress

  sleep "$INTERVAL"
done
