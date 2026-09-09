#!/usr/bin/env python3
"""Offline checks for the public checkout; does not download or load a model.

Checks README destination files (Markdown and HTML), required local resources,
the pinned provisioning manifest, ignore rules, and public/index file sizes.
External URLs and Markdown heading anchors are intentionally not link-checked.
"""

import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

from verify_model import load_lock

ROOT = Path(__file__).resolve().parent.parent
MAX_PUBLIC_FILE_BYTES = 10 * 1024 * 1024


def git(*args, input_data=None):
    return subprocess.run(["git", *args], cwd=ROOT, input=input_data,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


def public_paths():
    # Include ordinary untracked files so this can run before an initial commit.
    return {p.decode("utf-8") for p in git("ls-files", "--cached", "--others",
                                          "--exclude-standard", "-z").split(b"\0") if p}


def forbidden_path(name):
    path = Path(name)
    private_dirs = {".build", ".derivedData", "DerivedData", ".research", ".venv",
                    "xcuserdata", "__pycache__"}
    if any(part in private_dirs or part.endswith((".app", ".dSYM", ".xcresult", ".mlmodelc"))
           for part in path.parts):
        return True
    if path.name == ".DS_Store" or path.name == ".env" or path.name.startswith(".env."):
        return True
    if path.suffix.lower() in {".safetensors", ".gguf", ".xcuserstate", ".ipa",
                               ".mobileprovision", ".p12", ".p8", ".car"}:
        return True
    if name.startswith("evaluation/runs/"):
        return True
    if name.startswith("Resources/Models/") and name not in {
        "Resources/Models/.gitkeep", "Resources/Models/README.md"
    }:
        return True
    return False


def check_public_files(paths):
    errors = []
    for name in sorted(paths):
        path = ROOT / name
        if forbidden_path(name):
            errors.append(f"Private/generated/model artifact included in public files: {name}")
        if path.is_symlink():
            errors.append(f"Public assets must be regular files, not symlinks: {name}")
        elif not path.is_file():
            errors.append(f"Public file is missing from the working tree: {name}")
        elif path.stat().st_size > MAX_PUBLIC_FILE_BYTES:
            errors.append(f"Public file exceeds 10 MiB; keep model/build assets outside Git: {name}")

    # Check actual index blobs too: replacing a large staged file with a small
    # working file must not conceal the large object that would be committed.
    blobs = {}
    for record in git("ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        metadata, name = record.split(b"\t", 1)
        mode, oid, stage = metadata.split()
        if stage != b"0":
            errors.append(f"Unresolved index entry: {name.decode()}")
        if mode == b"160000":
            errors.append(f"Submodule needs an explicit public-check policy: {name.decode()}")
        else:
            blobs.setdefault(oid, []).append(name.decode())
    if blobs:
        result = git("cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)",
                     input_data=b"\n".join(blobs) + b"\n")
        for line in result.splitlines():
            oid, kind, size = line.split()
            if kind != b"blob" or int(size) > MAX_PUBLIC_FILE_BYTES:
                errors.append(f"Invalid or oversized staged blob: {', '.join(blobs[oid])}")
    return errors


def check_ignores(bundle_path):
    probes = [
        ".build/public-check-probe", ".derivedData/public-check-probe",
        f"{bundle_path}/model.safetensors",
        "CampingBuddy.xcodeproj/xcuserdata/developer.xcuserdatad/UserInterfaceState.xcuserstate",
        "CampingBuddy.xcodeproj/project.xcworkspace/xcuserdata/developer.xcuserdatad/settings.plist",
        "UserInterfaceState.xcuserstate",
    ]
    result = subprocess.run(["git", "check-ignore", "--no-index", "--stdin", "-z"], cwd=ROOT,
                            input=("\0".join(probes) + "\0").encode(), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    if result.returncode not in (0, 1):
        raise ValueError(result.stderr.decode().strip())
    ignored = {p.decode() for p in result.stdout.split(b"\0") if p}
    return [f".gitignore does not protect generated/private path: {p}" for p in probes if p not in ignored]


class HTMLLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if not value:
                continue
            if key in {"src", "href", "poster"}:
                self.links.append(value)
            elif key == "srcset":
                self.links.extend(part.strip().split()[0] for part in value.split(",") if part.strip())


def readme_links(text):
    # Ignore examples in fenced code blocks instead of treating them as links.
    visible = []
    fence = None
    for line in text.splitlines():
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if marker:
            if fence is None:
                fence = marker[1][0]
            elif marker[1][0] == fence:
                fence = None
            continue
        if fence is None:
            visible.append(line)
    text = "\n".join(visible)
    parser = HTMLLinks()
    parser.feed(text)
    links = list(parser.links)
    for match in re.finditer(r"!?\[[^\]\n]*\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+[^)]*)?\)", text):
        links.append(match[1] or match[2])
    # Reference-style links/images have their destination in a definition line.
    for match in re.finditer(r"(?m)^\s{0,3}\[[^\]]+\]:\s*(?:<([^>]+)>|(\S+))", text):
        links.append(match[1] or match[2])
    return links


def check_readme(paths):
    errors, checked = [], set()
    for destination in readme_links((ROOT / "README.md").read_text()):
        parsed = urlsplit(html.unescape(destination))
        if parsed.scheme in {"http", "https", "mailto", "data"} or parsed.netloc:
            continue
        if parsed.scheme:
            errors.append(f"README has a non-public URL scheme: {destination}")
            continue
        if not parsed.path:
            continue
        target = (ROOT / unquote(parsed.path).lstrip("/")).resolve()
        if not target.is_relative_to(ROOT):
            errors.append(f"README link leaves this repository: {destination}")
            continue
        name = target.relative_to(ROOT).as_posix()
        included = name in paths or any(p.startswith(name + "/") for p in paths)
        if not target.exists() or not included:
            errors.append(f"README link is missing from public checkout: {destination}")
        checked.add(name)
    return errors, len(checked)


def check_resources(paths, lock):
    required = {
        ".gitignore", "README.md", "model-lock.json",
        "Resources/ReferenceLibrary/references.json",
        "Resources/ModelCatalog/catalog.json",
        "Resources/Acknowledgments/ThirdPartyNotices.txt",
        "evaluation/scenarios.json", "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "App/Assets.xcassets/CampMark.imageset/CampMark.png",
        "scripts/provision_model.py", "scripts/verify_model.py", "Package.swift",
    }
    errors = [f"Required public resource missing: {p}" for p in sorted(required)
              if p not in paths or not (ROOT / p).is_file()]
    for filename in ("Resources/ReferenceLibrary/references.json", "evaluation/scenarios.json"):
        records = json.loads((ROOT / filename).read_text())
        if not isinstance(records, list) or not records:
            errors.append(f"Expected nonempty JSON array: {filename}")
    entries = {f["path"] for f in lock["files"]}
    for name in ("config.json", "tokenizer.json", "tokenizer_config.json", "chat_template.jinja"):
        if name not in entries:
            errors.append(f"Model lock omits required offline asset: {name}")
    if not any(p.endswith(".safetensors") for p in entries):
        errors.append("Model lock contains no weight file")
    if not any("LICENSE" in p.upper() for p in entries):
        errors.append("Model lock contains no license")
    if not lock.get("required_config") or not lock["bundle_path"].startswith("Resources/Models/"):
        errors.append("Model lock lacks expected architecture or local model destination")
    return errors


def check_catalog():
    catalog = json.loads((ROOT / "Resources/ModelCatalog/catalog.json").read_text())
    errors = []
    models = catalog["models"]
    if catalog["schemaVersion"] != 1 or len(models) != 1:
        errors.append("The catalog must ship exactly one model")
    ids = {model["id"] for model in models}
    if len(ids) != len(models) or catalog["defaultModelID"] not in ids:
        errors.append("Catalog identities must be unique and include the default")
    for model in models:
        if not re.fullmatch(r"[0-9a-f]{40}", model["revision"]):
            errors.append(f"Unpinned catalog revision: {model['id']}")
        if model["totalBytes"] != sum(file["size"] for file in model["files"]):
            errors.append(f"Catalog size mismatch: {model['id']}")
        for file in model["files"]:
            if not (file.get("sha256") or file.get("gitBlobSHA")):
                errors.append(f"Catalog file missing checksum: {model['id']}/{file['path']}")
    return errors


def main():
    try:
        paths = public_paths()
        lock = load_lock(ROOT / "model-lock.json")
        errors = check_public_files(paths) + check_ignores(lock["bundle_path"])
        link_errors, link_count = check_readme(paths)
        errors.extend(link_errors)
        errors.extend(check_resources(paths, lock))
        errors.extend(check_catalog())
        if errors:
            for error in errors:
                print(f"ERROR: {error}", file=sys.stderr)
            return 1
        print(f"Public repository checks passed: {len(paths)} public files, "
              f"{link_count} local README destinations, pinned model manifest, and offline resources.")
        print("No model weights downloaded, loaded, or required. Run swift test for core behavior.")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Public repository check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
