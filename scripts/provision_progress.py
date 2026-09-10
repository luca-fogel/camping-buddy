#!/usr/bin/env python3
"""Report provisioning progress, rate, and ETA by reading files on disk.

Safe to run at any time, including when no provisioner is running: it only
reads the lock and the staging directory, and never writes to either. The rate
is a rolling window over recent samples rather than an average since the start,
because sustained download and disk throughput on this machine drifts.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "model-lock.json"
SAMPLES = ROOT / ".build/model-provision/.progress-samples.json"
WINDOW_SECONDS = 120.0


def observed_bytes(lock: dict) -> tuple[int, int, str | None]:
    """Bytes present, bytes expected, and the file currently in flight."""
    final = ROOT / lock["bundle_path"]
    staging = ROOT / ".build/model-provision" / (final.name + ".download")
    total = sum(entry["size"] for entry in lock["files"])
    present = 0
    active = None
    for entry in lock["files"]:
        done = final / entry["path"]
        if done.is_file():
            present += min(done.stat().st_size, entry["size"])
            continue
        staged = staging / entry["path"]
        if staged.is_file():
            present += min(staged.stat().st_size, entry["size"])
            continue
        part = staging / (entry["path"] + ".part")
        if part.is_file():
            size = min(part.stat().st_size, entry["size"])
            present += size
            if 0 < size < entry["size"]:
                active = entry["path"]
    return present, total, active


def rolling_rate(present: int, now: float) -> tuple[float | None, int]:
    """Bytes per second over the recent window, and the sample count used."""
    history = []
    if SAMPLES.is_file():
        try:
            history = json.loads(SAMPLES.read_text())
        except ValueError:
            history = []
    # A shrinking total means a fresh run; drop the stale history.
    if history and present < history[-1][1]:
        history = []
    history.append([now, present])
    history = [s for s in history if now - s[0] <= WINDOW_SECONDS] or history[-1:]
    try:
        SAMPLES.parent.mkdir(parents=True, exist_ok=True)
        SAMPLES.write_text(json.dumps(history))
    except OSError:
        pass
    if len(history) < 2:
        return None, len(history)
    elapsed = history[-1][0] - history[0][0]
    moved = history[-1][1] - history[0][1]
    return (moved / elapsed if elapsed > 0 else None), len(history)


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1000 or unit == "GB":
            return f"{n:,.2f} {unit}" if unit != "B" else f"{n:,.0f} B"
        n /= 1000
    return f"{n:.2f} GB"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--watch", type=float, default=0,
                        help="Repeat every N seconds instead of reporting once")
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text())
    while True:
        present, total, active = observed_bytes(lock)
        rate, samples = rolling_rate(present, time.time())
        percent = 100 * present / total if total else 0
        line = f"{human(present)} of {human(total)} ({percent:.1f}%)"
        if active:
            line += f" · fetching {active}"
        print(line)
        if present >= total:
            print("All locked bytes are present. Run verify_model.py to confirm hashes.")
            return 0
        if rate and rate > 0:
            remaining = (total - present) / rate
            finish = time.localtime(time.time() + remaining)
            print(f"~{human(rate)}/s over the last {WINDOW_SECONDS:.0f}s ({samples} samples) · "
                  f"~{remaining / 60:.0f} min left · finishing about {time.strftime('%H:%M', finish)} "
                  f"(extrapolated from the recent rate, not a guarantee)")
        else:
            print("Rate needs a second sample; run this again in a few seconds.")
        if not args.watch:
            return 0
        time.sleep(args.watch)


if __name__ == "__main__":
    raise SystemExit(main())
