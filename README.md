# cihm-cantaloupe

`cihm-cantaloupe` is Canadiana's [Cantaloupe](https://cantaloupe-project.github.io/) configuration.

## Configuration

Expected environment variables can be found in `docker-compose.yml`. Note the use of the `SOURCE_STATIC` variable to choose between `HttpSource` (for Swift preauth URLs), `S3Source`, and `FilesystemSource` (for ZFS).

For Swift access-file extension lookup, the delegate checks an embedded Redis
hash loaded from:

```
/data/redis/dump.rdb
```

The Redis hash maps each canvas identifier to its master image extension. It
stores every real extension emitted by the CouchDB view, including `jpg`, `jp2`,
and `tif`; sentinel values such as `none` are treated as missing extensions.

## Redis Extension Index

The compose files mount `./data` into the container and set:

```text
IMAGE_EXTENSIONS_REDIS_URL=redis://127.0.0.1:6379/0
IMAGE_EXTENSIONS_REDIS_HASH=image_extensions
IMAGE_EXTENSIONS_REDIS_DIR=/data/redis
IMAGE_EXTENSIONS_REDIS_PRELOAD=true
```

Optional runtime tuning variables:

```text
IMAGE_EXTENSIONS_CACHE_SIZE=50000
IMAGE_EXTENSIONS_REDIS_POOL_SIZE=64
IMAGE_EXTENSIONS_REDIS_TIMEOUT_SECONDS=0.5
IMAGE_EXTENSIONS_REDIS_BACKOFF_SECONDS=10
IMAGE_EXTENSIONS_REDIS_STARTUP_TIMEOUT_SECONDS=300
```

`IMAGE_EXTENSIONS_CACHE_SIZE` controls the in-process LRU cache for repeated
identifier lookups. Redis is checked using `HGET IMAGE_EXTENSIONS_REDIS_HASH
identifier`. If Redis is unavailable or a row is missing, the delegate falls
back to `.jpg`.

Redis runs inside the Cantaloupe container and stores its snapshot in the same
data mount used by the rest of the deployment:

```text
/data/redis/dump.rdb
```

Cantaloupe's source and derivative filesystem cache also lives in that same data
mount:

```text
/data/cache
```

Keep this directory between container rebuilds/restarts. It is not part of the
Redis dump archive; it fills at runtime and prevents repeated cold reads from
Swift for images Cantaloupe has already processed.

On the Puppet-managed beta host, `/data/cache` is backed by the existing
`/var/cache/cantaloupe` LVM mount.

The Puppet-managed beta deployment uses `SOURCE_STATIC=S3Source` so Cantaloupe
authenticates to Swift through the S3-compatible API. `HttpSource` remains
available for environments where Swift object URLs are public or an auth header
is supplied, but unauthenticated Swift object URLs return `401`. Cantaloupe's
source, derivative, and image info caches persist under `/data/cache`. This
keeps cold reads efficient and lets repeated requests avoid going back to Swift.

TIFF images are assigned to `JaiProcessor`, matching the Platform 1.0 setup.
This avoids very slow cold thumbnail derivatives through Java2d.

The fallback retrieval strategy is `CacheStrategy`, also matching Platform 1.0,
so source files that cannot be streamed directly to a processor are cached on
disk instead of re-downloaded for each derivative.

The entrypoint removes zero-byte derivative/info cache files once per mounted
cache by default. This is intentional: earlier bad source/processor settings can
leave persistent empty JPEG responses in `/data/cache`, and those must be
purged without throwing away the whole warmed cache.

On startup, `IMAGE_EXTENSIONS_REDIS_PRELOAD=true` populates Redis directly from
CouchDB only if the Redis hash is empty.

Build or refresh the Redis dump from CouchDB with:

```
scripts/build-redis-dump-from-couch
```

The script loads CouchDB connection settings from an ignored local dotenv file:

```
scripts/populate_image_extensions.env
```

That file should contain:

```text
DB_USER=
DB_PASSWORD=
DB_URL=
DB_NAME=canvas
VIEW_NAME=stats/masterext
```

The builder writes the Redis snapshot:

```text
data/redis/dump.rdb
```

It also writes an uploadable archive:

```text
dist/redis-cache-data.tar.gz
```

Upload that archive to the host server, then extract it into the production data
directory before starting Cantaloupe:

```
sudo tar -xzf redis-cache-data.tar.gz -C /data/cantaloupe
sudo mkdir -p /data/cantaloupe/cache
sudo chown -R 8182:8182 /data/cantaloupe/redis /data/cantaloupe/cache
```

That creates `/data/cantaloupe/redis/dump.rdb`. The production compose file
mounts `/data/cantaloupe` as `/data`, so Cantaloupe starts with Redis already
loaded and skips the CouchDB preload. `/data/cantaloupe/cache` is the persistent
Cantaloupe filesystem cache.

For the Puppet-managed beta compose, `/var/cache/cantaloupe` is mounted as
`/data/cache`; make sure that host directory is owned by the Cantaloupe user:

```
sudo chown -R 8182:8182 /data/cantaloupe/redis /var/cache/cantaloupe
```

## Warming Large Manifests

Some manifests contain thousands of canvases. To avoid making the first viewer
pay the cost of warming every image service `info.json`, run the warmer inside
the Cantaloupe container:

```
docker exec <cantaloupe-container> warm-manifest-info-cache \
  --cantaloupe-base http://127.0.0.1:8182/iiif/2 \
  --viewer-thumbnails \
  --concurrency 4 \
  --timeout 180 \
  https://www-iiif-pres.canadiana.ca/manifest/69429/m0tt4fn16j1j
```

Use `--dry-run --limit 12` to inspect the URLs first. `--viewer-thumbnails`
warms `full/72,`, `full/144,`, and `full/289,` derivatives as well as
`info.json`, which covers the common viewer thumbnail requests. Warming through
`127.0.0.1` avoids the public proxy timeout while Cantaloupe is doing cold Swift
reads and derivative generation.

If an identifier is missing from Redis, the delegate falls back to `.jpg`. For
JP2/TIFF records, a 404 mentioning a `.jpg` key usually means the running
Cantaloupe instance cannot see the expected Redis row, is using an old dump, or
needs to restart after the refreshed dump is installed.

## Usage

```
docker compose build && docker compose -f docker-compose.override.yml up --force-recreate
```
