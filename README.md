# cihm-cantaloupe

`cihm-cantaloupe` is Canadiana's [Cantaloupe](https://cantaloupe-project.github.io/) configuration.

## Configuration

Expected environment variables can be found in `docker-compose.yml`. Note the use of the `SOURCE_STATIC` variable to choose between `S3Source` (for Swift) and `FilesystemSource` (for ZFS).

For Swift access-file extension lookup, the delegate uses a read-only SQLite index mounted at:

```
/data/image-extensions.sqlite
```

The index maps each canvas identifier to its master image extension:

```
CREATE TABLE image_extensions (
  identifier TEXT PRIMARY KEY,
  extension TEXT NOT NULL
);
```

## Image Extension Index

Build or refresh the SQLite index from CouchDB before starting Cantaloupe:

```
pip install -r scripts/requirements.txt
```

```
python scripts/populate_image_extensions.py --output data/image-extensions.sqlite
```

The script loads CouchDB connection settings from an ignored local dotenv file:

```
scripts/populate_image_extensions.env
```

The compose files mount `./data` read-only into the container and set:

```text
IMAGE_EXTENSIONS_DB=/data/image-extensions.sqlite
```

If an identifier is missing from the SQLite index, the delegate falls back to `.jpg`.

## Usage

```
docker compose build && docker compose -f docker-compose.override.yml up --force-recreate
```
