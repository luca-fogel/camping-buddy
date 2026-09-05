#!/bin/bash
set -euo pipefail
CAMPING_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAMPING_EXEC="$CAMPING_ROOT/.build/mac/Build/Products/Release/CampingModelCheck"
if [[ ! -x "$CAMPING_EXEC" ]]; then
  echo "Build CampingModelCheck in Release first; see README.md." >&2
  exit 1
fi
mkdir -p "$CAMPING_ROOT/evaluation/runs"
CAMPING_OUTPUT="$CAMPING_ROOT/evaluation/runs/mac-offline-$(date +%Y%m%d-%H%M%S).jsonl"
/usr/bin/sandbox-exec -f "$CAMPING_ROOT/scripts/no-network.sb" "$CAMPING_EXEC" "$CAMPING_ROOT" "$@" | tee "$CAMPING_OUTPUT"
echo "Saved actual Mac-only generation results: $CAMPING_OUTPUT" >&2
