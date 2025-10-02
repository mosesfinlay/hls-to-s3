#!/bin/sh
set -eu

FLV_DIR="/recordings/flv"
MP4_DIR="/recordings/mp4"
QUIET_SECONDS="${QUIET_SECONDS:-60}"
FLV_MAX_AGE_SECONDS="${FLV_MAX_AGE_SECONDS:-0}"

mkdir -p "$FLV_DIR" "$MP4_DIR"

is_quiet_enough () {
  file="$1"
  now=$(date +%s)
  mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file")
  age=$(( now - mtime ))
  [ "$age" -ge "$QUIET_SECONDS" ]
}

remux_one () {
  src="$1"
  base="$(basename "$src" .flv)"
  dst="${MP4_DIR}/${base}.mp4"
  lock="${src}.lock"

  [ -f "$dst" ] && return 0
  ( set -o noclobber; : > "$lock" ) 2>/dev/null || return 0

  echo "[remux] $src -> $dst"
  if ffmpeg -hide_banner -loglevel error -y -i "$src" -c copy "$dst"; then
    echo "[remux] done: $dst"
  else
    echo "[remux] ERROR processing $src" >&2
    rm -f "$dst"
  fi

  rm -f "$lock"
}

cleanup_old_flv () {
  [ "$FLV_MAX_AGE_SECONDS" -gt 0 ] || return 0
  find "$FLV_DIR" -type f -name '*.flv' -mmin +$(( FLV_MAX_AGE_SECONDS / 60 )) \
    -print | while read -r f; do
      base="$(basename "$f" .flv)"
      mp4="${MP4_DIR}/${base}.mp4"
      if [ -f "$mp4" ]; then
        echo "[cleanup] removing old FLV $f"
        rm -f "$f"
      fi
    done
}

echo "[remux] watching $FLV_DIR -> $MP4_DIR (QUIET_SECONDS=$QUIET_SECONDS)"
while true; do
  find "$FLV_DIR" -type f -name '*.flv' -print | while read -r f; do
    if is_quiet_enough "$f"; then
      remux_one "$f"
    fi
  done

  cleanup_old_flv

  sleep 5
done
