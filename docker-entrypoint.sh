#!/bin/sh
set -eu

start_redis() {
    redis_dir="${IMAGE_EXTENSIONS_REDIS_DIR:-/data/redis}"
    mkdir -p "$redis_dir"
    echo "Starting embedded Redis extension index in $redis_dir"

    redis-server \
        --bind 127.0.0.1 \
        --port 6379 \
        --dir "$redis_dir" \
        --dbfilename dump.rdb \
        --save 900 1 \
        --appendonly no \
        --daemonize yes

    wait_for_redis
}

prepare_cantaloupe_cache() {
    mkdir -p /data/cache
    if [ ! -w /data/cache ]; then
        echo "Cantaloupe cache directory is not writable: /data/cache" >&2
        return 1
    fi
    echo "Using Cantaloupe filesystem cache at /data/cache"
}

purge_zero_byte_cantaloupe_cache() {
    purge="${CANTALOUPE_PURGE_ZERO_BYTE_CACHE:-true}"
    [ "$purge" = "true" ] || return 0

    marker="${CANTALOUPE_ZERO_BYTE_CACHE_PURGE_MARKER:-/data/cache/.zero-byte-purge-v1}"
    [ ! -e "$marker" ] || return 0

    echo "Removing zero-byte Cantaloupe derivative/info cache files"
    purged_count="$(
        find /data/cache/image /data/cache/info \
            -type f \
            -size 0 \
            -print \
            -delete 2>/dev/null | wc -l
    )"
    echo "Removed ${purged_count} zero-byte cache files"
    date -Iseconds > "$marker"
}

print_runtime_diagnostics() {
    echo "Cantaloupe runtime diagnostics:"
    echo "  entrypoint=/usr/local/bin/docker-entrypoint.sh"
    echo "  SOURCE_STATIC=${SOURCE_STATIC:-}"
    echo "  S3SOURCE_ACCESSFILES_BUCKET_NAME=${S3SOURCE_ACCESSFILES_BUCKET_NAME:-}"
    echo "  S3SOURCE_ENDPOINT=${S3SOURCE_ENDPOINT:-}"
    echo "  IIIF_SWIFT_PREAUTH_URL=${IIIF_SWIFT_PREAUTH_URL:-}"
    echo "  SWIFT_PREAUTH_URL=${SWIFT_PREAUTH_URL:-}"
    echo "  SWIFT_TENANT=${SWIFT_TENANT:-}"
    echo "  SWIFT_TENNANT=${SWIFT_TENNANT:-}"
    echo "  IMAGE_EXTENSIONS_REDIS_URL=${IMAGE_EXTENSIONS_REDIS_URL:-}"
    grep -n \
        "HttpSource.lookup_strategy\|processor.ManualSelectionStrategy.tif\|processor.ManualSelectionStrategy.tiff\|processor.stream_retrieval_strategy\|processor.fallback_retrieval_strategy\|FilesystemCache.pathname" \
        /etc/cantaloupe.properties || true
    grep -n "def httpsource_resource_info" /etc/delegates.rb || true
}

wait_for_redis() {
    timeout="${IMAGE_EXTENSIONS_REDIS_STARTUP_TIMEOUT_SECONDS:-300}"
    deadline="$(($(date +%s) + timeout))"
    last_response=""

    while [ "$(date +%s)" -le "$deadline" ]; do
        last_response="$(redis-cli -h 127.0.0.1 -p 6379 ping 2>&1 || true)"
        if [ "$last_response" = "PONG" ]; then
            return 0
        fi
        sleep 1
    done

    echo "Redis did not start within ${timeout}s. Last response: $last_response" >&2
    return 1
}

preload_redis() {
    preload="${IMAGE_EXTENSIONS_REDIS_PRELOAD:-true}"
    [ "$preload" = "true" ] || return 0

    hash_name="${IMAGE_EXTENSIONS_REDIS_HASH:-image_extensions}"

    existing="$(redis-cli -h 127.0.0.1 -p 6379 HLEN "$hash_name")"
    if [ "$existing" != "0" ]; then
        echo "Redis extension index already contains $existing rows"
        return 0
    fi

    if [ -z "${CANVAS_DB:-}${DB_URL:-}" ]; then
        echo "Redis extension index is empty and no CouchDB source is configured"
        return 0
    fi

    echo "Loading Redis extension index from CouchDB"
    populate-redis-from-couch "$hash_name"
    redis-cli -h 127.0.0.1 -p 6379 SAVE >/dev/null
}

if [ -n "${IMAGE_EXTENSIONS_REDIS_URL:-}" ]; then
    start_redis
    preload_redis
else
    echo "IMAGE_EXTENSIONS_REDIS_URL is not set; Redis extension index disabled"
fi

prepare_cantaloupe_cache
purge_zero_byte_cantaloupe_cache
print_runtime_diagnostics

exec "$@"
