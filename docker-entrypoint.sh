#!/bin/sh
set -e

mkdir -p \
    /app/data/generations \
    /app/data/profiles \
    /app/data/cache \
    /home/voicebox/.cache/huggingface \
    /tmp/numba_cache

voicebox_owner="$(id -u voicebox):$(id -g voicebox)"

fix_owner() {
    path="$1"
    if [ "$(stat -c '%u:%g' "$path")" != "$voicebox_owner" ]; then
        chown -R voicebox:voicebox "$path"
    fi
}

fix_owner /app/data
fix_owner /home/voicebox/.cache
fix_owner /tmp/numba_cache

if [ "$(id -u)" = "0" ]; then
    exec runuser -u voicebox -- "$@"
fi

exec "$@"
