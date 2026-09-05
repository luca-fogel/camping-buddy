#!/usr/bin/env python3
"""Verify bundled model bytes and structure without networking or ML dependencies."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

PROJECT = Path(__file__).resolve().parent.parent
LOCK = PROJECT / "model-lock.json"


def safe_path(root, relative):
    """Reject traversal and symlinks, including existing directory ancestors."""
    relative = Path(relative)
    if relative.is_absolute() or not relative.parts or any(p in ("..", ".") for p in relative.parts):
        raise ValueError(f"Unsafe relative path: {relative}")
    path = root / relative
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink():
            raise ValueError(f"Symlinks are not allowed: {ancestor}")
    return path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_lock(path=LOCK):
    lock = json.loads(path.read_text())
    if lock.get("schema_version") != 1:
        raise ValueError("Unsupported model lock schema")
    if not re.fullmatch(r"[0-9a-f]{40}", lock.get("revision", "")):
        raise ValueError("Model revision must be an immutable commit SHA")
    files = lock.get("files", [])
    if not files or len({f["path"] for f in files}) != len(files):
        raise ValueError("Model lock needs a nonempty, unique file list")
    for entry in files:
        safe_path(PROJECT, entry["path"])
        if not re.fullmatch(r"[0-9a-f]{64}", entry.get("sha256", "")):
            raise ValueError(f"Missing SHA-256: {entry['path']}")
        if type(entry.get("size")) is not int or entry["size"] <= 0:
            raise ValueError(f"Invalid size: {entry['path']}")
        if entry["url"] != "https://www.apache.org/licenses/LICENSE-2.0.txt" and not re.fullmatch(r"https://huggingface\.co/[^/]+/[^/]+/resolve/[0-9a-f]{40}/[^?#]+", entry["url"]):
            raise ValueError(f"URL must name a pinned public Hugging Face file: {entry['path']}")
    safe_path(PROJECT, lock["bundle_path"])
    return lock


def valid_file(path, entry):
    return path.is_file() and not path.is_symlink() and path.stat().st_size == entry["size"] and sha256(path) == entry["sha256"]


def safetensors_keys(path):
    """Inspect only the non-executable header; check bounds and tensor coverage."""
    size = path.stat().st_size
    with path.open("rb") as handle:
        prefix = handle.read(8)
        if len(prefix) != 8:
            raise ValueError(f"Truncated safetensors header: {path.name}")
        header_size = struct.unpack("<Q", prefix)[0]
        if not 2 <= header_size <= min(128 * 1024 * 1024, size - 8):
            raise ValueError(f"Invalid safetensors header length: {path.name}")
        header = json.loads(handle.read(header_size))
    spans = []
    for name, tensor in header.items():
        if name == "__metadata__":
            continue
        offsets = tensor.get("data_offsets", [])
        shape = tensor.get("shape", [])
        if len(offsets) != 2 or any(type(x) is not int for x in offsets) or not 0 <= offsets[0] <= offsets[1] <= size - 8 - header_size:
            raise ValueError(f"Invalid tensor bounds: {name}")
        if not isinstance(shape, list) or any(type(x) is not int or x < 0 for x in shape):
            raise ValueError(f"Invalid tensor shape: {name}")
        spans.append((offsets[0], offsets[1], name))
    if not spans:
        raise ValueError(f"No tensors: {path.name}")
    end = 0
    for start, stop, name in sorted(spans):
        if start != end:
            raise ValueError(f"Gap or overlap in tensor data: {name}")
        end = stop
    if end != size - 8 - header_size:
        raise ValueError(f"Unexpected trailing tensor data: {path.name}")
    return {name for _, _, name in spans}


def verify(lock, directory, verbose=True):
    directory = Path(directory)
    safe_path(directory.parent, directory.name)
    if not directory.is_dir():
        raise ValueError(f"Model unavailable: {directory}. Run scripts/provision_model.py while online.")
    expected = {f["path"] for f in lock["files"]}
    actual = set()
    for path in directory.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"Symlink in model directory: {path}")
        if path.is_file():
            actual.add(str(path.relative_to(directory)))
    if actual != expected:
        raise ValueError(f"Model file set differs. Missing: {sorted(expected - actual)}; unexpected: {sorted(actual - expected)}")
    for entry in lock["files"]:
        path = safe_path(directory, entry["path"])
        if not valid_file(path, entry):
            raise ValueError(f"Missing, partial, or checksum-mismatched file: {entry['path']}")
        if verbose:
            print(f"Verified {entry['path']}", flush=True)
    config = json.loads((directory / "config.json").read_text())
    for dotted, required in lock["required_config"].items():
        value = config
        for key in dotted.split("."):
            value = value.get(key) if isinstance(value, dict) else None
        if value != required:
            raise ValueError(f"Expected config {dotted}={required!r}, received {value!r}")
    tokenizer = json.loads((directory / "tokenizer.json").read_text())
    tokenizer_config = json.loads((directory / "tokenizer_config.json").read_text())
    if not isinstance(tokenizer.get("model"), dict):
        raise ValueError("Tokenizer has no model definition")
    external = directory / "chat_template.jinja"
    if not tokenizer_config.get("chat_template") and not (external.is_file() and external.read_text().strip()):
        raise ValueError("Missing local chat template")
    if not any("LICENSE" in p.upper() for p in expected):
        raise ValueError("No model license bundled")
    tensor_files = {p: safetensors_keys(directory / p) for p in expected if p.endswith(".safetensors")}
    if not tensor_files:
        raise ValueError("No model tensors bundled")
    index_path = directory / "model.safetensors.index.json"
    if index_path.is_file():
        index = json.loads(index_path.read_text())
        mapping = index.get("weight_map", {})
        if not mapping:
            raise ValueError("Empty model shard index")
        for name, shard in mapping.items():
            if shard not in tensor_files or name not in tensor_files[shard]:
                raise ValueError(f"Index references absent tensor or shard: {name} -> {shard}")
        indexed = {(shard, name) for name, shard in mapping.items()}
        present = {(shard, name) for shard, names in tensor_files.items() for name in names}
        if indexed != present:
            raise ValueError("Tensor index does not cover every bundled tensor")
    total = sum(f["size"] for f in lock["files"])
    return {"repository": lock["repository"], "revision": lock["revision"], "files": len(expected), "bytes": total, "gib": round(total / 1024**3, 3), "tensors": sum(map(len, tensor_files.values())), "directory": str(directory)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=LOCK)
    parser.add_argument("--directory", type=Path, help="Verify an installed .app model directory instead")
    args = parser.parse_args()
    try:
        lock = load_lock(args.lock)
        directory = args.directory or safe_path(PROJECT, lock["bundle_path"])
        print(json.dumps(verify(lock, directory), indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"Model verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
