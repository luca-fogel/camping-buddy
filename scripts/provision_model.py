#!/usr/bin/env python3
"""Download the pinned public model before building. No account, token, or packages needed."""

import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import time
import urllib.error
import urllib.request

from verify_model import LOCK, PROJECT, load_lock, safe_path, valid_file, verify


def download(entry, staging):
    target = safe_path(staging, entry["path"])
    target.parent.mkdir(parents=True, exist_ok=True)
    if valid_file(target, entry):
        print(f"Reusing verified {entry['path']}", flush=True)
        return
    if target.exists():
        raise ValueError(f"Existing staged file failed verification; remove this specific file to retry: {target}")
    partial = safe_path(staging, entry["path"] + ".part")
    for attempt in range(3):
        try:
            offset = partial.stat().st_size if partial.exists() else 0
            if offset > entry["size"]:
                raise ValueError(f"Oversized partial file; remove to retry: {partial}")
            if offset == entry["size"]:
                if not valid_file(partial, entry):
                    raise ValueError(f"Partial download failed checksum; remove to retry: {partial}")
                partial.replace(target)
                return
            request = urllib.request.Request(entry["url"], headers={"User-Agent": "CampingBuddy-Provision/1.0"})
            if offset:
                request.add_header("Range", f"bytes={offset}-")
            print(f"Downloading {entry['path']} ({entry['size']:,} bytes, resume at {offset:,})", flush=True)
            with urllib.request.urlopen(request, timeout=60) as response:
                if not response.url.startswith("https://"):
                    raise ValueError("Refusing a non-HTTPS download redirect")
                if response.status == 206:
                    if not response.headers.get("Content-Range", "").startswith(f"bytes {offset}-"):
                        raise ValueError("Download range does not match partial file")
                elif response.status == 200:
                    offset = 0
                else:
                    raise ValueError(f"Unexpected download status: {response.status}")
                with partial.open("ab" if offset else "wb") as output:
                    count = offset
                    last_report = time.monotonic()
                    while block := response.read(4 * 1024 * 1024):
                        count += len(block)
                        if count > entry["size"]:
                            raise ValueError("Download exceeded locked file size")
                        output.write(block)
                        if time.monotonic() - last_report >= 10:
                            print(f"  {entry['path']}: {100 * count / entry['size']:.1f}%", flush=True)
                            last_report = time.monotonic()
                    output.flush()
                    os.fsync(output.fileno())
            if not valid_file(partial, entry):
                if partial.stat().st_size < entry["size"]:
                    raise OSError("Download ended early")
                raise ValueError(f"SHA-256 mismatch; remove this partial to retry: {partial}")
            partial.replace(target)
            return
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            if attempt == 2:
                raise
            print(f"Download interrupted ({error}); retrying from partial file", flush=True)
            time.sleep(2 * (attempt + 1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=LOCK)
    args = parser.parse_args()
    try:
        lock = load_lock(args.lock)
        destination = safe_path(PROJECT, lock["bundle_path"])
        if destination.exists():
            result = verify(lock, destination)
            print("Already provisioned; no network requests made.")
            print(json.dumps(result, indent=2))
            return 0
        provision_root = safe_path(PROJECT, ".build/model-provision")
        staging = safe_path(provision_root, destination.name + ".download")
        staging.mkdir(parents=True, exist_ok=True)
        lockfile = safe_path(provision_root, destination.name + ".provision.lock")
        # Advisory locking prevents two provisioners from writing the same partials.
        import fcntl
        with lockfile.open("a") as guard:
            try:
                fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError("Another model provisioner is already running")
            required = sum(f["size"] for f in lock["files"])
            staged = sum(p.stat().st_size for p in staging.rglob("*") if p.is_file() and not p.is_symlink())
            if shutil.disk_usage(staging).free < max(0, required - staged) + 512 * 1024**2:
                raise ValueError("Insufficient free disk space for model plus 512 MiB reserve")
            for entry in lock["files"]:
                download(entry, staging)
            result = verify(lock, staging)
            if destination.exists():
                raise ValueError(f"Model destination appeared while provisioning: {destination}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            staging.rename(destination)
        result["directory"] = str(destination)
        print("Model verified and atomically installed. Offline app builds can now bundle it.")
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"Model provisioning failed: {error}", file=sys.stderr)
        print("Completed staged files and .part downloads are preserved for retry. Existing model bundles are never overwritten.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
