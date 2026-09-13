#!/bin/sh
set -eu

wait_for_redis() {
    timeout="${IMAGE_EXTENSIONS_REDIS_STARTUP_TIMEOUT_SECONDS:-30}"
    deadline="$(($(date +%s) + timeout))"
    last_response=""

    echo "Connecting to Redis at $IMAGE_EXTENSIONS_REDIS_URL (timeout: ${timeout}s)..."
    while [ "$(date +%s)" -le "$deadline" ]; do
        last_response="$(redis-cli -u "$IMAGE_EXTENSIONS_REDIS_URL" ping 2>&1 || true)"
        if [ "$last_response" = "PONG" ]; then
            echo "Connected to Redis: PONG"
            return 0
        fi
        sleep 1
    done

    echo "Could not connect to Redis at $IMAGE_EXTENSIONS_REDIS_URL within ${timeout}s. Last response: $last_response" >&2
    return 1
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
    echo "  IMAGE_EXTENSIONS_REDIS_HASH=${IMAGE_EXTENSIONS_REDIS_HASH:-}"
    echo "  IMAGE_SOURCE_PATHS_REDIS_HASH=${IMAGE_SOURCE_PATHS_REDIS_HASH:-}"
    echo "  S3SOURCE_PRESERVATION_BUCKET_NAME=${S3SOURCE_PRESERVATION_BUCKET_NAME:-}"
    echo "  S3SOURCE_BASICLOOKUPSTRATEGY_BUCKET_NAME=${S3SOURCE_BASICLOOKUPSTRATEGY_BUCKET_NAME:-}"
    grep -n \
        "HttpSource.lookup_strategy\|processor.ManualSelectionStrategy.tif\|processor.ManualSelectionStrategy.tiff\|processor.stream_retrieval_strategy\|processor.fallback_retrieval_strategy\|FilesystemCache.pathname" \
        /etc/cantaloupe.properties || true
    grep -n "def httpsource_resource_info" /etc/delegates.rb || true
}

if [ -n "${IMAGE_EXTENSIONS_REDIS_URL:-}" ]; then
    wait_for_redis
else
    echo "IMAGE_EXTENSIONS_REDIS_URL is not set; Redis extension index disabled"
fi

prepare_cantaloupe_cache
purge_zero_byte_cantaloupe_cache
print_runtime_diagnostics

exec "$@"
