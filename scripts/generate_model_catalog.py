#!/usr/bin/env python3
"""Reproduce the exact single-model catalog from checked-in immutable metadata.

No network requests, model loading, or live revision resolution occur here.
Update model_catalog_source.json deliberately after checking primary metadata;
then regenerate and review the diff.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts/model_catalog_source.json"
OUTPUT = ROOT / "Resources/ModelCatalog/catalog.json"
DEFAULT_ID = "bonsai-27b-1bit"
# The one shipped choice: ID, user-visible name, exact repository, expected architecture.
CHOICE = (DEFAULT_ID, "Bonsai (27B)", "prism-ml/Bonsai-27B-mlx-1bit", "qwen3_5")
# model.safetensors is a single ~4.8 GiB artifact, so the per-asset ceiling sits above it.
MAX_ASSET_BYTES = 8_000_000_000

def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)

def validate_catalog(catalog: dict) -> None:
    require(catalog.get("schemaVersion") == 1 and catalog.get("defaultModelID") == DEFAULT_ID,
            "Catalog must default to the single shipped model")
    models = catalog.get("models", [])
    require(len(models) == 1, "The app ships exactly one model")
    model = models[0]
    ident, name, repo, architecture = CHOICE
    require((model["id"], model["name"], model["runtime"], model["repository"], model["modelType"]) ==
            (ident, name, "mlx", repo, architecture), f"Unexpected model identity or backend: {model['id']}")
    require(not model.get("bundledRelativePath"), "No model weight is bundled in the app")
    require(all(model.get(k) for k in ("family", "license", "provenance", "compatibilityNote")),
            "Missing model attribution")
    options = model["chatOptions"]
    require(0 <= options["temperature"] <= 2 and 0 < options["topP"] <= 1 and options["topK"] >= 0,
            "Invalid sampling options")
    require(options["systemPromptMode"] in ("system", "prependUser"), "Invalid prompt mode")
    require(re.fullmatch(r"[0-9a-f]{40}", model["revision"]) is not None, "Revision must be pinned")
    require(model.get("validationStatus") in ("compatible-candidate", "device-smoke-tested"),
            "Unknown evidence label")
    files = model["files"]
    paths = {file["path"] for file in files}
    require(len(paths) == len(files) and files, "Empty or duplicate assets")
    require({"config.json", "tokenizer.json", "tokenizer_config.json"} <= paths
            and any(p.endswith(".safetensors") for p in paths), "Missing MLX offline assets")
    require(any(p.lower().startswith("license") for p in paths), "Missing the upstream license file")
    require(model["quantizationBits"] == 1, "Bonsai 27B ships as 1-bit packed weights")
    for file in files:
        path, size = file["path"], file["size"]
        require(re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*", path) is not None, "Unsafe asset path")
        require(Path(path).suffix.lower() in (".json", ".safetensors", ".txt", ".jinja", ".md", ".model", ""),
                "Executable or unsupported asset")
        require(isinstance(size, int) and 0 < size < MAX_ASSET_BYTES, "Invalid asset size")
        sha, git = file.get("sha256"), file.get("gitBlobSHA")
        require((sha is not None and re.fullmatch(r"[0-9a-f]{64}", sha) is not None)
                or (git is not None and re.fullmatch(r"[0-9a-f]{40}", git) is not None and size <= 16 * 1024 * 1024),
                "Missing content identity")
    require(model["totalBytes"] == sum(f["size"] for f in files), "Download byte total mismatch")

def build_catalog() -> dict:
    source = json.loads(SOURCE.read_text())
    catalog = {"schemaVersion": source["schemaVersion"], "defaultModelID": source["defaultModelID"],
               "models": copy.deepcopy(source["models"])}
    validate_catalog(catalog)
    return catalog

def encoded_catalog(catalog: dict) -> bytes:
    return (json.dumps(catalog, indent=2, ensure_ascii=False) + "\n").encode()

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail when catalog differs from the immutable source")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    data = encoded_catalog(build_catalog())
    if args.check:
        if not args.output.exists() or args.output.read_bytes() != data:
            print(f"Catalog is missing or stale: {args.output}", file=sys.stderr)
            return 1
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(data)
    print(f"{'Verified' if args.check else 'Wrote'} the single shipped model; "
          f"SHA-256 {hashlib.sha256(data).hexdigest()}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
