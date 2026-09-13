#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def load_json(url, timeout):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.load(response)


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def service_id(service):
    if not isinstance(service, dict):
        return None
    return service.get("@id") or service.get("id")


def looks_like_image_service(service):
    identifier = service_id(service)
    profile = service.get("profile")
    if isinstance(profile, list):
        profile = " ".join(str(item) for item in profile)
    profile = str(profile or "")
    service_type = str(service.get("@type") or service.get("type") or "")
    return (
        "iiif.io/api/image" in profile
        or "ImageService" in service_type
        or bool(identifier and image_identifier(identifier))
    )


def iter_image_service_ids(value):
    if isinstance(value, dict):
        for service in as_list(value.get("service")):
            if isinstance(service, dict) and looks_like_image_service(service):
                identifier = service_id(service)
                if identifier:
                    yield identifier
            yield from iter_image_service_ids(service)

        for child in value.values():
            if child is not value.get("service"):
                yield from iter_image_service_ids(child)
    elif isinstance(value, list):
        for item in value:
            yield from iter_image_service_ids(item)


def service_url(service_id_value, cantaloupe_base=None):
    service_id_value = service_id_value.rstrip("/")
    if cantaloupe_base:
        identifier = image_identifier(service_id_value)
        if identifier:
            return f"{cantaloupe_base.rstrip('/')}/{identifier}"
    return service_id_value


def info_url(service_id_value, cantaloupe_base=None):
    return f"{service_url(service_id_value, cantaloupe_base)}/info.json"


def derivative_url(service_id_value, size, cantaloupe_base=None):
    return f"{service_url(service_id_value, cantaloupe_base)}/full/{size}/0/default.jpg"


def image_identifier(service_id_value):
    parsed = urllib.parse.urlparse(service_id_value)
    path = parsed.path.strip("/")
    for marker in ("iiif/2/", "iiif/3/"):
        if marker in path:
            return path.split(marker, 1)[1]
    return None


def request_url(url, method, timeout, retries):
    last_error = None
    for attempt in range(retries + 1):
        try:
            request = urllib.request.Request(url, method=method)
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = response.read()
                if (
                    method != "HEAD"
                    and response.headers.get_content_maintype() == "image"
                    and len(body) == 0
                ):
                    raise RuntimeError("empty image response")
                return url, response.status, len(body), None
        except urllib.error.HTTPError as error:
            if 400 <= error.code < 500:
                return url, error.code, 0, None
            last_error = error
        except Exception as error:
            last_error = error

        if attempt < retries:
            time.sleep(min(2 ** attempt, 10))

    return url, None, 0, last_error


def warm_urls(urls, method, timeout, concurrency, retries):
    ok = 0
    failed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [
            executor.submit(request_url, url, method, timeout, retries)
            for url in urls
        ]
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            url, status, bytes_read, error = future.result() if not future.exception() else (None, None, 0, future.exception())
            if error:
                failed += 1
                print(f"FAIL {error} {url or ''}", file=sys.stderr)
            elif 200 <= status < 400:
                ok += 1
            else:
                failed += 1
                print(f"FAIL {status} {url}", file=sys.stderr)

            if index % 100 == 0:
                print(f"Warmed {index} URLs", file=sys.stderr)

    return ok, failed


def parse_args():
    parser = argparse.ArgumentParser(
        description="Warm Cantaloupe IIIF image info/derivative cache from IIIF manifests."
    )
    parser.add_argument("manifest_url", nargs="+")
    parser.add_argument(
        "--cantaloupe-base",
        help="Optional replacement image service base, e.g. http://localhost:8182/iiif/2.",
    )
    parser.add_argument("--concurrency", type=int, default=4)
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--method", choices=["GET", "HEAD"], default="GET")
    parser.add_argument(
        "--no-info",
        action="store_true",
        help="Do not warm info.json URLs.",
    )
    parser.add_argument(
        "--thumbnail-width",
        action="append",
        type=int,
        default=[],
        help="Warm full/{width},/0/default.jpg thumbnails. May be repeated.",
    )
    parser.add_argument(
        "--viewer-thumbnails",
        action="store_true",
        help="Warm common viewer thumbnail widths: 72, 144, and 289.",
    )
    parser.add_argument(
        "--derivative-size",
        action="append",
        default=[],
        help="Warm a raw IIIF size segment, e.g. '512,' or '!512,512'. May be repeated.",
    )
    parser.add_argument("--limit", type=int)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    urls = []
    seen = set()
    sizes = []
    if args.viewer_thumbnails:
        sizes.extend(["72,", "144,", "289,"])
    sizes.extend(f"{width}," for width in args.thumbnail_width)
    sizes.extend(args.derivative_size)

    for manifest_url in args.manifest_url:
        manifest = load_json(manifest_url, args.timeout)
        for service_id_value in iter_image_service_ids(manifest):
            candidate_urls = []
            if not args.no_info:
                candidate_urls.append(info_url(service_id_value, args.cantaloupe_base))
            candidate_urls.extend(
                derivative_url(service_id_value, size, args.cantaloupe_base)
                for size in sizes
            )

            for url in candidate_urls:
                if url in seen:
                    continue
                seen.add(url)
                urls.append(url)
                if args.limit and len(urls) >= args.limit:
                    break
            if args.limit and len(urls) >= args.limit:
                break
        if args.limit and len(urls) >= args.limit:
            break

    print(f"Found {len(urls)} URLs", file=sys.stderr)

    if args.dry_run:
        for url in urls:
            print(url)
        return 0

    ok, failed = warm_urls(
        urls,
        args.method,
        args.timeout,
        max(1, args.concurrency),
        max(0, args.retries),
    )
    print(f"OK {ok}; failed {failed}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
