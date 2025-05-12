# cihm-cantaloupe

`cihm-cantaloupe` is Canadiana's [Cantaloupe](https://cantaloupe-project.github.io/) configuration.

## configuration

Expected environment variables can be found in `docker-compose.yml`. Note the use of the `SOURCE_STATIC` variable to choose between `S3Source` (for Swift) and `FilesystemSource` (for ZFS).

## Usage
`docker compose build && docker compose -f docker-compose.override.yml up --force-recreate`
