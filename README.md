# cihm-cantaloupe

`cihm-cantaloupe` is Canadiana's [Cantaloupe](https://cantaloupe-project.github.io/) configuration.

## Configuration

Expected environment variables can be found in `docker-compose.yml`. Note the use of the `SOURCE_STATIC` variable to choose between `HttpSource` (for Swift preauth URLs), `S3Source`, and `FilesystemSource` (for ZFS).

For Swift object lookup, the delegate checks external Redis hashes.

The primary Redis hash maps each canvas identifier to its master image
extension. It stores every real extension emitted by the CouchDB view, including
`jpg`, `jp2`, and `tif`; sentinel values such as `none` are treated as missing
extensions.

A second Redis hash maps legacy identifiers with no usable master extension to
their CouchDB `source.path`. Those rows are routed to the preservation bucket.
This restores the old preservation fallback without reintroducing per-request
CouchDB lookups or Swift existence probes.

## Redis Image Lookup Indexes

The compose files set:

```text
IMAGE_EXTENSIONS_REDIS_URL=redis://redis:6379/0
IMAGE_EXTENSIONS_REDIS_HASH=image_extensions
IMAGE_SOURCE_PATHS_REDIS_HASH=image_source_paths
S3SOURCE_PRESERVATION_BUCKET_NAME=preservation-cihm-aip
```

Optional runtime tuning variables:

```text
IMAGE_EXTENSIONS_CACHE_SIZE=50000
IMAGE_SOURCE_PATHS_CACHE_SIZE=50000
IMAGE_EXTENSIONS_REDIS_POOL_SIZE=64
IMAGE_EXTENSIONS_REDIS_TIMEOUT_SECONDS=0.5
IMAGE_EXTENSIONS_REDIS_BACKOFF_SECONDS=10
IMAGE_EXTENSIONS_REDIS_STARTUP_TIMEOUT_SECONDS=30
```

`IMAGE_EXTENSIONS_CACHE_SIZE` controls the in-process LRU cache for repeated
extension lookups. `IMAGE_SOURCE_PATHS_CACHE_SIZE` defaults to the same value
and controls repeated legacy source-path lookups. Redis is checked using:

```text
HGET IMAGE_EXTENSIONS_REDIS_HASH identifier
HGET IMAGE_SOURCE_PATHS_REDIS_HASH identifier
```

The delegate resolution order is:

1. If the extension hash has a real extension, use the access-files bucket and
   `<identifier>.<extension>`.
2. If the extension is missing and the source-path hash has a path, use the
   preservation bucket and that stored `source.path`.
3. If neither Redis lookup resolves the image, fall back to access-files
   `<identifier>.jpg`.

For compatibility with the old Platform 1.0 config,
`S3SOURCE_BASICLOOKUPSTRATEGY_BUCKET_NAME` is also accepted as the preservation
bucket name when `S3SOURCE_PRESERVATION_BUCKET_NAME` is not set.

Redis is hosted externally (e.g. as a separate container or shared service).
The Redis hashes are populated upstream via Windmill (`populate_download_cache.py`).
On container startup, `docker-entrypoint.sh` connects to `IMAGE_EXTENSIONS_REDIS_URL`
before launching Cantaloupe.

Cantaloupe's source and derivative filesystem cache lives in:

```text
/data/cache
```

Keep this directory between container rebuilds/restarts. It fills at runtime
and prevents repeated cold reads from Swift for images Cantaloupe has already
processed.

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

If an identifier is missing from both Redis hashes, the delegate falls back to
`.jpg`. For JP2/TIFF records, a 404 mentioning a `.jpg` key usually means the
running Cantaloupe instance cannot see the expected Redis row, is using an old
dump, or needs to restart after the refreshed dump is installed. For old records
whose CouchDB `master.extension` is `none` or missing, a 404 in the access-files
bucket usually means the `image_source_paths` hash is missing or empty.

## Runtime Tuning

The image runs on Java 25 LTS and relies on `JAVA_TOOL_OPTIONS` for heap and GC
settings. `JDK_JAVA_OPTIONS=--enable-native-access=ALL-UNNAMED` is also set so
JRuby/JFFI can use native access without Java 25 startup warnings. The production
compose profile sets:

```text
-Xms16g -Xmx64g -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError
```

The default/local compose profiles use smaller heaps so a developer workstation
can still start the service. Override `JAVA_TOOL_OPTIONS` in the shell or in the
Puppet-managed environment file when testing different heap sizes.

Cantaloupe's standalone server is capped at `http.max_threads = 128` with a
shorter accept queue. This applies back-pressure before the JVM can admit too
many simultaneous image decodes. The Docker health check calls `/health` with
dependency checks disabled, so health polling does not read from Swift.

## Usage

```
docker compose build && docker compose -f docker-compose.override.yml up --force-recreate
```


## Test URLs

Test url:

http://localhost:8182/iiif/2/69429%2Fc0q23qz31412/full/max/0/default.jpg

On server:

https://www-iiif-image.canadiana.ca/iiif/2/69429%2Fc0q23qz31412/full/max/0/default.jpg

VS old urls

https://image-tor.canadiana.ca/iiif/2/69429%2Fc0q23qz31412/full/max/0/default.jpg

https://image-uab.canadiana.ca/iiif/2/69429%2Fc0q23qz31412/full/max/0/default.jpg
