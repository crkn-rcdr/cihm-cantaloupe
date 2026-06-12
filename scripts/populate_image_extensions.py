#!/usr/bin/env python3
import argparse
import os
import sqlite3
import sys
import tempfile
import urllib.parse

import couchdb


DEFAULT_DB_NAME = "canvas"
DEFAULT_VIEW_NAME = "stats/masterext"
DEFAULT_ENV_FILE = os.path.join(
    os.path.dirname(__file__),
    "populate_image_extensions.env",
)
MISSING_EXTENSION_KEYS = {"none", "null", "nil"}


def load_env_file(path):
    if not path or not os.path.exists(path):
        return

    with open(path, encoding="utf-8") as env_file:
        for line in env_file:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            os.environ.setdefault(key, value)


def couch_server_url(db_user, db_password, db_url):
    credentials = ""
    if db_user or db_password:
        credentials = (
            f"{urllib.parse.quote(db_user or '', safe='')}:"
            f"{urllib.parse.quote(db_password or '', safe='')}@"
        )
    return f"http://{credentials}{db_url.rstrip('/')}/"


def server_and_db_from_couch_url(url):
    parsed = urllib.parse.urlparse(url)
    db_name = DEFAULT_DB_NAME

    if "/_utils" not in parsed.path:
        path_parts = parsed.path.strip("/").split("/")
        if path_parts and path_parts[0]:
            db_name = urllib.parse.unquote(path_parts[0])
        server_url = urllib.parse.urlunparse(
            (parsed.scheme, parsed.netloc, "/", "", "", "")
        )
        return server_url, db_name

    fragment_parts = parsed.fragment.strip("/").split("/")
    if len(fragment_parts) >= 2 and fragment_parts[0] == "database":
        db_name = urllib.parse.unquote(fragment_parts[1])
        server_url = urllib.parse.urlunparse(
            (
                parsed.scheme,
                parsed.netloc,
                "/",
                "",
                "",
                "",
            )
        )
        return server_url, db_name

    return url, db_name


def couch_database(args):
    if args.couch_url:
        server_url, db_name = server_and_db_from_couch_url(args.couch_url)
    else:
        db_user = args.db_user or os.getenv("DB_USER")
        db_password = args.db_password or os.getenv("DB_PASSWORD")
        db_url = args.db_url or os.getenv("DB_URL")
        if not db_url:
            raise ValueError("DB_URL is required")
        server_url = couch_server_url(db_user, db_password, db_url)
        db_name = args.db_name or os.getenv("DB_NAME", DEFAULT_DB_NAME)

    return couchdb.Server(server_url)[db_name]


def iter_extension_rows(database, view_name):
    for row in database.view(view_name, reduce=False):
        identifier = row.get("id")
        extension = row.get("key")
        if identifier and extension:
            yield identifier, normalize_extension(extension)


def normalize_extension(extension):
    if extension is None:
        return None
    normalized = str(extension).strip().lstrip(".").lower()
    if not normalized or normalized in MISSING_EXTENSION_KEYS:
        return None
    return normalized


def create_schema(connection):
    connection.execute("PRAGMA journal_mode = OFF")
    connection.execute("PRAGMA synchronous = OFF")
    connection.execute("PRAGMA temp_store = MEMORY")
    connection.execute(
        """
        CREATE TABLE image_extensions (
            identifier TEXT PRIMARY KEY,
            extension TEXT NOT NULL
        )
        """
    )


def populate_database(database, view_name, output_path, batch_size, limit, progress_interval):
    output_path = os.path.abspath(output_path)
    output_dir = os.path.dirname(output_path) or "."
    os.makedirs(output_dir, exist_ok=True)

    fd, temp_path = tempfile.mkstemp(
        prefix=".image-extensions-",
        suffix=".sqlite",
        dir=output_dir,
    )
    os.close(fd)

    inserted = 0
    try:
        connection = sqlite3.connect(temp_path)
        create_schema(connection)

        with connection:
            rows = []
            for identifier, extension in iter_extension_rows(database, view_name):
                if not identifier or not extension:
                    continue
                rows.append((identifier, extension))
                if limit is not None and inserted + len(rows) >= limit:
                    break
                if len(rows) >= batch_size:
                    connection.executemany(
                        """
                        INSERT OR REPLACE INTO image_extensions
                            (identifier, extension)
                        VALUES (?, ?)
                        """,
                        rows,
                    )
                    inserted += len(rows)
                    rows.clear()
                    if progress_interval and inserted % progress_interval == 0:
                        print(f"Inserted {inserted} rows", file=sys.stderr)

            if rows:
                if limit is not None:
                    rows = rows[: max(0, limit - inserted)]
                connection.executemany(
                    """
                    INSERT OR REPLACE INTO image_extensions
                        (identifier, extension)
                    VALUES (?, ?)
                    """,
                    rows,
                )
                inserted += len(rows)

        connection.execute("PRAGMA optimize")
        connection.close()
        os.replace(temp_path, output_path)
    except Exception:
        try:
            os.unlink(temp_path)
        except OSError:
            pass
        raise

    return inserted


def parse_args():
    load_env_file(DEFAULT_ENV_FILE)

    parser = argparse.ArgumentParser(
        description="Populate a SQLite identifier-to-extension index from CouchDB."
    )
    parser.add_argument(
        "--couch-url",
        default=os.getenv("CANVAS_DB"),
        help="Optional CouchDB database URL or Futon/_utils URL.",
    )
    parser.add_argument(
        "--db-user",
        default=os.getenv("DB_USER"),
        help="CouchDB username. Defaults to DB_USER or admin.",
    )
    parser.add_argument(
        "--db-password",
        default=os.getenv("DB_PASSWORD"),
        help="CouchDB password. Defaults to DB_PASSWORD.",
    )
    parser.add_argument(
        "--db-url",
        default=os.getenv("DB_URL"),
        help="CouchDB host:port. Defaults to DB_URL.",
    )
    parser.add_argument(
        "--db-name",
        default=os.getenv("DB_NAME", DEFAULT_DB_NAME),
        help="CouchDB database name. Defaults to DB_NAME or canvas.",
    )
    parser.add_argument(
        "--view-name",
        default=os.getenv("VIEW_NAME", DEFAULT_VIEW_NAME),
        help="CouchDB view name. Defaults to VIEW_NAME or stats/masterext.",
    )
    parser.add_argument(
        "--output",
        default="data/image-extensions.sqlite",
        help="SQLite database path to create atomically.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1000,
        help="CouchDB page size and SQLite insert batch size.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional maximum number of rows to write, mainly for testing.",
    )
    parser.add_argument(
        "--progress-interval",
        type=int,
        default=1000000,
        help="Rows between progress messages. Set to 0 to disable.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    database = couch_database(args)
    inserted = populate_database(
        database,
        args.view_name,
        args.output,
        args.batch_size,
        args.limit,
        args.progress_interval,
    )
    print(f"Wrote {inserted} rows to {args.output}")


if __name__ == "__main__":
    main()
